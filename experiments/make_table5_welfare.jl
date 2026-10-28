# =====================================================================

using OpenCGE, TOML, Printf

if !isdefined(OpenCGE, :AbstractPricing)   # the pricing-door line renames the type;
    @eval const AbstractPricing = OpenCGE.AbstractPricingClosure   # the release exports it
end
isdefined(@__MODULE__, :load_design) || include(joinpath(@__DIR__, "run.jl"))

const SIGMA = 0.9
const LAMBDA = 1.0
const GATE_TOL = 1e-6

const FIN = ["F1", "F2", "F3"]
const LABOUR = ["BF", "ALPHA", "BETA", "GAMMA", "DELTA"]
const ETAS = ["-etas05", "-etas1", "-etas2"]          # the bracket, low end first
const ETAS_LO, ETAS_HI = "0.5", "2"

const FINLABEL = Dict("F1" => "repurposing of consumption",
                      "F2" => "refinancing via taxes",
                      "F3" => "external finance")
const LABEL = Dict("BF" => "No-reallocation", "ALPHA" => "Standard CGE",
                   "BETA" => "Elastic supply", "GAMMA" => "Employment adjustment",
                   "DELTA" => "Leontief")

cell_id(lab, fin, suf = "") = "matrix_5x3-$lab-$fin" * (lab == "BETA" ? (suf == "" ? "-etas05" : suf) : "")

function bundle_block(sol::Solution; lam::Real = LAMBDA)
    final_demand_bundle(sol.model, sol.prices_raw, sol.quantities,
        OpenCGE._bundle_wage(sol); lambda = lam, external_transfer = sol.external_transfer)
end

fvec(b, stretch::Real; lam::Real = LAMBDA) = stretch .* b.c .+ lam .* b.g

function U_idx(q::AbstractVector, q0::AbstractVector, w::AbstractVector)
    k = (q .> 0) .& (q0 .> 0)
    qk, q0k, wk = q[k], q0[k], w[k]
    wk = wk ./ sum(wk)
    r = qk ./ q0k
    return (sum(wk .* r .^ ((SIGMA - 1) / SIGMA)))^(SIGMA / (SIGMA - 1))
end

function reads(sol::Solution, ref)
    b1, b0 = bundle_block(sol), bundle_block(ref.sol)
    ls, ls0 = sum(b1.L_i), sum(b0.L_i)
    w = b1.wage_bill / ls
    out = Dict{Symbol,Float64}()
    for (key, stretch) in ((:leak, 1.0), (:def, 1.0 / (1 - sol.model.data.saving_rate)))
        f, f0 = fvec(b1, stretch), fvec(b0, stretch)
        # W_CES and W_CES* are ONE construction at two weight vectors: the change
        # in the bundle valued at the dated tastes (W_CES) or at the ADOPTED
        # tastes (W_CES*), with both bundles priced at that one weight vector ---
        # so no comparison of utility levels across taste vectors is needed. The
        # utility evaluation at adopted tastes beta_i ∝ f_i^(1/sigma) p_i enters
        # this parameterisation as omega_i ∝ beta_i f0_i^rho, that is
        # p_i f_i^(1/sigma) f0_i^((sigma-1)/sigma).
        r_ces = U_idx(f, f0, f0)
        omega = (sol.prices .* f .^ (1 / SIGMA)) .* f0 .^ ((SIGMA - 1) / SIGMA)
        r_star = U_idx(f, f0, omega)
        # canary: at unchanged tastes omega0 = p0 f0^(1/sigma) f0^rho ∝ f0, so the
        # corrected construction must reproduce W_CES exactly
        omega0 = (ref.sol.prices .* f0 .^ (1 / SIGMA)) .* f0 .^ ((SIGMA - 1) / SIGMA)
        abs(U_idx(f, f0, omega0) - r_ces) < 1e-12 ||
            @warn "weight reduction failed" r_ces
        v0 = sum(ref.sol.prices .* f0)
        out[Symbol(:ces, key)] = 100 * (r_ces - 1)
        out[Symbol(:star, key)] = 100 * (r_star - 1)
        out[Symbol(:starl, key)] = 100 * ((r_star - 1) - w * (ls - ls0) / v0)
    end
    out[:d] = 100 * (sum(fvec(b1, 1.0)) / sum(fvec(b0, 1.0)) - 1)     # W_D
    return out
end

