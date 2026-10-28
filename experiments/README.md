# `experiments/` — the single experiment entry point

All runs go through `run.jl`. Status of scenarios lives in
`registry/scenarios.csv`; tables and text cite `run_id`s.

## Workflow: register before running

```bash
julia --project=. experiments/run.jl --list matrix_5x3
julia --project=. experiments/run.jl --preregister matrix_5x3 [--actor NAME]
# commit registry/preregistration.toml first; only then:
julia --project=. experiments/run.jl --design matrix_5x3 [--cell <run_id>] [--cells a,b,c] [--runs-dir DIR] [--budget-seconds N] [--actor NAME]
```

`--design` refuses to start — before creating any run dir — when
`experiments/designs/<design>.toml` is not preregistered with a matching
SHA-256 in `registry/preregistration.toml`. Re-running `--preregister`
after a design edit re-pins the record (the old row is overwritten; the
superseded design stays visible in git history).

## Reference continuation

Each batch computes the design's reference continuation once and reuses its
final solution as the warm start for all mobile cells and as the
`consumption` reference (the GDP reference is 1 by construction). The continuation runs `read_data` →
`retained_dataset` → bisect `exo_scale` for the smallest scale with
`saving_rate ≥ 0` → `exo_scale` steps × the θ ladder with
`mobile_labor_model(data, shocks, θ, 0.5, 0.9, η)` (`NoFinancing`; the
design's reference η ∈ {0,1}), warm-starting each solve (first init from
the linear fixed point `y0 = (I − Gk) \\ b`, with `F = 0` appended for the
canonical 2N+2 mobile vector `[p; y; w; F]`), stopping a ladder early when
`max|p−1| > 10`. `[reference] theta` must equal the final ladder value.
Cells then warm-start from `[p; y; w; F]`. At mobile η = 1 solutions the
reference asserts the external account: all N goods markets clear
and the identity gap `S + T + M − (I+X) − (F + B_gov)` is ≈ 0. (On singular
toy fixtures, where `(I − Gk)` is not invertible, the first init falls
back to `[ones(N); λ; 1.0; 0.0]`; real calibrations always take the
linear-fixed-point branch.)

## Cell construction

Shocks are always `Shocks(ones(N), ones(N), zeros(N))`. `ψ` is the
renormalized 2024 impulse share over kept sectors
(`[programme] source/year/column_slice`), `g = (total_eur_m / GDP) .* ψ`:

| Labour | Constructor |
| --- | --- |
| BF / ALPHA | `mobile_labor_model(data, shocks, θ, ϵ, σ, η)` (BF η = 0; ALPHA η = 1; intermediates rejected) |
| BETA | `solve_beta(data, shocks, θ, ϵ, σ, η; eta_s, financing, init)` |
| GAMMA | `mobile_labor_model(...; closure = :fixed, financing)` |
| DELTA | `delta_model(data, shocks; ε = delta_epsilon, financing)` |

| Financing | Constructor |
| --- | --- |
| F1 | `PreferenceReallocation(d)` with `d = 1 .+ G0 .* ψ1 ./ c0` (`f1_shift = "tilt_g0_over_c0"`; `ψ1` = `ψ` restricted to sectors with positive baseline household demand `c0 = data.household_baseline` and renormalised to sum 1, `G0 = sum(g)`) |
| F2 | `TaxFinanced(g)` |
| F3 | `ExternalDebt(g)` |

**Price basis.** `total_eur_m` is a 2019-price figure — the paper's 40.3 bn
(`paper/main.tex` footnote: deflator 1.46, construction-cost indices,
Hornykewycz 2025; ~58 bn in 2023 prices). The raw impulse table is in
current (2023) prices: its horizon mean is 58,893 EUR m, and
58,893 / 1.46 = 40,338 EUR m ≈ `total_eur_m`. The legacy deflation
apparatus is still in the kernel — `const inflator = 1.46`
(`src/OpenCGE.jl`) and `impulse_shock` (`src/core/diagnostics.jl`,
exercised by `tests/test_model.jl`) — but the harness does not call it: the
deflation is implicit in `total_eur_m`, and the incidence `ψ` is the raw
current-price 2024 composition (undeflated). G0 = the deflated horizon mean, 40.3 bn, is the principal
programme.

