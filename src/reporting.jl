"""
Reporting and visualisation layer: formats terminal output, aggregates metrics,
and generates plots/prompts for both interactive and scripted dashboard flows.
"""

using Dates
using DataFrames
using Plots
using PrettyTables

const HEADER_CRAYON = PrettyTables.Crayon(foreground=:cyan, bold=true)
const STRIPE_CRAYON = PrettyTables.Crayon(background=:blue)
const POSITIVE_CRAYON = PrettyTables.Crayon(foreground=:green, bold=true)
const NEGATIVE_CRAYON = PrettyTables.Crayon(foreground=:red, bold=true)

const TABLE_HIGHLIGHTERS = [
    PrettyTables.TextHighlighter((data, i, j) -> iseven(i), STRIPE_CRAYON),
    PrettyTables.TextHighlighter((data, i, j) -> data[i, j] isa Number && data[i, j] > 0, POSITIVE_CRAYON),
    PrettyTables.TextHighlighter((data, i, j) -> data[i, j] isa Number && data[i, j] < 0, NEGATIVE_CRAYON)
]

const REGION_METRIC_OPTIONS = (
    (key=:snow_depth, column=Symbol("Snow Depth (cm)"), display="Schneehöhe (cm)", color=:dodgerblue, window=7, recent_days=180, plot=:line),
    (key=:snow_new, column=Symbol("Snow_New (cm)"), display="Neuschnee (cm)", color=:lightskyblue, window=5, recent_days=120, plot=:bar),
    (key=:temperature, column=Symbol("Temperature (°C)"), display="Temperatur (°C)", color=:tomato, window=7, recent_days=180, plot=:line),
    (key=:precipitation, column=Symbol("Precipitation (mm)"), display="Niederschlag (mm)", color=:seagreen, window=7, recent_days=180, plot=:line),
    (key=:wind, column=Symbol("Wind (Beaufort)"), display="Wind (Beaufort)", color=:goldenrod, window=7, recent_days=180, plot=:line)
)

"""
    styled_table(data; kwargs...)

Wrapper around `pretty_table` that applies consistent highlighters for alternating
rows and positive/negative values across all reports.
"""
function styled_table(data; kwargs...)
    pretty_table(data; highlighters=TABLE_HIGHLIGHTERS, kwargs...)
end

"""
    lookup_column(df, col)

Return a column identifier compatible with `df`, handling both Symbol and String
column names. Returns `nothing` when the column does not exist.
"""
function lookup_column(df::DataFrame, col::Symbol)
    if col in names(df)
        return col
    end
    str = String(col)
    if str in names(df)
        return str
    end
    return nothing
end

function build_region_index(df::DataFrame)
    region_index = Dict{String,DataFrame}()
    if hasproperty(df, :Region)
        for sub in groupby(df, :Region)
            key = first(sub.Region)
            key === missing && continue
            region_index[slower(String(key))] = DataFrame(sub)
        end
    end
    return region_index
end

function prompt_session_finish(config::CLIConfig)
    config.command == :menu && return
    stdin_is_tty() || return
    println("\nTool beenden? (q = Quit, Enter = zurück)")
    print("> ")
    response = try
        lowercase(strip(readline()))
    catch err
        isa(err, InterruptException) && rethrow()
        ""
    end
    if response in ("q", "quit", "y", "yes", "j", "ja")
        println("Auf Wiedersehen!")
    end
end

"""
    qc_checks(df)

Run a series of lightweight quality checks on the filtered dataset, printing warnings
for missing days or implausible metric values.
"""
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
                println(@sprintf("[MISSING] Region=%s: %d missing days (%s%s)", string(grp[1][2]), length(missing), join(string.(missing[1:min(end,10)]), ", "), length(missing)>10 ? ", …" : ""))
            end
        end
    end

    if hasproperty(df, Symbol("Wind (Beaufort)"))
        w = df[!, Symbol("Wind (Beaufort)")]
        n = count(>(12), w)
        if n > 0
            issues = true
            println(@sprintf("[OUTLIER] %d wind values > 12 Beaufort", n))
        end
    end
    if hasproperty(df, Symbol("Precipitation (mm)"))
        p = df[!, Symbol("Precipitation (mm)")]
        n = count(<(0), p)
        if n > 0
            issues = true
            println(@sprintf("[OUTLIER] %d negative precipitation values", n))
        end
    end
    if hasproperty(df, Symbol("Snow Depth (cm)"))
        s = df[!, Symbol("Snow Depth (cm)")]
        n = count(<(0), s)
        if n > 0
            issues = true
            println(@sprintf("[OUTLIER] %d negative snow depth values", n))
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

