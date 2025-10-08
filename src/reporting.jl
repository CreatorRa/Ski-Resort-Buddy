"""
Reporting subsystem: glues together the monthly analytics, plotting, region insights,
and interactive prompts. This module aggregates specialised files so consumers only
need to import `Reporting` to access the full reporting surface.
"""
module Reporting

using Dates
using DataFrames
using Plots
using PrettyTables
using Printf: @sprintf
using Statistics

using ..Localization: t

const _PARENT = parentmodule(@__MODULE__)

const CLIConfig = getfield(_PARENT, :CLIConfig)
const COMMAND_PREFIX = getfield(_PARENT, :COMMAND_PREFIX)
const DEFAULT_METRIC_WEIGHTS = getfield(_PARENT, :DEFAULT_METRIC_WEIGHTS)
const METRIC_WEIGHT_CONFIG = getfield(_PARENT, :METRIC_WEIGHT_CONFIG)
const PLOTS_OUTPUT_DIR = getfield(_PARENT, :PLOTS_OUTPUT_DIR)

const available_regions = getfield(_PARENT, :available_regions)
const collect_valid = getfield(_PARENT, :collect_valid)
const ensure_plot_dir = getfield(_PARENT, :ensure_plot_dir)
const readline_with_speech = getfield(_PARENT, :readline_with_speech)
const rolling_mean = getfield(_PARENT, :rolling_mean)
const slugify = getfield(_PARENT, :slugify)
const print_available_regions = getfield(_PARENT, :print_available_regions)
const stdin_is_tty = getfield(_PARENT, :stdin_is_tty)
const clean_numeric_series = getfield(_PARENT, :clean_numeric_series)
const slower = getfield(_PARENT, :slower)

include("reporting_components/reporting_constants.jl")
include("reporting_components/reporting_helpers.jl")
include("reporting_components/monthly_overview.jl")
include("reporting_components/reporting_plots.jl")
include("reporting_components/region_details.jl")
include("reporting_components/reporting_workflow.jl")

export run_report,
       run_region,
       run_list,
       prompt_region_details,
       prompt_region_metric_plots,
       print_daily_scoreboard,
       print_monthly_overview_for_all_regions,
       print_weighted_ranking,
       print_active_weights,
       print_active_filters,
       print_region_history,
       save_region_metric_trend,
       save_region_snow_plot,
       save_region_score_trend,
       region_metric_options,
       qc_checks,
       print_data_preview

end # module Reporting
