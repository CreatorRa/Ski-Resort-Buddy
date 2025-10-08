"""
find_date_column(df)

Look through the table headers and return the column that most likely stores dates.
If nothing matches typical date names we return `nothing`.
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

Fill in missing numbers in a vector by connecting the known values with straight
lines. Values at the start or end copy the nearest known value.
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

Return a smoothed copy of a numeric vector by averaging neighbouring values. When the
window is too small we just give back the original data.
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