"""
    add_weighted_score!(df, weights)

Compute a weighted composite metric using the provided weights and append it as the
`WeightedScore` column. Missing or constant series fall back to neutral values.
"""
function add_weighted_score!(df::DataFrame, weights::Dict{Symbol,Float64})
    isempty(df) && return df
    scores = zeros(Float64, nrow(df))
    contributed = falses(nrow(df))
    any_metric = false
    current_names = names(df)
    for (key, cfg) in METRIC_WEIGHT_CONFIG
        weight = get(weights, key, 0.0)
        weight == 0.0 && continue
        column = cfg.column
        colref = column in current_names ? column : (String(column) in current_names ? String(column) : nothing)
        if colref === nothing
            continue
        end
        vals = df[!, colref]
        valid = collect(skipmissing(vals))
        isempty(valid) && continue
        minv = minimum(valid)
        maxv = maximum(valid)
        rangev = maxv - minv
        any_metric = true
        for (idx, raw) in enumerate(vals)
            raw === missing && continue
            v = Float64(raw)
            normalized = rangev == 0 ? 0.5 : (v - minv) / rangev
            if get(cfg, :preference, :higher) == :lower
                normalized = 1 - normalized
            end
            normalized = clamp(normalized, 0.0, 1.0)
            scores[idx] += weight * normalized
            contributed[idx] = true
        end
    end
    if any_metric
        df[!, :WeightedScore] = map(eachindex(scores)) do i
            contributed[i] ? round(scores[i]; digits=3) : missing
        end
    else
        df[!, :WeightedScore] = fill(missing, nrow(df))
    end
    return df
end

"""
    print_data_preview(df; limit=5)

Show the first and last `limit` rows of the DataFrame using the shared table styling,
helpful for quick sanity checks.
"""
function print_data_preview(df::DataFrame; limit::Int=5)
    rows = min(limit, nrow(df))
    println("\n== Data Preview — first $(rows) rows ==")
    styled_table(first(df, rows))
    if nrow(df) > rows
        println("\n== Data Preview — last $(rows) rows ==")
        styled_table(last(df, rows))
    end
end

"""
    current_month_subset(df)

Return the current (or latest available) month label and the DataFrame rows
belonging to that month. When the dataset lacks dates, a sentinel `(Date(0),
DataFrame())` tuple is returned.
"""
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

"""
    print_current_month_overview(df)

Summarise key metrics for the current (or latest) month, printing averages and
extremes where data is available, and friendly info messages otherwise.
"""
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

"""
    safe_stat(values, reducer)

Apply `reducer` to the numeric subset of `values`, returning `missing` when no
valid entries are present.
"""
function safe_stat(v, f::Function)
    vals = collect_valid(v)
    isempty(vals) && return missing
    return f(vals)
end

"""
    metric_group_summary(df; groupcol, ycol)

Group `df` by `groupcol` (e.g., Region or Country) and tabulate counts plus summary
statistics for the metric column `ycol`. No output is produced when prerequisites are
missing.
"""
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

"""
    recent_conditions(df; recent_days=14)

Return a slice of the last `recent_days` observations, including available metrics and
identifying columns (`Date`, `Region`, `Country`).
"""
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

"""
    print_daily_scoreboard(df; top_n=5)

Generate and display a ranked table of daily snowfall leaders for the most recent day
with data, returning the table as a DataFrame for further processing.
"""
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

