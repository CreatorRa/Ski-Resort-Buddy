
using SHA
using Base: bytes2hex

const REMOTE_CACHE_DIR = joinpath(ROOT_DIR, "data", "remote_cache")


"""
Dataset ingestion & transformation helpers: column detection/normalisation,
interpolation, filtering, and CSV path resolution used prior to reporting.
"""

"""
    find_date_column(df)

Heuristically locate the column that contains date information by scanning common
keywords (`date`, `datum`, etc.). Returns `nothing` when no suitable column exists.
"""
function find_date_column(df::DataFrame)
    cols_lower = Dict(slower(c) => Symbol(c) for c in names(df))
    for key in ("date","datum","day","tag","datetime","timestamp")
        if haskey(cols_lower, key)
            return cols_lower[key]
        end
    end
    for c in names(df)
        lc = slower(c)
        if occursin("date", lc) || occursin("datum", lc)
            return Symbol(c)
        end
    end
    return nothing
end

"""
    lininterp!(v)

Fill gaps in a numeric vector by performing linear interpolation between known values.
Leading/trailing missings copy the nearest observed neighbour.
"""
function lininterp!(v::AbstractVector{T}) where {T}
    n = length(v)
    firstidx = findfirst(!ismissing, v)
    lastidx  = findlast(!ismissing, v)
    if firstidx === nothing || lastidx === nothing
        return v
    end
    for i in 1:firstidx-1
        v[i] = v[firstidx]
    end
    for i in lastidx+1:n
        v[i] = v[lastidx]
    end
    i = firstidx
    while i <= n
        if ismissing(v[i])
            j = i
            while j <= n && ismissing(v[j])
                j += 1
            end
            j > n && break
            left = v[i-1]
            right = v[j]
            gap = j - i
            if gap > 0
                for k in 1:gap
                    v[i + k - 1] = left + (right - left) * (k / (gap + 1))
                end
            end
            i = j
        else
            i += 1
        end
    end
    return v
end

"""
    rolling_mean(v, window)

Return a simple centred rolling mean over the numeric vector `v`. When the window is
smaller than two, the original series is returned.
"""
function rolling_mean(v::AbstractVector{T}, w::Int) where {T<:Real}
    n = length(v)
    w <= 1 && return collect(v)
    out = similar(v, Float64)
    half = cld(w, 2)
    for i in 1:n
        lo = max(1, i - half + 1)
        hi = min(n, i + half - 1)
        out[i] = mean(@view v[lo:hi])
    end
    return out
end

"""
    normalize_columns!(df)

Rename known data columns (temperature, snow, etc.) to consistent display labels so the
downstream reporting code can address them reliably.
"""
function normalize_columns!(df::DataFrame)
    ren = Dict{Symbol,Symbol}()
    for c in names(df)
        col_sym = Symbol(c)
        lc = replace(slower(c), "  " => " ")
        if occursin("elevation", lc)
            ren[col_sym] = Symbol("Elevation (m)")
        elseif occursin("wind", lc) && occursin("beaufort", lc)
            ren[col_sym] = Symbol("Wind (Beaufort)")
        elseif occursin("temp", lc)
            ren[col_sym] = Symbol("Temperature (°C)")
        elseif occursin("precip", lc) || occursin("niedersch", lc)
            ren[col_sym] = Symbol("Precipitation (mm)")
        elseif (occursin("snow", lc) || occursin("schnee", lc)) && (occursin("new", lc) || occursin("neu", lc) || occursin("fresh", lc))
            ren[col_sym] = Symbol("Snow_New (cm)")
        elseif occursin("snow", lc) || occursin("schnee", lc)
            ren[col_sym] = Symbol("Snow Depth (cm)")
        elseif lc == "region"
            ren[col_sym] = :Region
        elseif lc == "country"
            ren[col_sym] = :Country
        end
    end
    rename!(df, ren)
end

"""
    search_for_csv(filename)

Walk the project tree to locate a CSV file by name. Used as a fallback when the file
is not found in the expected locations.
"""
function search_for_csv(filename::String)
    for (root, _, files) in walkdir(ROOT_DIR)
        if filename in files
            return joinpath(root, filename)
        end
    end
    return nothing
end

"""
    normalize_path(path)

Strip surrounding whitespace from a path string and coerce empty results to `nothing`.
This keeps CLI and ENV overrides consistent with optional argument semantics.
"""
function normalize_path(p::String)
    cp = strip(p)
    return cp == "" ? nothing : cp
