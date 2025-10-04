using .Localization: t
import Base: lowercase

"""
Weight configuration & prompting utilities: centralises how scoring metrics are
described, defaulted, overridden (ENV/CLI), and normalised for interactive/report
runs.
"""
const METRIC_WEIGHT_CONFIG = (
    :snow_new => (column=Symbol("Avg Snow_New (cm)"), prompt_key=:weight_prompt_snow_new, label_key=:weight_label_snow_new, env="WEIGHT_SNOW_NEW", preference=:higher),
    :snow_depth => (column=Symbol("Avg Snow Depth (cm)"), prompt_key=:weight_prompt_snow_depth, label_key=:weight_label_snow_depth, env="WEIGHT_SNOW_DEPTH", preference=:higher),
    :temperature => (column=Symbol("Avg Temperature (°C)"), prompt_key=:weight_prompt_temperature, label_key=:weight_label_temperature, env="WEIGHT_TEMPERATURE", preference=:lower),
    :precipitation => (column=Symbol("Avg Precipitation (mm)"), prompt_key=:weight_prompt_precipitation, label_key=:weight_label_precipitation, env="WEIGHT_PRECIPITATION", preference=:lower),
    :wind => (column=Symbol("Avg Wind (Beaufort)"), prompt_key=:weight_prompt_wind, label_key=:weight_label_wind, env="WEIGHT_WIND", preference=:lower)
)

const DEFAULT_METRIC_WEIGHTS = Dict(
    :snow_new => 30.0,
    :snow_depth => 25.0,
    :temperature => 20.0,
    :precipitation => 15.0,
    :wind => 10.0
)

const WEIGHT_PRESET_CONFIG = (
    (key=:balanced,
     name_key=:weights_preset_balanced_name,
     description_key=:weights_preset_balanced_description,
     aliases=("balanced", "default", "standard", "ausgewogen"),
     weights=Dict(DEFAULT_METRIC_WEIGHTS)),
    (key=:powder,
     name_key=:weights_preset_powder_name,
     description_key=:weights_preset_powder_description,
     aliases=("powder", "pulver", "powderhunter", "powderjaeger", "powderjäger", "pulverschnee"),
     weights=Dict(
        :snow_new => 45.0,
        :snow_depth => 35.0,
        :temperature => 8.0,
        :precipitation => 7.0,
        :wind => 5.0
    )),
    (key=:family,
     name_key=:weights_preset_family_name,
     description_key=:weights_preset_family_description,
     aliases=("family", "familie", "familyfriendly", "familienfreundlich"),
     weights=Dict(
        :snow_new => 15.0,
        :snow_depth => 30.0,
        :temperature => 25.0,
        :precipitation => 15.0,
        :wind => 15.0
    )),
    (key=:sunny,
     name_key=:weights_preset_sunny_name,
     description_key=:weights_preset_sunny_description,
     aliases=("sunny", "sonnig", "sun", "sunnyskier", "sonnenskifahrer"),
     weights=Dict(
        :snow_new => 20.0,
        :snow_depth => 20.0,
        :temperature => 35.0,
        :precipitation => 10.0,
        :wind => 15.0
    ))
)

const METRIC_WEIGHT_FLAGS = Dict(
    "--weight-snow-new" => :snow_new,
    "--weight-snow-depth" => :snow_depth,
    "--weight-temperature" => :temperature,
    "--weight-precipitation" => :precipitation,
    "--weight-wind" => :wind
)

"""
    clone_metric_weights()

Return a fresh copy of the default metric weights dictionary so downstream callers can
mutate the map without affecting the global defaults.
"""
function clone_metric_weights()
    return Dict(key => DEFAULT_METRIC_WEIGHTS[key] for (key, _) in METRIC_WEIGHT_CONFIG)
end

"""
    parse_weight_value(raw)

Normalise user-provided weight strings by trimming whitespace, converting commas to
decimal points, and attempting to parse a `Float64`. Returns `nothing` on failure.
"""
function parse_weight_value(raw::AbstractString)
    normalized = replace(strip(raw), "," => ".")
    normalized = lowercase(normalized)
    endswith(normalized, "%") && (normalized = normalized[1:end-1])
    val = tryparse(Float64, normalized)
    return val
end

"""
    parse_bool(value)

Interpret typical boolean string forms (`"true"`, `"1"`, `"yes"`, etc.) and return
`true`/`false`, or `nothing` when the token cannot be classified.
"""
function parse_bool(value::AbstractString)
    normalized = lowercase(strip(value))
    normalized in ("1", "true", "yes", "y", "on") && return true
    normalized in ("0", "false", "no", "n", "off") && return false
    return nothing
end

"""
    apply_weight_env_overrides!(weights)

Apply environment-variable overrides (`WEIGHT_*`) to the weight dictionary in-place.
Invalid values emit warnings while leaving the current weight untouched.
"""
function apply_weight_env_overrides!(weights::Dict{Symbol,Float64})
    for (key, cfg) in METRIC_WEIGHT_CONFIG
        env_key = cfg.env
        if haskey(ENV, env_key)
            parsed = parse_weight_value(ENV[env_key])
            if parsed !== nothing
                weights[key] = parsed
            else
                @warn t(:warn_invalid_weight_env; env=env_key) value=ENV[env_key]
            end
        end
    end
    return weights
