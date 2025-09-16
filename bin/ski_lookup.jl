#!/usr/bin/env julia
# CLI – Start:
#   julia --project=. bin/ski_lookup.jl --list
#   julia --project=. bin/ski_lookup.jl --name "Golm"

try
    using Pkg
    Pkg.activate(joinpath(@__DIR__, ".."))
catch e
    @warn "Projekt nicht aktiviert: $e"
end

using SkiLookup, ArgParse

function parser()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--list"
            help = "Liste der Resorts anzeigen"
            action = :store_true
        "--name","-n"
            help = "Exakter Resort-Name (wie in --list angezeigt)"
        "--data-dir","-d"
            help = "Verzeichnis mit processed-Dateien"
            default = "data/processed"
    end
    return s
end

function check_processed!(data_dir::AbstractString)
    path = joinpath(data_dir, "resorts_processed.csv")
    isfile(path) || begin
        @error "Processed-Datei fehlt: $(path)\n→ Bitte zuerst:  julia --project=. scripts/build_resorts.jl"
        exit(2)
    end
end

function main()
    args = parse_args(parser())
    data_dir = args["data-dir"]

    if get(args, "list", false)
        check_processed!(data_dir)
        for r in SkiLookup.list_resorts(data_dir)
            println(r)
        end
        return
    end

    if !haskey(args, "name") || isnothing(args["name"])
        @error "Bitte zuerst --list nutzen und dann mit --name \"GENAUER NAME\" aufrufen."
        exit(3)
    end

    check_processed!(data_dir)
    meta = SkiLookup.query_resort_meta(args["name"]; data_dir=data_dir)
    SkiLookup.print_resort_meta(meta)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