end

function is_remote_source(path::AbstractString)
    trimmed = lowercase(strip(String(path)))
    return startswith(trimmed, "http://") || startswith(trimmed, "https://")
end

function remote_cache_path(url::AbstractString)
    sanitized = split(String(url), '?'; limit=2)[1]
    filename = Base.basename(strip(sanitized, '/'))
    filename = isempty(filename) ? "dataset.csv" : filename
    digest = bytes2hex(sha1(String(url)))
    return joinpath(REMOTE_CACHE_DIR, string(digest, "_", filename))
end

"""
    resolve_csv_path(csv_path)

Determine the CSV file to load by checking CLI/ENV overrides, default locations, and a
recursive search. Returns an absolute path or `nothing` when nothing can be found.
"""
function resolve_csv_path(csv_path::Union{Nothing,String})
    requested = csv_path === nothing ? get(ENV, "CSV_PATH", nothing) : csv_path
    requested = requested === nothing ? nothing : normalize_path(String(requested))

    candidate_list = String[]
    if requested !== nothing
        push!(candidate_list, requested)
        if !is_remote_source(requested)
            push!(candidate_list, joinpath(ROOT_DIR, requested))
            if lowercase(splitext(requested)[2]) != ".csv"
                push!(candidate_list, joinpath(ROOT_DIR, CSV_FILE_NAME))
            end
        end
    end
    push!(candidate_list, CSV_PATH_DEFAULT)
    push!(candidate_list, joinpath(ROOT_DIR, "data", CSV_FILE_NAME))

    seen = Set{String}()
    for cand in candidate_list
        candidate = normalize_path(String(cand))
        candidate === nothing && continue
        if is_remote_source(candidate)
            remote = candidate
            if remote in seen
                continue
            end
            push!(seen, remote)
            return remote
        end
        c = abspath(candidate)
        if c in seen
            continue
        end
        push!(seen, c)
        if isfile(c)
            return c
        end
    end

    fallback = search_for_csv(CSV_FILE_NAME)
    if fallback !== nothing
        @warn t(:warn_using_fallback_csv) fallback=fallback
        return fallback
    end

    return nothing
end

function ensure_local_csv(path::AbstractString)
    if is_remote_source(path)
        cache_path = remote_cache_path(String(path))
        try
            mkpath(dirname(cache_path))
        catch
            # ignore directory creation errors; download may fail later
        end
        if !isfile(cache_path)
            println("[INFO] Downloading remote dataset to cache: " * cache_path)
            Base.download(String(path), cache_path)
        end
        return cache_path, false
    end
    return path, false
end

"""
    load_data([csv_path])

Load the resort dataset into a `DataFrame`, normalise column names/types, and ensure
dates are sorted. Raises an error when no CSV can be located.
"""
function load_data(csv_path::Union{Nothing,String}=nothing)
    path = resolve_csv_path(csv_path)
    path === nothing && error(t(:error_csv_missing; default_file=CSV_FILE_NAME))
    println(t(:info_loading_csv; path=path))
    local_path, cleanup = ensure_local_csv(path)
    df = try
        CSV.read(local_path, DataFrame)
    finally
        if cleanup && isfile(local_path)
            try
                rm(local_path; force=true)
            catch
                # ignore cleanup errors
            end
        end
    end
    rename!(df, Dict(c => Symbol(strip(String(c))) for c in names(df)))

    date_col = find_date_column(df)
    isnothing(date_col) && error(t(:error_no_date_column))

    df[!, date_col] = DateTime.(df[!, date_col]) .|> Date
    sort!(df, date_col)
    rename!(df, Dict(date_col => :Date))

    normalize_columns!(df)

    for c in (Symbol("Elevation (m)"), Symbol("Wind (Beaufort)"), Symbol("Temperature (°C)"), Symbol("Precipitation (mm)"), Symbol("Snow Depth (cm)"))
        if hasproperty(df, c)
            df[!, c] = map(df[!, c]) do x
                if x === missing || x === nothing
                    missing
                elseif x isa Number
                    Float64(x)
                else
                    val = tryparse(Float64, string(x))
                    isnothing(val) ? missing : val
                end
            end
        end
    end

    for c in (:Region, :Country)
        if hasproperty(df, c)
            df[!, c] = map(x -> begin
                s = strip(string(x))
                s == "" ? missing : s
            end, df[!, c])
        end
    end

    if hasproperty(df, :Country)
        df[!, :Country] = map(canonical_country, coalesce.(df[!, :Country], ""))
    end

    if hasproperty(df, Symbol("Precipitation (mm)"))
        df[!, Symbol("Precipitation (mm)")] = coalesce.(df[!, Symbol("Precipitation (mm)")], 0.0)
    end

    for c in (Symbol("Wind (Beaufort)"), Symbol("Temperature (°C)"), Symbol("Snow Depth (cm)"))
        if hasproperty(df, c)
            v = Vector{Union{Missing,Float64}}(df[!, c])
            lininterp!(v)
            df[!, c] = Float64.(coalesce.(v, NaN))
        end
    end

    return df
