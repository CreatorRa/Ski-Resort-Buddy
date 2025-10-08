# Monthly overview calculations: aggregates per-region metrics, applies weighting,
# and builds tables used by leaderboards and decision hints. Keeping these routines
# together avoids circular references between plotting/region workflows.

"""
add_weighted_score!(df, weights)

Create or update a `WeightedScore` column by mixing the metrics according to the
chosen weights. Missing data is treated gently so gaps do not skew the result.
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
build_monthly_overview(df; weights=DEFAULT_METRIC_WEIGHTS)

Collect the latest month of data, calculate averages for each region, and return both
the table and a handy month label. A status flag explains why the table might be empty.
"""
function build_monthly_overview(df::DataFrame; weights::Dict{Symbol,Float64}=DEFAULT_METRIC_WEIGHTS)
    if !hasproperty(df, :Date)
        return (table=DataFrame(), label="", status=:no_date)
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
        return (table=DataFrame(), label="", status=:no_metrics)
    end

    month_df = transform(copy(df), :Date => ByRow(d -> Date(year(d), month(d), 1)) => :Month)
    unique_months = unique(month_df.Month)
    if isempty(unique_months)
        return (table=DataFrame(), label="", status=:no_month_values)
    end

    focus_month = maximum(unique_months)
    month_subset = filter(:Month => m -> m == focus_month, month_df)
    if isempty(month_subset)
        return (table=DataFrame(), label="", status=:no_rows)
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
        return (table=DataFrame(), label="", status=:empty_grouping)
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
    return (table=aggregated, label=month_label, status=:ok)
end

"""
print_monthly_overview_for_all_regions(df; weights=DEFAULT_METRIC_WEIGHTS, display=true)

Prepare the monthly overview table for every region. By default it prints a nicely
formatted table, but it can also return the data silently for reuse elsewhere.
"""
function print_monthly_overview_for_all_regions(df::DataFrame; weights::Dict{Symbol,Float64}=DEFAULT_METRIC_WEIGHTS, display::Bool=true)
    overview = build_monthly_overview(df; weights=weights)
    if display
        println()
        if overview.status != :ok
            msg_key = get(MONTHLY_OVERVIEW_STATUS_MESSAGES, overview.status, nothing)
            msg_key !== nothing && println(t(msg_key))
            return overview
        end
        println(t(:monthly_overview_header; month=overview.label))
        styled_table(overview.table)
    end
    return overview
end

"""
print_weighted_ranking(monthly_table, month_label; top_n=10)

Sort the monthly overview by weighted score, list the top regions, and show the rank
table to the user. Returns the table so it can be inspected again later.
"""
function print_weighted_ranking(monthly_table::DataFrame, month_label::AbstractString; top_n::Int=10)
    if isempty(monthly_table)
        println()
        println(t(:info_ranking_unavailable))
        return DataFrame()
    end
    local_table = copy(monthly_table)
    if !(:WeightedScore in names(local_table)) && !("WeightedScore" in names(local_table))
        add_weighted_score!(local_table, DEFAULT_METRIC_WEIGHTS)
    end

    if !(:WeightedScore in names(local_table)) && !("WeightedScore" in names(local_table))
        println()
        println(t(:info_ranking_missing_score))
        return DataFrame()
    end

    score_col = :WeightedScore in names(local_table) ? :WeightedScore : "WeightedScore"
    valid_rows = filter(score_col => x -> x !== missing, local_table)
    if isempty(valid_rows)
        println()
        println(t(:info_ranking_no_valid_scores))
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
    println()
    println(t(:ranking_header; label=label))
    styled_table(rank_df)
    return rank_df
end