DELTA cells pin `theta = epsilon = sigma = delta_epsilon = 1e-4` (the
actually solved values). `matrix_5x3-DELTA-F1` is expected to fail the
scale-indeterminacy guard: F1 has no additive anchor and the fixed-wage
η = 1 system is homogeneous (kept visible, never dropped).

Smoke designs (`smoke = true`) pin `[programme] explicit = [...]` instead
of the impulses file and are used only by tests, which pass the `Data`
object directly to `build_reference(...; data = ...)` (then a single θ
ladder runs on that data: no read/retain/bisect/`exo_scale` loop).

## Design file schema (`experiments/designs/<design>.toml`)

`schema_version = 1`, `design`, `description`, `smoke`,
`[data]` (`vintage`, `drops`; `calibration_root`/`calibration_artifacts`
are provenance-only — `recalibrate_open` reads `data.io`),
`[programme]` (`source`, `year`, `column_slice` 1-based inclusive,
`total_eur_m`, `f1_shift`; or `explicit` for smoke designs),
`[reference]` (`labor`, `eta`, `theta`, `epsilon`, `sigma`,
`exo_scale_steps`, `thetas`), `[gates]` (`residual_tol`, `budget_tol`,
`labour_tol`, `wage_tol`), `[cells.<run_id>]` (`labor`, `financing`,
`eta`, `eta_s`, `theta`, `epsilon`, `sigma`, `delta_epsilon` for DELTA,
`note`).

**Pricing doors.** An optional `[pricing]` block sets
the design-wide door defaults — `kind = "none" | "capacity" | "markup"`,
`delta` (capacity, closure `P1`), `kappa` and `s_pi` (markup, closure `P2`;
`s_pi = 1` retains the rent, Stage A) — plus `multistart_tol` (the
uniqueness gate, default `1e-6`) and `continuation_steps` (default 4). A cell
overrides `kind`, `delta`, `kappa` or `s_pi` with the same keys
(`cell_pricing` in `run.jl`). Absent or `kind = "none"`, the harness and the
manifests are byte-identical to the pre-pricing ones. Since OpenCGE v0.2.1
the capacity `delta` is the value-added (Verdoorn) elasticity; the
kernel scales the exponent by `factor_share`. A capacity cell (or the block)
may set `delta_services`: the sectors in `[pricing] services` (1-based
indices, with `[pricing] n_sectors`) then carry `delta_services` and all
others `delta`, a per-sector `CapacityPricing` vector; the manifest adds
`delta_services` and `services`. A priced cell is solved
by continuation: the NoPricing twin from the reference warm start, then the
door opened in `continuation_steps` equal steps of its parameter. Doors are
wired into BF, ALPHA, sectoral BETA and GAMMA (`mobile_labor_model`); scalar
BETA (`solve_beta`) and DELTA reject them. Priced manifests add, to
`[scenario]`: `pricing` (`P1`/`P2`), `pricing_kind`, `delta` or
`kappa`/`s_pi`; to `[gates]`: `uniqueness` (the `pricing_admissibility`
multi-start spread, passing with at least two converged starts within
`multistart_tol` and a full-rank residual Jacobian); to `[metrics]`:
`price_dev_mean` (baseline-gross-output-weighted mean of `p − 1`),
`price_dev_min`, `price_dev_max`, `factor_income` (`w·ΣL + Π`), `profit`,
`retained_profit`, `profit_share`, `real_income` (`real_income_index`
against the reference) and, for markup cells, `markup_min` / `markup_max`; to
`[diagnostics]`: `canary_retained_profit`, `multistart_converged`,
`multistart_starts`, `jacobian_rank`, `jacobian_n`, `jacobian_cond`. The
budget gate's `E` includes the distributed rent `(1 − s_pi)·Π`.

## Manifest schema (`runs/<run_id>/manifest.toml`)

### Pricing-table reporting

