# Flow tables — the supply arm `supply_etas_unif` (ADR-0023, 63 cells)

Generated from `runs/supply_etas_unif-*/manifest.toml` on the full-71 A-bill
calibration (G0 = 40,300 EUR m at 2019 prices, ADR-0024): no re-solve and no
hand-typed numbers. A uniform productivity shock in all industries. The reference continuation is the
no-shock baseline (ADR-0023 decision 2). Identification matrix per ADR-0023:
ALPHA control + scalar single-wage BETA (2N+2, the scalar `ln L / ln w`
signature) + sectoral uniform BETA (3N+1) as the robustness row.

## Table 1 — Baseline and shock

| Quantity | Value | Source |
| --- | ---: | --- |
| Programme | 1.331 % of GDP | G0 / GDP_P = 40300 / 3027818 |
| Shock | A_i in {1.01, 1.02, 1.03} in every sector | `[shock]` per ADR-0023 |
| Reference | no-shock, no-programme continuation | `build_reference` (unchanged) |

## Table 2 — Identification: implied `eta_s` against input (scalar BETA, 2N+2)

`ln L / ln w` per cell; recovery is exact and invariant to the A ladder.

| Cell | A | Employment L | Wage w | Impl. `eta_s` | Real GDP rel. | max abs(p-1) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `supply_etas_unif-BETA-F1-e05-m101` | 1.01 | 1.010112 | 1.020327 | 0.5000 | +0.02998 | 0.0228 |
| `supply_etas_unif-BETA-F1-e05-m102` | 1.02 | 1.020172 | 1.040751 | 0.5000 | +0.06036 | 0.0446 |
| `supply_etas_unif-BETA-F1-e05-m103` | 1.03 | 1.030180 | 1.061271 | 0.5000 | +0.09115 | 0.0655 |
| `supply_etas_unif-BETA-F1-e1-m101` | 1.01 | 1.020327 | 1.020327 | 1.0000 | +0.04039 | 0.0228 |
| `supply_etas_unif-BETA-F1-e1-m102` | 1.02 | 1.040751 | 1.040751 | 1.0000 | +0.08173 | 0.0446 |
| `supply_etas_unif-BETA-F1-e1-m103` | 1.03 | 1.061271 | 1.061271 | 1.0000 | +0.12405 | 0.0655 |
| `supply_etas_unif-BETA-F1-e2-m101` | 1.01 | 1.041067 | 1.020327 | 2.0000 | +0.06153 | 0.0228 |
| `supply_etas_unif-BETA-F1-e2-m102` | 1.02 | 1.083163 | 1.040751 | 2.0000 | +0.12579 | 0.0446 |
| `supply_etas_unif-BETA-F1-e2-m103` | 1.03 | 1.126297 | 1.061271 | 2.0000 | +0.19285 | 0.0655 |
| `supply_etas_unif-BETA-F1-e5-m101` | 1.01 | 1.105851 | 1.020327 | 5.0000 | +0.12756 | 0.0228 |
| `supply_etas_unif-BETA-F1-e5-m102` | 1.02 | 1.221053 | 1.040751 | 5.0000 | +0.26901 | 0.0446 |
| `supply_etas_unif-BETA-F1-e5-m103` | 1.03 | 1.346270 | 1.061271 | 5.0000 | +0.42561 | 0.0655 |
| `supply_etas_unif-BETA-F2-e05-m101` | 1.01 | 1.010112 | 1.020327 | 0.5000 | +0.03000 | 0.0228 |
| `supply_etas_unif-BETA-F2-e05-m102` | 1.02 | 1.020172 | 1.040751 | 0.5000 | +0.06040 | 0.0446 |
| `supply_etas_unif-BETA-F2-e05-m103` | 1.03 | 1.030180 | 1.061271 | 0.5000 | +0.09121 | 0.0655 |
| `supply_etas_unif-BETA-F2-e1-m101` | 1.01 | 1.020327 | 1.020327 | 1.0000 | +0.04041 | 0.0228 |
| `supply_etas_unif-BETA-F2-e1-m102` | 1.02 | 1.040751 | 1.040751 | 1.0000 | +0.08178 | 0.0446 |
| `supply_etas_unif-BETA-F2-e1-m103` | 1.03 | 1.061271 | 1.061271 | 1.0000 | +0.12411 | 0.0655 |
| `supply_etas_unif-BETA-F2-e2-m101` | 1.01 | 1.041067 | 1.020327 | 2.0000 | +0.06155 | 0.0228 |
| `supply_etas_unif-BETA-F2-e2-m102` | 1.02 | 1.083163 | 1.040751 | 2.0000 | +0.12583 | 0.0446 |
| `supply_etas_unif-BETA-F2-e2-m103` | 1.03 | 1.126297 | 1.061271 | 2.0000 | +0.19292 | 0.0655 |
| `supply_etas_unif-BETA-F2-e5-m101` | 1.01 | 1.105851 | 1.020327 | 5.0000 | +0.12758 | 0.0228 |
| `supply_etas_unif-BETA-F2-e5-m102` | 1.02 | 1.221053 | 1.040751 | 5.0000 | +0.26905 | 0.0446 |
| `supply_etas_unif-BETA-F2-e5-m103` | 1.03 | 1.346270 | 1.061271 | 5.0000 | +0.42568 | 0.0655 |
| `supply_etas_unif-BETA-F3-e05-m101` | 1.01 | 1.010112 | 1.020327 | 0.5000 | +0.03000 | 0.0228 |
| `supply_etas_unif-BETA-F3-e05-m102` | 1.02 | 1.020172 | 1.040751 | 0.5000 | +0.06040 | 0.0446 |
| `supply_etas_unif-BETA-F3-e05-m103` | 1.03 | 1.030180 | 1.061271 | 0.5000 | +0.09121 | 0.0655 |
| `supply_etas_unif-BETA-F3-e1-m101` | 1.01 | 1.020327 | 1.020327 | 1.0000 | +0.04041 | 0.0228 |
| `supply_etas_unif-BETA-F3-e1-m102` | 1.02 | 1.040751 | 1.040751 | 1.0000 | +0.08178 | 0.0446 |
| `supply_etas_unif-BETA-F3-e1-m103` | 1.03 | 1.061271 | 1.061271 | 1.0000 | +0.12411 | 0.0655 |
| `supply_etas_unif-BETA-F3-e2-m101` | 1.01 | 1.041067 | 1.020327 | 2.0000 | +0.06155 | 0.0228 |
| `supply_etas_unif-BETA-F3-e2-m102` | 1.02 | 1.083163 | 1.040751 | 2.0000 | +0.12583 | 0.0446 |
| `supply_etas_unif-BETA-F3-e2-m103` | 1.03 | 1.126297 | 1.061271 | 2.0000 | +0.19292 | 0.0655 |
| `supply_etas_unif-BETA-F3-e5-m101` | 1.01 | 1.105851 | 1.020327 | 5.0000 | +0.12758 | 0.0228 |
| `supply_etas_unif-BETA-F3-e5-m102` | 1.02 | 1.221053 | 1.040751 | 5.0000 | +0.26905 | 0.0446 |
| `supply_etas_unif-BETA-F3-e5-m103` | 1.03 | 1.346270 | 1.061271 | 5.0000 | +0.42568 | 0.0655 |

