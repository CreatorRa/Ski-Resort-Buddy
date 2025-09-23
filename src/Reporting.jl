const HEADER_CRAYON   = PrettyTables.Crayon(foreground=:cyan, bold=true)
const STRIPE_CRAYON   = PrettyTables.Crayon(background=:blue)
const NUMERIC_CRAYON  = PrettyTables.Crayon(foreground=:white)
const POSITIVE_CRAYON = PrettyTables.Crayon(foreground=:green, bold=true)
const NEGATIVE_CRAYON = PrettyTables.Crayon(foreground=:red, bold=true)

const TABLE_HIGHLIGHTERS = [
    PrettyTables.TextHighlighter((data, i, j) -> data[i, j] isa Number, NUMERIC_CRAYON),
    PrettyTables.TextHighlighter((data, i, j) -> iseven(i), STRIPE_CRAYON; merge=true),
    PrettyTables.TextHighlighter((data, i, j) -> data[i, j] isa Number && data[i, j] > 0, POSITIVE_CRAYON; merge=true),
    PrettyTables.TextHighlighter((data, i, j) -> data[i, j] isa Number && data[i, j] < 0, NEGATIVE_CRAYON; merge=true)
]

styled_table(data; kwargs...) = pretty_table(data; highlighters=TABLE_HIGHLIGHTERS, kwargs...)

function collect_valid(v)
    out = Float64[]
    for x in v
        if x === missing || x === nothing
            continue
        end
        xv = try
            Float64(x)
        catch
            continue
        end
        if !isnan(xv)
            push!(out, xv)
        end
    end
    return out
end

metric_stats(values::Vector{Float64}) = isempty(values) ? DataFrame(Statistic=String[], Value=Any[]) : DataFrame(
    Statistic = ["Count","Mean","Median","Minimum","Maximum","Std. Deviation"],
    Value = Any[
        length(values),
        round(mean(values); digits=2),
        round(median(values); digits=2),
        round(minimum(values); digits=2),
        round(maximum(values); digits=2),
        length(values) > 1 ? round(std(values); digits=2) : 0.0
    ]
)

function print_data_preview(df::DataFrame; limit::Int=5)
    rows = min(limit, nrow(df))
    println("\n== Data Preview — first $(rows) rows ==")
    styled_table(first(df, rows))
    if nrow(df) > rows
        println("\n== Data Preview — last $(rows) rows ==")
        styled_table(last(df, rows))
    end
end

function current_month_subset(df::DataFrame)
    if !hasproperty(df, :Date) || isempty(df)
        return (Date(0), DataFrame())
    end
    today = Dates.today()
    subset = filter(:Date => d -> month(d) == month(today) && year(d) == year(today), df)
    label_date = today
    if isempty(subset)
        label_date = maximum(df.Date)
        subset = filter(:Date => d -> month(d) == month(label_date) && year(d) == year(label_date), df)
    end
    return (label_date, subset)
end

function print_current_month_overview(df::DataFrame)
    label_date, subset = current_month_subset(df)
    label = isempty(subset) ? "n/a" : string(Dates.monthname(month(label_date)), " ", year(label_date))
    println("\n== Current Month Overview — $(label) ==")
    if isempty(subset)
        println("[INFO] No data for the current or latest month.")
        return
    end
    metrics = [
        Symbol("Temperature (°C)"),
        Symbol("Snow Depth (cm)"),
        Symbol("Snow_New (cm)"),
        Symbol("Precipitation (mm)"),
        Symbol("Wind (Beaufort)")
    ]
    rows = NamedTuple{(:Metric, :Average, :Minimum, :Maximum),Tuple{String,Float64,Float64,Float64}}[]
    for metric in metrics
        if hasproperty(subset, metric)
            vals = collect_valid(subset[!, metric])
            isempty(vals) && continue
            push!(rows, (Metric=string(metric), Average=round(mean(vals); digits=2), Minimum=round(minimum(vals); digits=2), Maximum=round(maximum(vals); digits=2)))
        end
    end
    if isempty(rows)
        println("[INFO] No numeric metrics available to summarise.")
        return
    end
    styled_table(DataFrame(rows))