"""
    print_monthly_overview_for_all_regions(df; weights=DEFAULT_METRIC_WEIGHTS, display=true)

Aggregate the most recent month of data per region (and optional country), compute
summaries for the configured metrics, and add a weighted score used for ranking.
When `display` is `false`, the table is returned silently for reuse in other views.
"""
function print_monthly_overview_for_all_regions(df::DataFrame; weights::Dict{Symbol,Float64}=DEFAULT_METRIC_WEIGHTS, display::Bool=true)
    if !hasproperty(df, :Date)
        display && println("\n[INFO] No Date column available - cannot build the monthly overview.")
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
        display && println("\n[INFO] No numeric metrics available to build the monthly overview.")
        return (table=DataFrame(), label="")
    end

    month_df = transform(copy(df), :Date => ByRow(d -> Date(year(d), month(d), 1)) => :Month)
    unique_months = unique(month_df.Month)
    if isempty(unique_months)
        display && println("\n[INFO] Monthly overview not available (no month values detected).")
        return (table=DataFrame(), label="")
    end
    focus_month = maximum(unique_months)
    month_subset = filter(:Month => m -> m == focus_month, month_df)
    if isempty(month_subset)
        display && println("\n[INFO] No rows for the monthly overview.")
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
    if !isempty(aggregated)
        current = names(aggregated)
        rename!(aggregated, Pair.(current, Symbol.(string.(current))))
    end
    if isempty(aggregated)
        display && println("\n[INFO] Monthly overview could not be generated (empty grouping result).")
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

    add_weighted_score!(aggregated, weights)

    sort_col = if :WeightedScore in names(aggregated) && any(x -> x !== missing, aggregated[!, :WeightedScore])
        :WeightedScore
    else
        Symbol("Avg Snow_New (cm)")
    end

    if sort_col in names(aggregated)
        sort!(aggregated, sort_col, rev=true, by=x -> x isa Missing ? -Inf : Float64(x))
    end

    month_label = Dates.format(focus_month, "yyyy-mm")
    if display
        println("\n== Monthly Overview - Regional Averages for $(month_label) ==")
        styled_table(aggregated)
    end
    return (table=aggregated, label=month_label)
end

"""
    print_weighted_ranking(monthly_table, month_label; top_n=10)

Display a concise ranking table derived from the monthly overview, listing the top
regions according to the weighted score.
"""
function print_weighted_ranking(monthly_table::DataFrame, month_label::AbstractString; top_n::Int=10)
    if isempty(monthly_table)
        println("\n[INFO] Kein Ranking verfügbar. Prüfe deine Filter oder Datenlage.")
        return DataFrame()
    end
    local_table = copy(monthly_table)
    if !(:WeightedScore in names(local_table)) && !("WeightedScore" in names(local_table))
        add_weighted_score!(local_table, DEFAULT_METRIC_WEIGHTS)
    end

    if !(:WeightedScore in names(local_table)) && !("WeightedScore" in names(local_table))
        println("\n[INFO] Gewichteter Score nicht verfügbar – Ranking wird übersprungen.")
        return DataFrame()
    end

    score_col = :WeightedScore in names(local_table) ? :WeightedScore : "WeightedScore"
    valid_rows = filter(score_col => x -> x !== missing, local_table)
    if isempty(valid_rows)
        println("\n[INFO] Keine gültigen Score-Werte vorhanden – Ranking wird übersprungen.")
        return DataFrame()
    end

    sort!(valid_rows, score_col, rev=true, by=x -> Float64(x))
    count = min(top_n, nrow(valid_rows))
    ranked = valid_rows[1:count, :]

    rank_df = DataFrame(
        Rank = collect(1:count),
        Region = hasproperty(ranked, :Region) ? map(x -> string(x), ranked.Region) : map(_ -> "n/a", 1:count),
        Country = hasproperty(ranked, :Country) ? map(x -> x === missing ? "n/a" : string(x), ranked.Country) : fill("n/a", count),
        Score = round.(Float64.(ranked[!, score_col]); digits=2)
    )

    label = isempty(month_label) ? "" : " (" * month_label * ")"
    println("\n== Top Ski-Regionen nach Gewichtung$(label) ==")
    styled_table(rank_df)
    return rank_df
