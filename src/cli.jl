using .Localization: t, set_language!, current_language, available_languages, is_supported_language, normalize_language

"""
CLI coordination: parses arguments/environment, loads data via transforms, and
dispatches to list/report/region/menu flows exposed by the reporting and menu layers.
"""

"""
    parse_cli()

Parse CLI arguments and environment variables into a `CLIConfig`, including the active
subcommand, data path, filters, weight overrides, and menu-specific flags.
"""
function parse_cli()
    from_str = get(ENV, "FROM_DATE", nothing)
    to_str = get(ENV, "TO_DATE", nothing)
    season = uppercase(get(ENV, "SEASON", "ALL"))
    csv_path = get(ENV, "CSV_PATH", nothing)
    region_focus = get(ENV, "REGION", nothing)
    command = :menu
    weights = clone_metric_weights()
    apply_weight_env_overrides!(weights)
    force_prompt = true
    speech_cmd = get(ENV, "SPEECH_CMD", get(ENV, "SPEECH_TO_TEXT_CMD", nothing))

    language = set_language!(:en)
    language_explicit = false
    for (key, explicit_flag) in (("SKI_LOOKUP_LANG", true), ("APP_LANGUAGE", true), ("LANGUAGE", false), ("LANG", false))
        if haskey(ENV, key)
            candidate = strip(String(ENV[key]))
            if candidate != ""
                language, applied = apply_language_choice(candidate, language)
                if applied
                    language_explicit = language_explicit || explicit_flag
                    if explicit_flag
                        break
                    end
                end
            end
        end
    end

    if haskey(ENV, "FORCE_WEIGHT_PROMPT")
        parsed = parse_bool(ENV["FORCE_WEIGHT_PROMPT"])
        if parsed !== nothing
            force_prompt = parsed
        else
            @warn t(:warn_invalid_force_weight_prompt_env) value=ENV["FORCE_WEIGHT_PROMPT"]
        end
    end

    i = 1
    while i <= length(ARGS)
        arg = ARGS[i]
        if arg == "report"
            command = :report
        elseif arg == "menu"
            command = :menu
        elseif arg == "list"
            command = :list
        elseif arg == "region" && i < length(ARGS)
            command = :region
            region_focus = ARGS[i+1]
            i += 1
        elseif arg == "--from" && i < length(ARGS)
            from_str = ARGS[i+1]; i += 1
        elseif arg == "--to" && i < length(ARGS)
            to_str = ARGS[i+1]; i += 1
        elseif arg == "--season" && i < length(ARGS)
            season = uppercase(ARGS[i+1]); i += 1
        elseif arg == "--csv" && i < length(ARGS)
            csv_path = ARGS[i+1]; i += 1
        elseif arg == "--ask-weights"
            force_prompt = true
        elseif arg == "--no-ask-weights"
            force_prompt = false
        elseif arg in ("--lang", "--language") && i < length(ARGS)
            language, applied = apply_language_choice(ARGS[i+1], language)
            language_explicit |= applied
            i += 1
        elseif startswith(arg, "--lang=") || startswith(arg, "--language=")
            parts = split(arg, "=", limit=2)
            if length(parts) == 2
                language, applied = apply_language_choice(parts[2], language)
                language_explicit |= applied
            end
        elseif arg == "--speech-cmd" && i < length(ARGS)
            speech_cmd = ARGS[i+1]
            i += 1
        elseif startswith(arg, "--speech-cmd=")
            parts = split(arg, "=", limit=2)
            length(parts) == 2 && (speech_cmd = parts[2])
        elseif arg in ("--no-speech", "--speech-off")
            speech_cmd = nothing
        elseif startswith(arg, "--weight-")
            flag = arg
            value = nothing
            if occursin('=', arg)
                parts = split(arg, "=", limit=2)
                flag = parts[1]
                value = parts[2]
            elseif i < length(ARGS)
                value = ARGS[i+1]
                i += 1
            end
            key = get(METRIC_WEIGHT_FLAGS, flag, nothing)
            if key === nothing
                @warn t(:warn_unknown_weight_flag) option=arg
            elseif value === nothing
                @warn t(:warn_weight_flag_requires_value; flag=flag)
            else
                parsed = parse_weight_value(value)
                if parsed === nothing
                    @warn t(:warn_weight_parse_failed) option=flag value=value
                else
                    weights[key] = parsed
                end
            end
        elseif startswith(arg, "--")
            @warn t(:warn_unknown_option) option=arg
        elseif csv_path === nothing
            csv_path = arg
        else
            @warn t(:warn_unrecognized_argument) argument=arg
        end
        i += 1
    end

    from_date = isnothing(from_str) ? nothing : try
        Date(from_str)
    catch
        @warn t(:warn_invalid_from_date) value=from_str
        nothing
    end

    to_date = isnothing(to_str) ? nothing : try
        Date(to_str)
    catch
        @warn t(:warn_invalid_to_date) value=to_str
        nothing
    end

    normalize_weights!(weights)

    speech_cmd = set_speech_cmd!(speech_cmd)
    speech_cmd = maybe_prompt_speech_cmd!(speech_cmd)

    runargs = RunArgs(from_date, to_date, season)
    language = current_language()
    return CLIConfig(command, csv_path, runargs, region_focus, weights, force_prompt, nothing, speech_cmd, language, language_explicit)