end

safe_stat(v, f::Function) = (vals = collect_valid(v); isempty(vals) ? missing : f(vals))

function metric_group_summary(df::DataFrame; groupcol::Symbol, ycol::Symbol)
    if !hasproperty(df, groupcol) || !hasproperty(df, ycol)
        return
    end
    grouped = combine(groupby(df, groupcol),
        ycol => (v -> length(collect_valid(v))) => :Count,
        ycol => (v -> safe_stat(v, mean)) => :Average,
        ycol => (v -> safe_stat(v, median)) => :Median,
        ycol => (v -> safe_stat(v, minimum)) => :Min,
        ycol => (v -> safe_stat(v, maximum)) => :Max
    )
    isempty(grouped) && return
    sort!(grouped, :Average, rev=true, by=x -> x isa Missing ? -Inf : Float64(x))
    for col in (:Average, :Median, :Min, :Max)
        grouped[!, col] = map(x -> x isa Missing ? missing : round(x; digits=2), grouped[!, col])
    end
    println("\n== $(String(ycol)) — by $(String(groupcol)) ==")
    styled_table(grouped)
end

function recent_conditions(df::DataFrame; recent_days::Int=14)
    if isempty(df)
        return DataFrame()
    end
    start_idx = max(nrow(df) - recent_days + 1, 1)
    cols = Symbol[:Date]
    for col in (:Region, :Country)
        hasproperty(df, col) && push!(cols, col)
    end
    slice = df[start_idx:end, cols]
    for col in (Symbol("Temperature (°C)"), Symbol("Snow Depth (cm)"), Symbol("Snow_New (cm)"), Symbol("Precipitation (mm)"), Symbol("Wind (Beaufort)"))
        if hasproperty(df, col)
            slice[!, col] = df[start_idx:end, col]
        end
    end
    return slice
end

function print_daily_scoreboard(df::DataFrame; top_n::Int=5)
    snow_col = Symbol("Snow_New (cm)")
    if !hasproperty(df, :Date) || !hasproperty(df, snow_col)
        println("\n[INFO] Unable to build the daily snowfall leaderboard (missing required columns).")
        return DataFrame()
    end
    if isempty(df)
        println("\n[INFO] No rows available for the daily snowfall leaderboard.")
        return DataFrame()
    end
    today = Dates.today()
    day_df = filter(:Date => d -> d == today, df)
    label = "today ($(string(today)))"
    if isempty(day_df)
        latest_date = maximum(df.Date)
        day_df = filter(:Date => d -> d == latest_date, df)
        label = "latest available date ($(string(latest_date)))"
    end
    if isempty(day_df)
        println("\n[INFO] No data rows match the latest available date for the daily snowfall leaderboard.")
        return DataFrame()
    end
    day_df = copy(day_df)
    sort!(day_df, snow_col, rev=true, by=x -> x isa Missing ? -Inf : Float64(x))
    count = min(top_n, nrow(day_df))
    day_df = day_df[1:count, :]

    scoreboard = DataFrame(
        Rank = collect(1:count),
        Region = hasproperty(day_df, :Region) ? map(x -> string(x), day_df.Region) : fill("n/a", count),
        Country = hasproperty(day_df, :Country) ? map(x -> string(x), day_df.Country) : fill("n/a", count),
        Elevation = hasproperty(day_df, Symbol("Elevation (m)")) ? day_df[!, Symbol("Elevation (m)")] : fill(missing, count),
        SnowNew = day_df[!, snow_col],
        Temperature = hasproperty(day_df, Symbol("Temperature (°C)")) ? day_df[!, Symbol("Temperature (°C)")] : fill(missing, count)
    )

    scoreboard.Elevation = map(x -> x === missing || x === nothing ? missing : round(Float64(x); digits=0), scoreboard.Elevation)
    scoreboard.SnowNew = round.(coalesce.(scoreboard.SnowNew, 0.0); digits=1)
    scoreboard.Temperature = map(x -> x === missing || x === nothing ? missing : round(Float64(x); digits=1), scoreboard.Temperature)

    rename!(scoreboard, Dict(
        :Elevation => Symbol("Elevation (m)"),
        :SnowNew => Symbol("Snow_New (cm)"),
        :Temperature => Symbol("Temperature (°C)")
    ))

    println("\n== Daily Snowfall Leaderboard — $(label) ==")
    styled_table(scoreboard)
    return scoreboard
