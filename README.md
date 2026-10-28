# Which Short Run? Whose Money?

Replication materials for *Which Short Run? Whose Money? Closure Choice in
Input–Output Models of the Socio-Ecological Transformation* (Jakob Kapeller
and Franz Scharnreitner). The paper compares labour-market and financing
closures of a production-network model (Baqaee–Farhi lineage) on a
71-sector German input–output table, with the housing transformation as the
application.

## Abstract

Input–output models are widely used to estimate the economic effects of green investment, industrial policy and other structural programs aiming to achieve a socio-ecological transformation. This practice often treats the model as a neutral analytical device, where it is not: every estimate presupposes a closure — an assumption about how factor markets clear and how expenditure is financed. Such closure assumptions carry substantial economic content and can have a strong impact on estimated effects. Using the decarbonization of the German residential housing stock as an example, we explore how typical closure choices on labor markets and financing affect estimates, with the largest differences concentrated in one interaction: a fixed wage and external finance. All estimates are produced within a single shared model core, available open-access, so that the differences we report reflect closure choice alone, making it easier for transformation research to consider a broader spectrum of input–output modeling approaches.

## This repository

This repository holds the manuscript, the experiment designs, the recorded
run manifests behind every number in the paper, and the scripts that turn
those manifests into the paper's tables.

## The model: OpenCGE

The model itself lives in the separate Julia package
[OpenCGE](https://github.com/theplatters/OpenCGE). The committed
`Manifest.toml` pins the exact release, so `Pkg.instantiate()` installs the
version used here. Every run manifest records the OpenCGE version it was
solved with in its `[provenance]` block.

## Quick start

[Julia](https://julialang.org/) ≥ 1.10 and Python ≥ 3.11 are required. From
the repository root:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'   # install dependencies, incl. the pinned OpenCGE
julia --project=. tests/runtests.jl                    # test suite
```

The manuscript builds with `latexmk -pdf` in `revision/` (entry
`revision/main.tex`).

## Input data

Two inputs are needed to run any design:

- `data/impulses.csv` — the investment-programme impulses (2024 row used);
  shipped with the repository.
- `data/I-O_DE2019_formatiert.csv` — the German 2019 input–output table,
  **not included** (Destatis licence). Obtain *Input-Output-Tabelle
  (Revision 2019) – Inländische Produktion (Herstellungspreise)* from
  Destatis GENESIS-Online, statistic 81511
  (<https://www-genesis.destatis.de/datenbank/online/statistic/81511/details>),
  export it as a `;`-separated CSV with `,` decimals (71 product rows,
  million EUR) and save it under that name in `data/`. The run manifests
  record its SHA-256
  (`e9c3299731940f7ce683f0e508495c62ad255f0a5536cf1da63c02478058914d`);
  the pricing-table pipeline refuses a file with a different hash.

Without the IO table the designs, the run harness and the table generators
cannot run; the committed run manifests and the generated tables in
`revision/tables/` remain readable without it.

## Designs and runs

Six designs in `experiments/designs/` produce every result in the paper:

| Design | Paper use |
| --- | --- |
| `matrix_5x3` | Results matrix: five labour closures (BF, ALPHA, BETA, GAMMA, DELTA) × three financing closures (F1–F3), plus the sectoral BETA cells |
| `pricing_capacity_rows` | Capacity pricing door on the BF, BETA and DELTA rows (+ ALPHA canary) |
| `pricing_capacity` | Capacity pricing door on the GAMMA row |
| `pricing_mobile` | Capacity pricing door on the mobile ALPHA row (robustness) |
| `pricing_markup` | Markup pricing door, rent retained |
| `pricing_profit` | Markup pricing door, rent distributed to households |

Each executed cell has a manifest at `runs/<run_id>/manifest.toml` (run ids
are `<design>-<labour>-<financing>[-<variant>]`); `runs/index.csv` lists
them all. `registry/scenarios.csv` holds one row per cell and
`registry/preregistration.toml` the SHA-256 each design was registered with;
the run harness refuses to execute a design whose file no longer matches.

List or re-solve cells with the single entry point:

```bash
julia --project=. experiments/run.jl --list matrix_5x3
julia --project=. experiments/run.jl --design matrix_5x3 --cell matrix_5x3-ALPHA-F2 --runs-dir /tmp/runs
```

Use `--runs-dir` to write fresh runs outside `runs/` (the harness refuses to
overwrite an existing run directory) and compare the new manifest's
`[metrics]` with the committed one. Running a design updates the status
columns of `registry/scenarios.csv`.

## Regenerating the tables

The tables in `revision/tables/` are generated from the run manifests; no
number is typed by hand.

```bash
julia --project=. experiments/make_pricing_prices.jl      # price sidecar for Tables 6, 7 and A8
julia --project=. experiments/make_table6_wd.jl           # W_D sidecars for Tables 6, 7 and A8
julia --project=. experiments/make_table7_wd.jl
julia --project=. experiments/make_tableE_wd.jl
python3 revision/tables/make_pricing_door.py             # Tables 6, 7 and A8
python3 revision/tables/make_table4_results.py           # Table 4 (results matrix)
julia --project=. experiments/make_table5_welfare.jl      # Table 5 (welfare comparison)
python3 revision/tables/make_io_summary.py               # IO summary table (appendix)
julia --project=. experiments/plot_matrix.jl --design matrix_5x3   # figures
```

`experiments/README.md` documents the design, manifest and index schemas.

## Repository layout

| Path | What it is |
| --- | --- |
| `revision/` | Manuscript sources (`main.tex`), sections, tables, figures and the response to the referees |
| `experiments/` | Run harness `run.jl`, the six designs, table and figure generators |
| `runs/` | One `manifest.toml` per executed cell, plus `index.csv` |
| `registry/` | `scenarios.csv` (one row per cell) and `preregistration.toml` (registered design hashes) |
| `data/` | Input data; only `impulses.csv` is tracked |
| `tests/` | Test suite (`tests/runtests.jl`) |
| `Project.toml`, `Manifest.toml` | Julia environment with the pinned OpenCGE release |

## Citation

See `CITATION.cff`. Please cite the paper and the OpenCGE software
separately.