function check_table5_source(man, design, cell, id;
        root = default_root(), source_tree = nothing)
    man["run_id"] == man["cell"] == id || error("run identity mismatch: $id")
    man["design"] == design["design"] || error("design mismatch: $id")
    man["status"] == "executed" && man["gates"]["overall"] == "pass" ||
        error("unaccepted cell: $id")
    provenance = man["provenance"]
    provenance["design_sha256"] == design_sha256(design["design"]; root) ||
        error("design changed: $id")
    for path in (design["data"]["source_table"], design["programme"]["source"])
        get(provenance["data_sha256"], path, nothing) == sha256_file(joinpath(root, path)) ||
            error("input changed ($path): $id")
    end
    for (key, value) in (("labor", "labour"), ("financing", "financing"))
        cell[key] == man["scenario"][value] || error("$key mismatch: $id")
    end
    for key in ("eta", "eta_s", "theta", "epsilon", "sigma", "delta_epsilon")
        haskey(cell, key) || continue
        get(man["scenario"], key, nothing) == cell[key] || error("$key mismatch: $id")
    end
    tree = provenance["opencge"]["git_tree_sha1"]
    occursin(r"^[0-9a-f]{40}$", tree) || error("missing kernel tree: $id")
    source_tree === nothing || tree == source_tree || error("mixed kernel trees: $id")
    return tree
end

function check_table5_result(man, evaluated, id)
    evaluated.gates["overall"] == "pass" || error("current design gates failed: $id")
    max_gap = 0.0
    for (key, recorded) in man["metrics"]
        actual = get(evaluated.metrics, key, nothing)
        recorded isa Real && actual isa Real && isfinite(recorded) && isfinite(actual) ||
            error("missing or non-finite metric $key: $id")
        gap = abs(actual - recorded)
        gap < GATE_TOL || error("metric $key changed by $gap: $id")
        max_gap = max(max_gap, gap)
    end
    return max_gap
end

function main()
    root = default_root()
    dd = load_design("matrix_5x3"; root = root)
    @printf("building no-program baseline for matrix_5x3 ...\n")
    ref = build_reference(dd; root = root)
    drops = Vector{Int}(dd["data"]["drops"])
    kept = sort(setdiff(1:(length(ref.data.factor_share) + length(drops)), drops))
    ψ, g = programme_vectors(dd, ref.data, kept; root = root)

    rows, side = NamedTuple[], NamedTuple[]
    source_tree = nothing
    for fin in FIN, lab in LABOUR
        sufs = lab == "BETA" ? ETAS : [""]
        got, okall, wc = NamedTuple[], true, NaN
        for suf in sufs
            id = cell_id(lab, fin, suf)
            manpath = joinpath(root, "runs", id, "manifest.toml")
            man = TOML.parsefile(manpath)
            cell = design_cell(dd, id)
            source_tree = check_table5_source(man, dd, cell, id; root, source_tree)
            sol = solve_cell(cell, dd, ref.data, ψ, g, ref.init_warm)
            evaluated = evaluate_gates(cell, dd, sol.model, sol, ref.sol)
            gap = check_table5_result(man, evaluated, id)
            @printf("  %s: %d metrics reproduced, max gap %.2e\n", id, length(man["metrics"]), gap)
            r = reads(sol, ref)
            wc = 100 * man["metrics"]["consumption_rel"]
            # canary: the baseline-weight CES must reproduce the kernel's index
            ker = real_final_demand_ces(sol, ref.sol; lambda = LAMBDA, sigma = SIGMA) - 1
            abs(r[:cesleak] - 100 * ker) < 1e-8 || @warn "W_CES differs from the kernel" id r[:cesleak] ker
            ok = abs(wc - 100 * (real_consumption(sol) / real_consumption(ref.sol) - 1)) < GATE_TOL
            push!(got, (; wc = wc, ok = ok, d = r[:d], cesleak = r[:cesleak],
                starleak = r[:starleak], starlleak = r[:starlleak], starldef = r[:starldef]))
            push!(side, (run_id = id, w_c = wc, w_d = r[:d], w_ces = r[:cesleak],
                w_ces_star = r[:starleak], w_l = r[:starlleak]))
        end
        okall = all(x -> x.ok, got)
        lo, hi = x -> minimum(x), x -> maximum(x)
        agg(f) = (lo([f(x) for x in got]), hi([f(x) for x in got]))
        push!(rows, (lab = lab, fin = fin, ok = okall,
            wc = agg(x -> x.wc), wd = agg(x -> x[:d]),
            ces = agg(x -> x[:cesleak]), star = agg(x -> x[:starleak]),
            sl = agg(x -> x[:starlleak]), sd = agg(x -> x[:starldef])))
        @printf("  %-26s gate %s  Wc %+7.3f  Wd %+7.3f  CES %+7.3f  CES* %+7.3f  L %+7.3f/%+7.3f\n",
            cell_id(lab, fin), okall ? "ok" : "FAIL", got[1].wc, got[1][:d],
            got[1][:cesleak], got[1][:starleak], got[1][:starlleak], got[1][:starldef])
    end
    all(r -> r.ok, rows) || error("manifest gate failed; nothing written")
    path = joinpath(root, "revision", "tables", "table5_welfare-comparison.tex")
    open(path, "w") do io
        render(io, rows)
    end
    println("wrote ", path)
    # The five-column sidecar: every number the table prints, per run, so the
    # table is checkable without re-solving. Written only after the gate passes.
    sidepath = joinpath(root, "revision", "tables", "table5_welfare.csv")
    open(sidepath, "w") do io
        println(io, "run_id,w_c,w_d,w_ces,w_ces_star,w_l")
        for s in side
            @printf(io, "%s,%.6f,%.6f,%.6f,%.6f,%.6f\n", s.run_id, s.w_c, s.w_d,
                s.w_ces, s.w_ces_star, s.w_l)
        end
    end
    println("wrote ", sidepath)
    return all(r -> r.ok, rows) ? 0 : 1
