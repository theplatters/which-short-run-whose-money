# experiments/run.jl — single experiment entry point (Phase 3, ADR-0006)

using OpenCGE
using TOML
using SHA
using Dates
using Printf
using LinearAlgebra
using CSV
using DataFrames

const RUN_SEED = 1234
const RUN_SCHEMA_VERSION = 2
const RUN_IO_TABLE = "I-O_DE2019_formatiert.csv"
const RUN_INDEX_HEADER = "run_id,date,design,closures,status,gate_summary,headline_metrics,commit"

default_root() = normpath(joinpath(@__DIR__, ".."))

default_runs_dir(root::AbstractString) = joinpath(root, "runs")

default_actor() = get(ENV, "USER", "unknown")

# ── Small utilities ────────────────────────────────────────────────────

function sha256_file(path::AbstractString)::String
    return bytes2hex(SHA.sha256(read(path)))
end

sha256_or_absent(path::AbstractString) = isfile(path) ? sha256_file(path) : "absent"

function _git(root::AbstractString, args::String...)::Union{String,Nothing}
    try
        return strip(read(`git -C $root $args`, String))
    catch
        return nothing
    end
end

git_commit(root::AbstractString) = something(_git(root, "rev-parse", "HEAD"), "unknown")

function git_dirty(root::AbstractString)::Bool
    porch = _git(root, "status", "--porcelain")
    porch === nothing && return true
    return !isempty(porch)
end

iso_date() = string(Dates.today())

iso_timestamp() = Dates.format(Dates.now(Dates.UTC), dateformat"yyyy-mm-ddTHH:MM:SS")

# ── Design files ───────────────────────────────────────────────────────

design_path(design::AbstractString; root::AbstractString = default_root()) =
    joinpath(root, "experiments", "designs", design * ".toml")

function load_design(design::AbstractString; root::AbstractString = default_root())::Dict{String,Any}
    path = design_path(design; root = root)
    isfile(path) || throw(ArgumentError("design file not found: $path"))
    return TOML.parsefile(path)
end

function cell_order(design::AbstractString; root::AbstractString = default_root())::Vector{String}
    path = design_path(design; root = root)
    return cell_order_file(path)
end

function cell_order_file(path::AbstractString)::Vector{String}
    ids = String[]
    for line in eachline(path)
        m = match(r"^\s*\[cells\.([^\]]+)\]\s*$", line)
        m === nothing || push!(ids, strip(m.captures[1]))
    end
    return ids
end

design_sha256(design::AbstractString; root::AbstractString = default_root()) =
    sha256_file(design_path(design; root = root))

function design_cell(design_d::Dict{String,Any}, run_id::AbstractString)::Dict{String,Any}
    cells = get(design_d, "cells", Dict{String,Any}())
    haskey(cells, run_id) || throw(ArgumentError("unknown cell \"$run_id\" for this design"))
    return cells[run_id]
end

function cell_summary(run_id::AbstractString, cell::Dict{String,Any})::String
    parts = String["labor=$(cell["labor"])", "financing=$(cell["financing"])"]
    for k in ("eta", "eta_s", "theta", "epsilon", "sigma", "delta_epsilon")
        haskey(cell, k) && push!(parts, "$k=$(cell[k])")
    end
    return "$run_id: " * join(parts, " ") * " — " * get(cell, "note", "")
end

function list_cells(design::AbstractString; root::AbstractString = default_root(),
        io::IO = stdout)::Nothing
    design_d = load_design(design; root = root)
    println(io, "design $(design_d["design"]) — $(get(design_d, "description", ""))")
    for id in cell_order(design; root = root)
        println(io, cell_summary(id, design_cell(design_d, id)))
    end
    return nothing
end

# ── Preregistration ────────────────────────────────────────────────────

prereg_path(; root::AbstractString = default_root()) =
    joinpath(root, "registry", "preregistration.toml")

function load_prereg(; root::AbstractString = default_root())::Dict{String,Any}
    path = prereg_path(; root = root)
    isfile(path) || return Dict{String,Any}()
    return TOML.parsefile(path)
end

function pinned_params(design_d::Dict{String,Any})::Dict{String,Any}
    prog = get(design_d, "programme", Dict{String,Any}())
    ref = get(design_d, "reference", Dict{String,Any}())
    out = Dict{String,Any}(
        "theta" => get(ref, "theta", 0.0),
        "epsilon" => get(ref, "epsilon", 0.0),
        "sigma" => get(ref, "sigma", 0.0),
        "eta" => get(ref, "eta", 0.0),
        "exo_scale_steps" => get(ref, "exo_scale_steps", 0),
        "total_eur_m" => get(prog, "total_eur_m", 0.0),
        "programme_year" => get(prog, "year", 0),
        "f1_shift" => get(prog, "f1_shift", ""),
    )
    # ADR-0029: a pricing design also pins its door defaults (informational;
    # pricing-free designs keep the pre-pricing record).
    if haskey(design_d, "pricing")
        for (k, v) in design_d["pricing"]
            out["pricing_" * string(k)] = v
        end
    end
    return out
end

function preregister_design(design::AbstractString; root::AbstractString = default_root(),
        actor::AbstractString = default_actor())::String
    design_d = load_design(design; root = root)
    sha = design_sha256(design; root = root)
    preg = load_prereg(; root = root)
    get!(preg, "schema_version", RUN_SCHEMA_VERSION)
    designs = get!(preg, "designs", Dict{String,Any}())
    designs[design] = Dict{String,Any}(
        "design_sha256" => sha,
        "registered_at" => iso_timestamp(),
        "git_commit" => git_commit(root),
        "actor" => actor,
        "pinned" => pinned_params(design_d),
        "note" => get(design_d, "description", ""),
    )
    open(prereg_path(; root = root), "w") do io
        TOML.print(io, preg)
    end
    return sha
end

function preregistration_status(design::AbstractString;
        root::AbstractString = default_root())::Tuple{Bool,String}
    preg = load_prereg(; root = root)
    designs = get(preg, "designs", Dict{String,Any}())
    haskey(designs, design) || return (false,
        "design \"$design\" is not preregistered; run `experiments/run.jl --preregister $design` first")
    recorded = get(designs[design], "design_sha256", "")
    current = design_sha256(design; root = root)
    recorded == current || return (false,
        "design \"$design\" changed since preregistration (recorded $(recorded[1:min(8,end)]) vs current $(current[1:8])); re-run `experiments/run.jl --preregister $design`")
    return (true, "")
end

# ── Programme incidence ────────────────────────────────────────────────