## Table 3 — The control and the robustness row (F2; F3 identical by financing neutrality)

| Cell | A | Employment L | Wage | Real GDP rel. | max abs(p-1) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `supply_etas_unif-ALPHA-F2-m101` | 1.01 | 1.000000 | 1.020327 | +0.01969 | 0.0228 |
| `supply_etas_unif-ALPHA-F2-m102` | 1.02 | 1.000000 | 1.040751 | +0.03945 | 0.0446 |
| `supply_etas_unif-ALPHA-F2-m103` | 1.03 | 1.000000 | 1.061271 | +0.05928 | 0.0655 |
| `supply_etas_unif-BETA-F2-sec-e05-m101` | 1.01 | 1.008201 | 1.016859 | +0.02793 | 0.0881 |
| `supply_etas_unif-BETA-F2-sec-e05-m102` | 1.02 | 1.015179 | 1.031297 | +0.05514 | 0.0740 |
| `supply_etas_unif-BETA-F2-sec-e05-m103` | 1.03 | 1.022185 | 1.046180 | +0.08292 | 0.1098 |
| `supply_etas_unif-BETA-F2-sec-e2-m101` | 1.01 | 1.033293 | 1.016705 | +0.05359 | 0.0322 |
| `supply_etas_unif-BETA-F2-sec-e2-m102` | 1.02 | 1.065894 | 1.033022 | +0.10812 | 0.0641 |
| `supply_etas_unif-BETA-F2-sec-e2-m103` | 1.03 | 1.099692 | 1.049948 | +0.16558 | 0.0942 |

## Notes

- **Identification exact and A-invariant** (spread < 1e-3 across the ladder);
  ALPHA pins L = 1 with w > 1; real GDP monotone in eta_s per column; F2 = F3
  financing neutrality holds under the supply shock; the ADR-0019 canary is asserted on
  all 63 cells at A != 1.
- The **uniform shock** moves the real wage directly (w = 1.041 at A = 1.02) and, being productivity, scales real GDP — up to +27 % at eta_s = 5.

## Status

63/63 `executed`, all gates pass. Design commits 202837a/5b834cb; batch commit below.