end

"""
    print_active_filters(config, df)

Print the currently active season/date/region/country filters along with dataset row
counts so users understand the scope of subsequent tables.
"""
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
    if config.menu_country !== nothing
        println(" - Country filter (menu): $(config.menu_country)")
    elseif haskey(ENV, "COUNTRY")
        println(" - Country filter (ENV): " * ENV["COUNTRY"])
    else
        println(" - No country preselected")
    end
    if !isempty(df) && hasproperty(df, :Date)
        println(" - Observations after filters: $(nrow(df)) rows, window $(string(minimum(df.Date))) - $(string(maximum(df.Date)))")
    else
        println(" - No data available after applying filters")
    end
end

"""
    print_active_weights(weights)

Print the currently normalised weights as percentages and show the sum of absolute
weights for reference.
"""
function print_active_weights(weights::Dict{Symbol,Float64})
    println("\n== Aktive Gewichte ==")
    for (key, cfg) in METRIC_WEIGHT_CONFIG
        value = get(weights, key, 0.0)
        label = get(cfg, :label, string(key))
        preference = get(cfg, :preference, :higher) == :lower ? " (weniger ist besser)" : ""
        println(" - $(label): $(round(value; digits=2))%" * preference)
    end
    total = round(sum(values(weights)); digits=2)
    println("   Summe = $(total)%")
end

"""
    prompt_region_choice(df, scoreboard, config)

Ask the user to pick a region for deeper analysis, offering suggestions from the
scoreboard or the full region list. Returns the resolved region name or `nothing`.
"""
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

"""
    print_decision_hints(scoreboard, monthly_table, weights)

Derive narrative tips from the current leaderboard and weighted monthly overview,
pointing users toward notable regions (powder, calm wind, precipitation extremes).
"""
function print_decision_hints(scoreboard::DataFrame, monthly_table::DataFrame, weights::Dict{Symbol,Float64})
    println("\n== Decision Support ==")
    hints = String[]
    if !isempty(scoreboard) && all(col -> col in names(scoreboard), [Symbol("Region"), Symbol("Snow_New (cm)")])
        top_row = scoreboard[1, :]
        snow_val = top_row[Symbol("Snow_New (cm)")]
        snow_label = (snow_val === missing || snow_val === nothing) ? "" : string(round(Float64(snow_val); digits=1)) * " cm"
        push!(hints, "Fresh powder in $(top_row.Region) $(snow_label)")
    end

    if :WeightedScore in names(monthly_table)
        best_idx = nothing
        best_score = -Inf
        for (idx, score) in enumerate(monthly_table[!, :WeightedScore])
            if score === missing
                continue
            end
            if score > best_score
                best_score = score
                best_idx = idx
            end
        end
        if best_idx !== nothing
            region_name = monthly_table[best_idx, :Region]
            region_name !== missing && push!(hints, @sprintf("Beste Gesamtwertung: %s (Score %.2f)", string(region_name), best_score))
        end
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

"""
    print_region_history(df, region_name; months=12)

Display per-month averages and totals for the chosen region across the past `months`
period, offering historical context in the regional deep dive view.
"""
function print_region_history(df::DataFrame, region_name::Union{Nothing,AbstractString}; months::Int=12)
    if isnothing(region_name)
        return DataFrame()
    end
    if !hasproperty(df, :Date) || isempty(df)
        println("\n[INFO] No data available for region $(region_name). Adjust filters or check the region name.")
        return DataFrame()
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

    println("\n== Region Insights — $(region_name) (last $(months) months) ==")
    styled_table(display_df)

    return grouped
end

"""
    region_top_snow_events(df; top_n=5)

Return the top `top_n` snowfall gain days for a region, including optional snow depth
and temperature context when available.
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
    save_region_snow_plot(region_df, region_name; recent_days=90)

Create a combined line/bar chart of snow depth and new snow for the specified region
and save it as a PNG. Returns the written path or `nothing` when plotting is skipped.
"""
function save_region_snow_plot(region_df::DataFrame, region_name::AbstractString; recent_days::Int=90)
    required_cols = (:Date, Symbol("Snow Depth (cm)"))
    if any(col -> !hasproperty(region_df, col), required_cols)
        return nothing
    end

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

