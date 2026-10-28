# experiments/plot_matrix.jl — comparative figures for the executed 5x3 matrix

using OpenCGE
using TOML
using CSV
using DataFrames
using Printf

# run.jl is include-safe (PROGRAM_FILE guard); skip the re-include when it is
# already loaded (as `tests/test_run_manifest.jl` does).
isdefined(Main, :run_design) || include(joinpath(@__DIR__, "run.jl"))

function plot_usage()::Int
  println(
    stderr, """usage:
    julia --project=. experiments/plot_matrix.jl --design <design> [--cells a,b,c] [--outdir DIR] [--data-dir DIR] [--panel-dir DIR] [--comparison-out FILE] [--comparison-sectors s1,s2,s3] [--comparison-closures c1,c2] [--scatter-out FILE] [--scatter-pairs BF/F1,BETA/F2] [--scatter-split | --scatter-panel] [--no-figures] [--quiet]"""
  )
  return 1
end

const DEFAULT_COMPARISON_SECTORS = [
  "Electrical.equipment",
  "Metal.ores..other.mining.and.quarr..prod..services",
  "Other.personal.service.activities",
]

const MANUSCRIPT_COMPARISON_CLOSURES = ["BF", "BETA", "DELTA"]
const PLOT_LABOUR_LABELS = Dict(
  "BF" => "No-reallocation", "ALPHA" => "Standard CGE",
  "BETA" => "Elastic labor supply", "GAMMA" => "Employment adjustment",
  "DELTA" => "Leontief closure"
)
const PLOT_FINANCING_LABELS = Dict(
  "F1" => "Repurposing of consumption", "F2" => "Refinancing via taxes",
  "F3" => "External / debt finance"
)

# Panel titles of the two-financing scatter use the short financing names, so
# "(a) F3: External finance" fits a half-column; the longer legend label above
# ("External / debt finance") stays for the bar comparison.
const PLOT_SCATTER_FINANCING_TITLES = Dict(
  "F1" => "Repurposing of consumption", "F2" => "Refinancing via taxes",
  "F3" => "External finance"
)

const PLOT_SCATTER_TITLE = "Sectoral price and output responses under different closures"

# Display names for the characteristic-sector comparison, keyed by the design's
# dotted sector id. Only entries listed here are renamed; everything else keeps
# the kernel's label (the curated sector_short_names.csv is absent here).
const PLOT_SECTOR_LABELS = Dict(
  "Metal.ores..other.mining.and.quarr..prod..services" => "Metal ores and mining"
)

plot_labour_label(id::AbstractString) = get(PLOT_LABOUR_LABELS, id, id)
plot_financing_label(id::AbstractString) = get(PLOT_FINANCING_LABELS, id, id)

function plot_scatter_outputs(path::AbstractString, pairs::AbstractVector, split::Bool)
  split || return [(; path=String(path), pairs)]
  stem, ext = splitext(path)
  return [
    (;
      path=stem * "_" * fin * ext,
      pairs=filter(p -> last(p) == fin, pairs),
    ) for fin in unique(last.(pairs))
  ]
end

function plot_scatter_labels(pairs::AbstractVector)
  common_financing = length(unique(last.(pairs))) == 1
  return [
    plot_labour_label(first(p)) * (
      common_financing ? "" :
      " — " * plot_financing_label(last(p))
    ) for p in pairs
  ]
end