function programme_vectors(design_d::Dict{String,Any}, data::Data, kept::AbstractVector{<:Integer};
        root::AbstractString = default_root())::Tuple{Vector{Float64},Vector{Float64}}
    prog = design_d["programme"]
    n = length(data.factor_share)
    if get(design_d, "smoke", false) && haskey(prog, "explicit")
        ψ = Float64.(prog["explicit"])
        length(ψ) == n || throw(ArgumentError(
            "explicit programme vector has length $(length(ψ)), expected $n"))
        return ψ, ψ
    end
    total_eur_m = Float64(prog["total_eur_m"])
    slice = prog["column_slice"]
    imp = CSV.read(joinpath(root, prog["source"]), DataFrame)
    col_lo, col_hi = Int(slice[1]), Int(slice[2])
    rows = imp[imp.year .== Int(prog["year"]), :]
    size(rows, 1) >= 1 || throw(ArgumentError("no programme row for year $(prog["year"])"))
    raw = Matrix{Float64}(rows[1:1, col_lo:col_hi])[:]
    v = raw[kept]
    sum(v) > 0 || throw(ArgumentError("programme incidence has zero mass over kept sectors"))
    ψ = v ./ sum(v)
    g = (total_eur_m / data.gdp_production) .* ψ
    return ψ, g
end

# ── Reference continuation (ports cbase2/scripts/verify_v3.jl 18–77) ───

function build_reference(design_d::Dict{String,Any}; root::AbstractString = default_root(),
        data::Union{Data,Nothing} = nothing)::NamedTuple
    ref = design_d["reference"]
    eta = Float64(ref["eta"])
    epsilon = Float64(ref["epsilon"])
    sigma = Float64(ref["sigma"])
    thetas = Float64.(ref["thetas"])
    Float64(ref["theta"]) == thetas[end] || throw(ArgumentError(
        "reference theta ($(ref["theta"])) must equal the final ladder value ($(thetas[end])))"))

    if data !== nothing
        N = length(data.factor_share)
        shocks = Shocks(ones(N), ones(N), zeros(N))
        init_warm, ref_sol = _theta_ladder(data, shocks, thetas, epsilon, sigma, eta, nothing)
        return _reference_result(data, ref_sol, init_warm)
    end

    dat = design_d["data"]
    # `Vector{Int}(...)`, not `Int.(...)`: inside any process that has loaded
    # OpenCGE (the NonlinearSolve/SciML stack), inference returns `Any`
    # for `Int(::Any)`, so broadcasting over an EMPTY vector degrades to
    # `Vector{Any}` (`Int.(Any[]) === Any[]`) and `retained_dataset` rejects
    # it. Typed conversion is inference-independent.
    drops = Vector{Int}(dat["drops"])
    K = Int(ref["exo_scale_steps"])

    data_full = read_data(RUN_IO_TABLE; datadir = root)
    data_v1 = retained_dataset(data_full, drops)
    N = length(data_v1.factor_share)
    shocks = Shocks(ones(N), ones(N), zeros(N))

    # Bisection: smallest exo_scale with saving_rate ≥ 0 (s is monotone).
    s_of(esc) = recalibrate_open(data_v1; exo_scale = esc).saving_rate
    s_of(1.0) > 0 || throw(ErrorException("reference continuation: saving rate at exo_scale = 1 is not positive"))
    lo, hi = 0.0, 1.0
    for _ in 1:40
        mid = (lo + hi) / 2
        s_of(mid) < 0 ? (lo = mid) : (hi = mid)
    end
    esc0 = hi

    init_warm = nothing
    data_cal = data_v1
    ref_sol = nothing
    t0 = time()
    for k in 0:K
        exo_scale = esc0 + (1.0 - esc0) * k / K
        data_cal = recalibrate_open(data_v1; exo_scale = exo_scale)
        init_warm, ref_sol = _theta_ladder(data_cal, shocks, thetas, epsilon, sigma, eta, init_warm)
    end
    @info "reference continuation done" seconds = round(time() - t0; digits = 1)
    return _reference_result(data_cal, ref_sol, init_warm)
end

function _theta_ladder(data::Data, shocks::Shocks, thetas::Vector{Float64},
        epsilon::Float64, sigma::Float64, eta::Float64,
        init_warm::Union{Vector{Float64},Nothing})::Tuple{Vector{Float64},Solution}
    N = length(data.factor_share)
    ref_sol = nothing
    for θ in thetas
        ref = mobile_labor_model(data, shocks, θ, epsilon, sigma, eta)
        if init_warm === nothing
            # Very first solve: warm start from the linear fixed point (exact
            # on real calibrations; singular toy fixtures fall back to λ).
            # Canonical 2N+2 mobile vector (ADR-0019): F = 0 first.
            (; Ω_raw, factor_share, consumption_share, import_margin,
                gov_demand, exo_demand, exports_demand) = data
            init_warm = try
                M0 = Ω_raw' * Diagonal(1.0 .- factor_share)
                Gk = M0 + Diagonal(1.0 .- import_margin) * consumption_share *
                    factor_share' * (1 - data.saving_rate) * (1 - sum(gov_demand))
                y0 = (I - Gk) \ ((1.0 .- import_margin) .* (gov_demand .+ exo_demand) .+ exports_demand)
                [ones(N); y0; 1.0; 0.0]
            catch
                [ones(N); data.λ; 1.0; 0.0]
            end
        end
        ref_sol = solve(ref; init = init_warm)
        mxp = maximum(abs.(ref_sol.prices_raw .- 1))
        init_warm = [ref_sol.prices_raw; ref_sol.quantities; ref_sol.wages_raw[1]; ref_sol.external_transfer]
        @info "reference rung" theta = θ resid =
            maximum(abs, equilibrium_residuals(ref, init_warm)) w_star = ref_sol.wages_raw[1] max_p_dev = mxp
        mxp > 10 && (@warn "exploded branch; stopping the θ ladder"; break)
    end
    return init_warm, ref_sol
end

function assert_external_account(model::Model, sol::Solution;
        clearing_tol::Real = 1e-6, gap_tol::Real = 1e-9)
    fixed = labor_closure(model.options) isa Union{FixedWageClosure,NominalWageClosure}
    p, q = sol.prices_raw, sol.quantities
    # eta = 0 carries the sectoral wage vector (ADR-0020 option C); an ADR-0022
    # sectoral cell (eta_s_vec) carries one too; every other eta = 1 regime
    # carries one common wage.
    w = (model.options.elasticities.η == 0.0 ||
         model.options.elasticities.eta_s_vec !== nothing) ? sol.wages_raw : sol.wages_raw[1]
    X = fixed ? [p; q] : [p; q; w; sol.external_transfer]
    clearing = maximum(abs, market_clearing_residuals(model, X))
    clearing < clearing_tol || error(
        "external-account clearing failure: max|market_clearing_residuals| = $clearing " *
        ">= $clearing_tol (ADR-0019: all N markets must clear)")
    gap = abs(external_balance_canary(model, X).diff)
    gap < gap_tol || error(
        "external-account identity gap failure: |diff| = $gap >= $gap_tol " *
        "(ADR-0019/ADR-0020: S + T + M − (I+X) = F + B_gov in every regime)")
    return nothing
end