"""
print_active_filters(config, df)

Tell the user which filters are currently active (season, date range, region, country)
and how many rows remain after filtering.
"""
function print_active_filters(config::CLIConfig, df::DataFrame)
    println()
    println(t(:filters_header))
    rargs = config.runargs
    from_label = isnothing(rargs.fromdate) ? "open" : string(rargs.fromdate)
    to_label = isnothing(rargs.todate) ? "open" : string(rargs.todate)
    season_label = isempty(rargs.season) ? "ALL" : rargs.season
    println(t(:filters_season; value=season_label))
    println(t(:filters_date_range; from=from_label, to=to_label))
    if config.region_focus !== nothing
        println(t(:filters_region_selected; value=config.region_focus))
    elseif haskey(ENV, "REGION")
        env_region = ENV["REGION"]
        println(t(:filters_region_env; value=env_region))
    else
        println(t(:filters_region_none))
    end
    if config.menu_country !== nothing
        println(t(:filters_country_menu; value=config.menu_country))
    elseif haskey(ENV, "COUNTRY")
        println(t(:filters_country_env; value=ENV["COUNTRY"]))
    else
        println(t(:filters_country_none))
    end
    if !isempty(df) && hasproperty(df, :Date)
        println(t(:filters_observation_window; rows=nrow(df), start=string(minimum(df.Date)), stop=string(maximum(df.Date))))
    else
        println(t(:filters_no_data))
    end
end

"""
print_active_weights(weights)

Show each metric weight in an easy-to-read format so the user sees how much influence
each factor has at the moment.
"""
function print_active_weights(weights::Dict{Symbol,Float64})
    println()
    println(t(:weights_active_header))
    for (key, cfg) in METRIC_WEIGHT_CONFIG
        value = get(weights, key, 0.0)
        label_key = get(cfg, :label_key, nothing)
        label = label_key === nothing ? string(key) : t(label_key)
        preference_suffix = get(cfg, :preference, :higher) == :lower ? t(:weights_preference_lower_suffix) : ""
        println(t(:weights_active_line; label=label, value=round(value; digits=2), preference=preference_suffix))
    end
    total = round(sum(values(weights)); digits=2)
    println(t(:weights_active_sum; total=total))
end

"""
print_decision_hints(scoreboard, monthly_table, weights)

Print a short list of helpful suggestions, such as which region has the most powder
or the calmest winds based on the latest ranking tables.
"""
function print_decision_hints(scoreboard::DataFrame, monthly_table::DataFrame, weights::Dict{Symbol,Float64})
    println()
    println(t(:decision_support_header))
    hints = String[]
    if !isempty(scoreboard) && all(col -> col in names(scoreboard), [Symbol("Region"), Symbol("Snow_New (cm)")])
        top_row = scoreboard[1, :]
        snow_val = top_row[Symbol("Snow_New (cm)")]
        snow_label = (snow_val === missing || snow_val === nothing) ? "" : string(round(Float64(snow_val); digits=1)) * " cm"
        push!(hints, t(:decision_hint_fresh_powder; region=top_row.Region, amount=snow_label))
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
            region_name !== missing && push!(hints, t(:decision_hint_best_overall; region=string(region_name), score=round(best_score; digits=2)))
        end
    end

    function best_hint(df::DataFrame, col::Symbol; rev::Bool=false, label_key::Union{Symbol,String}=:decision_hint_metric_label, unit::String="")
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
        label_text = label_key isa Symbol ? t(label_key) : String(label_key)
        return t(:decision_hint_metric; label=label_text, region=string(region), value=round(target; digits=2), unit=unit)
    end

    cold_hint = best_hint(monthly_table, Symbol("Avg Temperature (°C)"); label_key=:decision_hint_coldest, unit="°C")
    cold_hint !== nothing && push!(hints, cold_hint)

    calm_hint = best_hint(monthly_table, Symbol("Avg Wind (Beaufort)"); label_key=:decision_hint_calmest, unit=" Bft")
    calm_hint !== nothing && push!(hints, calm_hint)

    wettest_hint = best_hint(monthly_table, Symbol("Avg Precipitation (mm)"); rev=true, label_key=:decision_hint_wettest, unit=" mm")
    wettest_hint !== nothing && push!(hints, wettest_hint)

    if isempty(hints)
        println(t(:decision_no_hints))
    else
        for h in hints
            println(t(:decision_hint_line; hint=h))
        end
    end
end
