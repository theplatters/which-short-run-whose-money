# Staged for the paper repo by the kernel split (2026-10-12, WP1).

using OpenCGE
using DataFrames
using LinearAlgebra
using Test

calibration_test_root() = normpath(joinpath(@__DIR__, ".."))

isdefined(Main, :tiny_fixture) || include(joinpath(@__DIR__, "test_helpers.jl"))

@testset "calibration: real-data v3 numbers (guarded)" begin
	root = calibration_test_root()
	io_path = joinpath(root, "data", "I-O_DE2019_formatiert.csv")
	if !isfile(io_path)
		@test_skip true  # data/ is gitignored; this block needs the IO table
	else
		full = read_data("I-O_DE2019_formatiert.csv"; datadir = root)
		@test length(full.factor_share) == 71
		@test sum(full.labor_share) ≈ 1.0 atol=1e-10
		recal71 = recalibrate_open(full; exo_scale = 1.0)
		# ADR-0012 (A-bill): the identity-implied saving rate; the clamp is gone.
		@test recal71.saving_rate ≈ 0.1199 atol = 1e-3
		@test sum(recal71.gov_demand) ≈ 0.214101 atol = 1e-4
		@test sum(recal71.M_int) ≈ 0.2214 atol = 1e-3
		# ADR-0013: row 75 (product taxes on intermediate use) is the third
		# component of the purchaser-price bill; booking it closes the canary.
		@test sum(recal71.T_int) ≈ 0.0257 atol = 1e-3
		@test sum(recal71.A_bill) + sum(recal71.M_int) + sum(recal71.T_int) ≈
			sum(recal71.λ) - 1.0 atol = 1e-10
		@test all(>=(0), recal71.household_baseline)

		# ADR-0013 contract (ADR-0019 reading): at the baseline root (F = 0,
		# B_gov = 0, all clearings ~0 and diff ~0) the value-weighted clearing
		# residual equals the external canary to machine precision. Before the
		# T_int term the identity was short by exactly sum(T_int) = 2.5745e-2
		# (the "−2.6e-2 reconciliation gap"). At the solved root both sides are
		# ≈ 0, so the all-N clearings and the identity gap are gated directly.
		mdl71 = mobile_labor_model(recal71, Shocks(ones(71), ones(71), zeros(71)),
			0.5, 0.5, 0.9, 1.0)
		X71 = [ones(71); recal71.λ; 1.0]
		@test abs(dot(ones(71), market_clearing_residuals(mdl71, X71)) -
			external_balance_canary(mdl71, X71).diff) < 1e-12
		sol71 = solve(mdl71)
		X71s = [sol71.prices_raw; sol71.quantities; sol71.wages_raw[1]; sol71.external_transfer]
		@test abs(dot(sol71.prices_raw, market_clearing_residuals(mdl71, X71s)) -
			external_balance_canary(mdl71, X71s).diff) < 1e-12
		@test maximum(abs, market_clearing_residuals(mdl71, X71s)) ≤ 1e-10
		@test abs(external_balance_canary(mdl71, X71s).diff) ≤ 1e-12

		# ADR-0016: off-baseline leak valuation. A +20 % sector-1 supply shock
		# moves the CES bill factor k away from 1. Under all-N + F the
		# supply-shock solution carries F ≠ 0 and the canary still closes
		# exactly; the pre-ADR-0016 valuation (k ≡ 1) would break it, as the
		# leak_fix/leak_old contrast at the solution point demonstrates.
		shock_sh = Shocks([1.2; ones(70)], ones(71), zeros(71))
		mdl_sh = mobile_labor_model(recal71, shock_sh, 0.5, 0.5, 0.9, 1.0)
		sol_sh = solve(mdl_sh)
		X_sh = [sol_sh.prices_raw; sol_sh.quantities; sol_sh.wages_raw[1]; sol_sh.external_transfer]
		P_sh = OpenCGE._intermediate_price(recal71.Ω_raw, sol_sh.prices_raw, 0.5)
		k_sh = sol_sh.prices_raw .^ 0.5 .* shock_sh.supply_shock .^ (-0.5) .* P_sh .^ 0.5
		@test maximum(abs.(k_sh .- 1)) > 1e-2
		@test abs(sol_sh.external_transfer) > 1e-6
		cl_sh = market_clearing_residuals(mdl_sh, X_sh)
		can_sh = external_balance_canary(mdl_sh, X_sh)
		@test maximum(abs, cl_sh) ≤ 1e-10
		@test abs(can_sh.diff) ≤ 1e-12
		leak_fix = dot(k_sh .* (recal71.M_int .+ recal71.T_int) ./ recal71.λ, sol_sh.quantities)
		leak_old = dot(sol_sh.prices_raw .* (recal71.M_int .+ recal71.T_int) ./ recal71.λ, sol_sh.quantities)
		@test abs(dot(sol_sh.prices_raw, cl_sh) - (can_sh.diff - (leak_fix - leak_old))) > 1e-6

		# Review findings 2.2/2.3: the rebuilt 70-sector dataset has probability
		# rows (the old slice left 0.9713) and Σ labor_share = 1 (was 0.9878).
		dropped = retained_dataset(full, [71])
		@test length(dropped.factor_share) == 70
		@test vec(sum(dropped.Ω_raw; dims = 2)) ≈ ones(70) atol=1e-10
		@test sum(dropped.labor_share) ≈ 1.0 atol=1e-10
		recal70 = recalibrate_open(dropped; exo_scale = 1.0)
		# ADR-0012: 70s re-anchored rate; one microscopic identity residual
		# (−2.4e-6, the retained-economy gap) is clamped and documented.
		@test recal70.saving_rate ≈ 0.1285 atol = 1e-3
		@test sum(recal70.gov_demand) ≈ 0.216741 atol = 1e-4
		@test 1.0 - sum(recal70.gov_demand) ≈ 0.783259 atol = 1e-4
		@test sum(recal70.M_int) ≈ 0.2237 atol = 1e-3
		@test sum(recal70.T_int) ≈ 0.0260 atol = 1e-3
		# The 70s canary identity holds to machine precision around the
		# documented microscopic retained-economy residual (−2.4e-6), which
		# appears identically on both sides (ADR-0013).
		mdl70 = mobile_labor_model(recal70, Shocks(ones(70), ones(70), zeros(70)),
			0.5, 0.5, 0.9, 1.0)
		X70 = [ones(70); recal70.λ; 1.0]   # legacy vector: F = 0
		mk70 = dot(ones(70), market_clearing_residuals(mdl70, X70))
		@test abs(mk70 - external_balance_canary(mdl70, X70).diff) < 1e-12
		@test abs(mk70) < 1e-5   # the disclosed microscopic clamp
		# Finiteness gate: worst-case round-gain column sums strictly below 1.
		colsums = (1.0 .- recal70.factor_share) .+
			(1.0 .- recal70.import_margin) .* (1.0 - recal70.saving_rate) .*
			recal70.factor_share
		@test maximum(colsums) < 1.0
		# Clamp mass (review finding 2.5) is disclosed, not reconciled: recompute
		# from the returned fields and pin the modelled number.
		m = recal70.import_margin
		c0 = dropped.λ .- dropped.Ω_raw' * ((1.0 .- dropped.factor_share) .* dropped.λ) .-
			(1.0 .- m) .* (recal70.gov_demand .+ recal70.exo_demand) .- recal70.exports_demand
		@test sum(abs.(min.(c0, 0.0))) ≈ 0.086197 atol = 1e-4
	end
end