function _reference_result(data::Data, ref_sol::Solution, init_warm::Vector{Float64})::NamedTuple
    p = ref_sol.prices_raw
    w = ref_sol.wages_raw[1]
    L = sum(sectoral_labor_demand(p, ref_sol.quantities, w, ref_sol.model))
    X = [p; ref_sol.quantities; w; ref_sol.external_transfer]
    canary = external_balance_canary(ref_sol.model, X)
    assert_external_account(ref_sol.model, ref_sol)
    return (data = data, sol = ref_sol, init_warm = init_warm,
        resid = maximum(abs, equilibrium_residuals(ref_sol.model, X)),
        w_star = w, employment = L, max_p_dev = maximum(abs.(p .- 1)),
        canary_s = canary.S, canary_ixm = canary.IX - canary.M,
        canary_diff = canary.diff, external_position = canary.financing)
end

# ── Cell construction ──────────────────────────────────────────────────

function f1_tilt_weights(baseline::AbstractVector, ψ::AbstractVector, g::AbstractVector)::Vector{Float64}
    n = length(baseline)
    length(ψ) == n && length(g) == n || throw(ArgumentError(
        "f1_tilt_weights: length mismatch (baseline=$n, ψ=$(length(ψ)), g=$(length(g)))"))
    all(isfinite, baseline) || throw(ArgumentError("f1_tilt_weights: baseline must be finite"))
    all(isfinite, ψ) || throw(ArgumentError("f1_tilt_weights: ψ must be finite"))
    all(isfinite, g) || throw(ArgumentError("f1_tilt_weights: g must be finite"))
    all(>=(0), ψ) || throw(ArgumentError("f1_tilt_weights: ψ entries must be nonnegative"))
    all(>=(0), g) || throw(ArgumentError("f1_tilt_weights: g entries must be nonnegative"))
    pos = baseline .> 0
    any(pos) || throw(ArgumentError("f1_tilt_weights: no baseline entry is positive"))
    ψ1 = ψ .* pos
    s = sum(ψ1)
    s > 0 || throw(ArgumentError("f1_tilt_weights: programme has zero mass over positive-baseline sectors"))
    ψ1 = ψ1 ./ s
    G0 = sum(g)
    return 1.0 .+ G0 .* ψ1 ./ max.(baseline, 1e-12)
end

function cell_financing(fin::AbstractString, ψ::Vector{Float64}, g::Vector{Float64},
        f1_shift::AbstractString, data::Data)::AbstractFinancing
    fin == "F1" || return fin == "F2" ? TaxFinanced(g) : fin == "F3" ? ExternalDebt(g) :
        throw(ArgumentError("unknown financing id $fin"))
    if f1_shift == "one_plus_psi"
        throw(ArgumentError("retired f1_shift \"one_plus_psi\": the non-reference 1 .+ ψ tilt adds ψ directly instead of G0 .* ψ1 ./ c0; use \"tilt_g0_over_c0\""))
    end
    f1_shift == "tilt_g0_over_c0" || throw(ArgumentError("unknown f1_shift \"$f1_shift\""))
    return PreferenceReallocation(f1_tilt_weights(data.household_baseline, ψ, g))
end

function cell_eta_s_vec(cell::Dict{String,Any}, data::Data,
        ψ::Vector{Float64})::Union{Nothing,Vector{Float64}}
    haskey(cell, "eta_s_vec") && return Float64.(cell["eta_s_vec"])
    grp = string(get(cell, "eta_s_rigid_group", "scalar"))
    grp == "scalar" && return nothing
    N = length(data.factor_share)
    eta = Float64(get(cell, "eta_s", 0.0))
    grp == "none" && return fill(eta, N)
    mask = if grp == "programme"
        ψ .> 0
    elseif grp == "largest_half"
        order = sortperm(data.labor_share; rev = true)
        m = falses(N); m[order[1:cld(N, 2)]] .= true; m
    else
        throw(ArgumentError("unknown eta_s_rigid_group \"$grp\""))
    end
    v = fill(eta, N); v[mask] .= 0.0
    return v
end

function resolve_supply_shock(design_d::Dict{String,Any}, cell::Dict{String,Any},
        data::Data, ψ::Vector{Float64})::Tuple{Shocks,Dict{String,Any}}
    N = length(data.factor_share)
    sh = get(design_d, "shock", Dict{String,Any}())
    kind = lowercase(string(get(sh, "kind", "none")))
    if kind == "none"
        return Shocks(ones(N), ones(N), zeros(N)),
            Dict{String,Any}("shock" => "impulses.csv", "magnitude" => 1.0)
    end
    A = ones(N)
    if kind == "sectoral"
        mag = Float64(get(cell, "shock_magnitude", get(sh, "magnitude", 1.2)))
        targets = Vector{Int}(get(sh, "targets", Int[]))
        isempty(targets) && throw(ArgumentError(
            "sectoral supply shock: `[shock] targets` must be nonempty"))
        all(t -> 1 <= t <= N, targets) || throw(ArgumentError(
            "sectoral supply shock: targets out of range 1..$N"))
        A[targets] .= mag
    elseif kind == "programme"
        alpha = Float64(get(cell, "shock_alpha", get(sh, "alpha", 0.10)))
        alpha >= 0 || throw(ArgumentError(
            "programme supply shock: alpha must be nonnegative"))
        A = A .+ alpha .* ψ
    elseif kind == "uniform"
        mag = Float64(get(cell, "shock_magnitude", get(sh, "magnitude", 1.01)))
        A = fill(mag, N)
    else
        throw(ArgumentError(
            "unknown [shock] kind \"$kind\" (none|sectoral|programme|uniform)"))
    end
    all(isfinite, A) && all(>(0), A) || throw(ArgumentError(
        "supply shock produces non-finite or non-positive productivity vector A"))
    fields = Dict{String,Any}(
        "shock" => "$kind:supply",
        "shock_kind" => kind,
        "shock_A" => A)
    if kind == "programme"
        a = Float64(get(cell, "shock_alpha", get(sh, "alpha", 0.10)))
        fields["shock_alpha"] = a
        fields["magnitude"] = a
    else
        m = Float64(get(cell, "shock_magnitude",
            get(sh, "magnitude", kind == "sectoral" ? 1.2 : 1.01)))
        fields["shock_magnitude"] = m
        fields["magnitude"] = m
        kind == "sectoral" && (fields["shock_targets"] = Vector{Int}(get(sh, "targets", Int[])))
    end
    return Shocks(A, ones(N), zeros(N)), fields
end