end

"""
    canonical_country(value)

Map various country labels (ISO codes, German spellings, etc.) to a consistent English
name. Unknown inputs pass through unchanged after trimming.
"""
function canonical_country(value)
    key = uppercase(strip(String(value)))
    get(DACH_SYNONYMS, key, strip(String(value)))
end

"""
    add_newsnow!(df)

Append a `Snow_New (cm)` column that captures day-to-day snow depth increases per
region/country grouping. Flat or negative changes become zero.
"""
function add_newsnow!(df::DataFrame)
    sn = Symbol("Snow Depth (cm)")
    if !hasproperty(df, sn)
        return df
    end
    new_col = Symbol("Snow_New (cm)")
    hasproperty(df, :Date) || return df

    existing_new = if hasproperty(df, new_col)
        Vector{Union{Missing,Float64}}(df[!, new_col])
    else
        Union{Missing,Float64}[missing for _ in 1:nrow(df)]
    end
    computed = zeros(Float64, nrow(df))

    temp_col = hasproperty(df, Symbol("Temperature (°C)")) ? Symbol("Temperature (°C)") : nothing
    precip_col = hasproperty(df, Symbol("Precipitation (mm)")) ? Symbol("Precipitation (mm)" ) : nothing
    temps = temp_col === nothing ? nothing : df[!, temp_col]
    precips = precip_col === nothing ? nothing : df[!, precip_col]

    function snow_possible(idx::Int, prev_idx::Int)
        temp_ok = true
        if temps !== nothing
            curr_t = temps[idx]
            prev_t = temps[prev_idx]
            temp_ok = ((curr_t !== missing && curr_t <= 2.5) || (prev_t !== missing && prev_t <= 2.5))
        end
        precip_ok = true
        if precips !== nothing
            curr_p = precips[idx]
            prev_p = precips[prev_idx]
            precip_ok = ((curr_p !== missing && curr_p >= 2.0) || (prev_p !== missing && prev_p >= 2.0))
        end
        return temp_ok || precip_ok
    end

    groupcols = [col for col in (:Region, :Country) if col in names(df)]

    function process_indices(indices::Vector{Int})
        isempty(indices) && return
        depths = df[indices, sn]
        prev_depth = depths[1]
        computed[indices[1]] = 0.0
        for j in 2:length(indices)
            idx = indices[j]
            prev_idx = indices[j-1]
            current_depth = depths[j]
            if current_depth === missing || prev_depth === missing
                computed[idx] = 0.0
                if current_depth !== missing
                    prev_depth = current_depth
                end
                continue
            end
            delta = Float64(current_depth) - Float64(prev_depth)
            if delta > 0 && snow_possible(idx, prev_idx)
                computed[idx] = delta
            else
                computed[idx] = 0.0
            end
            prev_depth = current_depth
        end
    end

    if isempty(groupcols)
        order = sortperm(df[!, :Date])
        process_indices(order)
    else
        for sub in groupby(df, groupcols)
            sort!(sub, :Date)
            indices = collect(parentindices(sub)[1])
            process_indices(indices)
        end
    end

    final = Union{Missing,Float64}[existing_new[i] === missing ? computed[i] : existing_new[i] for i in 1:nrow(df)]
    df[!, new_col] = final
    return df
end

"""
    in_season(date, season)

Return `true` when the provided `Date` falls within the specified season keyword.
`WINTER` spans November–April, `SUMMER` May–October, and everything else accepts all.
"""
function in_season(d::Date, season::String)
    m = month(d)
    season == "WINTER" && return m in (11,12,1,2,3,4)
    season == "SUMMER" && return m in (5,6,7,8,9,10)
    return true
end

"""
    apply_filters(df, runargs)

Apply region/country/environment filters along with optional date bounds and season
restrictions, returning a filtered copy of the DataFrame.
"""
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
