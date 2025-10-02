using .Localization: t, set_language!, current_language, available_languages, is_supported_language, normalize_language

"""
CLI coordination: parses arguments/environment, loads data via transforms, and
dispatches to list/report/region/menu flows exposed by the reporting and menu layers.
"""

mutable struct CLIParseState
    command::Symbol
    csv_path::Union{Nothing,String}
    from_str::Union{Nothing,String}
    to_str::Union{Nothing,String}
    season::String
    region_focus::Union{Nothing,String}
    weights::Dict{Symbol,Float64}
    force_prompt::Bool
    speech_cmd::Union{Nothing,String}
    language::Symbol
    language_explicit::Bool
end

function build_initial_state()
    weights = clone_metric_weights()
    apply_weight_env_overrides!(weights)

    state = CLIParseState(
        :menu,
        get(ENV, "CSV_PATH", nothing),
        get(ENV, "FROM_DATE", nothing),
        get(ENV, "TO_DATE", nothing),
        uppercase(get(ENV, "SEASON", "ALL")),
        get(ENV, "REGION", nothing),
        weights,
        true,
        get(ENV, "SPEECH_CMD", get(ENV, "SPEECH_TO_TEXT_CMD", nothing)),
        set_language!(:en),
        false,
    )

    apply_env_language!(state)
    apply_force_prompt_env!(state)
    return state
end

function apply_env_language!(state::CLIParseState)
    for (key, explicit_flag) in (("SKI_LOOKUP_LANG", true), ("APP_LANGUAGE", true), ("LANGUAGE", false), ("LANG", false))
        haskey(ENV, key) || continue
        candidate = strip(String(ENV[key]))
        candidate == "" && continue
        applied = register_language_choice!(state, candidate; mark_explicit=explicit_flag)
        if applied && explicit_flag
            break
        end
    end
end

function apply_force_prompt_env!(state::CLIParseState)
    haskey(ENV, "FORCE_WEIGHT_PROMPT") || return
    parsed = parse_bool(ENV["FORCE_WEIGHT_PROMPT"])
    if parsed === nothing
        @warn t(:warn_invalid_force_weight_prompt_env) value=ENV["FORCE_WEIGHT_PROMPT"]
        return
    end
    state.force_prompt = parsed
end

function register_language_choice!(state::CLIParseState, token; mark_explicit::Bool=false)
    language, applied = apply_language_choice(token, state.language)
    state.language = language
    if applied && mark_explicit
        state.language_explicit = true
    end
    return applied
end

function process_cli_arguments!(state::CLIParseState)
    i = 1
    while i <= length(ARGS)
        consumed = handle_cli_argument!(state, ARGS[i], i)
        i += 1 + consumed
    end
end

function handle_cli_argument!(state::CLIParseState, arg::String, index::Int)
    next_arg = index < length(ARGS) ? ARGS[index + 1] : nothing
    consumed = 0

    if arg == "report"
        state.command = :report
    elseif arg == "menu"
        state.command = :menu
    elseif arg == "list"
        state.command = :list
    elseif arg == "region" && next_arg !== nothing
        state.command = :region
        state.region_focus = next_arg
        consumed = 1
    elseif arg == "--from" && next_arg !== nothing
        state.from_str = next_arg
        consumed = 1
    elseif arg == "--to" && next_arg !== nothing
        state.to_str = next_arg
        consumed = 1
    elseif arg == "--season" && next_arg !== nothing
        state.season = uppercase(next_arg)
        consumed = 1
    elseif arg == "--csv" && next_arg !== nothing
        state.csv_path = next_arg
        consumed = 1
    elseif arg == "--ask-weights"
        state.force_prompt = true
    elseif arg == "--no-ask-weights"
        state.force_prompt = false
    elseif arg in ("--lang", "--language") && next_arg !== nothing
        applied = register_language_choice!(state, next_arg; mark_explicit=true)
        state.language_explicit = state.language_explicit || applied
        consumed = 1
    elseif startswith(arg, "--lang=") || startswith(arg, "--language=")
        parts = split(arg, "=", limit=2)
        if length(parts) == 2
            applied = register_language_choice!(state, parts[2]; mark_explicit=true)
            state.language_explicit = state.language_explicit || applied
        end
    elseif arg == "--speech-cmd" && next_arg !== nothing
        state.speech_cmd = next_arg
        consumed = 1
    elseif startswith(arg, "--speech-cmd=")
        parts = split(arg, "=", limit=2)
        length(parts) == 2 && (state.speech_cmd = parts[2])
    elseif arg in ("--no-speech", "--speech-off")
        state.speech_cmd = nothing
    elseif startswith(arg, "--weight-")
        flag = arg
        value = nothing
        if occursin('=', arg)
            parts = split(arg, "=", limit=2)
            flag = parts[1]
            value = parts[2]
        elseif next_arg !== nothing
            value = next_arg
            consumed = 1
        end
        apply_weight_override!(state, flag, value)
    elseif startswith(arg, "--")
        @warn t(:warn_unknown_option) option=arg
    elseif state.csv_path === nothing
        state.csv_path = arg
    else
        @warn t(:warn_unrecognized_argument) argument=arg
    end

    return consumed
end

function apply_weight_override!(state::CLIParseState, flag::String, value)
    key = get(METRIC_WEIGHT_FLAGS, flag, nothing)
    if key === nothing
        @warn t(:warn_unknown_weight_flag) option=flag
        return
    end
    if value === nothing
        @warn t(:warn_weight_flag_requires_value; flag=flag)
        return
    end
    parsed = parse_weight_value(String(value))
    if parsed === nothing
        @warn t(:warn_weight_parse_failed) option=flag value=value
        return
    end
    state.weights[key] = parsed
end

function parse_date_value(raw::Union{Nothing,String}, warn_key::Symbol)
    raw === nothing && return nothing
    try
        return Date(raw)
    catch
        @warn t(warn_key) value=raw
        return nothing
    end
end

function finalize_cli_config(state::CLIParseState)
    from_date = parse_date_value(state.from_str, :warn_invalid_from_date)
    to_date = parse_date_value(state.to_str, :warn_invalid_to_date)

    normalize_weights!(state.weights)

    speech_cmd = set_speech_cmd!(state.speech_cmd)
    speech_cmd = maybe_prompt_speech_cmd!(speech_cmd)

    runargs = RunArgs(from_date, to_date, state.season)
    language = current_language()
    return CLIConfig(state.command, state.csv_path, runargs, state.region_focus, state.weights, state.force_prompt, nothing, speech_cmd, language, state.language_explicit)
end

"""
    parse_cli()

Parse CLI arguments and environment variables into a `CLIConfig`, including the active
subcommand, data path, filters, weight overrides, and menu-specific flags.
"""
function parse_cli()
    state = build_initial_state()
    process_cli_arguments!(state)
    return finalize_cli_config(state)
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
