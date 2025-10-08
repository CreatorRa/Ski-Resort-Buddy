"""
search_for_csv(filename)

Walk through the project folders to find a CSV with the given name. Used as a last
resort when other lookup methods fail.
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

Trim extra spaces from a path string. If the result is empty we return `nothing` so
callers know there was no real value.
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

Figure out which CSV file to load by checking command-line values, environment
variables, and common fallbacks. Returns either a usable path or `nothing`.
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

"""
ensure_local_csv(path)

Make sure the CSV file exists locally. Remote files are downloaded to a cache folder
so later reads are fast and offline-friendly.
"""
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