Raw price metrics retain the solver's units in the immutable manifests.
Tables 6, 7 and E print the average real consumption wage (`metrics.wage`
over the sidecar CPI) and the CPI-relative dispersion on every labour row;
the consumption-unit sidecar supplies the CPI.
Regenerate:

```bash
julia --project=. experiments/make_pricing_prices.jl
python3 revision/tables/make_pricing_door.py
```

`make_pricing_prices.jl` reads saved pricing solutions and writes the
derived, run-id-keyed `revision/tables/pricing_prices.csv`. It reconstructs
the reference continuation and verifies raw-price agreement, data and
cell parameters, GDP-deflator homogeneity and real-GDP invariance on the
GAMMA/DELTA rows; no priced cell is re-solved. `--check` verifies that
the sidecar is current. The Python table builder checks source hashes and
rejects stale derived prices. A clean clone can use the committed sidecar
without machine-local solutions. The existing `table6_wd.csv` and
`table7_wd.csv` supply the unchanged quantity-of-demand welfare columns.

### Run records

Written `running` at cell start, `executed` (all gates pass) or `failed`
otherwise at the end. An existing run dir is never overwritten (register a
`-v2` variant). Any per-cell failure — solve, gates, metrics, or writes —
is caught and recorded (`[error]` with type/message; `[gates] overall =
"fail"` without per-gate values); the batch continues (an infrastructure
failure outside the cell's own manifest is reported as `error` for that
cell). `TOML.print` may render some tables non-inline; the
parsed structure is the contract.

- Top level: `schema_version` (= 2), `run_id`, `design`, `cell`, `status`,
  `date` (ISO), `actor`.
- `[provenance]`: `git_commit`, `git_dirty`, `julia_version`,
  `manifest_sha256` (of `Manifest.toml`, or `"absent"`), `design_sha256`,
  `data_sha256` (table of repo-relative path → SHA-256 for the design
  file, the IO table, the calibration artifact, and the programme source;
  `"absent"` for a missing file), `seed = 1234`.
- `[scenario]`: `labour`, `financing`, `eta`, `eta_s`, `theta`, `epsilon`,
  `sigma` (`delta_epsilon` additionally for DELTA), `shock =
  "impulses.csv"`, `magnitude = 1.0`.
- `[solver]`: `init = "warm:reference-final"`, `reference =
  "batch-continuation"`, `algorithm` (kernel `solve`/`solve_beta`).
- `[gates]`: per gate (`residual`, `budget`, `labour` for mobile /
  `wage` for fixed+DELTA) a table with `value`, `tolerance`, `pass`;
  `overall = "pass" | "fail"`. Gate definitions: `residual` =
  `maximum(abs, equilibrium_residuals(model, X)) < residual_tol` with
  `X = [p; q]` (fixed) or `[p; q; w; F]` (mobile, `F =
  sol.external_transfer`); `budget` = `|Σ p·c −
  (1−s)E| < budget_tol` with `E = household_expenditure(fin, model, w*L,
  p, L; external_transfer = sol.external_transfer)`; `labour` = the kernel `labor_market_residual` at `(L_sum, w)`
  below `labour_tol`; `wage` = `max|w_raw−1| < wage_tol` on the raw pinned
  wage (the CPI-normalized wage must not enter the gate). The acceptance
  gate is all-N clearing plus the external-account identity gap at η = 1
  (`assert_external_account` in `run.jl`: `maximum(abs,
  market_clearing_residuals(model, X)) < 1e-6` for every closure, and
  `abs(external_balance_canary(model, X).diff) < 1e-9` at η = 1; at the
  η = 0 endpoint the gap is the reported factor-market gap, not gated).
- `[metrics]`: `gdp`, `gdp_rel`, `gdp_expenditure`, `gdp_expenditure_rel`,
  `gdp_deflator`, `gdp_wedge`, `consumption`, `consumption_rel`, `employment`,
  `wage`, `nominal_gdp`, `max_abs_price_dev`, `external_transfer`,
  `programme_financing`, `external_position` (`= F + B_gov`, the booked net
  external position; schema v2). `gdp` is the
  income-side real GDP index against the batch reference, `consumption` the
  household-consumption (welfare) index; old v1 manifests (with `real_gdp*`)
  stay as immutable history.
