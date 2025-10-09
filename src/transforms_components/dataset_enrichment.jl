"""
normalize_columns!(df)

Rename columns that refer to temperature, snow, wind, and similar topics so their
names match the labels we use everywhere else.
"""
function normalize_columns!(df::DataFrame)
    ren = Dict{Symbol,Symbol}()
    temp_col_found = false
    for c in names(df)
        col_sym = Symbol(c)
        lc = replace(slower(c), "  " => " ")
        if occursin("elevation", lc)
            ren[col_sym] = Symbol("Elevation (m)")
        elseif occursin("wind", lc) && occursin("beaufort", lc)
            ren[col_sym] = Symbol("Wind (Beaufort)")
        elseif occursin("temp", lc) && !temp_col_found
            ren[col_sym] = Symbol("Temperature (°C)")
            temp_col_found = true
        elseif occursin("precip", lc) || occursin("niedersch", lc)
            ren[col_sym] = Symbol("Precipitation (mm)")
        elseif (occursin("snow", lc) || occursin("schnee", lc)) && (occursin("new", lc) || occursin("neu", lc) || occursin("fresh", lc))
            ren[col_sym] = Symbol("Snow_New (cm)")
        elseif (occursin("snow", lc) || occursin("schnee", lc)) && !occursin("daily", lc) && !occursin("monthly", lc) && !occursin("mean", lc) && !occursin("max", lc)
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
load_data([csv_path])

Read the ski dataset from a CSV file, tidy up the columns, and make sure dates are in
order. Throws a user-friendly error when no data file can be found.
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

    df[!, date_col] = Date.(df[!, date_col], dateformat"d/m/y")
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

Translate different spellings or codes for Austria, Germany, and Switzerland into a
single clean country name. Unknown values are returned as-is.
"""
function canonical_country(value)
    key = uppercase(strip(String(value)))
    get(DACH_SYNONYMS, key, strip(String(value)))
end

"""
add_newsnow!(df)

Add a column that records how much the snow depth grew from one day to the next for
each region. Drops in snow depth are treated as zero new snow.
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

Return `true` when the given date falls inside the named season. `WINTER` covers
November–April, `SUMMER` covers May–October, and `ALL` keeps every date.
"""
function in_season(d::Date, season::String)
    m = month(d)
    season == "WINTER" && return m in (11,12,1,2,3,4)
    season == "SUMMER" && return m in (5,6,7,8,9,10)
    return true
end

"""
apply_filters(df, runargs)

Filter the dataset by region, country, date range, and season based on the values in
`runargs` and environment variables. Returns the filtered copy.
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
