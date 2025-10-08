using SHA
using Base: bytes2hex

const REMOTE_CACHE_DIR = joinpath(ROOT_DIR, "data", "remote_cache")

# Data loading helpers live here but are split into three bite-sized files:
#   • series_processing – smoothing and interpolating number series
#   • data_paths        – finding and caching CSV files
#   • dataset_enrichment – cleaning column names and applying filters
include("transforms_components/series_processing.jl")
include("transforms_components/data_paths.jl")
include("transforms_components/dataset_enrichment.jl")
