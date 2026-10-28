# Staged for the paper repo by the kernel split (2026-10-12, WP1).

using OpenCGE, Test, LinearAlgebra
using CSV, DataFrames
isdefined(Main, :tiny_fixture) || include(joinpath(@__DIR__, "test_helpers.jl"))


ext_test_root() = normpath(joinpath(@__DIR__, ".."))


function ext_test_data()
	root = ext_test_root()
	isfile(joinpath(root, "data", "I-O_DE2019_formatiert.csv")) || return nothing
	return recalibrate_open(
		read_data("I-O_DE2019_formatiert.csv"; datadir = root); exo_scale = 1.0)
end


function ext_matrix_programme(data::Data)
	root = ext_test_root()
	imp_path = joinpath(root, "data", "impulses.csv")
	isfile(imp_path) || return nothing
	imp = CSV.read(imp_path, DataFrame)
	rows = imp[imp.year .== 2024, :]
	raw = Matrix{Float64}(rows[1:1, 3:73])[:]
	ψ = raw ./ sum(raw)
	return (40300.0 / data.gdp_production) .* ψ, ψ
end


function ext_tilt(c0::AbstractVector, ψ::AbstractVector, g::AbstractVector)
	pos = c0 .> 0
	ψ1 = (ψ .* pos) ./ sum(ψ .* pos)
	return 1.0 .+ sum(g) .* ψ1 ./ max.(c0, 1e-12)
end


function ext_financing(data::Data, g::Vector{Float64}, ψ::Vector{Float64})
	return (
		F1 = PreferenceReallocation(ext_tilt(data.household_baseline, ψ, g)),
		F2 = TaxFinanced(g),
		F3 = ExternalDebt(g),
	)
end

@testset "external closure: real-table baseline reproduction" begin
	data = ext_test_data()
	if data === nothing
		@test_skip true  # needs data/I-O_DE2019_formatiert.csv
	else
		N = length(data.factor_share)
		model = mobile_labor_model(data, Shocks(ones(N), ones(N), zeros(N)),
			0.5, 0.5, 0.9, 1.0)
		# The baseline is an exact root with F = 0; solve returns immediately.
		sol = solve(model)
		X = [sol.prices_raw; sol.quantities; sol.wages_raw[1]; sol.external_transfer]
		@test maximum(abs, equilibrium_residuals(model, X)) ≤ 1e-12
		@test abs(sol.external_transfer) ≤ 1e-12
		@test sol.prices_raw ≈ ones(N) atol=1e-10
		@test sol.quantities ≈ data.λ atol=1e-10
	end
end

@testset "external closure: real-table ALPHA cells" begin
	data = ext_test_data()
	pg = data === nothing ? nothing : ext_matrix_programme(data)
	if data === nothing || pg === nothing
		@test_skip true  # needs the IO table and data/impulses.csv
	else
		N = length(data.factor_share)
		g, ψ = pg
		fins = ext_financing(data, g, ψ)
		sh0 = Shocks(ones(N), ones(N), zeros(N))
		base = solve(mobile_labor_model(data, sh0, 0.5, 0.5, 0.9, 1.0);
			init = [ones(N); data.λ; 1.0])
		sols = Dict{Symbol,Any}()
		cans = Dict{Symbol,Any}()
		# Measured 2026-09-18: F = +7.848e-4 (F1) / −1.014e-3 (F2) /
		# −1.4324e-2 (F3); canary gap |diff| ≤ 3e-16 at all three.
		for (key, F_pin) in ((:F1, 7.848e-4), (:F2, -1.014e-3), (:F3, -1.4324e-2))
			m = alpha_model(data, sh0, 0.5, 0.5, 0.9; financing = fins[key])
			sol = solve(m; init = [ones(N); data.λ; 1.0])
			X = [sol.prices_raw; sol.quantities; sol.wages_raw[1]; sol.external_transfer]
			@test maximum(abs, equilibrium_residuals(m, X)) < 1e-10
			@test maximum(abs, market_clearing_residuals(m, X)) ≤ 1e-10
			can = external_balance_canary(m, X)
			@test abs(can.diff) ≤ 1e-12
			@test sol.external_transfer ≈ F_pin atol=1e-6
			# The booked external position is recorded, not lost.
			@test can.financing ≈ sol.external_transfer + can.programme_financing atol=1e-12
			@test gdp_income(sol, base) ≈ gdp_expenditure(sol, base) atol=1e-12
			sols[key] = sol
			cans[key] = can
		end
		@test cans[:F1].programme_financing ≈ 0 atol=1e-12
		@test cans[:F2].programme_financing ≈ 0 atol=1e-12
		@test cans[:F3].programme_financing ≈ 1.3310e-2 atol=1e-6
		# FINANCING NEUTRALITY (theorem of the closure): F2 and F3 have
		# identical real equilibria with F_F3 = F_F2 − B_gov, hence identical
		# net external positions F + B_gov.
		s2, s3 = sols[:F2], sols[:F3]
		@test maximum(abs, s2.prices_raw .- s3.prices_raw) ≤ 1e-10
		@test maximum(abs, s2.quantities .- s3.quantities) ≤ 1e-10
		@test abs(s2.wages_raw[1] - s3.wages_raw[1]) ≤ 1e-10
		@test abs(s3.external_transfer -
			(s2.external_transfer - cans[:F3].programme_financing)) ≤ 1e-10
		@test abs(cans[:F2].financing - cans[:F3].financing) ≤ 1e-12
	end