end

function print_monthly_overview_for_all_regions(df::DataFrame)
    if !hasproperty(df, :Date)
        println("\n[INFO] No Date column available - cannot build the monthly overview.")
        return (table=DataFrame(), label="")
    end
    metrics_map = [
        (Symbol("Temperature (°C)"), Symbol("Avg Temperature (°C)")),
        (Symbol("Precipitation (mm)"), Symbol("Avg Precipitation (mm)")),
        (Symbol("Wind (Beaufort)"), Symbol("Avg Wind (Beaufort)")),
        (Symbol("Snow Depth (cm)"), Symbol("Avg Snow Depth (cm)")),
        (Symbol("Snow_New (cm)"), Symbol("Avg Snow_New (cm)"))
    ]
    available_metrics = [col for (col, _) in metrics_map if hasproperty(df, col)]
    if isempty(available_metrics)
        println("\n[INFO] No numeric metrics available to build the monthly overview.")
        return (table=DataFrame(), label="")
    end

    month_df = transform(copy(df), :Date => ByRow(d -> Date(year(d), month(d), 1)) => :Month)
    unique_months = unique(month_df.Month)
    if isempty(unique_months)
        println("\n[INFO] Monthly overview not available (no month values detected).")
        return (table=DataFrame(), label="")
    end
    focus_month = maximum(unique_months)
    month_subset = filter(:Month => m -> m == focus_month, month_df)
    if isempty(month_subset)
        println("\n[INFO] No rows for the monthly overview.")
        return (table=DataFrame(), label="")
    end

    group_cols = [:Region]
    if hasproperty(month_subset, :Country)
        push!(group_cols, :Country)
    end

    transformations = Any[nrow => :Observations]
    for (col, label) in metrics_map
        hasproperty(month_subset, col) || continue
        push!(transformations, col => (v -> safe_stat(v, mean)) => label)
    end

    aggregated = combine(groupby(month_subset, group_cols), transformations...)
    if isempty(aggregated)
        println("\n[INFO] Monthly overview could not be generated (empty grouping result).")
        return (table=DataFrame(), label="")
    end

    for col in names(aggregated)
        if col in group_cols || col == :Observations
            continue
        end
        column_data = aggregated[!, col]
        if all(x -> x === missing || x isa Number, column_data)
            aggregated[!, col] = map(x -> x === missing ? missing : round(Float64(x); digits=2), column_data)
        end
    end

    sort_col = Symbol("Avg Snow_New (cm)")
    if sort_col in names(aggregated)
        sort!(aggregated, sort_col, rev=true, by=x -> x isa Missing ? -Inf : Float64(x))
    end

    month_label = Dates.format(focus_month, "yyyy-mm")
    println("\n== Monthly Overview - Regional Averages for $(month_label) ==")
    styled_table(aggregated)
    return (table=aggregated, label=month_label)
end