function cell_pricing(design_d::Dict{String,Any},
        cell::Dict{String,Any})::Tuple{AbstractPricing,Dict{String,Any}}
    pb = get(design_d, "pricing", Dict{String,Any}())
    val(k, default) = get(cell, k, get(pb, k, default))
    kind = lowercase(string(val("kind", "none")))
    kind == "none" && return NoPricing(), Dict{String,Any}()
    if kind == "capacity"
        δ = Float64(val("delta", 0.0))
        fields = Dict{String,Any}("pricing" => "P1", "pricing_kind" => kind, "delta" => δ)
        val("delta_services", nothing) === nothing && return CapacityPricing(δ), fields
        δs = Float64(val("delta_services", 0.0))
        svc = Vector{Int}(get(pb, "services", Int[]))
        N = Int(get(pb, "n_sectors", 0))
        (!isempty(svc) && N > 0) || throw(ArgumentError(
            "delta_services needs `[pricing] services` and `[pricing] n_sectors`"))
        (allunique(svc) && all(in(1:N), svc)) || throw(ArgumentError(
            "`[pricing] services` must be distinct sector indices in 1..$N"))
        v = fill(δ, N)
        v[svc] .= δs
        fields["delta_services"] = δs
        fields["services"] = svc
        return CapacityPricing(v), fields
    elseif kind == "markup"
        κ = Float64(val("kappa", 0.0))
        s_pi = Float64(val("s_pi", 1.0))
        return MarkupPricing(κ; s_pi = s_pi), Dict{String,Any}(
            "pricing" => "P2", "pricing_kind" => kind, "kappa" => κ, "s_pi" => s_pi)
    end
    throw(ArgumentError("unknown [pricing] kind \"$kind\" (none|capacity|markup)"))
end

scaled_pricing(::NoPricing, t::Real) = NoPricing()
scaled_pricing(pr::CapacityPricing, t::Real) = CapacityPricing(t * pr.δ)
scaled_pricing(pr::MarkupPricing, t::Real) = MarkupPricing(t * pr.κ; s_pi = pr.s_pi)

function build_cell_model(cell::Dict{String,Any}, design_d::Dict{String,Any},
        data::Data, ψ::Vector{Float64}, g::Vector{Float64};
        pricing::Union{AbstractPricing,Nothing} = nothing)::Model
    N = length(data.factor_share)
    shocks, _ = resolve_supply_shock(design_d, cell, data, ψ)
    labor, fin_id = cell["labor"], cell["financing"]
    fin = cell_financing(fin_id, ψ, g, design_d["programme"]["f1_shift"], data)
    pr = pricing === nothing ? first(cell_pricing(design_d, cell)) : pricing
    if labor == "BF" || labor == "ALPHA"
        return mobile_labor_model(data, shocks, Float64(cell["theta"]),
            Float64(cell["epsilon"]), Float64(cell["sigma"]), Float64(cell["eta"]);
            financing = fin, pricing = pr)
    elseif labor == "BETA"
        esv = cell_eta_s_vec(cell, data, ψ)
        if esv === nothing
            pr isa NoPricing || throw(ArgumentError(
                "pricing doors are not wired into scalar BETA (solve_beta); use the sectoral form"))
            return mobile_labor_model(data, shocks,
                Float64(cell["theta"]), Float64(cell["epsilon"]), Float64(cell["sigma"]),
                Float64(cell["eta"]); financing = fin, eta_s = Float64(cell["eta_s"]))
        end
        return mobile_labor_model(data, shocks, Float64(cell["theta"]),
            Float64(cell["epsilon"]), Float64(cell["sigma"]), Float64(cell["eta"]);
            financing = fin, eta_s = Float64(cell["eta_s"]), eta_s_vec = esv, pricing = pr)
    elseif labor == "GAMMA"
        return mobile_labor_model(data, shocks, Float64(cell["theta"]),
            Float64(cell["epsilon"]), Float64(cell["sigma"]), Float64(cell["eta"]);
            closure = :fixed, financing = fin, pricing = pr)
    elseif labor == "DELTA"
        # `delta_model` spelled out so the door reaches the cost line (ADR-0032);
        # with NoPricing this is the `delta_model` call bit for bit.
        el = delta_elasticities(Float64(cell["delta_epsilon"]))
        return mobile_labor_model(data, shocks, el.θ, el.ϵ, el.σ, el.η;
            closure = :fixed, financing = fin, pricing = pr)
    end
    throw(ArgumentError("unknown labor id $labor"))
end

function solve_cell(cell::Dict{String,Any}, design_d::Dict{String,Any}, data::Data,
        ψ::Vector{Float64}, g::Vector{Float64}, init_warm::Vector{Float64})::Solution
    model = build_cell_model(cell, design_d, data, ψ, g)
    if !(model.pricing isa NoPricing)
        steps = Int(get(get(design_d, "pricing", Dict{String,Any}()), "continuation_steps", 4))
        steps >= 1 || throw(ArgumentError("[pricing] continuation_steps must be >= 1"))
        twin = build_cell_model(cell, design_d, data, ψ, g; pricing = NoPricing())
        x = OpenCGE._solution_vector(twin, solve(twin; init = init_warm))
        local sol
        for k in 1:steps
            mk = build_cell_model(cell, design_d, data, ψ, g;
                pricing = scaled_pricing(model.pricing, k / steps))
            sol = solve(mk; init = x)
            x = OpenCGE._solution_vector(mk, sol)
        end
        return sol
    end
    if cell["labor"] == "BETA"
        # ADR-0022: the sectoral form is solved by the kernel's own dispatcher.
        model.options.elasticities.eta_s_vec === nothing ||
            return solve(model; init = init_warm)
        N = length(data.factor_share)
        shocks, _ = resolve_supply_shock(design_d, cell, data, ψ)
        return solve_beta(data, shocks, Float64(cell["theta"]), Float64(cell["epsilon"]),
            Float64(cell["sigma"]), Float64(cell["eta"]); eta_s = Float64(cell["eta_s"]),
            financing = cell_financing(cell["financing"], ψ, g, design_d["programme"]["f1_shift"], data),
            init = init_warm)
    end
    return solve(model; init = init_warm)
end

# ── Gates / metrics / diagnostics ──────────────────────────────────────

gate_frag(name::AbstractString, value::Real, tol::Real, pass::Bool) =
    @sprintf("%s %.3g<=%.0e %s", name, value, tol, pass ? "ok" : "FAIL")

