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
            left = v[i-1]
            right = v[j]
            gap = j - i
            if gap > 0
                span = gap + 1
                for k in 0:(gap-1)
                    v[i + k] = left + (right - left) * (k + 1) / span
                end
            end
            i = j
        else
            i += 1
        end
    end
    return v
end

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

function search_for_csv(filename::String)
    for (root, _, files) in walkdir(ROOT_DIR)
        if filename in files
            return joinpath(root, filename)
        end
    end
    return nothing
end

normalize_path(p::String) = (cp = strip(p); cp == "" ? nothing : cp)

function resolve_csv_path(csv_path::Union{Nothing,String})
    requested = csv_path === nothing ? get(ENV, "CSV_PATH", nothing) : csv_path
    requested = requested === nothing ? nothing : normalize_path(String(requested))

    candidate_list = String[]
    if requested !== nothing
        push!(candidate_list, requested)
        push!(candidate_list, joinpath(ROOT_DIR, requested))
        if lowercase(splitext(requested)[2]) != ".csv"
            push!(candidate_list, joinpath(ROOT_DIR, CSV_FILE_NAME))
        end
    end
    push!(candidate_list, CSV_PATH_DEFAULT)
    push!(candidate_list, joinpath(ROOT_DIR, "data", CSV_FILE_NAME))

    seen = Set{String}()
    for cand in candidate_list
        c = abspath(cand)
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
        @warn "Using fallback CSV" fallback
        return fallback
    end

    return nothing
end

function load_data(csv_path::Union{Nothing,String}=nothing)
    path = resolve_csv_path(csv_path)
    path === nothing && error("CSV not found. Set CSV_PATH env variable, pass a path argument, or keep $(CSV_FILE_NAME) in the project directory.")
    println("[INFO] Loading CSV: $(path)")
    df = CSV.read(path, DataFrame)
    rename!(df, Dict(c => Symbol(strip(String(c))) for c in names(df)))

    date_col = find_date_column(df)
    isnothing(date_col) && error("No date column detected. Expecting something like 'Date'.")

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

function canonical_country(value)
    key = uppercase(strip(String(value)))
    get(DACH_SYNONYMS, key, strip(String(value)))
end

function add_newsnow!(df::DataFrame)
    sn = Symbol("Snow Depth (cm)")
    if !hasproperty(df, sn)
        return df
    end
    new_col = Symbol("Snow_New (cm)")
    df[!, new_col] = fill(0.0, nrow(df))
    groupcols = intersect([:Region, :Country], names(df))
    if isempty(groupcols)
        sort!(df, :Date)
        diffs = [NaN; diff(df[!, sn])]
        df[!, new_col] = map(x -> isnan(x) ? 0.0 : max(x, 0.0), diffs)
        return df
    end
    for sub in groupby(df, groupcols)
        sort!(sub, :Date)
        diffs = [NaN; diff(sub[!, sn])]
        gains = map(x -> isnan(x) ? 0.0 : max(x, 0.0), diffs)
        df[!, new_col][sub.row .|> Int] = gains
    end
    return df
end