"""
    save_region_score_trend(region_monthly, region_name)

Create a line chart of the monthly weighted score for a region (with optional rolling
average) and persist it to disk. Returns the file path or `nothing` when data is
insufficient.
"""
function save_region_score_trend(region_monthly::DataFrame, region_name::AbstractString)
    if !(:Month in names(region_monthly)) || !(:WeightedScore in names(region_monthly))
        return nothing
    end

    valid = filter(:WeightedScore => x -> x !== missing, region_monthly)
    isempty(valid) && return nothing

    dates = Date.(valid.Month)
    scores = Float64.(valid[!, :WeightedScore])
    order = sortperm(dates)
    dates = dates[order]
    scores = scores[order]

    plot_obj = plot(dates, scores;
        color=:mediumpurple,
        linewidth=2,
        marker=:circle,
        markersize=4,
        xlabel="Month",
        ylabel="Weighted Score",
        title="$(region_name) — weighted score trend",
        legend=:topright,
        background_color=:white,
        label="Weighted Score")

    if length(scores) >= 3
        window = min(length(scores), 3)
        trend = rolling_mean(scores, window)
        plot!(plot_obj, dates, trend;
            color=:orange,
            linewidth=2,
            linestyle=:dash,
            label="Rolling mean (w=$(window))")
    end

    ensure_plot_dir()
    filename = slugify(region_name) * "_score_trend.png"
    out_path = joinpath(PLOTS_OUTPUT_DIR, filename)
    savefig(plot_obj, out_path)
    return out_path
end

"""
    save_region_metric_trend(region_df, region_name, option)

Persist a time-series chart for a specific regional metric configured in
`REGION_METRIC_OPTIONS`.
"""
function save_region_metric_trend(region_df::DataFrame, region_name::AbstractString, option; recent_days_override::Union{Nothing,Int}=nothing)
    local_df = sort(copy(region_df), :Date)
    recent_days = isnothing(recent_days_override) ? option.recent_days : recent_days_override
    if recent_days > 0 && nrow(local_df) > recent_days
        local_df = local_df[end - recent_days + 1:end, :]
    end
    if isempty(local_df)
        @debug "metric plot skipped: empty window" region=region_name metric=option.key
        return nothing
    end

    date_col = lookup_column(local_df, :Date)
    if date_col === nothing
        @debug "metric plot skipped: no date column" region=region_name metric=option.key
        return nothing
    end

    colref = lookup_column(local_df, option.column)
    if colref === nothing
        @debug "metric plot skipped: column missing" region=region_name metric=option.key
        return nothing
    end

    dates_raw = local_df[!, date_col]
    metric_series = local_df[!, colref]
    xs, ys = clean_numeric_series(dates_raw, metric_series)
    if isempty(ys)
        @debug "metric plot skipped: no numeric data" region=region_name metric=option.key
        return nothing
    end

    ylabel = option.display
    plot_title = "$(region_name) — $(option.display)"
    seriestype = get(option, :plot, :line)
    color = get(option, :color, :steelblue)

    if seriestype == :bar
        plot_obj = plot(xs, ys;
            seriestype=:bar,
            color=color,
            alpha=0.65,
            bar_width=0.8,
            label=option.display,
            xlabel="Datum",
            ylabel=ylabel,
            legend=:topright,
            title=plot_title,
            background_color=:white)
    else
        plot_obj = plot(xs, ys;
            seriestype=:line,
            color=color,
            linewidth=2,
            marker=:circle,
            markersize=3,
            label=option.display,
            xlabel="Datum",
            ylabel=ylabel,
            legend=:topright,
            title=plot_title,
            background_color=:white)
    end

    window = max(get(option, :window, 0), 0)
    if window >= 2 && length(ys) >= window
        trend = rolling_mean(ys, window)
        plot!(plot_obj, xs, trend;
            seriestype=:line,
            color=:darkgray,
            linewidth=2,
            linestyle=:dash,
            label="Rollender Mittelwert (w=$(window))")
    end

    ensure_plot_dir()
    metric_slug = replace(string(option.key), ":" => "")
    filename = slugify(region_name) * "_" * metric_slug * "_trend.png"
    out_path = joinpath(PLOTS_OUTPUT_DIR, filename)
    savefig(plot_obj, out_path)
    @debug "metric plot saved" region=region_name metric=option.key path=out_path
    return out_path