function evaluate_gates(cell::Dict{String,Any}, design_d::Dict{String,Any},
        model::Model, sol::Solution, ref_sol::Solution)::NamedTuple
    gates = design_d["gates"]
    residual_tol = Float64(gates["residual_tol"])
    budget_tol = Float64(gates["budget_tol"])
    labour_tol = Float64(gates["labour_tol"])
    wage_tol = Float64(gates["wage_tol"])
    data = model.data
    fin = model.financing
    fixed = labor_closure(model.options) isa Union{FixedWageClosure,NominalWageClosure}

    p, q = sol.prices_raw, sol.quantities
    # eta = 0 carries the sectoral wage vector (ADR-0020 option C); an ADR-0022
    # sectoral cell (eta_s_vec) carries one too; every other eta = 1 regime
    # carries one common wage.
    η0 = model.options.elasticities.η == 0.0
    sect = η0 || model.options.elasticities.eta_s_vec !== nothing
    w = sect ? sol.wages_raw : sol.wages_raw[1]
    X = fixed ? [p; q] : [p; q; w; sol.external_transfer]
    resid = maximum(abs, equilibrium_residuals(model, X))
    L_i = sectoral_labor_demand(p, q, w, model)
    L_sum = sum(L_i)
    # eta = 0: household wage income is the sectoral wage bill sum_i w_i L_i
    # (L_i = data.labor_share there); sectoral (ADR-0022): the same bill at the
    # solved L^cm_i; eta = 1 single-wage regimes: the common wage times L_sum.
    wage_income = η0 ? sum(sol.wages_raw .* data.labor_share) :
        model.options.elasticities.eta_s_vec !== nothing ? sum(w .* L_i) :
        w * L_sum
    # ADR-0030: a markup closure with s_pi < 1 pays the distributed rent
    # (1 - s_pi)·Π into household expenditure; every other closure adds nothing.
    comp = gdp_components(model, sol)
    profit_income = model.pricing isa MarkupPricing ? (1 - model.pricing.s_pi) * comp.profit : 0.0
    E = household_expenditure(fin, model, wage_income, p, L_sum;
        external_transfer = sol.external_transfer, profit_income = profit_income)
    budget = abs(dot(p, sol.consumption) - (1 - data.saving_rate) * E)
    resid_pass = resid < residual_tol
    budget_pass = budget < budget_tol

    cpi_val = sum(data.consumption_share .* p .^ (1 - model.options.elasticities.σ))^(1 / (1 - model.options.elasticities.σ))
    third_name, third_value, third_tol, third_pass =
        # Fixed closures hard-pin w = 1 (wages_raw); the normalized sol.wages
        # folds in the CPI numeraire and must not enter the gate.
        fixed ? ("wage", maximum(abs.(sol.wages_raw .- 1)), wage_tol,
                 maximum(abs.(sol.wages_raw .- 1)) < wage_tol) :
        η0 ? # eta = 0 (ADR-0020 option C): the sectoral labour-market gap, the
             # block that replaces the aggregate labour equation there.
             ("sectoral", sectoral_labor_gap(model, p, q, w), labour_tol,
              sectoral_labor_gap(model, p, q, w) < labour_tol) :
        model.options.elasticities.eta_s_vec !== nothing ?
             # ADR-0022: the N sectoral labour markets replace the aggregate
             # labour equation, so the gate is the sectoral supply gap (which
             # reduces to sectoral_labor_gap at eta_s,i = 0).
             ("sectoral", sectoral_supply_gap(model, p, q, w), labour_tol,
              sectoral_supply_gap(model, p, q, w) < labour_tol) :
                ("labour", abs(labor_market_residual(labor_closure(model.options), model, L_sum, w, cpi_val)),
                 labour_tol, abs(labor_market_residual(labor_closure(model.options), model, L_sum, w, cpi_val)) < labour_tol)

    # ADR-0029 #11: a pricing door adds the uniqueness gate — the multi-start
    # spread of `pricing_admissibility` (at least two converged starts, all
    # within `[pricing] multistart_tol`) and a full-rank residual Jacobian.
    priced = !(model.pricing isa NoPricing)
    adm = priced ? pricing_admissibility(model, sol) : nothing
    if priced
        ms_tol = Float64(get(get(design_d, "pricing", Dict{String,Any}()), "multistart_tol", 1e-8))
        uniq_pass = adm.converged >= 2 && adm.spread < ms_tol && adm.rank == adm.n
    end

    gdp = gdp_income(sol, ref_sol)
    gdp_exp = gdp_expenditure(sol, ref_sol)
    defl = gdp_deflator(sol, ref_sol)
    cons = real_consumption(sol) / real_consumption(ref_sol)
    wedge = gdp_wedge(sol)
    overall = (resid_pass && budget_pass && third_pass && (!priced || uniq_pass)) ? "pass" : "fail"
    summary = gate_frag("resid", resid, residual_tol, resid_pass) * "; " *
        gate_frag("budget", budget, budget_tol, budget_pass) * "; " *
        gate_frag(third_name, third_value, third_tol, third_pass)
    priced && (summary *= "; " * gate_frag("uniqueness", adm.spread, ms_tol, uniq_pass))

    # ADR-0019/ADR-0020 external account: every cell asserts all-N clearing and
    # the identity gap S + T + M − (I+X) − (F + B_gov) ≈ 0. Both hold at every
    # endpoint: at η = 0 the sectoral wages satisfy the per-sector FOC, which is
    # what closes the identity there.
    assert_external_account(model, sol)
    canary = external_balance_canary(model, X)
    # ADR-0019/ADR-0022 companion identity: the gdp wedge IS the negated
    # canary gap (`gdp_wedge = -canary.diff` exactly, on and off equilibrium).
    # The C1 defect (a scalar-wage collapse in `gdp_components` on ADR-0022
    # cells) violated it at ~1e-3 while every correct path closes it at
    # float-reassociation level (measured <= 1e-11 on full-71).
    wedge_gap = abs(comp.wedge + canary.diff)
    wedge_gap < 1e-9 || error(
        "gdp wedge identity failure: |gdp_wedge + canary_diff| = $wedge_gap >= 1e-9 " *
        "(ADR-0019: gdp_wedge = -canary_diff; a wage-vector collapse in gdp_components breaks it)")
    # `wage` must be a SCALAR metric: the η = 0 endpoint and the ADR-0022
    # sectoral closure carry SECTORAL wages, so the reported aggregate is the
    # wage-bill-weighted average wage; at η = 1 with one common wage it is that
    # wage (bit-identical to the pre-ADR-0020 metric). Dispersion is reported in
    # the diagnostics (wage_min / wage_max).
    w_metric = η0 ? sum(sol.wages_raw .* data.labor_share) / sum(data.labor_share) :
        model.options.elasticities.eta_s_vec !== nothing ?
            sum(sol.wages_raw .* L_i) / sum(L_i) : w
    gates_d = Dict{String,Any}(
        "residual" => Dict{String,Any}("value" => resid, "tolerance" => residual_tol, "pass" => resid_pass),
        "budget" => Dict{String,Any}("value" => budget, "tolerance" => budget_tol, "pass" => budget_pass),
        third_name => Dict{String,Any}("value" => third_value, "tolerance" => third_tol, "pass" => third_pass),
        "overall" => overall)
    metrics_d = Dict{String,Any}(
        "gdp" => gdp, "gdp_rel" => gdp - 1,
        "gdp_expenditure" => gdp_exp, "gdp_expenditure_rel" => gdp_exp - 1,
        "gdp_deflator" => defl, "gdp_wedge" => wedge,
        "consumption" => cons, "consumption_rel" => cons - 1,
        "employment" => L_sum, "wage" => w_metric,
        "nominal_gdp" => nominal_gdp(sol),
        "max_abs_price_dev" => maximum(abs.(p .- 1)),
        "external_transfer" => sol.external_transfer,
        "programme_financing" => canary.programme_financing,
        "external_position" => canary.financing)
    diagnostics_d = Dict{String,Any}(
        "canary_s" => canary.S, "canary_ixm" => canary.IX - canary.M,
        "canary_diff" => canary.diff,
        "wage_min" => minimum(sol.wages_raw),
        "wage_max" => maximum(sol.wages_raw),
        "gdp_c" => comp.V[1], "gdp_g" => comp.V[2], "gdp_i" => comp.V[3],
        "gdp_x" => comp.V[4], "gdp_m_final" => comp.V[5],
        "gdp_m_int" => comp.V[6], "gdp_t_int" => comp.V[7],
        "external_balance" => external_balance(fin, model, p),
        "gov_deficit" => gov_deficit(fin, model, p),
        "public_budget" => public_budget(fin, model, p))
    if priced
        # Pricing fields only on priced cells, so a pricing-free design keeps
        # its byte-identical manifest. ADR-0029 #10: SIGNED price statistics
        # beside max|p - 1| (`price_dev_mean` is weighted by baseline gross
        # output λ); ADR-0030: rent, its retained part, the profit share and the
        # household real-income index.
        dp = p .- 1
        gates_d["uniqueness"] = Dict{String,Any}("value" => adm.spread, "tolerance" => ms_tol,
            "pass" => uniq_pass)
        merge!(metrics_d, Dict{String,Any}(
            "price_dev_mean" => dot(data.λ, dp) / sum(data.λ),
            "price_dev_min" => minimum(dp), "price_dev_max" => maximum(dp),
            "factor_income" => comp.income,
            "profit" => comp.profit, "retained_profit" => retained_profit(model, sol),
            "profit_share" => profit_share(model, sol),
            "real_income" => real_income_index(sol, ref_sol)))
        if model.pricing isa MarkupPricing
            μ = pricing_markup(model.pricing, q, data.λ)
            metrics_d["markup_min"] = minimum(μ)
            metrics_d["markup_max"] = maximum(μ)
        end
        merge!(diagnostics_d, Dict{String,Any}(
            "canary_retained_profit" => canary.retained_profit,
            "multistart_converged" => adm.converged,
            "multistart_starts" => length(adm.starts),
            "jacobian_rank" => adm.rank, "jacobian_n" => adm.n,
            "jacobian_cond" => adm.cond))
    end
    return (gates = gates_d, gate_summary = summary, metrics = metrics_d,
        diagnostics = diagnostics_d)