function print_decision_hints(scoreboard::DataFrame, monthly_table::DataFrame)
    println("\n== Decision Support ==")
    hints = String[]
    if !isempty(scoreboard) && all(col -> col in names(scoreboard), [Symbol("Region"), Symbol("Snow_New (cm)")])
        top_row = scoreboard[1, :]
        snow_val = top_row[Symbol("Snow_New (cm)")]
        snow_label = (snow_val === missing || snow_val === nothing) ? "" : string(round(Float64(snow_val); digits=1)) * " cm"
        push!(hints, "Fresh powder in $(top_row.Region) $(snow_label)")
    end

    function best_hint(df::DataFrame, col::Symbol; rev::Bool=false, label::String="", unit::String="")
        col ∈ names(df) || return nothing
        vals = collect(skipmissing(df[!, col]))
        isempty(vals) && return nothing
        target = (rev ? maximum(vals) : minimum(vals))
        idx = findfirst(x -> x !== missing && isapprox(x, target; atol=1e-6), df[!, col])
        idx === nothing && return nothing
        region = df[idx, :Region]
        if region === missing || strip(string(region)) == ""
            return nothing
        end
        return "$(label): $(region) (avg $(round(target; digits=2))$(unit))"
    end

    cold_hint = best_hint(monthly_table, Symbol("Avg Temperature (°C)"); label="Coldest regions", unit="°C")
    cold_hint !== nothing && push!(hints, cold_hint)

    calm_hint = best_hint(monthly_table, Symbol("Avg Wind (Beaufort)"); label="Calmest wind spots", unit=" Bft")
    calm_hint !== nothing && push!(hints, calm_hint)

    wettest_hint = best_hint(monthly_table, Symbol("Avg Precipitation (mm)"); rev=true, label="Highest precipitation", unit=" mm")
    wettest_hint !== nothing && push!(hints, wettest_hint)

    if isempty(hints)
        println("No quick suggestions available - please adjust filters.")
    else
        for h in hints
            println(" - " * h)
        end
    end
end

function qc_checks(df::DataFrame)
    println("\n== QC Checks ==")
    issues = false

    if all(x -> hasproperty(df, x), [:Region, :Date])
        for (grp, sub) in pairs(groupby(df, :Region))
            sort!(sub, :Date)
            dmin, dmax = sub.Date[1], sub.Date[end]
            expected = collect(dmin:Day(1):dmax)
            have = Set(sub.Date)
            missing = [d for d in expected if !(d in have)]
            if !isempty(missing)
                issues = true
                println(@sprintf("[GAP] %s missing %d days (e.g., %s)", grp, length(missing), string(missing[1])))
            end
        end
    end

    if hasproperty(df, Symbol("Snow Depth (cm)"))
        negatives = count(x -> x < 0, df[!, Symbol("Snow Depth (cm)")])
        if negatives > 0
            issues = true
            println(@sprintf("[QC] %d snow depth values are negative", negatives))
        end
    end

    if hasproperty(df, Symbol("Precipitation (mm)"))
        neg_precip = count(x -> x < 0, df[!, Symbol("Precipitation (mm)")])
        if neg_precip > 0
            issues = true
            println(@sprintf("[QC] %d precipitation entries are negative", neg_precip))
        end
    end

    if hasproperty(df, Symbol("Snow_New (cm)"))
        n = count(x -> x < 0, df[!, Symbol("Snow_New (cm)")])
        if n > 0
            issues = true
            println(@sprintf("[QC] %d new snow entries are negative", n))
        end
    end

    if hasproperty(df, Symbol("Temperature (°C)"))
        t = df[!, Symbol("Temperature (°C)")]
        nbad = count(x -> x < -60 || x > 50, t)
        if nbad > 0
            issues = true
            println(@sprintf("[OUTLIER] %d temperature values outside [-60,50]°C", nbad))
        end
    end

    if !issues
        println("No anomalies detected.")
    end
end