end

"""
    region_metric_options(df)

Return the subset of `REGION_METRIC_OPTIONS` that are available (non-empty) in the
provided `DataFrame`.
"""
function region_metric_options(df::DataFrame)
    options = NamedTuple[]
    for opt in REGION_METRIC_OPTIONS
        colref = lookup_column(df, opt.column)
        colref === nothing && continue
        values = df[!, colref]
        if any(x -> !(x === missing || x === nothing), values)
            push!(options, opt)
        end
    end
    return options
end

function resolve_metric_tokens(tokens::AbstractVector{<:AbstractString}, options::Vector{<:NamedTuple})
    selected = NamedTuple[]
    seen = Set{Symbol}()
    unknown = String[]
    isempty(tokens) && return selected, unknown
    all_keys = length(options)

    for raw in tokens
        token = strip(raw)
        token == "" && continue
        low = slower(token)
        if low in ("all", "alle", "*", "alles")
            for opt in options
                if !(opt.key in seen)
                    push!(selected, opt)
                    push!(seen, opt.key)
                end
            end
            continue
        end

        idx = tryparse(Int, token)
        if idx !== nothing && 1 <= idx <= all_keys
            opt = options[idx]
            if !(opt.key in seen)
                push!(selected, opt)
                push!(seen, opt.key)
            end
            continue
        end

        matched = nothing
        for opt in options
            if opt.key in seen
                continue
            end
            names_to_match = (slower(opt.display), slower(string(opt.key)))
            if low == names_to_match[1] || low == names_to_match[2] || occursin(low, names_to_match[1])
                matched = opt
                break
            end
        end

        if matched === nothing
            push!(unknown, token)
        else
            push!(selected, matched)
            push!(seen, matched.key)
        end
    end
    return selected, unknown
end

function generate_metric_plots(region_df::DataFrame, region_name::AbstractString, selections::Vector{<:NamedTuple})
    for opt in selections
        try
            path = save_region_metric_trend(region_df, region_name, opt)
            if path === nothing
                println(@sprintf("[INFO] Diagramm für %s wurde übersprungen (keine Daten).", opt.display))
            else
                println(@sprintf("[INFO] Diagramm für %s gespeichert unter: %s", opt.display, path))
            end
        catch err
            @warn "Unable to save metric plot" region=region_name metric=opt.key exception=(err, catch_backtrace())
        end
    end
end