end

# ── Manifest / index / scenarios ───────────────────────────────────────

function opencge_pin(root::AbstractString)::Dict{String,Any}
    out = Dict{String,Any}("version" => "absent", "repo_url" => "absent",
        "repo_rev" => "absent", "git_tree_sha1" => "absent")
    mpath = joinpath(root, "Manifest.toml")
    if !isfile(mpath)
        ap = Base.active_project()
        ap === nothing || (mpath = joinpath(dirname(ap), "Manifest.toml"))
    end
    isfile(mpath) || return out
    man = try
        TOML.parsefile(mpath)
    catch
        return out
    end
    entries = get(get(man, "deps", Dict{String,Any}()), "OpenCGE", nothing)
    (entries isa AbstractVector) || (entries = entries === nothing ? [] : [entries])
    isempty(entries) && return out
    e = entries[1]
    out["version"] = string(get(e, "version", "absent"))
    out["repo_url"] = string(get(e, "repo-url", "absent"))
    out["repo_rev"] = string(get(e, "repo-rev", "absent"))
    out["git_tree_sha1"] = string(get(e, "git-tree-sha1", "absent"))
    return out
end

function batch_provenance(design::AbstractString, design_d::Dict{String,Any};
        root::AbstractString = default_root())::Dict{String,Any}
    dat = design_d["data"]
    prog = design_d["programme"]
    HEAD = git_commit(root)
    # Smoke designs pin an explicit programme vector instead of a source
    # file; absent keys simply contribute no hashes.
    paths = String[
        "experiments/designs/" * design * ".toml",
        "data/" * RUN_IO_TABLE,
        String.(dat["calibration_artifacts"])...,
    ]
    haskey(prog, "source") && push!(paths, prog["source"])
    data_sha = Dict{String,Any}(p => sha256_or_absent(joinpath(root, p)) for p in paths)
    return Dict{String,Any}(
        "git_commit" => HEAD,
        "git_dirty" => git_dirty(root),
        "julia_version" => string(VERSION),
        "manifest_sha256" => sha256_or_absent(joinpath(root, "Manifest.toml")),
        "opencge" => opencge_pin(root),
        "design_sha256" => design_sha256(design; root = root),
        "data_sha256" => data_sha,
        "seed" => RUN_SEED,
    )
end

function run_log(rundir::AbstractString, line::AbstractString)::Nothing
    open(joinpath(rundir, "log.txt"), "a") do io
        println(io, iso_timestamp() * " " * line)
    end
    println(line)
    return nothing
end

function write_solution(rundir::AbstractString, data::Data, sol::Solution)::Nothing
    open(joinpath(rundir, "solution.csv"), "w") do io
        println(io, "sector,price,quantity")
        for i in 1:length(sol.quantities)
            println(io, "\"", replace(string(data.io.Sektoren[i]), "\"" => "\"\""), "\"",
                ",", sol.prices_raw[i], ",", sol.quantities[i])
        end
    end
    return nothing
end

csv_field(s::AbstractString) =
    (occursin(r"[,\"\n]", s) ? "\"" * replace(s, "\"" => "\"\"") * "\"" : s)

function rewrite_index(; runs_dir::AbstractString)::Nothing
    rows = Dict{String,Vector{String}}()
    isdir(runs_dir) || mkpath(runs_dir)
    for entry in readdir(runs_dir)
        mandir = joinpath(runs_dir, entry)
        manpath = joinpath(mandir, "manifest.toml")
        isdir(mandir) && isfile(manpath) || continue
        man = TOML.parsefile(manpath)
        scen = get(man, "scenario", Dict{String,Any}())
        gt = get(man, "gates", Dict{String,Any}())
        me = get(man, "metrics", Dict{String,Any}())
        closures = string(get(scen, "labour", ""), "+", get(scen, "financing", ""))
        gs = if haskey(gt, "overall")
            parts = String[]
            for (k, v) in gt
                k == "overall" && continue
                v isa Dict || continue
                push!(parts, gate_frag(k == "residual" ? "resid" : k,
                    v["value"], v["tolerance"], v["pass"]))
            end
            isempty(parts) ? "overall=$(gt["overall"])" : join(sort(parts), "; ")
        else
            "overall=$(get(man, "status", "?"))"
        end
        hm = haskey(me, "gdp_rel") ?
            @sprintf("gdp_rel=%.6f; cons_rel=%.6f; L=%.6f; w=%.6f", me["gdp_rel"], me["consumption_rel"], me["employment"], me["wage"]) : ""
        rows[string(man["run_id"])] = String[
            string(man["run_id"]), string(get(man, "date", "")),
            string(get(man, "design", "")), closures, string(get(man, "status", "")),
            gs, hm, string(get(get(man, "provenance", Dict()), "git_commit", ""))]
    end
    open(joinpath(runs_dir, "index.csv"), "w") do io
        println(io, RUN_INDEX_HEADER)
        for id in sort(collect(keys(rows)))
            println(io, join(csv_field.(rows[id]), ","))
        end
    end
    return nothing
