import Base: lowercase

"""
slower(x)

Turn any value into a lowercase string. This helps us compare names without worrying
about uppercase or lowercase letters.
"""
slower(x) = lowercase(String(x))

"""
Base.lowercase(x::Symbol)

Allow symbols (like `:Region`) to be lowered directly so callers do not need to convert
them to strings first.
"""
lowercase(x::Symbol) = lowercase(String(x))

"""
slugify(name)

Create a safe filename from a region name. We keep letters and numbers, replace other
characters with underscores, and remove extras so saved plots have tidy names.
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

Create the `plots/` folder if it does not already exist and return the full path. We
call this right before saving images so saving never fails because of a missing folder.
"""
function ensure_plot_dir()
    isdir(PLOTS_OUTPUT_DIR) || mkpath(PLOTS_OUTPUT_DIR)
  	return PLOTS_OUTPUT_DIR
end

"""
clean_numeric_series(dates, values)

Walk two matching lists of dates and numbers, skipping entries that are empty or not
convertible to numbers. The clean pairs are returned so plots and stats can rely on
valid data only.
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

Collect all usable numbers from an input list. Entries that are missing, `nothing`, or
not real numbers are ignored so callers receive a clean vector of `Float64` values.
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
