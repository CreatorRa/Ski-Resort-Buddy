"""
stdin_is_tty()

Return `true` when the program is connected to a real terminal window. Interactive
prompts should only appear in that case.
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

Clean up a speech command string. Empty or whitespace-only input returns `nothing`,
which signals that speech capture is disabled.
"""
function normalize_speech_cmd(cmd)
    isnothing(cmd) && return nothing
    text = strip(String(cmd))
    return text == "" ? nothing : text
end

"""
current_speech_cmd()

Return the speech command stored for the current session, or `nothing` when speech
input is off.
"""
current_speech_cmd() = SPEECH_CMD[]

"""
set_speech_cmd!(cmd)

Store the active speech command after cleaning it with `normalize_speech_cmd`. The
effective command (or `nothing`) is returned.
"""
function set_speech_cmd!(cmd)
    SPEECH_CMD[] = normalize_speech_cmd(cmd)
    return SPEECH_CMD[]
end

"""
run_speech_capture(cmd)

Run the external speech command and return its trimmed output. Any problem results in
`nothing` plus a warning so keyboard input can take over.
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
readline_with_speech(prompt="> "; ...)

Ask the user for input. If a speech command is configured we try it first and fall
back to keyboard input when nothing useful is heard.
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

Look for known helper scripts (`transcribe.sh`, etc.) and return the first command we
find. If no helper is present, `nothing` is returned.
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

Offer the user a choice to enable speech input when we are running in a terminal. The
resolved command (or `nothing`) is returned.
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
