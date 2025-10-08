"""
available_regions(df)

Return all distinct region names found in the data, sorted alphabetically.
"""
available_regions(df::DataFrame) = available_values(df, :Region)

"""
available_countries(df)

Return all distinct country names found in the data, sorted alphabetically.
"""
available_countries(df::DataFrame) = available_values(df, :Country)

function available_values(df::DataFrame, column::Symbol)
    hasproperty(df, column) || return String[]
    raw = String[]
    for value in skipmissing(df[!, column])
        name = strip(string(value))
        name == "" && continue
        push!(raw, name)
    end
    unique!(raw)
    sort!(raw)
    return raw
end

"""
filter_country(df, country)

Return only the rows that belong to `country`, ignoring case differences. If no
country is provided the original table is returned.
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

Print a simple bulleted list of region names. When the list is empty a friendly
message explains that no regions were found.
"""
function print_available_regions(regions::AbstractVector{<:AbstractString})
    println(t(:regions_header))
    if isempty(regions)
        println(t(:regions_none))
    else
        for r in regions
            println(t(:regions_entry; name=r))
        end
    end
    println()
end