function prompt_region_metric_plots(region_df::DataFrame, region_name::AbstractString; env_selection::Union{Nothing,String}=nothing)
    options = region_metric_options(region_df)
    isempty(options) && return

    env_selected = NamedTuple[]
    if env_selection !== nothing && strip(env_selection) != ""
        tokens = split(env_selection, r"[ ,;]+"; keepempty=false)
        env_selected, unknown = resolve_metric_tokens(tokens, collect(options))
        if !isempty(unknown)
            println("[WARN] REGION_METRICS unverstanden: " * join(unknown, ", "))
        end
        if !isempty(env_selected)
            println("\n[INFO] Generiere Attribute-Plots gemäß REGION_METRICS...")
            generate_metric_plots(region_df, region_name, env_selected)
        end
        if !stdin_is_tty()
            !isempty(env_selected) || println("[INFO] Keine weiteren Attribute-Plots (REGION_METRICS nicht gesetzt oder leer).")
            return
        end
    elseif !stdin_is_tty()
        println("\n[INFO] Keine TTY erkannt – Diagrammauswahl wird dennoch versucht. Setze alternativ REGION_METRICS, z. B. REGION_METRICS=\"Schneehöhe,Temperatur\".")
    end

    println("\nZusätzliche Attribute visualisieren? (Nummern oder Namen, Enter zum Überspringen)")
    println("Verfügbare Optionen:")
    option_list = collect(options)
    for (idx, opt) in enumerate(option_list)
        println(" $(idx)) $(opt.display)")
    end
    println("Beispieleingabe: 1,3 oder Schneehöhe Temperatur oder 'all'")

    while true
        print("> ")
        input = try
            strip(readline())
        catch err
            isa(err, InterruptException) && rethrow()
            ""
        end

        input == "" && return

        tokens = split(input, r"[ ,;]+"; keepempty=false)
        selections, unknown = resolve_metric_tokens(tokens, option_list)
        if !isempty(unknown)
            println("Nicht erkannt: " * join(unknown, ", "))
        end
        if isempty(selections)
            println("Bitte gültige Nummern oder Namen eingeben (Enter für Abbruch).")
            continue
        end

        generate_metric_plots(region_df, region_name, selections)

        println("\nWeitere Attribute plotten? (y/N)")
        print("> ")
        again = try
            lowercase(strip(readline()))
        catch err
            isa(err, InterruptException) && rethrow()
            ""
        end
        again in ("y", "yes", "j", "ja") || return
        println("\nNächste Auswahl (Enter zum Beenden):")
    end
end

"""
    print_available_commands()

Display a quick reference of available subcommands and environment/CLI options.
"""
function print_available_commands()
    println()
    printstyled("Available commands\n"; color=:cyan, bold=true)
    printstyled("  menu          "; color=:green, bold=true); println("- interactive terminal menu")
    printstyled("  report        "; color=:green, bold=true); println("- default full dashboard (this view)")
    printstyled("  list          "; color=:green, bold=true); println("- list all DACH regions")
    printstyled("  region NAME   "; color=:green, bold=true); println("- deep dive into a single resort (replace NAME)")
    println()
    printstyled("Options:"; color=:yellow, bold=true); println(" --from YYYY-MM-DD | --to YYYY-MM-DD | --season WINTER|SUMMER|ALL")
    printstyled("Weights:"; color=:yellow, bold=true); println(" --weight-snow-new <v> | --weight-temperature <v> | ... (Prompt via --ask-weights)")
    printstyled("Environment:"; color=:yellow, bold=true); println(" REGION, CSV_PATH, WEIGHT_SNOW_NEW, ...")
    println()
    printstyled("Quick copy:"; color=:magenta, bold=true); println(" $(COMMAND_PREFIX) menu")
    printstyled("Region example:"; color=:magenta, bold=true); println(" $(COMMAND_PREFIX) region \"Zermatt\"")
end

"""
    run_list(df)

Print the alphabetised list of regions present in the dataset.
"""
function run_list(df::DataFrame)
    print_available_regions(available_regions(df))
end

"""
    resolve_region_name(df, name)

Resolve a user-supplied region string to an exact dataset entry, returning the match
and a list of suggestions when no exact hit is found.
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

Render the region deep dive, including high-level metadata, monthly summaries, recent
conditions, historical aggregates, and plot generation for the chosen region.
"""
function run_region(df::DataFrame, region_name::Union{Nothing,String}; weights::Dict{Symbol,Float64}=DEFAULT_METRIC_WEIGHTS, monthly_table::Union{Nothing,DataFrame}=nothing, region_index::Union{Nothing,Dict{String,DataFrame}}=nothing)
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

    region_key = slower(String(actual))
    region_df = if region_index !== nothing && haskey(region_index, region_key)
        region_index[region_key]
    else
        subset(df, :Region => ByRow(x -> !ismissing(x) && slower(String(x)) == region_key); view=true)
    end
    if region_df === nothing || isempty(region_df)
        println("No data available for region $(actual) after applying filters.")
        return
    end

    region_df = DataFrame(region_df)

    country = hasproperty(region_df, :Country) ? unique([string(c) for c in region_df.Country if c !== missing]) : String[]
    country_label = isempty(country) ? "Unknown" : country[1]

    println("== Region Overview — $(actual) ==")
    println(@sprintf("Country: %s | Observations: %d | Date range: %s to %s", country_label, nrow(region_df), string(minimum(region_df.Date)), string(maximum(region_df.Date))))
    if monthly_table === nothing
        print_active_weights(weights)
    end

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

    history_df = print_region_history(region_df, actual; months=12)

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
        println("[INFO] Score trend plot saved to: $(score_plot_path)")
    elseif score_plot_ok
        println("[INFO] Score trend plot skipped (insufficient data).")
    end

    prompt_region_metric_plots(region_df, actual; env_selection=get(ENV, "REGION_METRICS", nothing))
