# Consumption-unit prices for Tables 6, 7 and E (ADR-0037); the tables use the
using OpenCGE, TOML, CSV, DataFrames, Printf
isdefined(Main, :load_design) || include(joinpath(@__DIR__, "run.jl"))

const PRICE_DESIGNS = ["pricing_capacity_rows", "pricing_capacity",
    "pricing_mobile", "pricing_markup", "pricing_profit"]
const PRICE_SIDECAR = "revision/tables/pricing_prices.csv"
# pricing_profit runs on the numerically identical v0.5.4 pin (ADR-0045, ADR-0046).
run_generation(design) = design == "pricing_profit" ? "v0.5.4" : "v0.5.0"

function consumption_unit_prices(p, beta, sigma, deflator; cpi_reference = 1.0)
    all(isfinite, p) && all(>(0), p) || error("prices must be finite and positive")
    C = sigma == 1 ? exp(sum(beta .* log.(p))) :
        sum(beta .* p .^ (1 - sigma))^(1 / (1 - sigma))
    return (; cpi_raw = C, cpi_reference,
        gdp_deflator_cpi = deflator / (C / cpi_reference),
        max_abs_price_dev_cpi = maximum(abs.(p .* (cpi_reference / C) .- 1)))
end

function pricing_price_rows(; root = default_root())
    first_design = load_design(first(PRICE_DESIGNS); root)
    ref = build_reference(first_design; root)
    maximum(abs.(ref.sol.prices_raw .- 1)) < 1e-10 ||
        error("reference prices differ from one; revise the reporting baseline")
    data = ref.data
    N = length(data.factor_share)
    kept = sort(setdiff(1:(N + length(first_design["data"]["drops"])),
        Vector{Int}(first_design["data"]["drops"])))
    io_path = "data/" * RUN_IO_TABLE
    io_hash = sha256_file(joinpath(root, io_path))
    rows = NamedTuple[]
    fixed_count = 0
    # Solutions are untracked: a run whose solution.csv is absent keeps its
    # sidecar row, provided its manifest is the one that row was checked against.
    sidecar = joinpath(root, PRICE_SIDECAR)
    previous = isfile(sidecar) ?
        Dict(r.run_id => r for r in eachrow(CSV.read(sidecar, DataFrame; stringtype = String))) :
        Dict{String,Any}()
    reused_count = 0
    for name in PRICE_DESIGNS
        design = load_design(name; root)
        design["reference"] == first_design["reference"] || error("reference mismatch: $name")
        design["data"] == first_design["data"] || error("calibration mismatch: $name")
        psi, g = programme_vectors(design, data, kept; root)
        design_hash = design_sha256(name; root)
        for id in sort(collect(keys(design["cells"])))
            path = joinpath(root, "runs", id, "manifest.toml")
            man = TOML.parsefile(path)
            man["provenance"]["opencge"]["repo_rev"] == run_generation(name) || error("wrong kernel generation: $id")
            man["status"] == "failed" && continue  # historical failure stays recorded
            man["status"] == "executed" && man["gates"]["overall"] == "pass" ||
                error("cell is not accepted: $id")
            man["provenance"]["data_sha256"][io_path] == io_hash || error("IO table changed: $id")
            cell = design_cell(design, id)
            cell["labor"] == man["scenario"]["labour"] || error("labour mismatch: $id")
            cell["financing"] == man["scenario"]["financing"] || error("financing mismatch: $id")
            man["provenance"]["design_sha256"] == design_hash || error("design changed: $id")
            # Verify the recorded numerical and pricing parameters as well.
            for key in ("theta", "epsilon", "sigma", "eta", "eta_s", "delta_epsilon")
                haskey(cell, key) || continue
                cell[key] == man["scenario"][key] || error("$key mismatch: $id")
            end
            for (key, value) in last(cell_pricing(design, cell))
                value == man["scenario"][key] || error("$key mismatch: $id")
            end
            solution_path = joinpath(root, "runs", id, "solution.csv")
            if !isfile(solution_path)
                old = get(previous, id, nothing)
                old !== nothing && old.manifest_sha256 == sha256_file(path) &&
                    old.design_sha256 == design_hash && old.io_sha256 == io_hash ||
                    error("no saved solution and no matching sidecar row: $id")
                push!(rows, (; run_id = id, cpi_raw = old.cpi_raw, cpi_reference = old.cpi_reference,
                    gdp_deflator_cpi = old.gdp_deflator_cpi,
                    max_abs_price_dev_cpi = old.max_abs_price_dev_cpi,
                    manifest_sha256 = old.manifest_sha256, solution_sha256 = old.solution_sha256,
                    design_sha256 = old.design_sha256, io_sha256 = old.io_sha256))
                reused_count += 1
                continue
            end
            stored = CSV.read(solution_path, DataFrame)
            String.(stored.sector) == string.(data.io.Sektoren[1:N]) || error("sector order: $id")
            p, q = Float64.(stored.price), Float64.(stored.quantity)
            metrics = man["metrics"]
            isapprox(maximum(abs.(p .- 1)), metrics["max_abs_price_dev"]; atol = 1e-12) ||
                error("saved prices disagree with manifest: $id")
            C0 = consumption_unit_prices(ref.sol.prices_raw, data.consumption_share,
                Float64(cell["sigma"]), 1.0).cpi_raw
            report = consumption_unit_prices(p, data.consumption_share,
                Float64(cell["sigma"]), metrics["gdp_deflator"]; cpi_reference = C0)
            if cell["labor"] in ("GAMMA", "DELTA")
                model = build_cell_model(cell, design, data, psi, g)
                sol = Solution(p, q, ones(N), zeros(N), report.cpi_raw, 1.0, 1.0, model)
                normalized = Solution(p ./ report.cpi_raw, q,
                    ones(N) ./ report.cpi_raw, zeros(N), 1.0, 1.0, 1.0, model)
                isapprox(gdp_deflator(sol, ref.sol), metrics["gdp_deflator"]; atol = 1e-10, rtol = 0) ||
                    error("deflator reconstruction failed: $id")
                isapprox(gdp_deflator(normalized, ref.sol), report.gdp_deflator_cpi; atol = 1e-10, rtol = 0) ||
                    error("deflator rescaling failed: $id")
                isapprox(gdp_income(sol, ref.sol), gdp_income(normalized, ref.sol); atol = 1e-10, rtol = 0) ||
                    error("real GDP changed under rescaling: $id")
                fixed_count += 1
            else
                isapprox(report.cpi_raw, 1.0; atol = 1e-8, rtol = 0) || error("CPI gate: $id")
            end
            push!(rows, (; run_id = id, report..., manifest_sha256 = sha256_file(path),
                solution_sha256 = sha256_file(solution_path), design_sha256 = design_hash,
                io_sha256 = io_hash))
        end
    end
    @info "consumption-unit price checks passed" cells = length(rows) fixed_cells = fixed_count reused_rows = reused_count
    return DataFrame(sort(rows; by = r -> r.run_id))
end

function pricing_prices_main(args = ARGS)
    all(==("--check"), args) || error("usage: make_pricing_prices.jl [--check]")
    rows = pricing_price_rows()
    path = joinpath(default_root(), PRICE_SIDECAR)
    output = sprint(io -> CSV.write(io, rows))
    if "--check" in args
        isfile(path) && read(path, String) == output || error("stale $PRICE_SIDECAR; regenerate it")
        println(PRICE_SIDECAR, " is up to date")
    else
        write(path, output)
        println("wrote ", path)
    end
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    pricing_prices_main()
end