end

function update_scenario_row(run_id::AbstractString, design::AbstractString,
        cell::Dict{String,Any}, status::AbstractString, commit::AbstractString;
        root::AbstractString = default_root(), note_suffix::AbstractString = "",
        vintage::AbstractString = "unknown",
        shock_desc::AbstractString = "impulses.csv",
        shock_magnitude::AbstractString = "1.0")::Nothing
    scenpath = joinpath(root, "registry", "scenarios.csv")
    # Normalize every column to String: without `stringtype = String`, CSV
    # infers narrow InlineString widths (e.g. String7) from the current cell
    # values and the longer status/evidence/commit assignments below throw
    # `ArgumentError: string too large`. (Found by the smoke-manifest tests.)
    raw = DataFrame(CSV.File(scenpath; stringtype = String))
    df = DataFrame([c => string.(coalesce.(raw[!, c], "")) for c in names(raw)])
    r = findfirst(==(run_id), string.(coalesce.(df.run_id, "")))
    r === nothing && throw(ArgumentError("no scenarios.csv row for run_id \"$run_id\""))
    df[r, :design] = design
    df[r, :status] = status
    df[r, :labor] = string(cell["labor"])
    df[r, :financing] = string(cell["financing"])
    df[r, :eta] = string(cell["eta"])
    df[r, :eta_s] = string(get(cell, "eta_s", 0.0))
    df[r, :theta] = string(cell["theta"])
    df[r, :epsilon] = string(cell["epsilon"])
    df[r, :sigma] = string(cell["sigma"])
    df[r, :shock] = shock_desc
    df[r, :magnitude] = shock_magnitude
    df[r, :data_vintage] = vintage
    df[r, :evidence] = "runs/$run_id/manifest.toml; runs/$run_id/log.txt"
    df[r, :commit] = commit
    isempty(note_suffix) || (df[r, :notes] = string(coalesce(df[r, :notes], ""), note_suffix))
    CSV.write(scenpath, df)
    return nothing
end

# ── Cell execution ─────────────────────────────────────────────────────

function execute_cell(run_id::AbstractString, design::AbstractString,
        design_d::Dict{String,Any}, data::Data, ψ::Vector{Float64}, g::Vector{Float64},
        ref_sol::Solution, init_warm::Vector{Float64}, prov::Dict{String,Any};
        root::AbstractString = default_root(), runs_dir::AbstractString = default_runs_dir(root),
        actor::AbstractString = default_actor())::String
    cell = design_cell(design_d, run_id)
    _, scen = resolve_supply_shock(design_d, cell, data, ψ)
    rundir = joinpath(runs_dir, run_id)
    if ispath(rundir)
        println("refusing to overwrite existing run dir runs/$run_id/ — " *
            "register a variant run_id ($run_id-v2) for a rerun")
        return "refused"
    end
    mkpath(rundir)
    man = Dict{String,Any}(
        "schema_version" => RUN_SCHEMA_VERSION,
        "run_id" => run_id, "design" => design, "cell" => run_id,
        "status" => "running", "date" => iso_date(), "actor" => actor,
        "provenance" => prov,
        "scenario" => Dict{String,Any}(
            "labour" => string(cell["labor"]), "financing" => string(cell["financing"]),
            "eta" => Float64(cell["eta"]), "eta_s" => Float64(get(cell, "eta_s", 0.0)),
            "theta" => Float64(cell["theta"]), "epsilon" => Float64(cell["epsilon"]),
            "sigma" => Float64(cell["sigma"]),
            "shock" => scen["shock"], "magnitude" => scen["magnitude"]),
        "solver" => Dict{String,Any}(
            "blas_threads" => BLAS.get_num_threads(),
            "init" => "warm:reference-final", "reference" => "batch-continuation",
            "algorithm" => "kernel solve / solve_beta (Newton + residual-gated LM polish)"),
        "artifacts" => Dict{String,Any}("log" => "log.txt", "solution" => ""),
    )
    if haskey(cell, "delta_epsilon")
        man["scenario"]["delta_epsilon"] = Float64(cell["delta_epsilon"])
    end
    # ADR-0022: record the sectoral elasticity vector so the provenance of a
    # sectoral cell is explicit in the manifest.
    esv = cell_eta_s_vec(cell, data, ψ)
    if esv !== nothing
        man["scenario"]["eta_s_vec"] = esv
        man["scenario"]["eta_s_rigid_group"] = string(get(cell, "eta_s_rigid_group", "explicit"))
    end
    # ADR-0023: record the resolved supply shock (kind != "none" only, so a
    # no-shock design keeps its byte-identical manifest).
    if haskey(scen, "shock_kind")
        man["scenario"]["shock_kind"] = scen["shock_kind"]
        man["scenario"]["shock_A"] = scen["shock_A"]
        if haskey(scen, "shock_alpha")
            man["scenario"]["shock_alpha"] = scen["shock_alpha"]
        else
            man["scenario"]["shock_magnitude"] = scen["shock_magnitude"]
            haskey(scen, "shock_targets") &&
                (man["scenario"]["shock_targets"] = scen["shock_targets"])
        end
    end
    # ADR-0029/ADR-0030: record the pricing closure and the continuation path
    # (priced cells only, so a pricing-free design keeps its byte-identical
    # manifest).
    _, pscen = cell_pricing(design_d, cell)
    if !isempty(pscen)
        merge!(man["scenario"], pscen)
        steps = Int(get(get(design_d, "pricing", Dict{String,Any}()), "continuation_steps", 4))
        man["solver"]["init"] = "warm:reference-final -> no-pricing twin -> continuation($steps)"
    end
    open(joinpath(rundir, "manifest.toml"), "w") do io
        TOML.print(io, man)
    end
    run_log(rundir, "start $run_id design=$design actor=$actor commit=$(prov["git_commit"])")
    run_log(rundir, "reference consumption_ref=$(real_consumption(ref_sol))")
    vintage = string(get(get(design_d, "data", Dict{String,Any}()), "vintage", "unknown"))
    update_scenario_row(run_id, design, cell, "running", prov["git_commit"]; root = root,
        vintage = vintage, shock_desc = scen["shock"], shock_magnitude = string(scen["magnitude"]))
    try
        sol = solve_cell(cell, design_d, data, ψ, g, init_warm)
        ev = evaluate_gates(cell, design_d, sol.model, sol, ref_sol)
        for (k, v) in ev.metrics
            isfinite(v) || throw(ErrorException("non-finite metric $k in $run_id"))
        end
        status = ev.gates["overall"] == "pass" ? "executed" : "failed"
        man["status"] = status
        man["gates"] = ev.gates
        man["metrics"] = ev.metrics
        man["diagnostics"] = ev.diagnostics
        if status == "executed"
            write_solution(rundir, data, sol)
            man["artifacts"]["solution"] = "solution.csv"
        end
        open(joinpath(rundir, "manifest.toml"), "w") do io
            TOML.print(io, man)
        end
        run_log(rundir, "$(status): $(ev.gate_summary)")
        rewrite_index(; runs_dir = runs_dir)
        update_scenario_row(run_id, design, cell, status, prov["git_commit"]; root = root,
            vintage = vintage,
            shock_desc = scen["shock"], shock_magnitude = string(scen["magnitude"]),
            note_suffix = " | $(status) $(iso_date()) (see runs/$run_id/manifest.toml)")
        return status
    catch e
        # Any per-cell failure — solve, gates, metrics, or writes — becomes
        # a `failed` manifest; the batch continues.
        man["status"] = "failed"
        man["gates"] = Dict{String,Any}("overall" => "fail")
        man["error"] = Dict{String,Any}("type" => string(typeof(e)), "message" => sprint(showerror, e))
        try
            open(joinpath(rundir, "manifest.toml"), "w") do io
                TOML.print(io, man)
            end
        catch io_e
            println("could not write failed manifest for $run_id: $(sprint(showerror, io_e))")
        end
        run_log(rundir, "failed: $(typeof(e)): $(sprint(showerror, e))")
        rewrite_index(; runs_dir = runs_dir)
        update_scenario_row(run_id, design, cell, "failed", prov["git_commit"]; root = root,
            vintage = vintage,
            shock_desc = scen["shock"], shock_magnitude = string(scen["magnitude"]),
            note_suffix = " | failed $(iso_date()) (see runs/$run_id/manifest.toml)")
        return "failed"
    end
