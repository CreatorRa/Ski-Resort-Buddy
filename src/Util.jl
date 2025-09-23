import Base: lowercase

slower(x) = lowercase(String(x))
lowercase(x::Symbol) = lowercase(String(x))

function slugify(name::AbstractString)
    slug = lowercase(strip(name))
    slug = replace(slug, r"[^a-z0-9]+" => "_")
    slug = replace(slug, r"_+" => "_")
    slug = strip(slug, '_')
    return slug == "" ? "region" : slug
end

function ensure_plot_dir()
    isdir(PLOTS_OUTPUT_DIR) || mkpath(PLOTS_OUTPUT_DIR)
    return PLOTS_OUTPUT_DIR
end

function ensure_plots_ready()
    if PLOTS_INITIALISED[]
        return true
    end
    try
        gr()
        Plots.default(; fmt=:png, legend=:topright, size=(900, 500))
        PLOTS_INITIALISED[] = true
        return true
    catch err
        @warn "Plotting backend unavailable; skipping snow trend plots" exception=(err, catch_backtrace())
        return false
    end
end
