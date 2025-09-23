module SkiLookup

using CSV
using DataFrames
using Dates
using Statistics
using Printf
using PrettyTables
using Plots

const ROOT_DIR   = abspath(joinpath(@__DIR__, ".."))
const CSV_FILE_NAME = "ski-regions-data.csv"
const CSV_PATH_DEFAULT = joinpath(ROOT_DIR, CSV_FILE_NAME)
const COMMAND_PREFIX = "julia --project=. bin/dach_resort_advisor"
const PLOTS_OUTPUT_DIR = joinpath(ROOT_DIR, "plots")
const PLOTS_INITIALISED = Ref(false)
const DACH_SYNONYMS = Dict(
    "AUSTRIA" => "Austria",
    "OESTERREICH" => "Austria",
    "AT" => "Austria",
    "AUT" => "Austria",
    "GERMANY" => "Germany",
    "DEUTSCHLAND" => "Germany",
    "DE" => "Germany",
    "DEU" => "Germany",
    "SWITZERLAND" => "Switzerland",
    "SCHWEIZ" => "Switzerland",
    "CH" => "Switzerland",
    "CHE" => "Switzerland"
)

include("Util.jl")
include("Data.jl")
include("Cli.jl")
include("Reporting.jl")

export main

function main()
    config = parse_cli()
    df = load_data(config.csv_path)
    add_newsnow!(df)
    df = apply_filters(df, config.runargs)

    if isempty(df)
        println("No data available after applying filters.")
        print_available_commands()
        return
    end

    if config.command == :list
        run_list(df)
    elseif config.command == :region
        run_region(df, config.region_focus)
    else
        run_report(df, config)
    end

    println("\nDone. Terminal reporting finished.")
    print_available_commands()
end

end # module
