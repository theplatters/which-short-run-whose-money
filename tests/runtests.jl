# tests/runtests.jl — paper-repo suite (post kernel split).
using Test

include("test_helpers.jl")
include("test_calibration.jl")
include("test_gdp_measurement.jl")
include("test_external_closure.jl")
include("test_table5_welfare.jl")
include("test_pricing_reporting.jl")
include("test_sectoral_labour.jl")
include("test_run_manifest.jl")
include("test_f1_tilt.jl")
