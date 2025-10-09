# High-level reporting workflow: ties together filters, leaderboards, and region
# prompts to drive the primary user experience within the reporting subsystem.

"""
prompt_region_details(df, ranking; config, weights, monthly_table)

Let the user pick regions from the ranking table for a deeper dive. Works interactively
when a terminal is available and prints hints otherwise.
"""
function prompt_region_details(df::DataFrame, ranking::DataFrame; config::CLIConfig, weights::Dict{Symbol,Float64}, monthly_table::DataFrame, region_index::Union{Nothing,Dict{String,DataFrame}}=nothing)
    if isempty(ranking)
        println()
        println(t(:hint_region_command))
        prompt_session_finish(config)
        return
    end

    regions = [string(r) for r in ranking.Region if r !== missing && strip(string(r)) != ""]
    tty = stdin_is_tty()
    if !tty
        if !isempty(regions)
            println()
            println(t(:info_no_tty_region_top; region=regions[1]))
        else
            println()
            println(t(:info_no_tty_region_generic))
        end
    end

    println()
    println(t(:prompt_region_details))
    while true
        input = try
            readline_with_speech("> ")
        catch err
            isa(err, InterruptException) && rethrow()
            ""
        end

        if input == ""
            prompt_session_finish(config)
            return
        end

        selection = nothing
        idx = tryparse(Int, input)
        if idx !== nothing && 1 <= idx <= nrow(ranking)
            region_value = ranking.Region[idx]
            if region_value !== missing && strip(string(region_value)) != ""
                selection = String(region_value)
            end
        end
        if selection === nothing
            for name in regions
                if slower(name) == slower(input)
                    selection = name
                    break
                end
            end
        end

        if selection === nothing
            println(t(:region_prompt_retry))
            continue
        end

        run_region(df, String(selection); weights=weights, monthly_table=monthly_table, region_index=region_index)

        println()
        println(t(:prompt_region_another))
        if !prompt_yes_no()
            prompt_session_finish(config)
            return
        end
        println()
        println(t(:prompt_region_next))
    end
end

"""
run_report(df, config, weights)

The main reporting pipeline: show the active filters, display leaderboards, and then
offer detailed region exploration.
"""
function run_report(df::DataFrame, config::CLIConfig, weights::Dict{Symbol,Float64}; weights_adjusted::Bool=true)
    print_active_filters(config, df)
    print_active_weights(weights)

    !weights_adjusted && print_daily_scoreboard(df; top_n=10)

    monthly = print_monthly_overview_for_all_regions(df; weights=weights, display=!weights_adjusted)
    ranked = print_weighted_ranking(monthly.table, monthly.label)
    region_index = build_region_index(df)
    prompt_region_details(df, ranked; config=config, weights=weights, monthly_table=monthly.table, region_index=region_index)
end