end

# ── Batch driver ───────────────────────────────────────────────────────

function run_design(design::AbstractString; root::AbstractString = default_root(),
        runs_dir::AbstractString = default_runs_dir(root),
        cell::Union{AbstractString,Nothing} = nothing,
        cells::Union{AbstractString,Vector{<:AbstractString},Nothing} = nothing,
        budget_seconds::Union{Real,Nothing} = nothing,
        actor::AbstractString = default_actor(),
        data::Union{Data,Nothing} = nothing)::Dict{String,String}
    ok, reason = preregistration_status(design; root = root)
    ok || throw(ErrorException("refusing to run: $reason"))
    design_d = load_design(design; root = root)
    order = cell_order(design; root = root)
    wanted = if cell !== nothing && cells !== nothing
        throw(ArgumentError("pass at most one of --cell and --cells"))
    elseif cell !== nothing
        [cell]
    elseif cells !== nothing
        cells isa AbstractString ? String.(split(cells, ",")) : String.(cells)
    else
        order
    end
    for id in wanted
        id in order || throw(ArgumentError("unknown cell \"$id\" for design \"$design\""))
    end

    ref = build_reference(design_d; root = root, data = data)
    # Typed conversion (see the note in `build_reference`): broadcasting over
    # an empty `drops = []` yields `Vector{Any}` once OpenCGE is loaded.
    drops = Vector{Int}(design_d["data"]["drops"])
    kept = if data !== nothing
        collect(1:length(ref.data.factor_share))
    else
        n_full = length(ref.data.factor_share) + length(drops)
        sort(setdiff(1:n_full, drops))
    end
    ψ, g = programme_vectors(design_d, ref.data, kept; root = root)
    prov = batch_provenance(design, design_d; root = root)

    t0 = time()
    results = Dict{String,String}()
    for id in order
        id in wanted || continue
        if budget_seconds !== nothing && (time() - t0) > Float64(budget_seconds)
            println("budget exceeded ($(round(time()-t0; digits=1))s > $budget_seconds s); " *
                "stopping cleanly before $id")
            break
        end
        results[id] = try
            execute_cell(id, design, design_d, ref.data, ψ, g,
                ref.sol, ref.init_warm, prov; root = root, runs_dir = runs_dir, actor = actor)
        catch e
            # Infrastructure failures outside the cell itself (already
            # manifest-backed inside execute_cell) must not abort the batch.
            println("cell $id errored outside its manifest: $(sprint(showerror, e))")
            "error"
        end
    end
    return results
end

# ── CLI ────────────────────────────────────────────────────────────────

function usage()::Nothing
    println(stderr, """usage:
  julia --project=. experiments/run.jl --list <design>
  julia --project=. experiments/run.jl --preregister <design> [--actor NAME]
  julia --project=. experiments/run.jl --design <design> [--cell <run_id>] [--cells a,b,c] [--runs-dir DIR] [--budget-seconds N] [--actor NAME]""")
    exit(1)
end

function main(args::Vector{String} = ARGS; root::AbstractString = default_root())::Nothing
    isempty(args) && usage()
    mode, design = args[1], length(args) >= 2 && !startswith(args[2], "--") ? args[2] : nothing
    opts = Dict{String,String}()
    i = 3
    while i <= length(args)
        a = args[i]
        startswith(a, "--") || usage()
        key = a[3:end]
        key in ("cell", "cells", "runs-dir", "budget-seconds", "actor") ||
            (println(stderr, "unknown option $a"); usage())
        i + 1 > length(args) && usage()
        opts[key] = args[i+1]
        i += 2
    end
    if mode == "--list"
        design === nothing && usage()
        list_cells(design; root = root)
    elseif mode == "--preregister"
        design === nothing && usage()
        sha = preregister_design(design; root = root, actor = get(opts, "actor", default_actor()))
        println("preregistered $design (sha256=$sha)")
    elseif mode == "--design"
        design === nothing && usage()
        budget = haskey(opts, "budget-seconds") ? parse(Float64, opts["budget-seconds"]) : nothing
        results = run_design(design; root = root,
            runs_dir = get(opts, "runs-dir", default_runs_dir(root)),
            cell = get(opts, "cell", nothing), cells = get(opts, "cells", nothing),
            budget_seconds = budget, actor = get(opts, "actor", default_actor()))
        for id in sort(collect(keys(results)))
            println("$id: $(results[id])")
        end
    else
        usage()
    end
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    # These 71-sector systems benefit from avoiding threaded BLAS overhead.
    # Keep the resource choice explicit and overridable for other workloads.
    BLAS.set_num_threads(parse(Int, get(ENV, "BEYONDHULTEN_BLAS_THREADS", "1")))
    main()
end
