using .Localization: t

"""
Interactive menu workflow: handles the TUI navigation to adjust weights, pick
countries, and launch the reporting view with the desired configuration.
"""

"""
    prompt_country_choice(df)

Interactively prompt the user to select one of the available countries, returning the
chosen name as a string or `nothing` when the input is blank or cancelled.
"""
function prompt_country_choice(df::DataFrame)
    countries = available_countries(df)
    if isempty(countries)
        println(t(:info_no_country_metadata))
        return nothing
    end
    println()
    println(t(:menu_available_countries_header))
    for (idx, country) in enumerate(countries)
        println(t(:menu_country_entry; index=idx, country=country))
    end
    println(t(:menu_country_prompt))
    while true
        input = try
            readline_with_speech("> ")
        catch err
            isa(err, InterruptException) && rethrow()
            println(t(:info_input_aborted; error=string(err)))
            return nothing
        end
        input == "" && return nothing
        parsed_idx = tryparse(Int, input)
        if parsed_idx !== nothing && 1 <= parsed_idx <= length(countries)
            return String(countries[parsed_idx])
        end
        idx = findfirst(c -> slower(c) == slower(input), countries)
        if idx !== nothing
            return String(countries[idx])
        end
        println(t(:menu_country_retry))
    end
end

"""
    run_menu(df, config)

Drive the interactive main menu, letting users start the report for all countries,
filter by a chosen country, or exit the application.
"""
function ask_adjust_weights!(weights::Dict{Symbol,Float64})
    println(t(:prompt_adjust_weights))
    response = try
        lowercase(readline_with_speech("> "))
    catch err
        isa(err, InterruptException) && rethrow()
        ""
    end
    if response in ("y", "yes", "j", "ja")
        prepare_weights!(weights; force=true, prompt=true)
        return true
    end
    return false
end

function report_config_for_menu(base::CLIConfig, weights::Dict{Symbol,Float64}; country::Union{Nothing,String}=nothing)
    return CLIConfig(:report, base.csv_path, base.runargs, base.region_focus, weights, base.force_weight_prompt, country, base.speech_cmd, base.language, base.language_explicit)
end

function run_menu(df::DataFrame, config::CLIConfig)
    base_weights = deepcopy(config.weights)
    while true
        println()
        println(t(:menu_header))
        println(t(:menu_option_overview))
        println(t(:menu_option_country))
        println(t(:menu_option_exit))
        choice = try
            lowercase(readline_with_speech("> "))
        catch err
            isa(err, InterruptException) && rethrow()
            println(t(:info_input_aborted; error=string(err)))
            return
        end

        if choice in ("1", "überblick", "ubersicht")
            weights = deepcopy(base_weights)
            adjusted = ask_adjust_weights!(weights)
            adjusted && (base_weights = deepcopy(weights))
            report_config = report_config_for_menu(config, weights)
            run_report(df, report_config, weights; weights_adjusted=adjusted)
            println()
            println(t(:info_return_menu))
        elseif choice in ("2", "land", "l")
            country = prompt_country_choice(df)
            if country === nothing
                println(t(:info_no_country_selection))
                continue
            end
            filtered = filter_country(df, country)
            if isempty(filtered)
                println(t(:info_no_data_for_country; country=country))
                continue
            end
            weights = deepcopy(base_weights)
            adjusted = ask_adjust_weights!(weights)
            adjusted && (base_weights = deepcopy(weights))
            local_config = report_config_for_menu(config, weights; country=country)
            run_report(filtered, local_config, weights; weights_adjusted=adjusted)
            println()
            println(t(:info_return_menu))
        elseif choice in ("3", "q", "quit", "exit", "beenden")
            println(t(:farewell))
            return
        elseif choice == ""
            println(t(:menu_select_option))
        else
            println(t(:menu_unknown_choice; choice=choice))
        end
    end
end
