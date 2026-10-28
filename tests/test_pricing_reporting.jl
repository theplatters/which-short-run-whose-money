using Test, CSV, DataFrames
isdefined(Main, :consumption_unit_prices) ||
    include(joinpath(@__DIR__, "..", "experiments", "make_pricing_prices.jl"))

@testset "pricing reporting: invariant to the solver's nominal scale" begin
    p = [0.94, 1.08, 1.03]
    beta = [0.2, 0.5, 0.3]
    for sigma in (0.0001, 0.9, 1.0)
        a = consumption_unit_prices(p, beta, sigma, 0.99)
        b = consumption_unit_prices(3.7 .* p, beta, sigma, 3.7 * 0.99)
        @test isapprox(a.gdp_deflator_cpi, b.gdp_deflator_cpi; atol = 1e-12)
        @test isapprox(a.max_abs_price_dev_cpi, b.max_abs_price_dev_cpi; atol = 1e-12)
        normalized = consumption_unit_prices(p ./ a.cpi_raw, beta, sigma, a.gdp_deflator_cpi)
        @test isapprox(normalized.cpi_raw, 1.0; atol = 1e-12)
    end
    @test_throws ErrorException consumption_unit_prices([0.0, 1.0], [0.5, 0.5], 0.9, 1.0)
end

@testset "pricing reporting: derived table and source gates" begin
    root = default_root()
    stored = CSV.read(joinpath(root, PRICE_SIDECAR), DataFrame)
    @test length(unique(stored.run_id)) == nrow(stored)
    # A full reconstruction additionally checks real GDP invariance on every
    # wage-normalized cell. Run it when machine-local solution artifacts exist.
    available = isfile(joinpath(root, "data", RUN_IO_TABLE)) &&
        all(isfile(joinpath(root, "runs", id, "solution.csv")) for id in stored.run_id)
    if available
        got = pricing_price_rows(; root)
        @test got.run_id == stored.run_id
        @test got.manifest_sha256 == stored.manifest_sha256
        @test got.solution_sha256 == stored.solution_sha256
        @test isapprox(got.gdp_deflator_cpi, stored.gdp_deflator_cpi; atol = 1e-12)
        @test isapprox(got.max_abs_price_dev_cpi, stored.max_abs_price_dev_cpi; atol = 1e-12)
    else
        @test_skip "machine-local pricing solutions unavailable"
    end
    # The table builder must use the normalized prices and reject stale
    # provenance, including when a clean clone has no solution.csv files.
    code = """
import importlib.util
spec = importlib.util.spec_from_file_location('pricing', 'revision/tables/make_pricing_door.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
rid = 'pricing_capacity_rows-DELTA-F3-dm05-s0'
v = m.values(rid)
# Level column (ADR-0058): the average real consumption wage on every row,
# never the deflator-over-CPI ratio. A pinned cell has w = 1, so omega = P0/P.
prices = m.PRICES[rid]
cpi = float(prices['cpi_raw'])/float(prices['cpi_reference'])
assert abs(v['P'] - 100*(1.0/cpi - 1.0)) < 1e-7
assert abs(v['P'] - 100*(float(prices['gdp_deflator_cpi'])-1.0)) > 0.1, 'must not print the ratio'
for r_, w_ in [('pricing_profit-GAMMA-F3-k05-spi0', (-1.99, 9.89)),
               ('pricing_capacity-GAMMA-F3-dp05-s0', (-0.30, 4.26)),
               ('pricing_profit-DELTA-F3-k05-spi0', (-2.19, 12.05)),
               ('pricing_markup-ALPHA-F2-k05', (0.18, 10.50)),
               ('pricing_markup-BF-F2-k05', (0.77, 34.63)),
               ('matrix_5x3-BF-F2', (0.70, 27.90))]:
    g = m.values(r_)
    assert abs(g['P'] - w_[0]) < 0.011 and abs(g['D'] - w_[1]) < 0.3, (r_, g, w_)
# The merged Table 7 keeps its no-extension reference rows and W_D sidecar (printed as Delta Y).
assert m.COLS_MK[3][0] == 'WD'
for row, _ in m.ROWS:
    for f in m.FIN:
        baseline = f'matrix_5x3-{row}-{f}' + ('-etas05' if row == 'BETA' else '')
        got = m.values(baseline)
        assert abs(got['P'] - 100*(m.manifest(baseline)['metrics']['wage']-1)) < 1e-6
        assert abs(got['WD'] - m.WD[baseline]) < 1e-12
assert abs(m.values('pricing_profit-GAMMA-F3-k05-spi0')['WD'] - 3.86) < 0.005
table = m.build_mk_table()
assert table.count('no extension') == 5
assert 'Delta Y' in table and 'W_D' not in table
m.reported_prices.cache_clear()
m.PRICES[rid]['manifest_sha256'] = 'stale'
try:
    m.reported_prices(rid)
except AssertionError as e:
    assert 'stale prices' in str(e)
else:
    raise AssertionError('stale price sidecar accepted')
"""
    @test success(Cmd(`python3 -c $code`; dir = root))
end
