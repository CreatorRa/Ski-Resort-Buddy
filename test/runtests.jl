# Test suite for SkiLookup helper functions used by the resort advisor tooling.
# Each testset documents the critical behaviour expected from its target helper.
using Test
using Dates
using DataFrames
using SkiLookup

const SL = SkiLookup
const SNOW_DEPTH_COL = Symbol("Snow Depth (cm)")
const SNOW_NEW_COL = Symbol("Snow_New (cm)")
const PRECIP_COL = Symbol("Precipitation (mm)")
const TEMP_COL = Symbol("Temperature (A$(Char(0x00B0))C)")


# Verifies numeric series cleaning removes non-numeric entries while keeping dates in sync.
# Input: sequential dates plus mixed-value vector. Output: filtered date vector and Float64 values.
@testset "clean_numeric_series" begin
    dates = collect(Date(2025, 1, 1):Day(1):Date(2025, 1, 5))
    values = Any[1, missing, 3, nothing, "bad"]
    xs, ys = SL.clean_numeric_series(dates, values)
    @test xs == [Date(2025, 1, 1), Date(2025, 1, 3)]
    @test ys == [1.0, 3.0]
end

# Ensures collect_valid keeps only numeric values and skips missing-like entries.
# Input: heterogeneous collection with numerics and sentinel values. Output: Float64 array of valid entries.
@testset "collect_valid" begin
    vals = Any[1, missing, 2.5, nothing, "bad", 3.0, NaN]
    @test SL.collect_valid(vals) == [1.0, 2.5, 3.0]
end


# Checks the rolling mean uses trailing windows and preserves input when window=1.
# Input: Float64 series and window length. Output: trailing-window averages matching original length.
@testset "rolling_mean" begin
    v = [1.0, 2.0, 3.0, 4.0, 5.0]
    result = SL.rolling_mean(v, 3)
    @test isapprox(result, [1.5, 2.0, 3.0, 4.0, 4.5]; atol=1e-8)
    @test SL.rolling_mean(v, 1) == v
end

# Confirms country codes are mapped to canonical names after trimming.
# Input: ISO code or padded country name. Output: canonical country string.
@testset "canonical_country" begin
    @test SL.canonical_country("DE") == "Germany"
    @test SL.canonical_country(" Liechtenstein ") == "Liechtenstein"
end



# Tests weight parsing tolerates whitespace, percentages, and locale decimal separators.
# Input: string tokens with whitespace, percent, or locale decimal marks. Output: parsed Float64 or nothing.
@testset "parse_weight_value" begin
    @test SL.parse_weight_value(" 12.5 ") == 12.5
    @test SL.parse_weight_value("55%") == 55.0
    @test SL.parse_weight_value("7,5") == 7.5
    @test SL.parse_weight_value("invalid") === nothing
end

# Validates tolerant boolean parsing for common on/off keywords.
# Input: case-insensitive truthy/falsy string. Output: Bool flag or nothing when unrecognized.
@testset "parse_bool" begin
    @test SL.parse_bool(" yes ") === true
    @test SL.parse_bool("OFF") === false
    @test SL.parse_bool("maybe") === nothing
end

# Asserts weight normalization sums to 100 and falls back to defaults when all weights are zero.
# Input: metric weight dictionary. Output: mutated dictionary normalized to 100% or reset to defaults.
@testset "normalize_weights!" begin
    weights = Dict(
        :snow_new => 10.0,
        :snow_depth => 10.0,
        :temperature => 10.0,
        :precipitation => 10.0,
        :wind => 10.0
    )
    SL.normalize_weights!(weights)
    @test isapprox(sum(values(weights)), 100.0; atol=1e-8)
    @test isapprox(weights[:snow_new], 20.0; atol=1e-8)
    zero_weights = Dict(
        :snow_new => 0.0,
        :snow_depth => 0.0,
        :temperature => 0.0,
        :precipitation => 0.0,
        :wind => 0.0
    )
    SL.normalize_weights!(zero_weights)
    for (key, value) in SL.DEFAULT_METRIC_WEIGHTS
        @test zero_weights[key] == value
    end
end