function parse_plot_args(args::Vector{String})::NamedTuple
  design::Union{String,Nothing} = nothing
  cells::Union{Vector{String},Nothing} = nothing
  outdir::Union{String,Nothing} = nothing
  data_dir::Union{String,Nothing} = nothing
  panel_dir::Union{String,Nothing} = nothing
  comparison_out::Union{String,Nothing} = nothing
  comparison_sectors::Union{Vector{String},Nothing} = nothing
  comparison_closures::Union{Vector{String},Nothing} = nothing
  scatter_out::Union{String,Nothing} = nothing
  scatter_pairs::Union{Vector{Tuple{String,String}},Nothing} = nothing
  scatter_split = false
  scatter_panel = false
  no_figures = false
  quiet = false
  i = 1
  while i <= length(args)
    a = args[i]
    if a in (
      "--design", "--cells", "--outdir", "--data-dir", "--panel-dir",
      "--comparison-out", "--comparison-sectors", "--comparison-closures",
      "--scatter-out", "--scatter-pairs",
    )
      i + 1 > length(args) && throw(ArgumentError("missing value for $a"))
      key = a[3:end]
      val = args[i+1]
      if key == "design"
        design = val
      elseif key == "cells"
        cells = unique(String.(strip.(split(val, ","))))
      elseif key == "outdir"
        outdir = val
      elseif key == "panel-dir"
        panel_dir = val
      elseif key == "comparison-out"
        comparison_out = val
      elseif key == "comparison-sectors"
        comparison_sectors = String.(strip.(split(val, ",")))
      elseif key == "comparison-closures"
        comparison_closures = String.(strip.(split(val, ",")))
      elseif key == "scatter-out"
        scatter_out = val
      elseif key == "scatter-pairs"
        scatter_pairs = Tuple{String,String}[]
        for entry in split(val, ",")
          pair = strip.(split(entry, "/"))
          length(pair) == 2 && all(!isempty, pair) ||
            throw(ArgumentError("scatter pairs must use LABOUR/FINANCING, e.g. BF/F1,BETA/F2"))
          push!(scatter_pairs, (String(pair[1]), String(pair[2])))
        end
        length(unique(scatter_pairs)) == length(scatter_pairs) ||
          throw(ArgumentError("scatter pairs must be unique"))
      else
        data_dir = val
      end
      i += 2
    elseif a == "--no-figures"
      no_figures = true
      i += 1
    elseif a == "--scatter-split"
      scatter_split = true
      i += 1
    elseif a == "--scatter-panel"
      scatter_panel = true
      i += 1
    elseif a == "--quiet"
      quiet = true
      i += 1
    else
      throw(ArgumentError("unknown option \"$a\""))
    end
  end
  scatter_split && scatter_panel && throw(
      ArgumentError(
        "--scatter-split and --scatter-panel are mutually exclusive"
      )
    )
  scatter_panel && scatter_out === nothing && throw(
      ArgumentError(
        "--scatter-panel requires --scatter-out"
      )
    )
  return (;
    design=design, cells=cells, outdir=outdir,
    data_dir=data_dir, panel_dir=panel_dir,
    comparison_out=comparison_out,
    comparison_sectors=comparison_sectors,
    comparison_closures=comparison_closures,
    scatter_out=scatter_out, scatter_pairs=scatter_pairs, scatter_split=scatter_split, scatter_panel=scatter_panel,
    no_figures=no_figures, quiet=quiet,
  )
end

function plot_default_cell_ids(
  design_d::Dict{String,Any},
  ids::AbstractVector{<:AbstractString}, design::AbstractString
)::Vector{String}
  have = Set(String.(ids))
  out = String[]
  for id in matrix_cell_ids(ids, design)
    cell = design_cell(design_d, id)
    if string(cell["labor"]) == "BETA"
      financing = string(cell["financing"])
      id *= "-etas05"
      id in have || throw(
        ArgumentError(
          "no headline uniform-sectoral BETA cell \"$id\"; " *
          "pass --cells explicitly to plot historical benchmarks"
        )
      )
      cell = design_cell(design_d, id)
      uniform = if haskey(cell, "eta_s_vec")
        esv = cell["eta_s_vec"]
        !isempty(esv) && all(x -> Float64(x) == 0.5, esv)
      else
        string(get(cell, "eta_s_rigid_group", "scalar")) == "none"
      end
      (
        string(cell["labor"]) == "BETA" &&
        string(cell["financing"]) == financing &&
        uniform && Float64(cell["eta"]) == 1.0 &&
        Float64(get(cell, "eta_s", NaN)) == 0.5
      ) || throw(
        ArgumentError(
          "headline BETA cell \"$id\" must use sectoral wages " *
          "with uniform eta_s = 0.5"
        )
      )
    end
    push!(out, id)
  end
  return out
end

function plot_short_sector_labels(
  labels::AbstractVector{<:AbstractString};
  root::AbstractString=default_root()
)::Union{Nothing,Vector{String}}
  path = joinpath(root, "data", "sector_short_names.csv")
  if !isfile(path)
    @warn "no curated sector names at $path; panels use fallback names"
    return nothing
  end
  df = CSV.read(path, DataFrame; types=String)
  table = Dict(zip(df.label, df.short))
  for l in labels
    haskey(table, l) && continue
    @warn "no curated short name for sector \"$l\" in $path; panels use fallback names"
    return nothing
  end
  return [table[l] for l in labels]
end

