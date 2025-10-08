# Region deep-dive helpers: prompts, tabular summaries, and plot generation that
# power the interactive region exploration workflow.

"""
prompt_region_choice(df, scoreboard, config)

Help the user choose a region by offering sensible suggestions. Returns the region
name when recognised, otherwise `nothing`.
"""
function prompt_region_choice(df::DataFrame, scoreboard::DataFrame, config::CLIConfig)
    preselected = config.region_focus
    if preselected !== nothing && strip(String(preselected)) != ""
        return String(preselected)
    end
    !stdin_is_tty() && return nothing
    regions = available_regions(df)
    isempty(regions) && return nothing

    println()
    println(t(:region_prompt_header))
    suggestions = String[]
    if !isempty(scoreboard) && :Region in names(scoreboard)
        suggestions = [string(r) for r in scoreboard.Region if strip(string(r)) != ""]
    end
    if isempty(suggestions)
        suggestions = regions[1:min(length(regions), 10)]
    end
    println(t(:region_prompt_suggestions; suggestions=join(suggestions, ", ")))
    try
        input = readline_with_speech("> ")
        input == "" && return nothing
        actual, alternatives = resolve_region_name(df, input)
        if actual === nothing
            limit = min(length(alternatives), 5)
            if limit > 0
                println(t(:region_not_found_with_suggestions; suggestions=join(alternatives[1:limit], ", ")))
            else
                println(t(:region_not_found_no_suggestions))
            end
            return nothing
        end
        return actual
    catch err
        isa(err, InterruptException) && rethrow()
        println(t(:region_input_error; error=string(err)))
        return nothing
    end
end

"""
print_region_history(df, region_name; months=12)

Show a month-by-month summary (averages and totals) for the chosen region so users can
spot longer trends.
"""
function print_region_history(df::DataFrame, region_name::Union{Nothing,AbstractString}; months::Int=12)
    if isnothing(region_name)
        return DataFrame()
    end
    if !hasproperty(df, :Date) || isempty(df)
        println()
        println(t(:info_region_no_data; region=region_name))
        return DataFrame()
    end
    region_df = hasproperty(df, :Region) ? filter(:Region => x -> !ismissing(x) && slower(x) == slower(region_name), df) : df
    if isempty(region_df)
        println()
        println(t(:info_region_no_data; region=region_name))
        return
    end
    latest = maximum(region_df.Date)
    month_start = Date(year(latest), month(latest), 1)
    cutoff = month_start - Month(months - 1)
    recent_df = filter(:Date => d -> d >= cutoff, region_df)
    if isempty(recent_df)
        recent_df = region_df
    end

    month_df = transform(recent_df, :Date => ByRow(d -> Date(year(d), month(d), 1)) => :Month)
    grouped = combine(groupby(month_df, :Month),
        Symbol("Temperature (°C)") => (v -> safe_stat(v, mean)) => :AvgTemperature,
        Symbol("Snow Depth (cm)") => (v -> safe_stat(v, mean)) => :AvgSnowDepth,
        Symbol("Snow_New (cm)") => (v -> sum(collect_valid(v))) => :TotalNewSnow,
        Symbol("Precipitation (mm)") => (v -> safe_stat(v, mean)) => :AvgPrecipitation,
        Symbol("Wind (Beaufort)") => (v -> safe_stat(v, mean)) => :AvgWind
    )

    if isempty(grouped)
        println()
        println(t(:info_region_no_aggregates; region=region_name))
        return DataFrame()
    end

    sort!(grouped, :Month)
    rename_map = Dict(
        :AvgTemperature => Symbol("Avg Temperature (°C)"),
        :AvgSnowDepth => Symbol("Avg Snow Depth (cm)"),
        :TotalNewSnow => Symbol("Total New Snow (cm)"),
        :AvgPrecipitation => Symbol("Avg Precipitation (mm)"),
        :AvgWind => Symbol("Avg Wind (Beaufort)")
    )
    rename!(grouped, rename_map)

    display_df = copy(grouped)
    display_df.Month = Dates.format.(display_df.Month, "yyyy-mm")
    for col in values(rename_map)
        if col in names(display_df)
            display_df[!, col] = map(x -> x isa Missing ? missing : round(x; digits=2), display_df[!, col])
        end
    end

    println()
    println(t(:region_insights_header; region=region_name, months=months))
    styled_table(display_df)

    return grouped
end

"""
region_top_snow_events(df; top_n=5)

Return the days with the biggest fresh-snow gains for a region, plus helpful context
such as snow depth and temperature when available.
"""
function region_top_snow_events(df::DataFrame; top_n::Int=5)
    col = Symbol("Snow_New (cm)")
    if !hasproperty(df, col)
        return DataFrame()
    end
    slice = DataFrame(:Date => df[!, :Date], col => df[!, col])
    if hasproperty(df, Symbol("Snow Depth (cm)"))
        slice[!, Symbol("Snow Depth (cm)")] = df[!, Symbol("Snow Depth (cm)")]
    end
    if hasproperty(df, Symbol("Temperature (°C)"))
        slice[!, Symbol("Temperature (°C)")] = df[!, Symbol("Temperature (°C)")]
    end
    slice = filter(row -> !ismissing(row[col]) && row[col] > 0, slice)
    if isempty(slice)
        return DataFrame()
    end
    sort!(slice, col, rev=true)
    return slice[1:min(top_n, nrow(slice)), :]
