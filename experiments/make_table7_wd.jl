# =====================================================================

using OpenCGE, TOML, Printf

isdefined(Main, :load_design) || include(joinpath(@__DIR__, "run.jl"))

const LAMBDA = 1.0
const GATE_TOL = 1e-6
const TABLE7_CELLS = Dict(
    # the no-door row of Table 7 uses the eta_s = 0.5 cell on BETA (the plain
    # matrix_5x3-BETA-F1 cell uses scalar supply and reproduces ALPHA), as Table 4/6 do.
    "matrix_5x3"     => r"^matrix_5x3-([A-Z]+-F[123]|BETA-F[123]-etas05)$",
    "pricing_markup"  => r"^pricing_markup-[A-Z]+-F[123]-k(025|05)$",
    "pricing_profit"  => r"^pricing_profit-[A-Z]+-F[123]-k05-spi(05|0)$",
)

# The plain scalar-supply BETA cells reproduce ALPHA under this shock.
# Select the sectoral eta_s = 0.5 cells for the table.
const SKIP = r"^matrix_5x3-BETA-F[123]$"

function w_d(sol::Solution, ref_sol::Solution)
    f(s) = final_demand_bundle(s.model, s.prices_raw, s.quantities, OpenCGE._bundle_wage(s);
        lambda = LAMBDA, external_transfer = s.external_transfer).f
    return 100 * (sum(f(sol)) / sum(f(ref_sol)) - 1)
end

function manifest_gap(got::Dict{String,Any}, man::Dict{String,Any})
    gap = 0.0
    for (k, v) in man["metrics"]
        (v isa Real && haskey(got, k) && got[k] isa Real) || continue
        gap = max(gap, abs(got[k] - v))
    end
    return gap
end

function main()
    root = default_root()
    rows = Tuple{String,Float64}[]
    ok = true
    for (name, re) in TABLE7_CELLS
        dd = load_design(name; root = root)
        ids = sort([id for id in keys(dd["cells"]) if occursin(re, id) && !occursin(SKIP, id)])
        @printf("building reference continuation for %s (%d cells) ...\n", name, length(ids))
        ref = build_reference(dd; root = root)
        drops = Vector{Int}(dd["data"]["drops"])
        kept = sort(setdiff(1:(length(ref.data.factor_share) + length(drops)), drops))
        ψ, g = programme_vectors(dd, ref.data, kept; root = root)
        for id in ids
            man = TOML.parsefile(joinpath(root, "runs", id, "manifest.toml"))
            # pricing_profit runs on the numerically identical v0.5.4 pin (ADR-0045, ADR-0046).
            man["provenance"]["opencge"]["repo_rev"] == (name == "pricing_profit" ? "v0.5.4" : "v0.5.0") ||
                error("wrong kernel generation: $id")
            cell = design_cell(dd, id)
            sol = solve_cell(cell, dd, ref.data, ψ, g, ref.init_warm)
            ev = evaluate_gates(cell, dd, sol.model, sol, ref.sol)
            gap = manifest_gap(ev.metrics, man)
            pass = man["status"] == "executed" && gap < GATE_TOL
            ok &= pass
            wd = w_d(sol, ref.sol)
            @printf("  %-42s gate %s (%.1e)  W_C %+7.3f  W_D %+7.3f\n", id, pass ? "ok" : "FAIL",
                gap, 100 * man["metrics"]["consumption_rel"], wd)
            push!(rows, (id, wd))
        end
    end
    ok || (println("manifest gate failed; nothing written"); return 1)
    path = joinpath(root, "revision", "tables", "table7_wd.csv")
    open(path, "w") do io
        println(io, "run_id,w_d")
        for (id, wd) in sort(rows)
            @printf(io, "%s,%.12g\n", id, wd)
        end
    end
    println("wrote ", path, "  (", length(rows), " cells)")
    return 0
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    exit(main())
end