end

# same convention as table4_results-5x3.tex: values in math mode, so the
# unary minus is a proper minus sign and "--" stays a text en-dash between them
num(x) = (!isfinite(x)) ? "n/a" : (abs(x) < 5e-5 ? "\$0.00\$" :
         (x > 0 ? @sprintf("\$+%.2f\$", x) : @sprintf("\$%.2f\$", x)))

function rngv(p)
    lo, hi = p
    abs(hi - lo) < 5e-5 && return num(lo)
    return num(lo) * "--" * num(hi)
end

# the variables shown, in the order they appear inside each cell
const MEAS = [(:wc,   "\$W_C\$"),
              (:wd,   "\$W_D\$"),
              (:ces,  "\$W_{CES}\$"),
              (:star, "\$W_{CES^*}\$"),
              (:sl,   "\$W_{L}\$")]

CELL_SPEC = raw"@{}l@{\hspace{3pt}}r@{}"
# elastic-supply cell: label column + one bracketed column
ETAS_CELL_SPEC = raw"@{}>{\raggedright\arraybackslash}p{1.05cm}@{\hspace{3pt}}>{\raggedleft\arraybackslash}p{2.2cm}@{}"

plain_str(r) = "\\begin{tabular}{" * CELL_SPEC * "}\n" *
    join([lab * " & " * num(getfield(r, k)[1]) * " \\\\" for (k, lab) in MEAS], "\n") *
    "\\end{tabular}"

etas_str(r) = "\\begin{tabular}{" * ETAS_CELL_SPEC * "}\n" *
    join([lab * " & " * rngv(getfield(r, k)) * " \\\\" for (k, lab) in MEAS], "\n") *
    "\\end{tabular}"

cellstr(lab, r) = lab == "BETA" ? etas_str(r) : plain_str(r)

# --- the collapsing routine, ported from tables/make_table4_results.py -------
# The two coincidences the table states are PRINTED ONCE:
#   * F2 and F3 coincide in the three flexible-wage columns -> that cell is set
#     with \multirow on the F2 row, the F3 row leaves those columns empty, and
#     the rule between the two rows is a \cmidrule over the GAMMA/DELTA pair only
#     (a full \midrule would cut through the merged cells).
#   * the employment-adjustment and Leontief columns coincide -> one \multicolumn{2}
#     cell per row, horizontally centred.
# check_collapses() compares the PRINTED strings before anything is written, so a
# kernel change that breaks an equivalence aborts the run instead of silently
# printing one value in two cells.
const FLEX_COLS   = ["BF", "ALPHA", "BETA"]   # the three flexible-wage columns
const SHARED_ROWS = ["F2", "F3"]              # coincide in FLEX_COLS
const SHARED_COLS = ["GAMMA", "DELTA"]        # coincide in every financing row

# merged width of the GAMMA+DELTA pair: 2.0 + 2*\tabcolsep(3pt) + 2.0 = 4.21cm;
# 4.05cm leaves the same small slack Table 4's 4.35cm leaves in its 4.41cm pair
const MERGED_W = "4.05cm"