- `[diagnostics]` (never gates): `canary_s`, `canary_ixm`, `canary_diff`
  (the external-account identity gap `S + T + M − (I+X) − (F +
  B_gov)`), `gdp_c`, `gdp_g`, `gdp_i`, `gdp_x`, `gdp_m_final`,
  `gdp_m_int`, `gdp_t_int`, `external_balance`, `public_budget`.
- `[artifacts]`: `log = "log.txt"`, `solution = "solution.csv" | ""`.

## Index (`runs/index.csv`)

Header exactly
`run_id,date,design,closures,status,gate_summary,headline_metrics,commit`;
one row per run dir with a manifest, sorted by `run_id`, rewritten on
every status transition. `closures = "<L>+<F>"`; `gate_summary` like
`resid 1.20e-07<=1e-06 ok; budget 3e-12<=1e-09 ok`; `headline_metrics`
like `gdp_rel=...; cons_rel=...; L=...; w=...`.

Only `runs/index.csv` and `runs/*/manifest.toml` are tracked (see
`.gitignore`); verify with `git check-ignore`.

## Plotting the matrix

`experiments/plot_matrix.jl` generates the comparative figures for an
executed matrix generation. It re-solves each selected cell with the
harness and hard-validates it against the recorded run artifacts; figures
(and the tidy CSVs) cover only the cells that validate. No run dirs are
created and no registry/run files are modified.

```bash
julia --project=. experiments/plot_matrix.jl --design matrix_5x3 [--cells id1,id2] [--outdir DIR] [--data-dir DIR] [--panel-dir DIR] [--comparison-out FILE] [--comparison-sectors s1,s2,s3] [--comparison-closures c1,c2] [--no-figures] [--quiet]
```

- `--design` (required) must be preregistered with a matching SHA-256;
  otherwise the driver aborts before solving. `--cells` selects a subset
  (comma-separated run ids, each validated against the design); the default
  is the fifteen headline labour × financing cells, with the three BETA
  benchmarks replaced by the uniform-sectoral `-etas05` cells
  (`eta_s = 0.5`, separate sectoral wages). The driver verifies these
  settings in the pinned design rather than trusting the suffix alone.
  Historical designs lacking these cells require explicit `--cells` ids;
  scalar BETA and other sectoral variants remain available that way.
- Validation contract: per cell, `solve_cell` + `evaluate_gates` are
  re-run from the batch reference continuation (programme `ψ, g` exactly as
  `run_design` computes them); the cell is valid only if the recorded
  manifest status is `executed`, the re-solved gates pass, and
  `validate_cell` (manifest metrics plus the stored `solution.csv`
  prices/quantities) passes. A solve/gate/read failure is recorded as an
  invalid cell and never aborts the batch. The driver prints a
  one-line-per-cell validation report
  (`run_id | status | max|Δp| | max|Δq| | max|Δmetric| | ok/FAIL`) and a
  final `N/M cells validated` line; the exit code is 0 only when every
  selected cell validated (and figures were written or `--no-figures` was
  passed). `--quiet` suppresses the per-cell progress chatter but not the
  validation report.
- Figures need GLMakie: install it with
  `import Pkg; Pkg.add("GLMakie")`, then `using GLMakie` alongside
  `using OpenCGE` (headless rendering works). `--no-figures` runs the
  validation + data export only and never loads GLMakie (headless mode);
  without GLMakie on the figure path the driver prints the install
  instruction and exits 1.
- Outputs: `<data-dir>/<design>_summary.csv` (one row per validated cell,
  via `matrix_summary_frame`) and `<data-dir>/<design>_sectoral.csv`
  (tidy long frame, via `matrix_sectoral_frame`); defaults are
  `--data-dir <root>/output` and `--outdir <root>/plots` (both gitignored
  areas). With figures, `save_matrix_figures(ds; outdir, prefix = design)`
  writes the panels and the driver prints each path.