end

"""
run_list(df)

Print every region name in alphabetical order. Useful when a user is unsure about the
exact spelling.
"""
function run_list(df::DataFrame)
    print_available_regions(available_regions(df))
end

"""
resolve_region_name(df, name)

Try to match a user-entered region to the dataset. When no exact match is found, offer
up to five similar suggestions.
"""
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

"""
run_region(df, region_name; weights=DEFAULT_METRIC_WEIGHTS, monthly_table=nothing)

Drive the detailed region view: show headline stats, monthly summaries, recent
conditions, history tables, and create plots if possible.
"""
function run_region(df::DataFrame, region_name::Union{Nothing,String}; weights::Dict{Symbol,Float64}=DEFAULT_METRIC_WEIGHTS, monthly_table::Union{Nothing,DataFrame}=nothing, region_index::Union{Nothing,Dict{String,DataFrame}}=nothing)
    if region_name === nothing || strip(String(region_name)) == ""
        println(t(:region_prompt_missing; command=COMMAND_PREFIX))
        run_list(df)
        return
    end

    actual, suggestions = resolve_region_name(df, String(region_name))
    if actual === nothing
        println(t(:region_not_found_exact; region=region_name))
        if !isempty(suggestions)
            println(t(:region_did_you_mean; suggestions=join(suggestions[1:min(5, length(suggestions))], ", ")))
        end
        println(t(:region_run_list_hint))
        return
    end

    region_key = slower(String(actual))
    region_df = if region_index !== nothing && haskey(region_index, region_key)
        region_index[region_key]
    else
        subset(df, :Region => ByRow(x -> !ismissing(x) && slower(String(x)) == region_key); view=true)
    end
    if region_df === nothing || isempty(region_df)
        println(t(:info_region_no_data; region=actual))
        return
    end

    region_df = DataFrame(region_df)

    country = hasproperty(region_df, :Country) ? unique([string(c) for c in region_df.Country if c !== missing]) : String[]
    country_label = isempty(country) ? "Unknown" : country[1]

    println(t(:region_overview_header; region=actual))
    println(t(:region_overview_stats; country=country_label, rows=nrow(region_df), start=string(minimum(region_df.Date)), stop=string(maximum(region_df.Date))))
    if monthly_table === nothing
        print_active_weights(weights)
    end

    print_current_month_overview(region_df)
    events = region_top_snow_events(region_df; top_n=5)
    if !isempty(events)
        println()
        println(t(:region_top_snow_days))
        styled_table(events)
    end

    recent = recent_conditions(region_df; recent_days=14)
    if !isempty(recent)
        println()
        println(t(:region_recent_conditions))
        styled_table(recent)
    end

    history_df = print_region_history(region_df, actual; months=12)

    current_score = nothing
    current_score_month = nothing
    if monthly_table isa DataFrame && !isempty(monthly_table) && :Region in names(monthly_table)
        region_current = filter(:Region => x -> x !== missing && slower(String(x)) == slower(actual), monthly_table)
        if !isempty(region_current)
            if :WeightedScore ∉ names(region_current)
                add_weighted_score!(region_current, weights)
            end
            if :WeightedScore in names(region_current)
                value = region_current[1, :WeightedScore]
                if value !== missing
                    current_score = Float64(value)
                    current_score_month = (:Month in names(region_current)) ? region_current[1, :Month] : nothing
                    month_label = current_score_month isa Date ? Dates.format(current_score_month, "yyyy-mm") : "aktuell"
                    println(@sprintf("[INFO] Gewichteter Score (aktuelle Gewichte, %s): %.2f", month_label, current_score))
                end
            end
        end
    end

    score_history = history_df isa DataFrame ? copy(history_df) : DataFrame()
    score_plot_path = nothing
    score_plot_ok = true
    if !isempty(score_history)
        add_weighted_score!(score_history, weights)
        if :WeightedScore in names(score_history)
            sort!(score_history, :Month)
            valid_scores = filter(:WeightedScore => x -> x !== missing, score_history)
            if current_score === nothing && !isempty(valid_scores)
                latest = valid_scores[end, :]
                println(@sprintf("[INFO] Gewichteter Score (aktuelle Gewichte, %s): %.2f",
                    Dates.format(latest[:Month], "yyyy-mm"), Float64(latest[:WeightedScore])))
            end
            try
                score_plot_path = save_region_score_trend(score_history, actual)
            catch err
                score_plot_ok = false
                @warn "Unable to save score trend plot" region=actual exception=(err, catch_backtrace())
            end
        end
    end
    if score_plot_path !== nothing
        println(t(:info_score_plot_saved; path=score_plot_path))
    elseif score_plot_ok
        println(t(:info_score_plot_skipped))
    end

    prompt_region_metric_plots(region_df, actual; env_selection=get(ENV, "REGION_METRICS", nothing))
end