# \multirow counts LINES, not logical rows. The logical span is
# length(MEAS)*length(SHARED_ROWS); the measured correction is -length(MEAS)+2,
# which gives 7 for the five stacked reads -- the same value Table 4 measured,
# since both blocks are five lines tall. Re-measure if a read is added.
const SPAN = length(MEAS) * length(SHARED_ROWS) - length(MEAS) + 2
const VMOVE = "[\\dimexpr\\baselineskip/4\\relax]"

multirow(n, w, s) = "\\multirow{" * string(n) * "}{" * w * "}" * VMOVE * "{\\centering " * s * "}"
multicol(s) = "\\multicolumn{2}{|>{\\centering\\arraybackslash}p{" * MERGED_W * "}}{" * s * "}"

function check_collapses(by)
    for lab in FLEX_COLS
        a, b = cellstr(lab, by[("F2", lab)]), cellstr(lab, by[("F3", lab)])
        a == b || error("F2 != F3 in column $lab: the row merge would print a wrong value")
    end
    for fin in FIN
        a = cellstr(SHARED_COLS[1], by[(fin, SHARED_COLS[1])])
        b = cellstr(SHARED_COLS[2], by[(fin, SHARED_COLS[2])])
        a == b || error("GAMMA != DELTA in row $fin: the column merge would print a wrong value")
    end
end

function etas_head()
    return ("{\\footnotesize\\begin{tabular}{" * ETAS_CELL_SPEC * "}\n"
            * "& \$\\eta_s \\in [" * ETAS_LO * "," * ETAS_HI * "]\$\\end{tabular}}")
end