function print_region_history(df::DataFrame, region_name::Union{Nothing,AbstractString}; months::Int=12)
    if isnothing(region_name)
        return
    end
    if !hasproperty(df, :Date) || isempty(df)
        println("\n[INFO] No data available for region $(region_name). Adjust filters or check the region name.")
        return
    end
    region_df = hasproperty(df, :Region) ? filter(:Region => x -> !ismissing(x) && slower(x) == slower(region_name), df) : df
    if isempty(region_df)
        println("\n[INFO] No data available for region $(region_name). Adjust filters or check the region name.")
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
        println("\n[INFO] No monthly aggregates available for region $(region_name).")
        return
    end

    sort!(grouped, :Month)
    grouped.Month = Dates.format.(grouped.Month, "yyyy-mm")
    for col in (:AvgTemperature, :AvgSnowDepth, :TotalNewSnow, :AvgPrecipitation, :AvgWind)
        if col in names(grouped)
            grouped[!, col] = map(x -> x isa Missing ? missing : round(x; digits=2), grouped[!, col])
        end
    end

    rename!(grouped, Dict(
        :AvgTemperature => Symbol("Avg Temperature (°C)"),
        :AvgSnowDepth => Symbol("Avg Snow Depth (cm)"),
        :TotalNewSnow => Symbol("Total New Snow (cm)"),
        :AvgPrecipitation => Symbol("Avg Precipitation (mm)"),
        :AvgWind => Symbol("Avg Wind (Beaufort)")
    ))

    println("\n== Region Insights — $(region_name) (last $(months) months) ==")
    styled_table(grouped)
end

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

function save_region_snow_plot(region_df::DataFrame, region_name::AbstractString; recent_days::Int=90)
    required_cols = (:Date, Symbol("Snow Depth (cm)"))
    if any(col -> !hasproperty(region_df, col), required_cols)
        return nothing
    end

    ensure_plots_ready() || return nothing

    local_df = sort(copy(region_df), :Date)
    if recent_days > 0 && nrow(local_df) > recent_days
        local_df = local_df[end - recent_days + 1:end, :]
    end
    isempty(local_df) && return nothing

    dates = local_df[!, :Date]
    depth_dates, depth_values = clean_numeric_series(dates, local_df[!, Symbol("Snow Depth (cm)")])
    isempty(depth_values) && return nothing

    plot_obj = plot(depth_dates, depth_values;
        label="Snow depth (cm)",
        color=:dodgerblue,
        linewidth=2,
        xlabel="Date",
        ylabel="Centimetres",
        title="$(region_name) — snow trend",
        background_color=:white)

    new_col = Symbol("Snow_New (cm)")
    if hasproperty(local_df, new_col)
        new_dates, new_values = clean_numeric_series(dates, local_df[!, new_col])
        if !isempty(new_values)
            plot!(plot_obj, new_dates, new_values;
                seriestype=:bar,
                label="Daily new snow (cm)",
                color=:lightskyblue,
                alpha=0.45,
                bar_width=0.6)
        end
    end

    ensure_plot_dir()
    filename = slugify(region_name) * "_snow_trend.png"
    out_path = joinpath(PLOTS_OUTPUT_DIR, filename)
    savefig(plot_obj, out_path)
    return out_path
end

function print_available_commands()
    println()
    printstyled("Available Commands\n"; color=:cyan, bold=true)
    println("  report        - default full dashboard (this view)")
    println("  list          - list all DACH regions")
    println("  region NAME   - deep dive into a single resort (replace NAME)")
    println("  region NAME --season WINTER - seasonal regional deep dive")
    println("  list --season SUMMER  - regional rundown filtered by season")
    println()
    printstyled("Options\n"; color=:cyan, bold=true)
    println("  --from YYYY-MM-DD | --to YYYY-MM-DD | --season WINTER|SUMMER|ALL")
    println()
    printstyled("Environment\n"; color=:cyan, bold=true)
    println("  REGION, COUNTRY, CSV_PATH")
    println()
    printstyled("Quick Commands\n"; color=:cyan, bold=true)
    println("  $(COMMAND_PREFIX) report")
    println("  $(COMMAND_PREFIX) report --season WINTER")
    println("  $(COMMAND_PREFIX) region \"SELECTED_REGION\"")
end

