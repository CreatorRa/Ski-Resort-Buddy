"""
SkiLookup
========= 
Central module that bootstraps the project: loads shared dependencies, provides
global constants/structs, and exposes the `main()` entry point while including the
feature-specific submodules (utils, transforms, weights, reporting, menu, CLI).
"""
module SkiLookup

using CSV
using DataFrames
using Dates
using Statistics
using Printf
using PrettyTables
using Plots

export main

const ROOT_DIR   = abspath(joinpath(@__DIR__, ".."))
const CSV_FILE_NAME = "ski-regions-data.csv"
const CSV_PATH_DEFAULT = joinpath(ROOT_DIR, CSV_FILE_NAME)
const COMMAND_PREFIX = "julia --project=. bin/dach_resort_advisor"
const PLOTS_OUTPUT_DIR = joinpath(ROOT_DIR, "plots")

#---Main Logic with Saftey check---


if isfile(CSV_PATH_DEFAULT)


    println("File found at:", CSV_PATH_DEFAULT)


    println("Reading data...")


    


    df = CSV.read(CSV_PATH_DEFAULT, DataFrame)


    println("Display the first 10 rows:")


    println(first(df, 10))


else


    println("File not found!")


    println("Please ensure that the file 'ski-regions-data.csv' is located in the project directory.")




end

#---End of Main Logic with Saftey check---
gr()
Plots.default(; fmt=:png, legend=:topright, size=(900, 500))

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

"""
    RunArgs

Container for time/season filters parsed from CLI arguments or environment variables.
"""
struct RunArgs
    fromdate::Union{Nothing,Date}
    todate::Union{Nothing,Date}
    season::String
end

"""
    CLIConfig

High-level configuration for a script run, tracking the subcommand, dataset location,
filters, user-selected region, weight map, and menu-specific state.
"""
struct CLIConfig
    command::Symbol
    csv_path::Union{Nothing,String}
    runargs::RunArgs
    region_focus::Union{Nothing,String}
    weights::Dict{Symbol,Float64}
    force_weight_prompt::Bool
    menu_country::Union{Nothing,String}
end

include("utils.jl")
include("weights.jl")
include("transforms.jl")
include("reporting.jl")
include("menu.jl")
include("cli.jl")

end # module SkiLookup