- `--panel-dir DIR` writes the manuscript panel figures: one
  `panel_5x3_<labour>_<financing>.png` per matrix cell (fifteen files:
  `BF/ALPHA/BETA/GAMMA/DELTA` x `F1/F2/F3`)
  via `save_matrix_panels(ds; outdir = DIR, prefix = "panel_5x3", programme = g, variants = variants, style = :manuscript, sector_labels = …)`
  (OpenCGE ≥ `v0.3.2`), the print layout for about 14 cm width. The
  curated short sector names come from `data/sector_short_names.csv`
  (`label,short`, keyed by the dotted labels of `data/sector_names.txt`);
  when the file is missing or does not cover every sector the driver warns
  and the kernel falls back to its cleaned, truncated names.
  Each file pairs grouped bars over the programme sectors for that cell
  (programme demand in % of baseline gross output, change in output, change
  in consumption, price deviation from the numeraire) with a
  quantity bar chart over all sectors sorted descending only when every
  price is at baseline (within `1e-8`), or the quantity/price scatter
  otherwise. Thus BF and the headline sectoral BETA retain their price
  response; single-wage demand-only cells use quantity bars.
  `right = :auto` checks actual prices, not the labour-closure label;
  `right = :bars` / `:scatter` force either path in the plotting API.
  Each file is standalone with
  per-cell axis limits; it carries no title, footnotes or `run_id` (the
  legend states the four series and the sector grouping, and the driver's
  validation report ties each file to its `run_id`).
  The panels carry NO error bars: the σ-variant re-solves
  (σ ∈ {0.6, 0.99}, two extra solves per cell) were dropped on 2026-10-24 to
  keep the plate simple — the manuscript reports one elasticity, σ = 0.9
  (Section 4), and an unexplained band asks a question the text does not
  answer. `save_matrix_panels(variants = ...)` still accepts variant cells
  should a band ever be wanted back; the driver no longer computes them.
  **Regenerating the panels needs no `runs/*/solution.csv`** (it is
  gitignored): `read_stored_solution` returns `nothing` when the file is
  absent and `validate_cell` then skips the vector check while still
  comparing all fifteen manifest metrics at `rtol = atol = 1e-8`. What a
  fresh checkout does need is `data/` — the Destatis table
  `I-O_DE2019_formatiert.csv` and, for the manuscript's sector names,
  `sector_short_names.csv`; without the latter the kernel falls back to its
  cleaned names and the plate's labels change.
  Quantity bars label the three largest
  programme and three largest other movers by absolute quantity change;
  both right-panel paths retain the orange/blue sector grouping and legend.
  Forced degenerate scatter ranges retain a minimum span with an annotation
  instead of repeated "0.00%" ticks.
  `--panel-dir` loads GLMakie on its own and combines with `--no-figures`
  (which suppresses only the six standard exploratory figures).
- `--comparison-out FILE` writes a publication closure-comparison figure
  (`OpenCGE.save_closure_comparison`, OpenCGE tag `v0.5.0`): vertical output, sectoral household-consumption
  (`Delta c`), and price ranges, grouped by labour closure; each range spans
  financing outcomes, marked by financing-specific line styles in the
  variable's color. OpenCGE `v0.6.1` places the variable and financing
  legends below the plot and a title above it. The financing
  legend uses `F1`, `F2` and `F3`; the plot has no financing annotations.
  `--comparison-sectors` selects
  sectors by 1-based index, dotted label, or curated short name (default:
  `Electrical equipment`, `Metal ores & mining`, `Other personal services`);
  `--comparison-closures` selects labour ids or exact `run_id`s (default:
  BF, BETA and DELTA, shown as No-reallocation, Elastic labor supply and
  Leontief closure).