end

@testset "external closure: real-table BF cells (sectoral wages, closed account)" begin
	data = ext_test_data()
	pg = data === nothing ? nothing : ext_matrix_programme(data)
	if data === nothing || pg === nothing
		@test_skip true  # needs the IO table and data/impulses.csv
	else
		N = length(data.factor_share)
		g, ψ = pg
		fins = ext_financing(data, g, ψ)
		sh0 = Shocks(ones(N), ones(N), zeros(N))
		# ADR-0020 option C: at η = 0 the endpoint solves the per-sector FOC, so
		# the frozen allocation is cost-minimizing at the sectoral wages, the
		# identity gap vanishes and F is identified. The retired F = 0 pin left F
		# unidentified (the reported position collapsed to B_gov = Σp·g).
		# Measured 2026-09-18 on the full-71 table: F = −5.815e-3 (F1) /
		# −8.528e-3 (F2) / −2.337e-2 (F3); booked = −5.815e-3 / −8.528e-3 /
		# −8.528e-3; |gap| ≤ 1.04e-11 (BF-F1, the stiffest cell).
		sols = Dict{Symbol,Any}()
		cans = Dict{Symbol,Any}()
		for (key, F_ref) in ((:F1, -0.0058149704), (:F2, -0.0085284060), (:F3, -0.0233746904))
			m = bf_model(data, sh0, 0.5, 0.5, 0.9, 0.0; financing = fins[key])
			sol = solve(m)
			@test length(sol.wages_raw) == N
			X = [sol.prices_raw; sol.quantities; sol.wages_raw; sol.external_transfer]
			@test length(X) == 3N + 1
			@test maximum(abs, equilibrium_residuals(m, X)) < 1e-10
			@test maximum(abs, market_clearing_residuals(m, X)) ≤ 1e-10
			@test sectoral_labor_gap(m, sol.prices_raw, sol.quantities,
				sol.wages_raw) ≤ 1e-10
			can = external_balance_canary(m, X)
			@test abs(can.diff) ≤ 1e-10        # the account closes at η = 0
			@test sol.external_transfer ≈ F_ref atol=1e-6
			@test can.financing ≈ sol.external_transfer + can.programme_financing atol=1e-12
			sols[key] = sol
			cans[key] = can
		end
		# The sectoral wage vector is a real instrument, not a rescaling of one
		# common wage: measured range 0.9702 … 1.6719 on the full-71 table.
		@test minimum(sols[:F3].wages_raw) < 0.99
		@test maximum(sols[:F3].wages_raw) > 1.6
		@test cans[:F3].programme_financing ≈ 1.4846e-2 atol=1e-6
		# FINANCING NEUTRALITY at η = 0 (as at η = 1): identical real equilibria
		# with F_F3 = F_F2 − B_gov, hence identical net external positions.
		s2, s3 = sols[:F2], sols[:F3]
		@test maximum(abs, s2.prices_raw .- s3.prices_raw) ≤ 1e-9
		@test maximum(abs, s2.quantities .- s3.quantities) ≤ 1e-9
		@test maximum(abs, s2.wages_raw .- s3.wages_raw) ≤ 1e-9
		@test abs(s3.external_transfer -
			(s2.external_transfer - cans[:F3].programme_financing)) ≤ 1e-9
		@test abs(cans[:F2].financing - cans[:F3].financing) ≤ 1e-9
	end
end

@testset "external closure: fixed-wage GAMMA cell" begin
	data = ext_test_data()
	pg = data === nothing ? nothing : ext_matrix_programme(data)
	if data === nothing || pg === nothing
		@test_skip true  # needs the IO table and data/impulses.csv
	else
		N = length(data.factor_share)
		g, ψ = pg
		sh0 = Shocks(ones(N), ones(N), zeros(N))
		fin = TaxFinanced(g)
		m = gamma_model(data, sh0, 0.5, 0.5, 0.9, 1.0; financing = fin)
		sol = solve(m)
		@test maximum(abs,
			equilibrium_residuals(m, [sol.prices_raw; sol.quantities])) ≤ 1e-6
		@test abs(sol.external_transfer) ≤ 1e-12
		can = external_balance_canary(m, [sol.prices_raw; sol.quantities])
		@test abs(can.diff) ≤ 1e-9
	end
end