function resolve_comparison_sectors(
  ds::MatrixDataset,
  requested::Union{Nothing,AbstractVector{<:AbstractString}},
  short_all::Union{Nothing,AbstractVector{<:AbstractString}}
)
  isempty(ds.cells) && throw(ArgumentError("dataset contains no cells"))
  ref = first(ds.cells)
  n = length(ref.sectors)
  raw = requested === nothing ? DEFAULT_COMPARISON_SECTORS : collect(requested)
  idx = Int[]
  for s in raw
    k = tryparse(Int, s)
    if k !== nothing && 1 <= k <= n
      push!(idx, k)
      continue
    end
    m = findall(==(s), ref.sectors)
    isempty(m) && (m = findall(==(s), ref.labels))
    isempty(m) && short_all !== nothing && (m = findall(==(s), short_all))
    length(m) == 1 || throw(ArgumentError("unknown or ambiguous comparison sector $(repr(s))"))
    push!(idx, only(m))
  end
  slabels = short_all === nothing ? ref.labels[idx] : [String(short_all[j]) for j in idx]
  return idx, slabels
end

function glmakie_available()::Bool
  return Base.find_package("GLMakie") !== nothing
end

function plot_save_png(path::AbstractString, fig)
  lowercase(splitext(path)[2]) == ".png" ||
    throw(ArgumentError("comparison plots write .png files"))
  mkpath(dirname(abspath(path)))
  img = GLMakie.colorbuffer(fig; px_per_unit=600 / 72)
  GLMakie.FileIO.save(path, img; dpi=600)
  return path
end

function plot_save_comparison(path, ds, idx, closures, sector_labels)
  data = closure_comparison_data(ds, idx, closures)
  labour_labels = plot_labour_label.(unique(data.labours))
  fig = OpenCGE.plot_closure_comparison(
    ds, idx, closures;
    sector_labels, labour_labels,
    financing_labels=[
      f == "F2" ? "F2 = F3 (except Leontief)" :
      f == "F3" ? "F3 (Leontief only)" : f
      for f in unique(data.financings)
    ]
  )
  ax = only(
    a for a in fig.content if a isa GLMakie.Axis &&
    a.ylabel[] == "Change vs. baseline (%)"
  )
  ax.xticks = (first(ax.xticks[]), repeat(labour_labels, length(idx)))
  ax.xticklabelrotation = pi / 4
  ax.xticklabelalign = (:right, :center)
  GLMakie.resize_to_layout!(fig)
  return plot_save_png(path, fig)
end

function plot_save_scatter_panel(path, ds, left, right, programme, titles)
  fig = OpenCGE.plot_closure_scatter_panel(
    ds, left.pairs, right.pairs; programme, titles,
    figtitle=PLOT_SCATTER_TITLE,
    left_kwargs=(; closure_labels=plot_scatter_labels(left.pairs)),
    right_kwargs=(; closure_labels=plot_scatter_labels(right.pairs)),
    size=(964, 500), fontsize=16, max_markersize=20
  )
  plot_save_png(path, fig)
  return path
end

function plot_sector_labels(
  design_d::Dict{String,Any}, n::Integer;
  root::AbstractString=default_root()
)::Vector{String}
  try
    prog = design_d["programme"]
    haskey(prog, "source") || return string.(1:n)
    path = joinpath(root, prog["source"])
    isfile(path) || return string.(1:n)
    cols = names(DataFrame(CSV.File(path; limit=1)))
    length(cols) >= 2 + n || return string.(1:n)
    return String.(cols[3:(2+n)])
  catch
    return string.(1:n)
  end
end

function read_stored_solution(path::AbstractString)::Tuple
  isfile(path) || return (nothing, nothing)
  df = CSV.read(path, DataFrame; stringtype=String)
  return (Float64.(df.price), Float64.(df.quantity))
end

function plot_max_metric_delta(deltas::AbstractDict)::Float64
  best = NaN
  for (k, v) in deltas
    startswith(String(k), "metric:") || continue
    v isa Real && isfinite(v) || continue
    best = isnan(best) ? Float64(v) : max(best, Float64(v))
  end
  return best
end


