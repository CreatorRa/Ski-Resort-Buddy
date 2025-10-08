"""
styled_table(data; kwargs...)

Print tables with the same colours and highlights everywhere. Handy for keeping
reports easy to read.
"""
function styled_table(data; kwargs...)
    pretty_table(data; highlighters=TABLE_HIGHLIGHTERS, kwargs...)
end

"""
lookup_column(df, col)

Find a column by name, accepting either symbols or strings. Returns `nothing` when
the column cannot be found.
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
    println()
    println(t(:prompt_session_finish))
    response = try
        lowercase(readline_with_speech("> "))
    catch err
        isa(err, InterruptException) && rethrow()
        ""
    end
    if response in ("q", "quit", "y", "yes", "j", "ja")
        println(t(:farewell))
    end
end

"""
qc_checks(df)

Print friendly warnings when the dataset looks suspicious (missing days, negative snow
depth, unrealistic temperatures, and so on).
"""
function qc_checks(df::DataFrame)
    println()
    println(t(:qc_header))
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
                sample = join(string.(missing[1:min(end,10)]), ", ")
                extra = length(missing) > 10 ? ", …" : ""
                println(t(:qc_missing_days; region=string(grp[1][2]), count=length(missing), sample=sample, extra=extra))
            end
        end
    end

    if hasproperty(df, Symbol("Wind (Beaufort)"))
        w = df[!, Symbol("Wind (Beaufort)")]
        n = count(>(12), w)
        if n > 0
            issues = true
            println(t(:qc_outlier_wind; count=n))
        end
    end
    if hasproperty(df, Symbol("Precipitation (mm)"))
        p = df[!, Symbol("Precipitation (mm)")]
        n = count(<(0), p)
        if n > 0
            issues = true
            println(t(:qc_outlier_precipitation; count=n))
        end
    end
    if hasproperty(df, Symbol("Snow Depth (cm)"))
        s = df[!, Symbol("Snow Depth (cm)")]
        n = count(<(0), s)
        if n > 0
            issues = true
            println(t(:qc_outlier_snow_depth; count=n))
        end
    end
    if hasproperty(df, Symbol("Temperature (°C)"))
        tvals = df[!, Symbol("Temperature (°C)")]
        nbad = count(x -> x < -60 || x > 50, tvals)
        if nbad > 0
            issues = true
            println(t(:qc_outlier_temperature; count=nbad))
        end
    end

    if !issues
        println(t(:qc_no_issues))
    end
end

"""
print_data_preview(df; limit=5)

Show the first and last few rows of the table so the user can confirm the data looks
right before diving into bigger reports.
"""
function print_data_preview(df::DataFrame; limit::Int=5)
    rows = min(limit, nrow(df))
    println()
    println(t(:data_preview_first; rows=rows))
    styled_table(first(df, rows))
    if nrow(df) > rows
        println()
        println(t(:data_preview_last; rows=rows))
        styled_table(last(df, rows))
    end
end

"""
current_month_subset(df)

Return the rows that belong to the current month (or the most recent month with data)
along with the date label we should display.
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

Summarise the current month's temperature, snow, wind, and precipitation. Tells the
user when no data is available.
"""
function print_current_month_overview(df::DataFrame)
    label_date, subset = current_month_subset(df)
    label = isempty(subset) ? "n/a" : string(Dates.monthname(month(label_date)), " ", year(label_date))
    println()
    println(t(:current_month_header; label=label))
    if isempty(subset)
        println(t(:info_no_current_month_data))
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
        println(t(:info_no_metrics_to_summarise))
        return
    end
    styled_table(DataFrame(rows))
end

"""
safe_stat(values, reducer)

Run a summary function (like `mean`) on the values that can be converted to numbers.
Returns `missing` when nothing usable is found.
"""
function safe_stat(v, f::Function)
    vals = collect_valid(v)
    isempty(vals) && return missing
    return f(vals)
end

"""
metric_group_summary(df; groupcol, ycol)

Group the table by region or country and calculate how many values exist, plus the
average, median, min, and max for the selected metric.
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
    println()
    println(t(:metric_group_summary_header; metric=String(ycol), group=String(groupcol)))
    styled_table(grouped)
end

"""
recent_conditions(df; recent_days=14)

Pick the most recent rows (two weeks by default) and return just the columns that are
useful for a quick daily conditions table.
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

Show which regions picked up the most new snow within the last year, highlighting the
top rows for easy reading. Returns the table for reuse.
"""
function print_daily_scoreboard(df::DataFrame; top_n::Int=5)
    snow_col = Symbol("Snow_New (cm)")
    if !hasproperty(df, :Date) || !hasproperty(df, snow_col)
        println()
        println(t(:info_daily_board_missing_columns))
        return DataFrame()
    end
    if isempty(df)
        println()
        println(t(:info_daily_board_no_rows))
        return DataFrame()
    end

    latest_date = maximum(df.Date)
    window_start = latest_date - Day(364)
    window_df = filter(:Date => d -> window_start <= d <= latest_date, df)
    if isempty(window_df)
        println()
        println(t(:info_daily_board_latest_no_rows))
        return DataFrame()
    end

    group_cols = Symbol[:Region]
    hasproperty(window_df, :Country) && push!(group_cols, :Country)
    aggregation = combine(groupby(window_df, group_cols), snow_col => (v -> sum(skipmissing(v))) => :TotalSnow)
    if isempty(aggregation)
        println()
        println(t(:info_daily_board_latest_no_rows))
        return DataFrame()
    end
    sort!(aggregation, :TotalSnow, rev=true)
    count = min(top_n, nrow(aggregation))
    leaders = aggregation[1:count, :]

    label = "" * string(window_start) * " – " * string(latest_date)

    scoreboard = DataFrame(
        :Rank => collect(1:count),
        :Region => (hasproperty(leaders, :Region) ? map(x -> string(x), leaders.Region) : fill("n/a", count)),
        :Country => (hasproperty(leaders, :Country) ? map(x -> x === missing ? "n/a" : string(x), leaders.Country) : fill("n/a", count)),
        Symbol("Total Snow (cm)") => round.(leaders.TotalSnow; digits=1)
    )

    println()
    println("Yearly new snow leaderboard (" * label * ")")
    styled_table(scoreboard)
    return scoreboard
end
