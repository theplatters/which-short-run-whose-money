# Flow tables — the supply arm `supply_etas_prog` (ADR-0023, 63 cells)

Generated from `runs/supply_etas_prog-*/manifest.toml` on the full-71 A-bill
calibration (G0 = 40,300 EUR m at 2019 prices, ADR-0024): no re-solve and no
hand-typed numbers. The programme-own-sector productivity shock (the economically relevant arm): the same sectors the demand shock presses on become cheaper to produce. The reference continuation is the
no-shock baseline (ADR-0023 decision 2). Identification matrix per ADR-0023:
ALPHA control + scalar single-wage BETA (2N+2, the scalar `ln L / ln w`
signature) + sectoral uniform BETA (3N+1) as the robustness row.

## Table 1 — Baseline and shock

| Quantity | Value | Source |
| --- | ---: | --- |
| Programme | 1.331 % of GDP | G0 / GDP_P = 40300 / 3027818 |
| Shock | A_i = 1 + alpha*psi_i on the programme's own sectors, alpha in {0.05, 0.10, 0.20} | `[shock]` per ADR-0023 |
| Reference | no-shock, no-programme continuation | `build_reference` (unchanged) |

## Table 2 — Identification: implied `eta_s` against input (scalar BETA, 2N+2)

`ln L / ln w` per cell; recovery is exact and invariant to the alpha ladder.

| Cell | alpha | Employment L | Wage w | Impl. `eta_s` | Real GDP rel. | max abs(p-1) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `supply_etas_prog-BETA-F1-e05-a05` | 0.05 | 1.001174 | 1.002350 | 0.5000 | +0.00407 | 0.0323 |
| `supply_etas_prog-BETA-F1-e05-a10` | 0.1 | 1.002303 | 1.004611 | 0.5000 | +0.00799 | 0.0625 |
| `supply_etas_prog-BETA-F1-e05-a20` | 0.2 | 1.004434 | 1.008888 | 0.5000 | +0.01546 | 0.1178 |
| `supply_etas_prog-BETA-F1-e1-a05` | 0.05 | 1.002350 | 1.002350 | 1.0000 | +0.00525 | 0.0323 |
| `supply_etas_prog-BETA-F1-e1-a10` | 0.1 | 1.004611 | 1.004611 | 1.0000 | +0.01031 | 0.0625 |
| `supply_etas_prog-BETA-F1-e1-a20` | 0.2 | 1.008888 | 1.008888 | 1.0000 | +0.01996 | 0.1178 |
| `supply_etas_prog-BETA-F1-e2-a05` | 0.05 | 1.004705 | 1.002350 | 2.0000 | +0.00761 | 0.0323 |
| `supply_etas_prog-BETA-F1-e2-a10` | 0.1 | 1.009243 | 1.004611 | 2.0000 | +0.01497 | 0.0625 |
| `supply_etas_prog-BETA-F1-e2-a20` | 0.2 | 1.017856 | 1.008888 | 2.0000 | +0.02903 | 0.1178 |
| `supply_etas_prog-BETA-F1-e5-a05` | 0.05 | 1.011805 | 1.002350 | 5.0000 | +0.01473 | 0.0323 |
| `supply_etas_prog-BETA-F1-e5-a10` | 0.1 | 1.023267 | 1.004611 | 5.0000 | +0.02908 | 0.0625 |
| `supply_etas_prog-BETA-F1-e5-a20` | 0.2 | 1.045239 | 1.008888 | 5.0000 | +0.05672 | 0.1178 |
| `supply_etas_prog-BETA-F2-e05-a05` | 0.05 | 1.001174 | 1.002350 | 0.5000 | +0.00406 | 0.0323 |
| `supply_etas_prog-BETA-F2-e05-a10` | 0.1 | 1.002303 | 1.004611 | 0.5000 | +0.00797 | 0.0625 |
| `supply_etas_prog-BETA-F2-e05-a20` | 0.2 | 1.004434 | 1.008888 | 0.5000 | +0.01538 | 0.1178 |
| `supply_etas_prog-BETA-F2-e1-a05` | 0.05 | 1.002350 | 1.002350 | 1.0000 | +0.00524 | 0.0323 |
| `supply_etas_prog-BETA-F2-e1-a10` | 0.1 | 1.004611 | 1.004611 | 1.0000 | +0.01029 | 0.0625 |
| `supply_etas_prog-BETA-F2-e1-a20` | 0.2 | 1.008888 | 1.008888 | 1.0000 | +0.01988 | 0.1178 |
| `supply_etas_prog-BETA-F2-e2-a05` | 0.05 | 1.004705 | 1.002350 | 2.0000 | +0.00760 | 0.0323 |
| `supply_etas_prog-BETA-F2-e2-a10` | 0.1 | 1.009243 | 1.004611 | 2.0000 | +0.01495 | 0.0625 |
| `supply_etas_prog-BETA-F2-e2-a20` | 0.2 | 1.017856 | 1.008888 | 2.0000 | +0.02895 | 0.1178 |
| `supply_etas_prog-BETA-F2-e5-a05` | 0.05 | 1.011805 | 1.002350 | 5.0000 | +0.01472 | 0.0323 |
| `supply_etas_prog-BETA-F2-e5-a10` | 0.1 | 1.023267 | 1.004611 | 5.0000 | +0.02905 | 0.0625 |
| `supply_etas_prog-BETA-F2-e5-a20` | 0.2 | 1.045239 | 1.008888 | 5.0000 | +0.05662 | 0.1178 |
| `supply_etas_prog-BETA-F3-e05-a05` | 0.05 | 1.001174 | 1.002350 | 0.5000 | +0.00406 | 0.0323 |
| `supply_etas_prog-BETA-F3-e05-a10` | 0.1 | 1.002303 | 1.004611 | 0.5000 | +0.00797 | 0.0625 |
| `supply_etas_prog-BETA-F3-e05-a20` | 0.2 | 1.004434 | 1.008888 | 0.5000 | +0.01538 | 0.1178 |
| `supply_etas_prog-BETA-F3-e1-a05` | 0.05 | 1.002350 | 1.002350 | 1.0000 | +0.00524 | 0.0323 |
| `supply_etas_prog-BETA-F3-e1-a10` | 0.1 | 1.004611 | 1.004611 | 1.0000 | +0.01029 | 0.0625 |
| `supply_etas_prog-BETA-F3-e1-a20` | 0.2 | 1.008888 | 1.008888 | 1.0000 | +0.01988 | 0.1178 |
| `supply_etas_prog-BETA-F3-e2-a05` | 0.05 | 1.004705 | 1.002350 | 2.0000 | +0.00760 | 0.0323 |
| `supply_etas_prog-BETA-F3-e2-a10` | 0.1 | 1.009243 | 1.004611 | 2.0000 | +0.01495 | 0.0625 |
| `supply_etas_prog-BETA-F3-e2-a20` | 0.2 | 1.017856 | 1.008888 | 2.0000 | +0.02895 | 0.1178 |
| `supply_etas_prog-BETA-F3-e5-a05` | 0.05 | 1.011805 | 1.002350 | 5.0000 | +0.01472 | 0.0323 |
| `supply_etas_prog-BETA-F3-e5-a10` | 0.1 | 1.023267 | 1.004611 | 5.0000 | +0.02905 | 0.0625 |
| `supply_etas_prog-BETA-F3-e5-a20` | 0.2 | 1.045239 | 1.008888 | 5.0000 | +0.05662 | 0.1178 |