end

function apply_weight_preset!(weights::Dict{Symbol,Float64}, preset)
    for (key, _) in METRIC_WEIGHT_CONFIG
        weights[key] = get(preset.weights, key, get(DEFAULT_METRIC_WEIGHTS, key, 0.0))
    end
    normalize_weights!(weights)
    return weights
end

function prompt_weight_profile!(weights::Dict{Symbol,Float64}; force::Bool=false)
    if !(stdin_is_tty() || force)
        return :skip
    end
    println()
    println(t(:weights_profile_header))
    println(t(:weights_profile_hint))
    for (idx, preset) in enumerate(WEIGHT_PRESET_CONFIG)
        println(t(:weights_profile_option; index=idx, name=t(preset.name_key), description=t(preset.description_key)))
    end
    custom_index = length(WEIGHT_PRESET_CONFIG) + 1
    println(t(:weights_profile_option_custom; index=custom_index))
    while true
        input = try
            strip(readline_with_speech("> "; fallback_on_empty=true))
        catch err
            isa(err, InterruptException) && rethrow()
            println(t(:weights_profile_invalid))
            return :skip
        end
        if input == ""
            return :manual
        end
        lowered = lowercase(input)
        if lowered in ("custom", "manual", "manuell")
            return :manual
        end
        parsed = tryparse(Int, input)
        chosen = nothing
        if parsed !== nothing
            if 1 <= parsed <= length(WEIGHT_PRESET_CONFIG)
                chosen = WEIGHT_PRESET_CONFIG[parsed]
            elseif parsed == custom_index
                return :manual
            end
        else
            for preset in WEIGHT_PRESET_CONFIG
                if lowered in preset.aliases
                    chosen = preset
                    break
                end
            end
        end
        if chosen === nothing
            println(t(:weights_profile_invalid))
            continue
        end
        apply_weight_preset!(weights, chosen)
        println(t(:weights_profile_applied; name=t(chosen.name_key)))
        while true
            println(t(:weights_profile_adjust_prompt))
            response = try
                lowercase(strip(readline_with_speech("> "; fallback_on_empty=true)))
            catch err
                isa(err, InterruptException) && rethrow()
                response = ""
            end
            if response in ("", "n", "no", "nein")
                return :preset
            elseif response in ("y", "yes", "j", "ja")
                return :preset_manual
            else
                println(t(:weights_profile_invalid))
            end
        end
    end
end

"""
    prompt_metric_weights!(weights; force=false)

Interactively collect metric weights from the user. Non-interactive sessions can set
`force=true` to display the prompt regardless of TTY detection. Inputs must be between
0 and 100 and the final sum must equal 100.
"""
function prompt_metric_weights!(weights::Dict{Symbol,Float64}; force::Bool=false)
    if !(stdin_is_tty() || force)
        println(t(:info_weights_prompt_skipped))
        return weights
    end
    println()
    println(t(:weights_prompt_header))
    println(t(:weights_prompt_instructions))
    println(t(:weights_prompt_hint_lower_better))
    for (key, cfg) in METRIC_WEIGHT_CONFIG
        default = get(weights, key, 0.0)
        prompt_template = get(cfg, :prompt_key, nothing)
        prompt_text = prompt_template === nothing ? string(key) : t(prompt_template)
        while true
            response = try
                readline_with_speech("$(prompt_text) [$(round(default; digits=2))]: "; fallback_on_empty=false)
            catch err
                isa(err, InterruptException) && rethrow()
                ""
            end
            response == "" && break
            parsed = parse_weight_value(response)
            if parsed === nothing || parsed < 0 || parsed > 100
                println(t(:error_weight_value_range))
                continue
            end
            weights[key] = parsed
            break
        end
    end
    total = sum(values(weights))
    if !(abs(total - 100.0) <= 1e-6)
        println()
        println(t(:error_weight_sum; sum=round(total; digits=2)))
        return prompt_metric_weights!(weights; force=force)
    end
    return weights
end

"""
    normalize_weights!(weights)

Scale all weight values so that their sum equals 100. When the total is non-positive,
the defaults are restored.
"""
function normalize_weights!(weights::Dict{Symbol,Float64})
    total = sum(values(weights))
    if total <= eps(Float64)
        @warn t(:warn_weight_sum_non_positive) current=weights
        for (key, value) in DEFAULT_METRIC_WEIGHTS
            weights[key] = value
        end
        return weights
    end
    factor = 100.0 / total
    for (key, value) in weights
        weights[key] = value * factor
    end
    return weights
end

"""
    prepare_weights!(weights; force, prompt)

Optionally prompt the user for custom weights (honouring forced prompts for non-TTY
sessions). Returns the mutated dictionary for convenience.
"""
function prepare_weights!(weights::Dict{Symbol,Float64}; force::Bool, prompt::Bool)
    if prompt
        selection = prompt_weight_profile!(weights; force=force)
        if selection == :manual || selection == :preset_manual
            prompt_metric_weights!(weights; force=force)
        end
        normalize_weights!(weights)
    else
        normalize_weights!(weights)
    end
    return weights
end