- `--scatter-out FILE` writes the all-sector output/price scatter
  (`OpenCGE.plot_closure_scatter`, OpenCGE tag `v0.5.0`). `--scatter-pairs BF/F1,BETA/F2`
  selects explicit labour/financing pairs (default: the validated BF, BETA
  and DELTA cells). `--scatter-split` writes one image per selected financing
  closure, adding `_F1`, `_F2` or `_F3` before the extension. Legends use the
  manuscript descriptions instead of registry ids.
  `--scatter-panel` combines exactly two financing groups in one figure
  using `OpenCGE.plot_closure_scatter_panel`; it requires `--scatter-out`
  and cannot be combined with `--scatter-split`. Closure colors are shared
  across panels. OpenCGE `v0.6.1` uses one six-entry legend below the panels,
  showing each labour closure in its dark programme-sector shade and light
  other-sector shade. Point area is proportional to the pre-programme Domar weight.
  Standalone comparison outputs are 17 cm wide with 10-point text; the
  two-scatter panel uses a 964 by 500 layout with 16-point text. All use
  600-dpi PNGs and combine with `--no-figures` to suppress exploratory figures.

The Section 5.2 comparisons are regenerated together with:

```bash
julia --project=. experiments/plot_matrix.jl --design matrix_5x3 --no-figures \
  --comparison-out revision/images/closure_comparison.png \
  --comparison-closures BF,BETA,DELTA \
  --scatter-out revision/images/closure_scatter_panel.png --scatter-panel \
  --scatter-pairs BF/F1,BETA/F1,DELTA/F1,BF/F3,BETA/F3,DELTA/F3
```

The range plot covers BF, BETA and DELTA under all three financing closures.
The combined `closure_scatter_panel.png` uses
`OpenCGE.plot_closure_scatter_panel` to show those same labour closures
side by side under (a) repurposing of consumption (F1) and (b) external
financing (F3). The panels share the six-entry legend and retain independent
axis limits. Labels follow Table 4: No-reallocation, Elastic labor
supply and Leontief closure. Range labels are angled to keep the descriptions
legible at print width. GAMMA and DELTA coincide on this demand-only branch;
the selected employment-adjustment corner is represented by DELTA throughout.
Sources are `matrix_5x3-<LABOUR>-<FINANCING>`, replacing BETA by
`matrix_5x3-BETA-<FINANCING>-etas05` throughout.
Appendix D's detailed panels and the exploratory figures also use
`matrix_5x3`.
The environment pins the published OpenCGE `v1.0.0` release.
The refreshed release plots prices as `(p_i / CPI) / (p_i0 / CPI0)` on every
labour row; the price axes and legends identify these consumption units.
The source runs retain their recorded numerical generations.
Regenerate all matrix plots together by removing `--no-figures` from the
command above and adding `--panel-dir revision/images`. GLMakie can be
loaded from a separate environment through `JULIA_LOAD_PATH`, keeping the
committed dependency pin unchanged.

## Preregistration (`registry/preregistration.toml`)

`schema_version = 1`; `[designs.<design>]`: `design_sha256`,
`registered_at`, `git_commit`, `actor`, `pinned` (the key scalar
parameters, informational), `note`. Written only by
`experiments/run.jl --preregister`.

## Table generation

Source manifests for Tables 4–7 and Appendix E record OpenCGE tag `v0.5.0`
(package metadata `0.4.1`); the `pricing_profit` runs record the numerically
identical `v0.5.4`. The generators load the committed kernel pin. Designs:
`matrix_5x3`, `pricing_capacity_rows`, `pricing_capacity`, `pricing_mobile`,
`pricing_markup`, `pricing_profit`; run evidence is in
`registry/scenarios.csv`. Regenerate with `experiments/make_pricing_prices.jl`,
`experiments/make_table6_wd.jl`, `experiments/make_table7_wd.jl`,
`experiments/make_tableE_wd.jl`, `experiments/make_table5_welfare.jl` (all
with `julia --project=.`), then `python3 revision/tables/make_table4_results.py`
and `python3 revision/tables/make_pricing_door.py`. GAMMA/DELTA pin the
nominal wage; the tables print the average real consumption wage.

Table 5 checks source run identities, design and input hashes, a common source
kernel tree, all recorded metrics and the current design gates. Release names
and package-version labels in the source manifests are not acceptance
conditions. The original run provenance is retained; regenerating
the table verifies the selected runs with the current kernel.

The run CLI defaults to one BLAS thread for the small sector systems; set
`BEYONDHULTEN_BLAS_THREADS` to override it. New manifests record this resource
setting in `[solver] blas_threads`; solver algorithms and gates are unchanged.
