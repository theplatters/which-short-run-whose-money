# Staged for the paper repo by the kernel split (2026-10-12, WP1).

using OpenCGE, Test, LinearAlgebra
using CSV, DataFrames
isdefined(Main, :tiny_fixture) || include(joinpath(@__DIR__, "test_helpers.jl"))

"Repo root (parent of tests/)."

sec_test_root() = normpath(joinpath(@__DIR__, ".."))

"Full-71 A-bill calibration, or `nothing` when the IO table is absent."

function sec_test_data()
	root = sec_test_root()
	isfile(joinpath(root, "data", "I-O_DE2019_formatiert.csv")) || return nothing
	return recalibrate_open(
		read_data("I-O_DE2019_formatiert.csv"; datadir = root); exo_scale = 1.0)
end

"Matrix programme bundle `g` (and its incidence), or `nothing` when absent."

function sec_matrix_programme(data::Data)
	root = sec_test_root()
	imp_path = joinpath(root, "data", "impulses.csv")
	isfile(imp_path) || return nothing
	imp = CSV.read(imp_path, DataFrame)
	rows = imp[imp.year .== 2024, :]
	raw = Matrix{Float64}(rows[1:1, 3:73])[:]
	ψ = raw ./ sum(raw)
	return (40300.0 / data.gdp_production) .* ψ, ψ
end

@testset "ADR-0022 sectoral closure (full-71 calibration)" begin
	data = sec_test_data()
	if data === nothing
		@info "ADR-0022 real-data block skipped: IO table absent"
	else
		prog = sec_matrix_programme(data)
		if prog === nothing
			@info "ADR-0022 real-data block skipped: impulse table absent"
		else
			N = length(data.factor_share)
			shocks = Shocks(ones(N), ones(N), zeros(N))
			g, _ = prog

			# ── (2) THE CANARY: eta_s,i = 0 reproduces the eta = 0 endpoint ──
			# The committed matrix_5x3-v6 BF cells are exactly this system, so a
			# mismatch here means the kernel change is wrong.
			m0 = mobile_labor_model(data, shocks, 0.5, 0.5, 0.9, 0.0;
				financing = TaxFinanced(g))
			s0 = solve(m0)
			mz = mobile_labor_model(data, shocks, 0.5, 0.5, 0.9, 1.0;
				eta_s_vec = zeros(N), financing = TaxFinanced(g))
			sz = solve(mz; init = [s0.prices_raw; s0.quantities; s0.wages_raw;
				s0.external_transfer])
			@test length(sz.wages_raw) == N
			@test maximum(abs, sz.prices_raw .- s0.prices_raw) < 1e-10
			@test maximum(abs, sz.quantities .- s0.quantities) < 1e-10
			@test maximum(abs, sz.wages_raw .- s0.wages_raw) < 1e-10
			@test abs(sz.external_transfer - s0.external_transfer) < 1e-10
			@test max_equilibrium_residual(sz) < 1e-9

			# ── (3) demand sensitivity, and the contrast with scalar BETA ──
			# Same eta_s value, two closures: the N-market system moves prices
			# with the demand composition; the single-wage one does not.
			eta = 0.5
			m_f2 = mobile_labor_model(data, shocks, 0.5, 0.5, 0.9, 1.0;
				eta_s_vec = fill(eta, N), financing = TaxFinanced(g))
			m_f3 = mobile_labor_model(data, shocks, 0.5, 0.5, 0.9, 1.0;
				eta_s_vec = fill(eta, N), financing = ExternalDebt(g))
			s_f2 = solve(m_f2; init = [s0.prices_raw; s0.quantities; s0.wages_raw;
				s0.external_transfer])
			s_f3 = solve(m_f3; init = [s_f2.prices_raw; s_f2.quantities; s_f2.wages_raw;
				s_f2.external_transfer])
			@test maximum(abs, s_f2.prices_raw .- 1) > 1e-3     # prices move at all
			@test maximum(abs, s_f2.prices_raw .- s_f3.prices_raw) < 1e-8  # F2/F3 neutral
			@test maximum(abs, s_f2.wages_raw .- s_f3.wages_raw) < 1e-8

			m_beta = mobile_labor_model(data, shocks, 0.5, 0.5, 0.9, 1.0;
				eta_s = eta, financing = TaxFinanced(g))
			s_beta = solve(m_beta; init = [s_f2.prices_raw; s_f2.quantities;
				s_f2.wages_raw[1]; s_f2.external_transfer])
			@test maximum(abs, s_beta.prices_raw .- 1) < 1e-8   # single wage: no price move

			# ── the external account closes in the sectoral system too ──
			X = [s_f2.prices_raw; s_f2.quantities; s_f2.wages_raw; s_f2.external_transfer]
			@test abs(external_balance_canary(m_f2, X).diff) < 1e-8
			@test max_equilibrium_residual(s_f2) < 1e-9
			@test gdp_components(m_f2, s_f2).wage_bill ≈
				sum(s_f2.wages_raw .* sectoral_labor_demand(s_f2.prices_raw, s_f2.quantities, s_f2.wages_raw, m_f2)) rtol = 1e-10
			@test gdp_wedge(s_f2) ≈ -external_balance_canary(m_f2, X).diff atol = 1e-9
		end
	end
end
