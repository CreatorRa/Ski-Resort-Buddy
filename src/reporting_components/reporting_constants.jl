const HEADER_CRAYON = PrettyTables.Crayon(foreground=:cyan, bold=true)
const STRIPE_CRAYON = PrettyTables.Crayon(background=:blue)
const POSITIVE_CRAYON = PrettyTables.Crayon(foreground=:green, bold=true)
const NEGATIVE_CRAYON = PrettyTables.Crayon(foreground=:red, bold=true)

const TABLE_HIGHLIGHTERS = [
    PrettyTables.TextHighlighter((data, i, j) -> iseven(i), STRIPE_CRAYON),
    PrettyTables.TextHighlighter((data, i, j) -> data[i, j] isa Number && data[i, j] > 0, POSITIVE_CRAYON),
    PrettyTables.TextHighlighter((data, i, j) -> data[i, j] isa Number && data[i, j] < 0, NEGATIVE_CRAYON)
]

if !isdefined(@__MODULE__, :CLIConfig)
    const CLIConfig = Any
end

const REGION_METRIC_OPTIONS = (
    (key=:snow_depth, column=Symbol("Snow Depth (cm)"), display_key=:metric_snow_depth, aliases=("snow depth", "schneehöhe"), color=:dodgerblue, window=7, recent_days=180, plot=:line),
    (key=:snow_new, column=Symbol("Snow_New (cm)"), display_key=:metric_snow_new, aliases=("new snow", "neuschnee"), color=:lightskyblue, window=5, recent_days=120, plot=:bar),
    (key=:temperature, column=Symbol("Temperature (°C)"), display_key=:metric_temperature, aliases=("temperature", "temperatur"), color=:tomato, window=7, recent_days=180, plot=:line),
    (key=:precipitation, column=Symbol("Precipitation (mm)"), display_key=:metric_precipitation, aliases=("precipitation", "niederschlag"), color=:seagreen, window=7, recent_days=180, plot=:line),
    (key=:wind, column=Symbol("Wind (Beaufort)"), display_key=:metric_wind, aliases=("wind", "windstärke"), color=:goldenrod, window=7, recent_days=180, plot=:line),
    (key=:snow_trend, column=Symbol("Snow Depth (cm)"), display_key=:metric_snow_trend, aliases=("snow trend", "schneetrend", "schnee trend"), color=:dodgerblue, window=7, recent_days=120, plot=:line, plot_kind=:snow)
)

const MONTHLY_OVERVIEW_STATUS_MESSAGES = Dict(
    :no_date => :info_monthly_no_date,
    :no_metrics => :info_monthly_no_metrics,
    :no_month_values => :info_monthly_no_month_values,
    :no_rows => :info_monthly_no_rows,
    :empty_grouping => :info_monthly_empty_grouping
)
