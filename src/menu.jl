"""
Interactive menu workflow: handles the TUI navigation to adjust weights, pick
countries, and launch the reporting view with the desired configuration.
"""

"""
    build_report_config(base; weights, country=nothing)

Produce a `CLIConfig` tailored for report execution, optionally pinning a menu-selected
country while preserving other settings from `base`.
"""
function build_report_config(base::CLIConfig; weights::Dict{Symbol,Float64}, country::Union{Nothing,String}=nothing)
    return CLIConfig(:report, base.csv_path, base.runargs, base.region_focus, weights, base.force_weight_prompt, country)
end

"""
    prompt_country_choice(df)

Interactively prompt the user to select one of the available countries, returning the
chosen name as a string or `nothing` when the input is blank or cancelled.
"""
function prompt_country_choice(df::DataFrame)
    countries = available_countries(df)
    if isempty(countries)
        println("[INFO] Keine Länderinformation im Datensatz verfügbar.")
        return nothing
    end
    println("\nVerfügbare Länder:")
    for (idx, country) in enumerate(countries)
        println(" $(idx)) $(country)")
    end
    println("Wähle eine Nummer oder gib den Ländernamen ein (leer für alle Länder).")
    while true
        print("> ")
        input = try
            strip(readline())
        catch err
            isa(err, InterruptException) && rethrow()
            println("[INFO] Eingabe abgebrochen: " * string(err))
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
        println("Nicht erkannt. Bitte Nummer oder Namen erneut eingeben (Enter für Abbruch).")
    end
end

"""
    run_menu(df, config)

Drive the interactive main menu, letting users start the report for all countries,
filter by a chosen country, or exit the application.
"""
function ask_adjust_weights!(weights::Dict{Symbol,Float64})
    if !stdin_is_tty()
        println("[INFO] Eingabe wird erwartet – falls keine Tastatureingabe möglich ist, breche mit Ctrl+C ab.")
    end
    println("Gewichtung anpassen? (y/N)")
    print("> ")
    response = try
        lowercase(strip(readline()))
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
    return CLIConfig(:report, base.csv_path, base.runargs, base.region_focus, weights, base.force_weight_prompt, country)
end

function run_menu(df::DataFrame, config::CLIConfig)
    base_weights = deepcopy(config.weights)
    while true
        println("\n==== Menü ====")
        println("1) Überblick aller Regionen")
        println("2) Land auswählen")
        println("3) Beenden")
        print("> ")
        choice = try
            lowercase(strip(readline()))
        catch err
            isa(err, InterruptException) && rethrow()
            println("[INFO] Input aborted: " * string(err))
            return
        end

        if choice in ("1", "überblick", "ubersicht")
            weights = deepcopy(base_weights)
            adjusted = ask_adjust_weights!(weights)
            adjusted && (base_weights = deepcopy(weights))
            report_config = report_config_for_menu(config, weights)
            run_report(df, report_config, weights)
            println("\nZurück zum Menü...")
        elseif choice in ("2", "land", "l")
            country = prompt_country_choice(df)
            if country === nothing
                println("[INFO] Keine Auswahl – kehre zum Menü zurück.")
                continue
            end
            filtered = filter_country(df, country)
            if isempty(filtered)
                println("[INFO] Keine Daten für $(country) vorhanden.")
                continue
            end
            weights = deepcopy(base_weights)
            adjusted = ask_adjust_weights!(weights)
            adjusted && (base_weights = deepcopy(weights))
            local_config = report_config_for_menu(config, weights; country=country)
            run_report(filtered, local_config, weights)
            println("\nZurück zum Menü...")
        elseif choice in ("3", "q", "quit", "exit", "beenden")
            println("Auf Wiedersehen!")
            return
        elseif choice == ""
            println("Bitte eine Option wählen.")
        else
            println("Unbekannte Auswahl: $(choice)")
        end
    end
end