## Table 3 — The control and the robustness row (F2; F3 identical by financing neutrality)

| Cell | alpha | Employment L | Wage | Real GDP rel. | max abs(p-1) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `supply_etas_prog-ALPHA-F2-a05` | 0.05 | 1.000000 | 1.002350 | +0.00289 | 0.0323 |
| `supply_etas_prog-ALPHA-F2-a10` | 0.1 | 1.000000 | 1.004611 | +0.00566 | 0.0625 |
| `supply_etas_prog-ALPHA-F2-a20` | 0.2 | 1.000000 | 1.008888 | +0.01090 | 0.1178 |
| `supply_etas_prog-BETA-F2-sec-e05-a05` | 0.05 | 1.001942 | 1.004131 | +0.00483 | 0.1002 |
| `supply_etas_prog-BETA-F2-sec-e05-a10` | 0.1 | 1.002595 | 1.005346 | +0.00824 | 0.0947 |
| `supply_etas_prog-BETA-F2-sec-e05-a20` | 0.2 | 1.003812 | 1.007718 | +0.01468 | 0.1176 |
| `supply_etas_prog-BETA-F2-sec-e2-a05` | 0.05 | 1.005286 | 1.002705 | +0.00818 | 0.0332 |
| `supply_etas_prog-BETA-F2-sec-e2-a10` | 0.1 | 1.008540 | 1.004302 | +0.01422 | 0.0545 |
| `supply_etas_prog-BETA-F2-sec-e2-a20` | 0.2 | 1.014720 | 1.007370 | +0.02572 | 0.1190 |

## Notes

- **Identification exact and alpha-invariant** (spread < 1e-3 across the ladder);
  ALPHA pins L = 1 with w > 1; real GDP monotone in eta_s per column; F2 = F3
  financing neutrality holds under the supply shock; the ADR-0019 canary is asserted on
  all 63 cells at A != 1.
- The **programme-own-sector shock** concentrates the productivity gain on the seven

## Status

63/63 `executed`, all gates pass. Design commits 202837a/5b834cb; batch commit below.
