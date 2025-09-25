# Utility helpers for string normalization, filesystem prep, and lightweight
# collection/terminal helpers shared across the data pipeline and reporting layers.
import Base: lowercase

"""
    slower(x)

Return the lowercase string representation of `x` while tolerating any input type.
Used to implement case-insensitive comparisons throughout the data prep pipeline.
"""
slower(x) = lowercase(String(x))

"""
    Base.lowercase(x::Symbol)

Overload of `lowercase` so symbols participate in the `slower` conversions without
additional calls to `String` in the call sites.
"""
lowercase(x::Symbol) = lowercase(String(x))

"""
    slugify(name)

Transform a region name into a filesystem-friendly slug used for naming plot files.
Non alphanumeric characters collapse into underscores and redundant underscores are
removed to keep filenames tidy.
"""
function slugify(name::AbstractString)
    slug = lowercase(strip(name))
    slug = replace(slug, r"[^a-z0-9]+" => "_")
    slug = replace(slug, r"_+" => "_")
    slug = strip(slug, '_')
    return slug == "" ? "region" : slug
end

"""
    ensure_plot_dir()

Create the `plots/` output directory on demand and return its absolute path. This is
called before saving any generated PNGs to guarantee the destination exists.
"""
function ensure_plot_dir()
    isdir(PLOTS_OUTPUT_DIR) || mkpath(PLOTS_OUTPUT_DIR)
    return PLOTS_OUTPUT_DIR
end

"""
    clean_numeric_series(dates, values)

Pair a date vector with numeric values while skipping missing or non-parsable entries.
Returns two aligned vectors (`Date[]`, `Float64[]`) suitable for plotting time-series
metrics.
"""
function clean_numeric_series(dates::AbstractVector, values::AbstractVector)
    xs = Date[]
    ys = Float64[]
    for (d, v) in zip(dates, values)
        if v === missing || v === nothing
            continue
        end
        val = try
            Float64(v)
        catch
            continue
        end
        if isnan(val)
            continue
        end
        push!(xs, Date(d))
        push!(ys, val)
    end
    return xs, ys
end

"""
    collect_valid(values)

Gather numeric entries from `values`, skipping missing, `nothing`, or `NaN` entries and
returning a `Vector{Float64}` for statistical processing.
"""
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

"""
    metric_stats(values)

Build a short statistics table (count, mean, median, extrema, standard deviation) for
the provided numeric vector.
"""
function metric_stats(values::Vector{Float64})
    if isempty(values)
        return DataFrame(Statistic=String[], Value=Any[])
    end
    stats = [
        ("Count", length(values)),
        ("Mean", round(mean(values); digits=2)),
        ("Median", round(median(values); digits=2)),
        ("Minimum", round(minimum(values); digits=2)),
        ("Maximum", round(maximum(values); digits=2)),
        ("Std. Deviation", length(values) > 1 ? round(std(values); digits=2) : 0.0)
    ]
    return DataFrame(Statistic = first.(stats), Value = Any[x[2] for x in stats])
end

"""
    stdin_is_tty()

Check whether standard input is attached to a terminal, accounting for platforms where
`isatty` might throw. Used to decide if interactive prompts should be shown.
"""
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

"""
    available_regions(df)

Return a sorted list of distinct region names present in the dataset.
"""
function available_regions(df::DataFrame)
    if !hasproperty(df, :Region)
        return String[]
    end
    raw = [strip(string(r)) for r in skipmissing(df.Region) if strip(string(r)) != ""]
    unique!(raw)
    sort!(raw)
    return raw
end

"""
    available_countries(df)

Return a sorted list of distinct country names extracted from the dataset.
"""
function available_countries(df::DataFrame)
    if !hasproperty(df, :Country)
        return String[]
    end
    raw = [strip(string(c)) for c in skipmissing(df.Country) if strip(string(c)) != ""]
    unique!(raw)
    sort!(raw)
    return raw
end

"""
    filter_country(df, country)

Filter rows to those matching the supplied `country` (case-insensitive). When
`country === nothing`, the original DataFrame is returned.
"""
function filter_country(df::DataFrame, country::Union{Nothing,AbstractString})
    if country === nothing || !hasproperty(df, :Country)
        return df
    end
    target = slower(String(country))
    return filter(:Country => x -> !ismissing(x) && slower(String(x)) == target, df)
end

"""
    print_available_regions(regions)

Write a bullet list of region names to the terminal, with a fallback message when none
are available.
"""
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