end

"""
    run_report(df, config, weights)

Drive the primary reporting workflow: display filters and weights, show leaderboards
and monthly aggregates, prompt for a region deep dive, and optionally extend with
detailed analytics.
"""
function run_report(df::DataFrame, config::CLIConfig, weights::Dict{Symbol,Float64})
    print_active_filters(config, df)
    print_active_weights(weights)

    monthly = print_monthly_overview_for_all_regions(df; weights=weights, display=false)
    ranked = print_weighted_ranking(monthly.table, monthly.label)
    region_index = build_region_index(df)
    prompt_region_details(df, ranked; config=config, weights=weights, monthly_table=monthly.table, region_index=region_index)
end

"""
    prompt_region_details(df, ranking; config, weights, monthly_table)

Offer an interactive prompt (when running in a TTY) so users can inspect one or more
regions from the weighted ranking. Falls back to a hint for non-interactive runs.
"""
function prompt_region_details(df::DataFrame, ranking::DataFrame; config::CLIConfig, weights::Dict{Symbol,Float64}, monthly_table::DataFrame, region_index::Union{Nothing,Dict{String,DataFrame}}=nothing)
    if isempty(ranking)
        println("\nHinweis: Nutze `region <NAME>` für Details zu einem bestimmten Ort.")
        prompt_session_finish(config)
        return
    end

    regions = [string(r) for r in ranking.Region if r !== missing && strip(string(r)) != ""]
    tty = stdin_is_tty()
    if !tty
        if !isempty(regions)
            println("\n[INFO] Keine TTY erkannt – Eingaben funktionieren eventuell eingeschränkt. `region $(regions[1])` liefert Details zur Top-Region.")
        else
            println("\n[INFO] Keine TTY erkannt – Eingaben funktionieren eventuell eingeschränkt. Alternativ: `region <NAME>`.")
        end
    end

    println("\nRegiondetails anzeigen? (Rangnummer oder Name, Enter zum Überspringen)")
    while true
        print("> ")
        input = try
            strip(readline())
        catch err
            isa(err, InterruptException) && rethrow()
            ""
        end

        if input == ""
            prompt_session_finish(config)
            return
        end

        selection = nothing
        idx = tryparse(Int, input)
        if idx !== nothing && 1 <= idx <= nrow(ranking)
            region_value = ranking.Region[idx]
            if region_value !== missing && strip(string(region_value)) != ""
                selection = String(region_value)
            end
        end
        if selection === nothing
            for name in regions
                if slower(name) == slower(input)
                    selection = name
                    break
                end
            end
        end

        if selection === nothing
            println("Region nicht gefunden. Bitte Nummer oder exakten Namen eingeben (Enter zum Abbruch).")
            continue
        end

        run_region(df, selection; weights=weights, monthly_table=monthly_table, region_index=region_index)

        println("\nWeitere Region ansehen? (y/N)")
        print("> ")
        again = try
            lowercase(strip(readline()))
        catch err
            isa(err, InterruptException) && rethrow()
            ""
        end
        if !(again in ("y", "yes", "j", "ja"))
            prompt_session_finish(config)
            return
        end
        println("\nNächste Region (Nummer oder Name, Enter zum Beenden):")
    end
end
