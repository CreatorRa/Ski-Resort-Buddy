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
    if haskey(ENV, "FORCE_WEIGHT_PROMPT")
        parsed = parse_bool(ENV["FORCE_WEIGHT_PROMPT"])
        if parsed !== nothing
            force_prompt = parsed
        else
            @warn "Ignoring invalid FORCE_WEIGHT_PROMPT env value" value=ENV["FORCE_WEIGHT_PROMPT"]
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
                @warn "Unbekannte Gewichtungsoption" arg
            elseif value === nothing
                @warn "Option $(flag) benötigt einen numerischen Wert"
            else
                parsed = parse_weight_value(value)
                if parsed === nothing
                    @warn "Gewicht konnte nicht interpretiert werden" flag value
                else
                    weights[key] = parsed
                end
            end
        elseif startswith(arg, "--")
            @warn "Unknown option" arg
        elseif csv_path === nothing
            csv_path = arg
        else
            @warn "Unrecognized argument" arg
        end
        i += 1
    end

    from_date = isnothing(from_str) ? nothing : try
        Date(from_str)
    catch
        @warn "Could not parse FROM_DATE" from_str
        nothing
    end

    to_date = isnothing(to_str) ? nothing : try
        Date(to_str)
    catch
        @warn "Could not parse TO_DATE" to_str
        nothing
    end

    normalize_weights!(weights)

    runargs = RunArgs(from_date, to_date, season)
    return CLIConfig(command, csv_path, runargs, region_focus, weights, force_prompt, nothing)
end

"""
    main()

Top-level entry point: assemble the CLI configuration, load data, apply filters, and
dispatch to the appropriate subcommand before printing closing guidance.
"""
function main()
    config = parse_cli()
    df = load_data(config.csv_path)
    add_newsnow!(df)
    df = apply_filters(df, config.runargs)

    println("Hello, willkommen in unserem Tool!")

    if isempty(df)
        println("No data available after applying filters.")
        print_available_commands()
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
        run_menu(df, CLIConfig(:menu, config.csv_path, config.runargs, config.region_focus, weights, config.force_weight_prompt, nothing))
    else
        run_report(df, config, weights)
    end

    println("\nDone. Terminal reporting finished.")
    print_available_commands()
end