function render(io, rows)
    by = Dict((r.fin, r.lab) => r for r in rows)
    println(io, "% =====================================================================")
    println(io, "% Table 5 --- welfare comparison across the closure matrix (GENERATED)")
    println(io, "% Sources: runs/matrix_5x3-<labor>-<financing>[-etas{05,1,2}]/manifest.toml")
    println(io, "% Verification kernel: OpenCGE ", pkgversion(OpenCGE), "; source design, inputs, kernel-tree consistency and all recorded metrics checked.")
    println(io, "% ---------------------------------------------------------------------")
    println(io, "% Do NOT edit by hand. Regenerate with:")
    println(io, "%   julia --project=. experiments/make_table5_welfare.jl")
    println(io, "% Layout adopts the COLLAPSING ROUTINE of table4_results-5x3.tex: the two")
    println(io, "%   coincidences the table states are PRINTED ONCE -- F2/F3 share one cell in")
    println(io, "%   the three flexible-wage columns (\\multirow, centred across the two rows,")
    println(io, "%   the rule between them a \\cmidrule over the GAMMA/DELTA pair only) and the")
    println(io, "%   employment-adjustment and Leontief columns share one \\multicolumn{2} cell per")
    println(io, "%   row. check_collapses() asserts both on the PRINTED strings, so a broken")
    println(io, "%   equivalence aborts the run. Column widths and the cell contents are Table")
    println(io, "%   5's own; only the collapse/centre/rule grammar is Table 4's.")
    println(io, "% W_C is the manifest field; W_D, W_CES and W_CES* are computed here and")
    println(io, "%   gated against runs/<id>/manifest.toml (consumption_rel, tol 1e-6). No run")
    println(io, "%   directory is created or modified, and no number is hand-typed.")
    println(io, "% =====================================================================")
    println(io, "\\begin{table}[htbp]")
    println(io, "\\centering")
    println(io, "\\footnotesize")
    println(io, "\\setlength{\\tabcolsep}{3pt}")
    println(io, "\\setlength{\\parindent}{0pt}")
    println(io, "\\setlength{\\parskip}{2pt}")
    println(io, "\\renewcommand{\\arraystretch}{1.25}")
    # column widths: the plain columns were measured against the long
    # $W_{CES^*}$ label -- 2.0cm clears every overfull where Table 4's 2.1cm was
    # sized for the shorter $\Delta Y$-style labels, and 1.6cm clears the
    # "Financing"/"repurposing" boxes in the label column. MERGED_W above is
    # 2*plain + 2*\tabcolsep. Total 14.17cm against a 15.24cm text block.
    width = Dict("BETA" => "3.5cm")
    print(io, "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{1.6cm}")
    for lab in FLEX_COLS
        print(io, " >{\\raggedright\\arraybackslash}p{" * get(width, lab, "2.0cm") * "}")
    end
    # the vertical rule marks the boundary between the flexible block and the
    # GAMMA/DELTA pair, so the redrawn \cmidrules below trace the same boundary
    print(io, " |")
    for lab in SHARED_COLS
        print(io, " >{\\raggedright\\arraybackslash}p{" * get(width, lab, "2.0cm") * "}")
    end
    println(io, "@{}}")
    println(io, "\\toprule")
    println(io, "\\textbf{Financing closure}")
    println(io, "& \\textbf{No-reallocation}\\newline \\scriptsize immobile labor, sectoral wages")
    println(io, "& \\textbf{Standard CGE}\\newline \\scriptsize one flexible wage, mobile labor")
    println(io, "& \\textbf{Elastic labor supply}\\newline \\scriptsize sectoral supply on the real wage\\newline " * etas_head())
    println(io, "& \\textbf{Employment adjustment}\\newline \\scriptsize wage pinned, employment uncapped")
    println(io, "& \\textbf{Leontief closure}\\newline \\scriptsize wage pinned, quantities absorb")
    println(io, "\\\\")
    println(io, "\\midrule")
    # refuse to merge unless the two printed cells really are identical
    check_collapses(by)

    flagof(fin) = all(by[(fin, lab)].ok for lab in LABOUR) ? "" : "\\textsuperscript{\\dag}"

    # --- row F1: nothing is shared; all three flexible cells are separate, and
    #     the employment-adjustment and Leontief columns print once as one cell
    println(io, "\\textbf{F1}\\newline \\scriptsize " * FINLABEL["F1"] * flagof("F1"))
    for lab in FLEX_COLS
        print(io, "& " * cellstr(lab, by[("F1", lab)]))
    end
    println(io, "& " * multicol(cellstr(SHARED_COLS[1], by[("F1", SHARED_COLS[1])])) * "\\\\")
    # the rule separates the F1 row from the F2/F3 band in the left block and
    # restarts over the GAMMA/DELTA pair, so it marks the block boundary
    println(io, "\\cmidrule(lr){1-4}\\cmidrule(lr){5-6}")

    # --- row F2: its three flexible cells are shared with F3, so they are set
    #     once with \multirow and vertically centred across the two rows; the
    #     GAMMA/DELTA pair is shared within the row (\multicolumn).
    println(io, "\\textbf{F2}\\newline \\scriptsize " * FINLABEL["F2"] * flagof("F2"))
    for lab in FLEX_COLS
        print(io, "& " * multirow(SPAN, get(width, lab, "2.0cm"),
                                   cellstr(lab, by[("F2", lab)])))
    end
    println(io, "& " * multicol(cellstr(SHARED_COLS[1], by[("F2", SHARED_COLS[1])])) * "\\\\")
    # no full rule here: it would cut through the merged cells
    println(io, "\\cmidrule(lr){5-6}")

    # --- row F3: the flexible columns are already printed (the F2 cells, whose
    #     values equal F3's); only the GAMMA/DELTA pair belongs to this row
    println(io, "\\textbf{F3}\\newline \\scriptsize " * FINLABEL["F3"] * flagof("F3"))
    println(io, "& & & & " * multicol(cellstr(SHARED_COLS[1], by[("F3", SHARED_COLS[1])])) * "\\\\")
    println(io, "\\bottomrule")
    println(io, "\\end{tabular}")
    println(io, "\\caption{Welfare comparison across different closures in the closure matrix.")
    println(io, "The variables reported in each cell are welfare estimates of an identical")
    println(io, "allocation, all in percent against the baseline. \$W_C\$ is the")
    println(io, "household-consumption index of Table~\\ref{tab:results-matrix}; \$W_D\$ the")
    println(io, "quantity index of demand over \$c^{h}+g^{G}+g\$;")
    println(io, "\$W_{CES}\$ the CES evaluation of the change in that bundle at the \\emph{baseline}")
    println(io, "tastes (public demand included, both bundles valued at the dated preferences);")
    println(io, "\$W_{CES^*}\$ the same comparison at the household's \\emph{adopted} (post-program)")
    println(io, "tastes. \$W_{L}\$ the leisure-augmented form, also charging the program's extra work")
    println(io, "hours.}")
    println(io, "\\label{tab:welfare-comparison}")
    println(io, "\\end{table}")
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    exit(main())
end