end

"""
    main()

Top-level entry point: assemble the CLI configuration, load data, apply filters, and
dispatch to the appropriate subcommand before printing closing guidance.
"""
function main()
    config = parse_cli()
    set_language!(config.language)
    config = maybe_prompt_language(config)
    set_language!(config.language)
    df = load_data(config.csv_path)
    add_newsnow!(df)
    df = apply_filters(df, config.runargs)

    println(t(:greeting))

    if isempty(df)
        println(t(:info_no_data_after_filters))
        return
    end

    weights = config.weights
    if config.command in (:report, :region)
        prepare_weights!(weights; force=config.force_weight_prompt, prompt=true)
    end

    if config.command == :list
        run_list(df)
    elseif config.command == :region
        run_region(df, config.region_focus; weights=weights)
    elseif config.command == :menu
        run_menu(df, CLIConfig(:menu, config.csv_path, config.runargs, config.region_focus, weights, config.force_weight_prompt, nothing, config.speech_cmd, config.language, config.language_explicit))
    else
        run_report(df, config, weights)
    end

    println()
    println(t(:info_terminal_finished))
end
function language_display_name(lang::Symbol)
    key = Symbol("language_name_" * String(lang))
    return t(key)
end

function with_language(config::CLIConfig, lang::Symbol; explicit::Bool)
    return CLIConfig(
        config.command,
        config.csv_path,
        config.runargs,
        config.region_focus,
        config.weights,
        config.force_weight_prompt,
        config.menu_country,
        config.speech_cmd,
        lang,
        explicit,
    )
end

function apply_language_choice(token, fallback_language::Symbol)
    trimmed = strip(String(token))
    trimmed == "" && return (fallback_language, false)
    normalized = normalize_language(trimmed)
    if is_supported_language(normalized)
        return (set_language!(normalized), true)
    else
        choices = join(string.(available_languages()), ", ")
        @warn t(:warn_unsupported_language; requested=trimmed, options=choices)
        set_language!(fallback_language)
        return (fallback_language, false)
    end
end

function maybe_prompt_language(config::CLIConfig)
    if config.language_explicit || get(ENV, "SKI_LOOKUP_SKIP_LANGUAGE_PROMPT", "0") == "1"
        return config
    end
    current_lang = current_language()
    languages = sort(available_languages(); by=String)
    println()
    println(t(:prompt_language_header))
    for (idx, lang) in enumerate(languages)
        println(t(:prompt_language_option; index=idx, name=language_display_name(lang)))
    end
    println(t(:prompt_language_hint; current=language_display_name(current_lang)))

    while true
        input = try
            strip(readline_with_speech("> "; fallback_keyboard=true, fallback_on_empty=true))
        catch err
            isa(err, InterruptException) && rethrow()
            println(t(:prompt_language_cancelled; error=string(err)))
            return config
        end

        input == "" && return config

        parsed_idx = tryparse(Int, input)
        if parsed_idx !== nothing && 1 <= parsed_idx <= length(languages)
            selected = languages[parsed_idx]
            set_language!(selected)
            return with_language(config, selected; explicit=true)
        end

        normalized = normalize_language(input)
        if is_supported_language(normalized)
            set_language!(normalized)
            return with_language(config, normalized; explicit=true)
        end

        println(t(:prompt_language_retry))
    end
end