function run_report(df::DataFrame, config::CLIConfig)
    print_active_filters(config, df)

    scoreboard = print_daily_scoreboard(df; top_n=10)
    monthly = print_monthly_overview_for_all_regions(df)
    print_decision_hints(scoreboard, monthly.table)

    selected_region = prompt_region_choice(df, scoreboard, config)
    if selected_region !== nothing
        run_region(df, selected_region)
    else
        println("\nTip: use `list` to see every region or `region <NAME>` for an immediate deep dive.")
    end

    show_full = !stdin_is_tty()
    if stdin_is_tty()
        println("\nShow extended analytics? (y/N)")
        print("> ")
        response = try
            lowercase(strip(readline()))
        catch err
            isa(err, InterruptException) && rethrow()
            ""
        end
        show_full = response in ("y", "yes", "j", "ja")
    end

    if show_full
        println("\n== Extended Data Views ==")
        if nrow(df) > 0 && hasproperty(df, :Date)
            println(@sprintf("Dataset after filters: %d rows, %d columns (%s - %s)", nrow(df), ncol(df), string(minimum(df.Date)), string(maximum(df.Date))))
        else
            println("Dataset after filters: 0 rows.")
        end

        qc_checks(df)

        for ycol in (Symbol("Temperature (°C)"), Symbol("Wind (Beaufort)"), Symbol("Precipitation (mm)"), Symbol("Snow Depth (cm)"), Symbol("Snow_New (cm)"))
            metric_group_summary(df; groupcol=:Region, ycol=ycol)
            metric_group_summary(df; groupcol=:Country, ycol=ycol)
        end
    else
        println("\nQuick overview finished. Rerun the tool with specific filters (e.g. `--season WINTER` or `REGION=Verbier`) for deeper insights.")
    end
end

run_list(df::DataFrame) = print_available_regions(available_regions(df))

function run_region(df::DataFrame, region_name::Union{Nothing,String})
    if region_name === nothing || strip(String(region_name)) == ""
        println("Please provide a region name, e.g. `$(COMMAND_PREFIX) region \"Zermatt\"`.")
        run_list(df)
        return
    end

    actual, suggestions = resolve_region_name(df, String(region_name))
    if actual === nothing
        println("Region \"$(region_name)\" not found.")
        if !isempty(suggestions)
            println("Did you mean: " * join(suggestions[1:min(5, length(suggestions))], ", ") * "?")
        end
        println("Run `list` to show all available regions.")
        return
    end

    region_df = filter(:Region => x -> !ismissing(x) && slower(String(x)) == slower(actual), df)
    if isempty(region_df)
        println("No data available for region $(actual) after applying filters.")
        return
    end

    country = hasproperty(region_df, :Country) ? unique([string(c) for c in region_df.Country if c !== missing]) : String[]
    country_label = isempty(country) ? "Unknown" : country[1]

    println("== Region Overview — $(actual) ==")
    println(@sprintf("Country: %s | Observations: %d | Date range: %s to %s", country_label, nrow(region_df), string(minimum(region_df.Date)), string(maximum(region_df.Date))))

    print_current_month_overview(region_df)
    events = region_top_snow_events(region_df; top_n=5)
    if !isempty(events)
        println("\n== Top fresh snow days ==")
        styled_table(events)
    end

    recent = recent_conditions(region_df; recent_days=14)
    if !isempty(recent)
        println("\n== Recent conditions (last 14 days) ==")
        styled_table(recent)
    end

    print_region_history(region_df, actual; months=12)

    plot_path = nothing
    plot_ok = true
    try
        plot_path = save_region_snow_plot(region_df, actual; recent_days=120)
    catch err
        plot_ok = false
        @warn "Unable to save snow trend plot" region=actual exception=(err, catch_backtrace())
    end
    if plot_path !== nothing
        println("\n[INFO] Snow trend plot saved to: $(plot_path)")
    elseif plot_ok
        println("\n[INFO] Snow trend plot skipped (missing numeric data).")
    end
end
