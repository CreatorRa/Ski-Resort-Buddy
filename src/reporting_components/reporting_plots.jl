# Reporting plot helpers: functions that translate prepared data frames into PNG
# visualisations. Kept separate so plotting dependencies stay out of core analytics.

"""
save_region_snow_plot(region_df, region_name; recent_days=90)

Draw a snow trend chart (depth plus new snow bars) for a region and save it as a PNG
file. Returns the file path or `nothing` when plotting is not possible.
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

Plot how the weighted score changed over time for a region and save the image. Returns
`nothing` when there is not enough information.
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

Create a chart for a chosen metric (for example wind or precipitation) and save it to
the plots folder. Skips the chart when the data is missing.
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

    label_text = get(option, :display_key, nothing)
    metric_label = label_text === nothing ? string(option.column) : t(label_text)
    ylabel = metric_label
    plot_title = t(:metric_plot_title; region=region_name, metric=metric_label)
    seriestype = get(option, :plot, :line)
    color = get(option, :color, :steelblue)

    if seriestype == :bar
        plot_obj = plot(xs, ys;
            seriestype=:bar,
            color=color,
            alpha=0.65,
            bar_width=0.8,
            label=metric_label,
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
            label=metric_label,
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

List which metric plots make sense for the given region, based on the data columns
that actually contain values.
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

"""
resolve_metric_tokens(tokens, options)

Turn user input (numbers or keywords) into actual metric selections and tell the
caller which tokens were not understood.
"""
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
            label_key = get(opt, :display_key, nothing)
            base_label = label_key === nothing ? string(opt.key) : t(label_key)
            names_to_match = Set{String}()
            push!(names_to_match, slower(base_label))
            push!(names_to_match, slower(string(opt.key)))
            if haskey(opt, :aliases)
                for alias in opt.aliases
                    push!(names_to_match, slower(alias))
                end
            end
            if any(name -> name == low || occursin(low, name), names_to_match)
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

"""
generate_metric_plots(region_df, region_name, selections)

Create each selected metric plot in turn and report whether it was saved or skipped.
"""
function generate_metric_plots(region_df::DataFrame, region_name::AbstractString, selections::Vector{<:NamedTuple})
    for opt in selections
        try
            label_key = get(opt, :display_key, nothing)
            metric_label = label_key === nothing ? string(opt.key) : t(label_key)
            plot_kind = get(opt, :plot_kind, :metric)
            if plot_kind == :snow
                recent_days = get(opt, :recent_days, nothing)
                path = isnothing(recent_days) ?
                    save_region_snow_plot(region_df, region_name) :
                    save_region_snow_plot(region_df, region_name; recent_days=recent_days)
                if path === nothing
                    println(t(:info_snow_plot_skipped))
                else
                    println(t(:info_snow_plot_saved; path=path))
                end
            else
                path = save_region_metric_trend(region_df, region_name, opt; recent_days_override=get(opt, :recent_days, nothing))
                if path === nothing
                    println(t(:info_metric_plot_skipped; metric=metric_label))
                else
                    println(t(:info_metric_plot_saved; metric=metric_label, path=path))
                end
            end
        catch err
            plot_kind = get(opt, :plot_kind, :metric)
            if plot_kind == :snow
                @warn "Unable to save snow trend plot" region=region_name exception=(err, catch_backtrace())
            else
                @warn "Unable to save metric plot" region=region_name metric=opt.key exception=(err, catch_backtrace())
            end
        end
    end
end

"""
prompt_region_metric_plots(region_df, region_name; env_selection=nothing)

Interactively ask which extra metric charts to generate for a region. Supports preset
lists through the `REGION_METRICS` environment variable.
"""
function prompt_region_metric_plots(region_df::DataFrame, region_name::AbstractString; env_selection::Union{Nothing,String}=nothing)
    options = region_metric_options(region_df)
    isempty(options) && return

    env_selected = NamedTuple[]
    if env_selection !== nothing && strip(env_selection) != ""
        tokens = split(env_selection, r"[ ,;]+"; keepempty=false)
        env_selected, unknown = resolve_metric_tokens(tokens, collect(options))
        if !isempty(unknown)
            println(t(:warn_region_metrics_unknown; tokens=join(unknown, ", ")))
        end
        if !isempty(env_selected)
            println()
            println(t(:info_region_metrics_env))
            generate_metric_plots(region_df, region_name, env_selected)
        end
        if !stdin_is_tty()
            !isempty(env_selected) || println(t(:info_region_metrics_none))
            return
        end
    elseif !stdin_is_tty()
        println()
        println(t(:info_region_metrics_no_tty))
    end

    println()
    println(t(:prompt_metric_plots_header))
    println(t(:prompt_metric_plots_options))
    option_list = collect(options)
    for (idx, opt) in enumerate(option_list)
        label_key = get(opt, :display_key, nothing)
        metric_label = label_key === nothing ? string(opt.key) : t(label_key)
        println(t(:prompt_metric_plots_option_entry; index=idx, label=metric_label))
    end
    println(t(:prompt_metric_plots_examples))

    while true
        input = try
            readline_with_speech("> ")
        catch err
            isa(err, InterruptException) && rethrow()
            ""
        end

        input == "" && return

        tokens = split(input, r"[ ,;]+"; keepempty=false)
        selections, unknown = resolve_metric_tokens(tokens, option_list)
        if !isempty(unknown)
            println(t(:prompt_metric_plots_unknown_tokens; tokens=join(unknown, ", ")))
        end
        if isempty(selections)
            println(t(:prompt_metric_plots_retry))
            continue
        end

        generate_metric_plots(region_df, region_name, selections)

        println()
        println(t(:prompt_metric_plots_repeat))
        prompt_yes_no() || return
        println()
        println(t(:prompt_metric_plots_next))
    end
end
