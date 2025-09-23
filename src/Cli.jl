struct RunArgs
    fromdate::Union{Nothing,Date}
    todate::Union{Nothing,Date}
    season::String
end

struct CLIConfig
    command::Symbol
    csv_path::Union{Nothing,String}
    runargs::RunArgs
    region_focus::Union{Nothing,String}
end

function parse_cli()
    from_str = get(ENV, "FROM_DATE", nothing)
    to_str = get(ENV, "TO_DATE", nothing)
    season = uppercase(get(ENV, "SEASON", "ALL"))
    csv_path = get(ENV, "CSV_PATH", nothing)
    region_focus = get(ENV, "REGION", nothing)
    command = :report

    i = 1
    while i <= length(ARGS)
        arg = ARGS[i]
        if arg == "report"
            command = :report
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

    runargs = RunArgs(from_date, to_date, season)
    return CLIConfig(command, csv_path, runargs, region_focus)
end

in_season(d::Date, season::String) = season == "WINTER" ? month(d) in (11,12,1,2,3,4) : season == "SUMMER" ? month(d) in (5,6,7,8,9,10) : true

function apply_filters(df::DataFrame, rargs::RunArgs)
    region = get(ENV, "REGION", nothing)
    country = get(ENV, "COUNTRY", nothing)
    if !isnothing(region) && hasproperty(df, :Region)
        df = filter(:Region => x -> !ismissing(x) && slower(x) == slower(region), df)
    end
    if !isnothing(country) && hasproperty(df, :Country)
        df = filter(:Country => x -> !ismissing(x) && slower(x) == slower(country), df)
    end
    if rargs.fromdate !== nothing
        df = filter(:Date => d -> d >= rargs.fromdate, df)
    end
    if rargs.todate !== nothing
        df = filter(:Date => d -> d <= rargs.todate, df)
    end
    if rargs.season != "ALL"
        df = filter(:Date => d -> in_season(d, rargs.season), df)
    end
    return df
end

function stdin_is_tty()
    if isdefined(Base, :isatty)
        try
            return Base.isatty(stdin)
        catch
            return false
        end
    end
    if isdefined(Base, :Libc) && isdefined(Base.Libc, :isatty)
        try
            return Base.Libc.isatty(Base.Libc.fileno(stdin)) == 1
        catch
            return false
        end
    end
    return false
end

function print_active_filters(config::CLIConfig, df::DataFrame)
    println("\n== Active Filters ==")
    rargs = config.runargs
    from_label = isnothing(rargs.fromdate) ? "open" : string(rargs.fromdate)
    to_label = isnothing(rargs.todate) ? "open" : string(rargs.todate)
    season_label = isempty(rargs.season) ? "ALL" : rargs.season
    println(" - Season: $(season_label)")
    println(" - Date range: $(from_label) -> $(to_label)")
    if config.region_focus !== nothing
        println(" - Preselected region: $(config.region_focus)")
    elseif haskey(ENV, "REGION")
        env_region = ENV["REGION"]
        println(" - Preselected region (ENV): $(env_region)")
    else
        println(" - No region preselected")
    end
    if !isempty(df) && hasproperty(df, :Date)
        println(" - Observations after filters: $(nrow(df)) rows, window $(string(minimum(df.Date))) - $(string(maximum(df.Date)))")
    else
        println(" - No data available after applying filters")
    end
end

function available_regions(df::DataFrame)
    if !hasproperty(df, :Region)
        return String[]
    end
    raw = [strip(string(r)) for r in skipmissing(df.Region) if strip(string(r)) != ""]
    unique!(raw)
    sort!(raw)
    return raw
end

function print_available_regions(regions::AbstractVector{<:AbstractString})
    println("== Available Regions ==")
    if isempty(regions)
        println(" (no regions found)")
    else
        for r in regions
            println(" - $(r)")
        end
    end
    println()
end

function prompt_region_choice(df::DataFrame, scoreboard::DataFrame, config::CLIConfig)
    preselected = config.region_focus
    if preselected !== nothing && strip(String(preselected)) != ""
        return String(preselected)
    end
    !stdin_is_tty() && return nothing
    regions = available_regions(df)
    isempty(regions) && return nothing

    println("\nEnter region for a focused review (press Enter to skip):")
    suggestions = String[]
    if !isempty(scoreboard) && :Region in names(scoreboard)
        suggestions = [string(r) for r in scoreboard.Region if strip(string(r)) != ""]
    end
    if isempty(suggestions)
        suggestions = regions[1:min(length(regions), 10)]
    end
    println("Suggestions: " * join(suggestions, ", "))
    print("> ")
    try
        input = strip(readline())
        input == "" && return nothing
        actual, alternatives = resolve_region_name(df, input)
        if actual === nothing
            limit = min(length(alternatives), 5)
            if limit > 0
                println("Region not found. Suggestions: " * join(alternatives[1:limit], ", "))
            else
                println("Region not found. Use `list` to see all locations.")
            end
            return nothing
        end
        return actual
    catch err
        isa(err, InterruptException) && rethrow()
        println("Input could not be processed (" * string(err) * ").")
        return nothing
    end
end

function resolve_region_name(df::DataFrame, name::AbstractString)
    regs = available_regions(df)
    target = slower(name)
    for r in regs
        if slower(r) == target
            return (r, String[])
        end
    end
    suggestions = [r for r in regs if occursin(target, slower(r))]
    return (nothing, suggestions)
end
