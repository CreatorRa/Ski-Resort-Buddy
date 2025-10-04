"""
SkiLookup
========= 
Central module that bootstraps the project: loads shared dependencies, provides
global constants/structs, and exposes the `main()` entry point while including the
feature-specific submodules (utils, transforms, weights, reporting, menu, CLI).
"""
module SkiLookup

include("localization.jl")

using CSV
using DataFrames
using Dates
using Statistics
using Printf
using PrettyTables
using Plots
using .Localization: t

export main

const ROOT_DIR   = abspath(joinpath(@__DIR__, ".."))
const CSV_FILE_NAME = "ski-regions-data.csv"
const CSV_REMOTE_URL = "https://pzghdabqnsdthysjzacl.supabase.co/storage/v1/object/public/datasets//ski-regions-dataset-2025-10-02.csv"
const CSV_PATH_DEFAULT = CSV_REMOTE_URL
const COMMAND_PREFIX = "julia --project=. bin/dach_resort_advisor"
const PLOTS_OUTPUT_DIR = joinpath(ROOT_DIR, "plots")
const SPEECH_CMD = Ref{Union{Nothing,String}}(nothing)

#---Main Logic with Saftey check---


if get(ENV, "SKILOOKUP_BOOT_PREVIEW", "0") == "1"
    if occursin("://", CSV_PATH_DEFAULT)
        println("[INFO] Default CSV is remote - skipping boot preview.")
    elseif isfile(CSV_PATH_DEFAULT)
        println(t(:info_default_csv_found; path=CSV_PATH_DEFAULT))
        println(t(:info_default_csv_reading))
        df = CSV.read(CSV_PATH_DEFAULT, DataFrame)
        println(t(:info_default_csv_preview))
        println(first(df, 10))
    else
        println(t(:error_default_csv_missing))
        println(t(:error_default_csv_hint; file=CSV_FILE_NAME))
    end
    println()
end

#---End of optional preview block---

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
    speech_cmd::Union{Nothing,String}
    language::Symbol
    language_explicit::Bool
end

include("utils.jl")
include("weights.jl")
include("transforms.jl")
include("reporting.jl")
include("menu.jl")
include("cli.jl")

end # module SkiLookup
