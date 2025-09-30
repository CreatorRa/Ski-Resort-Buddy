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
    stdin_is_tty()

Check whether standard input is attached to a terminal, accounting for platforms where
`isatty` might throw. Used to decide if interactive prompts should be shown.
"""
function stdin_is_tty()
    fd = try
        Base.fd(stdin)
    catch
        return false
    end
    fd < 0 && return false
    try
        return ccall(:isatty, Cint, (Cint,), fd) == 1
    catch
        return false
    end
end

"""
    normalize_speech_cmd(cmd)

Trim and validate a speech command string, returning `nothing` when empty.
"""
function normalize_speech_cmd(cmd)
    isnothing(cmd) && return nothing
    text = strip(String(cmd))
    return text == "" ? nothing : text
end

"""
    current_speech_cmd()

Return the speech command configured for this session (or `nothing`).
"""
current_speech_cmd() = SPEECH_CMD[]

"""
    set_speech_cmd!(cmd)

Update the global speech command reference and return the effective value.
"""
function set_speech_cmd!(cmd)
    SPEECH_CMD[] = normalize_speech_cmd(cmd)
    return SPEECH_CMD[]
end

"""
    run_speech_capture(cmd)

Execute the configured speech command and return its trimmed stdout.
"""
function run_speech_capture(cmd::String)
    if strip(cmd) == ""
        return nothing
    end
    parts = try
        Base.shell_split(cmd)
    catch err
        @warn "SPEECH_CMD konnte nicht geparst werden" command=cmd error=err
        return nothing
    end
    isempty(parts) && return nothing
    command = Cmd(parts; windows_verbatim=false)
    try
        output = read(command, String)
        return strip(output)
    catch err
        isa(err, InterruptException) && rethrow()
        @warn "Sprachbefehl fehlgeschlagen" command=cmd error=err
        return nothing
    end
end

"""
    readline_with_speech([prompt]; kwargs...)

Read a user input line, optionally running speech recognition before falling back to
keyboard entry. Returns the trimmed string (may be empty).
"""
function readline_with_speech(prompt::AbstractString="> ";
        speech_cmd::Union{Nothing,String}=current_speech_cmd(),
        fallback_keyboard::Bool=true,
        fallback_on_empty::Bool=true)

    if speech_cmd !== nothing
        print(prompt)
        flush(stdout)
        println(t(:speech_prompt_active))
        spoken = run_speech_capture(speech_cmd)
        if spoken !== nothing
            trimmed = strip(spoken)
            if trimmed != ""
                println("↳ " * trimmed)
                return trimmed
            elseif fallback_on_empty && fallback_keyboard
                println(t(:speech_no_result))
            else
                return trimmed
            end
        elseif fallback_keyboard
            println(t(:speech_failed))
        else
            return ""
        end
    end

    print(prompt)
    flush(stdout)
    line = readline()
    return strip(line)
end

"""
    detect_speech_command()

Return a best-guess speech command by probing for known CLI tools. Returns `nothing`
when no suitable candidate is found.
"""
function detect_speech_command()
    candidates = (
        (joinpath(ROOT_DIR, "bin", "transcribe.sh"), "bash bin/transcribe.sh"),
        (joinpath(ROOT_DIR, "bin", "transcribe.py"), "python3 bin/transcribe.py"),
        (joinpath(ROOT_DIR, "bin", "transcribe.jl"), "julia --project=. bin/transcribe.jl"),
        (joinpath(ROOT_DIR, "bin", "speech_cmd"), "bin/speech_cmd")
    )
    for (path, cmd) in candidates
        if isfile(path)
            return cmd
        end
    end
    return nothing
end

"""
    maybe_prompt_speech_cmd!(current)

Interactively ask whether speech input should be enabled. Returns the active command
or `nothing` when skipped. Prompts only when running in a TTY.
"""
function maybe_prompt_speech_cmd!(current::Union{Nothing,String})
    current !== nothing && return current
    stdin_is_tty() || return nothing

    println()
    println(t(:speech_enable_prompt))
    print("> ")
    response = try
        lowercase(strip(readline()))
    catch err
        isa(err, InterruptException) && rethrow()
        ""
    end
    affirmative = response in ("y", "yes", "j", "ja")
    affirmative || return nothing

    suggestion = detect_speech_command()
    if suggestion !== nothing
        println(t(:speech_candidate_found; command=suggestion))
        println(t(:speech_candidate_prompt))
    else
        println(t(:speech_candidate_request))
        println(t(:speech_candidate_example))
    end

    print("> ")
    chosen = try
        strip(readline())
    catch err
        isa(err, InterruptException) && rethrow()
        ""
    end
    effective = chosen == "" ? suggestion : chosen
    effective = normalize_speech_cmd(effective)
    if effective === nothing
        println(t(:speech_disabled))
        return nothing
    end
    println(t(:speech_enabled))
    return set_speech_cmd!(effective)
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