function plot_main(
  args::Vector{String}=ARGS;
  root::AbstractString=default_root()
)::Int
  opts = try
    parse_plot_args(args)
  catch e
    println(stderr, sprint(showerror, e))
    return plot_usage()
  end
  if opts.design === nothing
    println(stderr, "missing required --design")
    return plot_usage()
  end
  design = opts.design
  quiet = opts.quiet

  # 1. The figures are tied to the pinned design: abort (before solving)
  # when the design file is not preregistered with a matching SHA-256.
  ok, reason = preregistration_status(design; root=root)
  if !ok
    println(stderr, "refusing to plot: $reason")
    return 1
  end

  # 2. Design, file order, and the wanted subset (every --cells id must be
  # a cell of this design; the default substitutes uniform-sectoral BETA).
  design_d = load_design(design; root=root)
  order = cell_order(design; root=root)
  wanted = if opts.cells === nothing
    try
      plot_default_cell_ids(design_d, order, design)
    catch e
      println(stderr, "refusing to plot: $(sprint(showerror, e))")
      return 1
    end
  else
    for id in opts.cells
      if !(id in order)
        println(stderr, "unknown cell \"$id\" for design \"$design\"")
        return 1
      end
    end
    String.(opts.cells)
  end
  if isempty(wanted)
    println(stderr, "no matrix cells selected for design \"$design\"")
    return 1
  end
  wanted_set = Set(wanted)
  outdir = opts.outdir === nothing ? joinpath(root, "plots") : opts.outdir
  data_dir = opts.data_dir === nothing ? joinpath(root, "output") : opts.data_dir

  # 3. Reference continuation and programme incidence, exactly as
  # `run_design` in `run.jl` computes them. Typed conversion (see the note
  # in `build_reference`): broadcasting over an empty `drops = []` yields
  # `Vector{Any}` once OpenCGE is loaded, so `Vector{Int}(...)` is
  # inference-independent.
  quiet || println("building reference continuation for $design ...")
  ref = build_reference(design_d; root=root)
  drops = Vector{Int}(design_d["data"]["drops"])
  n_full = length(ref.data.factor_share) + length(drops)
  kept = sort(setdiff(1:n_full, drops))
  ψ, g = programme_vectors(design_d, ref.data, kept; root=root)

  # 4. Short sector labels from the design's own programme source.
  n = length(ref.data.factor_share)
  labels = plot_sector_labels(design_d, n; root=root)
  baseline = matrix_baseline(ref.data, ref.sol)

  # 5-6. Per cell, in file order: re-solve, re-evaluate the
  # gates, and hard-validate against the recorded artifacts. A
  # solve/gate/read failure is recorded as an invalid cell and never
  # aborts the batch.
  cells = MatrixCellData[]
  validation = Dict{String,String}()
  man_commits = Dict{String,Any}()
  report = Tuple{String,String,Dict{String,Float64},String,String,Int}[]
  for id in order
    id in wanted_set || continue
    status = "n/a"
    deltas = Dict{String,Float64}()
    verdict = "FAIL"
    reason = ""
    n_skipped = 0
    try
      quiet || println("re-solving $id ...")
      cell = design_cell(design_d, id)
      sol = solve_cell(cell, design_d, ref.data, ψ, g, ref.init_warm)
      ev = evaluate_gates(cell, design_d, sol.model, sol, ref.sol)
      ev.gates["overall"] == "pass" ||
        throw(ErrorException("re-solved gates report \"$(ev.gates["overall"])\""))
      mandir = joinpath(root, "runs", id)
      manpath = joinpath(mandir, "manifest.toml")
      isfile(manpath) ||
        throw(ErrorException("recorded manifest not found: runs/$id/manifest.toml"))
      manifest = TOML.parsefile(manpath)
      status = string(get(manifest, "status", "?"))
      man_commits[id] = string(
        get(
          get(
            manifest, "provenance",
            Dict{String,Any}()
          ), "git_commit", "unknown"
        )
      )
      stored_prices, stored_quantities =
        read_stored_solution(joinpath(mandir, "solution.csv"))
      vc = validate_cell(
        manifest, ev.metrics, sol.prices_raw,
        sol.quantities, stored_prices, stored_quantities
      )
      deltas = vc.deltas
      n_skipped = length(vc.skipped)
      if vc.pass
        push!(
          cells, matrix_cell_data(
            id, string(cell["labor"]),
            string(cell["financing"]), Float64(cell["eta"]),
            Float64(get(cell, "eta_s", 0.0)), status,
            ref.data, sol, ref.sol; metrics=ev.metrics,
            diagnostics=ev.diagnostics, labels=labels
          )
        )
        # Panels carry no error bars (2026-10-24): the σ-variant
        # re-solves were dropped on request, see the note in the
        # panel bullet of README.md.
        verdict = "ok"
      else
        reason = join(vc.failures, "; ")
      end
    catch e
      reason = sprint(showerror, e)
    end
    validation[id] = verdict == "ok" ?
                     (n_skipped > 0 ? "ok ($n_skipped metrics skipped)" : "ok") :
                     (isempty(reason) ? "failed" : reason)
    push!(report, (id, status, deltas, verdict, reason, n_skipped))
  end

  # 7. Assemble the dataset: the shared baseline, the valid cells, the
  # per-run validation map, and the provenance block.
  prov = Dict{String,Any}(
    "design" => design,
    "design_sha256" => design_sha256(design; root=root),
    "git_commit" => git_commit(root),
    "julia_version" => string(VERSION),
    "plotted_at" => iso_timestamp(),
    "preregistration" => "ok",
    "run_commits" => man_commits,
  )
  ds = matrix_dataset(
    design, baseline, cells; provenance=prov,
    validation=validation
  )

  # 8. Validation report: one line per selected cell (never silenced by
  # --quiet), with the deltas from `validate_cell`.
  println("validation report for $design:")
  println("run_id | status | max|Δp| | max|Δq| | max|Δmetric| | verdict | skipped")
  for (id, status, deltas, verdict, reason, n_skipped) in report
    dp = get(deltas, "price", NaN)
    dq = get(deltas, "quantity", NaN)
    dm = plot_max_metric_delta(deltas)
    tail = verdict == "ok" ? "ok" : "FAIL ($reason)"
    println(
      "$id | $status | $(@sprintf("%.3g", dp)) | " *
      "$(@sprintf("%.3g", dq)) | $(@sprintf("%.3g", dm)) | $tail | skipped=$n_skipped"
    )
  end

  # 9. Tidy data for ad-hoc exploration (valid cells only).
  mkpath(data_dir)
  sum_path = joinpath(data_dir, design * "_summary.csv")
  sec_path = joinpath(data_dir, design * "_sectoral.csv")
  CSV.write(sum_path, matrix_summary_frame(ds))
  CSV.write(sec_path, matrix_sectoral_frame(ds))
  println("wrote $sum_path")
  println("wrote $sec_path")

  # 10. Figures (skipped headless-safe with --no-figures, which never
  # loads GLMakie). --no-figures suppresses only the six standard
  # exploratory figures; --panel-dir below loads GLMakie on its own.
  if !opts.no_figures
    if !glmakie_available()
      println(
        stderr, "`OpenCGE.save_matrix_figures` requires " *
                "the GLMakie extension, which is not loaded. " *
                "Run `using GLMakie` together with `using OpenCGE` " *
                "(install it first with `import Pkg; Pkg.add(\"GLMakie\")` " *
                "if necessary)."
      )
      return 1
    end
    try
      @eval using GLMakie
    catch e
      println(stderr, "could not load GLMakie: $(sprint(showerror, e))")
      return 1
    end
    mkpath(outdir)
    # `invokelatest`: the extension method is born when `using GLMakie`
    # runs above — after `plot_main` was already compiled — so a plain
    # call would dispatch in the caller's (older) world age and hit the
    # headless stub. `invokelatest` dispatches in the latest world.
    written = try
      Base.invokelatest(
        save_matrix_figures, ds;
        outdir=outdir, prefix=design
      )
    catch e
      println(
        stderr,
        "save_matrix_figures failed: $(sprint(showerror, e))"
      )
      return 1
    end
    paths = written isa AbstractVector ? written :
            (written === nothing ? String[] : [written])
    for p in paths
      println("wrote $p")
    end
  end

  # 10b. Manuscript panel figures (one per matrix cell, each standalone).
  # Independent of --no-figures, which suppresses only the six standard
  # figures above; without --panel-dir GLMakie is never loaded.
  if opts.panel_dir !== nothing
    if !glmakie_available()
      println(
        stderr, "`OpenCGE.save_matrix_panels` requires " *
                "the GLMakie extension, which is not loaded. " *
                "Run `using GLMakie` together with `using OpenCGE` " *
                "(install it first with `import Pkg; Pkg.add(\"GLMakie\")` " *
                "if necessary)."
      )
      return 1
    end
    try
      @eval using GLMakie
    catch e
      println(stderr, "could not load GLMakie: $(sprint(showerror, e))")
      return 1
    end
    # `invokelatest`, as above: the extension method is born at
    # `using GLMakie` time. Qualified access avoids relying on the
    # extension's exports; `programme = g` is the per-sector additive
    # programme demand in model units from step 3; no variant cells are
    # passed, so the panels carry no error bars; `:manuscript` is
    # the print layout (no title, footnotes or run id; legends explain),
    # with the curated short sector names.
    written = try
      Base.invokelatest(
        OpenCGE.save_matrix_panels, ds;
        outdir=opts.panel_dir, prefix="panel_5x3", programme=g,
        style=:manuscript,
        sector_labels=plot_short_sector_labels(labels; root=root)
      )
    catch e
      println(
        stderr,
        "save_matrix_panels failed: $(sprint(showerror, e))"
      )
      return 1
    end
    paths = written isa AbstractVector ? written :
            (written === nothing ? String[] : [written])
    for p in paths
      println("wrote $p")
    end
  end

  # 10c. Vertical ranges over financing, grouped by labour (OpenCGE v0.5.0).
  if opts.comparison_out !== nothing
    if !glmakie_available()
      println(
        stderr, "`OpenCGE.save_closure_comparison` requires " *
                "the GLMakie extension, which is not loaded. " *
                "Run `using GLMakie` together with `using OpenCGE` " *
                "(install it first with `import Pkg; Pkg.add(\"GLMakie\")` " *
                "if necessary)."
      )
      return 1
    end
    try
      @eval using GLMakie
    catch e
      println(stderr, "could not load GLMakie: $(sprint(showerror, e))")
      return 1
    end
    short_all = plot_short_sector_labels(labels; root=root)
    closures = opts.comparison_closures === nothing ?
               [l for l in MANUSCRIPT_COMPARISON_CLOSURES if any(c -> c.labour == l, ds.cells)] :
               opts.comparison_closures
    written = try
      idx, slabels = resolve_comparison_sectors(ds, opts.comparison_sectors, short_all)
      requested = opts.comparison_sectors === nothing ?
                  DEFAULT_COMPARISON_SECTORS : collect(opts.comparison_sectors)
      slabels = [
        get(PLOT_SECTOR_LABELS, requested[i], slabels[i])
        for i in eachindex(slabels)
      ]
      Base.invokelatest(
        plot_save_comparison,
        opts.comparison_out, ds, idx, closures, slabels
      )
    catch e
      println(
        stderr,
        "save_closure_comparison failed: $(sprint(showerror, e))"
      )
      return 1
    end
    println("wrote $written")
  end

  # 10d. All-sector output/price comparison; point area is the baseline
  # Domar weight, shared across the explicitly selected closure pairs.
  if opts.scatter_out !== nothing
    if !glmakie_available()
      println(stderr, "`OpenCGE.plot_closure_scatter` requires GLMakie; load it alongside OpenCGE.")
      return 1
    end
    try
      @eval using GLMakie
      pairs = opts.scatter_pairs === nothing ?
              [
        (c.labour, c.financing) for c in ds.cells
        if c.labour in MANUSCRIPT_COMPARISON_CLOSURES
      ] : opts.scatter_pairs
      if opts.scatter_panel
        outputs = plot_scatter_outputs(opts.scatter_out, pairs, true)
        length(outputs) == 2 || throw(
          ArgumentError(
            "--scatter-panel requires exactly two financing groups"
          )
        )
        left, right = outputs
        titles = Tuple(
          "(" * string(Char('a' + i - 1)) * ") " *
          last(first(output.pairs)) * ": " *
          get(
            PLOT_SCATTER_FINANCING_TITLES, last(first(output.pairs)),
            plot_financing_label(last(first(output.pairs)))
          )
          for (i, output) in enumerate(outputs)
        )
        Base.invokelatest(
          plot_save_scatter_panel,
          opts.scatter_out, ds, left, right, g, titles
        )
        println("wrote $(opts.scatter_out)")
      else
        for output in plot_scatter_outputs(opts.scatter_out, pairs, opts.scatter_split)
          fig = Base.invokelatest(
            OpenCGE.plot_closure_scatter, ds, output.pairs;
            programme=g, closure_labels=plot_scatter_labels(output.pairs),
            size=(482, 340), fontsize=10, max_markersize=16
          )
          Base.invokelatest(plot_save_png, output.path, fig)
          println("wrote $(output.path)")
        end
      end
    catch e
      println(stderr, "plot_closure_scatter failed: $(sprint(showerror, e))")
      return 1
    end
  end

  # 11. Exit code: 0 only when every selected cell validated (figures were
  # written above, or --no-figures skipped them).
  n_ok = count(v -> startswith(v, "ok"), values(validation))
  n_tot = length(wanted)
  println("$n_ok/$n_tot cells validated")
  return n_ok == n_tot ? 0 : 1
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
  exit(plot_main())
end
