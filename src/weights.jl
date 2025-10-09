using .Localization: t
import Base: lowercase

"""
Weight helpers: this module keeps everything related to metric weighting together.
It defines:
  • the available metrics and their defaults
  • optional presets users can choose from
  • parsing helpers for CLI/environment overrides
  • interactive prompts that guide manual adjustments
All weight-related tasks start here.
"""
# METRIC_WEIGHT_CONFIG: maps each metric key to the column we look at, the prompt text,
# the environment override name, and whether a higher or lower value should be treated
# as better.
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

# WEIGHT_PRESET_CONFIG: defines the preset bundles (balanced, powder, family, sunny)
# including display names, helpful aliases, and the weight values they apply.
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

# METRIC_WEIGHT_FLAGS: connects CLI flags (for example `--weight-snow-new`) to the
# internal metric keys so overrides land in the correct slot.
const METRIC_WEIGHT_FLAGS = Dict(
    "--weight-snow-new" => :snow_new,
    "--weight-snow-depth" => :snow_depth,
    "--weight-temperature" => :temperature,
    "--weight-precipitation" => :precipitation,
    "--weight-wind" => :wind
)

"""
clone_metric_weights()

Return a copy of the default weights so callers can tweak the values without touching
the shared defaults.
"""
function clone_metric_weights()
    return Dict(key => DEFAULT_METRIC_WEIGHTS[key] for (key, _) in METRIC_WEIGHT_CONFIG)
end

"""
parse_weight_value(raw)

Turn a user-supplied weight (like "25" or "25%") into a number. Returns `nothing`
when the text cannot be understood.
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

Read common yes/no strings and return `true`, `false`, or `nothing` if the value is
ambiguous.
"""
function parse_bool(value::AbstractString)
    normalized = lowercase(strip(value))
    normalized in ("1", "true", "yes", "y", "on") && return true
    normalized in ("0", "false", "no", "n", "off") && return false
    return nothing
end

"""
apply_weight_env_overrides!(weights)

Check environment variables like `WEIGHT_SNOW_NEW` and update the weight map when the
values look valid. Warnings are printed otherwise.
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

"""
apply_weight_preset!(weights, preset)

Copy the numbers from a preset into the weight map and normalise the result so the
weights still add up to 100.
"""
function apply_weight_preset!(weights::Dict{Symbol,Float64}, preset)
    for (key, _) in METRIC_WEIGHT_CONFIG
        weights[key] = get(preset.weights, key, get(DEFAULT_METRIC_WEIGHTS, key, 0.0))
    end
    normalize_weights!(weights)
    return weights
end

"""
prompt_weight_profile!(weights; force=false)

Show the preset list (balanced, powder, family, sunny) and let the user pick. Returns
one of four symbols:
  • `:skip`           – nothing was changed, move along
  • `:manual`         – user wants to enter every weight manually
  • `:preset`         – preset applied, no further adjustments requested
  • `:preset_manual`  – preset applied, user wants to tweak numbers afterwards
"""
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
        println(t(:weights_profile_adjust_prompt))
        return prompt_yes_no() ? :preset_manual : :preset
    end
end

"""
prompt_metric_weights!(weights; force=false)

Ask the user for each metric weight one by one. Pressing Enter keeps the current
value. The function loops until the total equals 100, otherwise it restarts the
questions with a friendly reminder.
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

Rescale all weights so they sum to 100. If the sum is zero or negative we warn the
user, restore the defaults, and return those.
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

High-level helper used by the CLI/menu. Steps:
  1. Optionally show the preset picker (forced when `force=true` without a TTY).
  2. If the user wants manual input, call `prompt_metric_weights!`.
  3. Normalise weights before returning them.
Always returns the updated dictionary.
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
