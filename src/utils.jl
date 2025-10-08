# Utility helpers split into three easy-to-find groups:
#   - string_and_numeric_utils : small text/number helpers used across the app
#   - speech_and_input_utils  : functions that ask the user questions or call speech tools
#   - dataset_lookup_utils    : shortcuts to list or filter regions and countries
# The includes keep the public API unchanged while making each file simpler to read.

include("utils_components/string_and_numeric_utils.jl")
include("utils_components/speech_and_input_utils.jl")
include("utils_components/dataset_lookup_utils.jl")
