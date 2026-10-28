# Flow tables — the supply arm `supply_etas_s1` (ADR-0023, 63 cells)

Generated from `runs/supply_etas_s1-*/manifest.toml` on the full-71 A-bill
calibration (G0 = 40,300 EUR m at 2019 prices, ADR-0024): no re-solve and no
hand-typed numbers. The design: `[shock] kind = "sectoral"`, targets = [1]
(sector 1, agriculture), magnitude ladder A1 in {1.1, 1.2, 1.3}; the programme
stays financed F1/F2/F3; the reference continuation is the no-shock baseline
(ADR-0023 decision 2). Identification vehicles per ADR-0023: ALPHA control,
scalar single-wage BETA (2N+2, the scalar `ln L / ln w` signature) and the
sectoral uniform BETA (3N+1, per-sector recovery) as the robustness row.
Paper text cites the `supply_etas_s1-*` run ids (ADR-0004).

## Table 1 — Baseline and shock

| Quantity | Value | Source |
| --- | ---: | --- |
| Programme | 1.331 % of GDP | G0 / GDP_P = 40300 / 3027818 |
| Shock | A1 = 1.1 / 1.2 / 1.3 (+10 / +20 / +30 % productivity in sector 1) | `[shock] targets = [1]` |
| Reference | no-shock, no-programme continuation | `build_reference` (unchanged) |

## Table 2 — Identification: implied `eta_s` against input (scalar BETA, 2N+2)

`ln L / ln w` per cell; the signature recovers the input elasticity to 1e-6 and is
invariant to the shock magnitude (the spread across A1 in {1.1,1.2,1.3} is < 1e-6).

| Cell | A1 | Employment L | Wage w | Implied `eta_s` | Real GDP rel. | max abs(p-1) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `supply_etas_s1-BETA-F1-e05-m11` | 1.1 | 1.001307 | 1.002617 | 0.5000 | +0.00285 | 0.1084 |
| `supply_etas_s1-BETA-F1-e05-m12` | 1.2 | 1.002448 | 1.004903 | 0.5000 | +0.00535 | 0.1962 |
| `supply_etas_s1-BETA-F1-e05-m13` | 1.3 | 1.003456 | 1.006925 | 0.5000 | +0.00759 | 0.2688 |
| `supply_etas_s1-BETA-F1-e1-m11` | 1.1 | 1.002617 | 1.002617 | 1.0000 | +0.00416 | 0.1084 |
| `supply_etas_s1-BETA-F1-e1-m12` | 1.2 | 1.004903 | 1.004903 | 1.0000 | +0.00781 | 0.1962 |
| `supply_etas_s1-BETA-F1-e1-m13` | 1.3 | 1.006925 | 1.006925 | 1.0000 | +0.01107 | 0.2688 |
| `supply_etas_s1-BETA-F1-e2-m11` | 1.1 | 1.005240 | 1.002617 | 2.0000 | +0.00678 | 0.1084 |
| `supply_etas_s1-BETA-F1-e2-m12` | 1.2 | 1.009830 | 1.004903 | 2.0000 | +0.01275 | 0.1962 |
| `supply_etas_s1-BETA-F1-e2-m13` | 1.3 | 1.013897 | 1.006925 | 2.0000 | +0.01807 | 0.2688 |
| `supply_etas_s1-BETA-F1-e5-m11` | 1.1 | 1.013152 | 1.002617 | 5.0000 | +0.01471 | 0.1084 |
| `supply_etas_s1-BETA-F1-e5-m12` | 1.2 | 1.024756 | 1.004903 | 5.0000 | +0.02772 | 0.1962 |
| `supply_etas_s1-BETA-F1-e5-m13` | 1.3 | 1.035107 | 1.006925 | 5.0000 | +0.03937 | 0.2688 |
| `supply_etas_s1-BETA-F2-e05-m11` | 1.1 | 1.001307 | 1.002617 | 0.5000 | +0.00286 | 0.1084 |
| `supply_etas_s1-BETA-F2-e05-m12` | 1.2 | 1.002448 | 1.004903 | 0.5000 | +0.00538 | 0.1962 |
| `supply_etas_s1-BETA-F2-e05-m13` | 1.3 | 1.003456 | 1.006925 | 0.5000 | +0.00763 | 0.2688 |
| `supply_etas_s1-BETA-F2-e1-m11` | 1.1 | 1.002617 | 1.002617 | 1.0000 | +0.00417 | 0.1084 |
| `supply_etas_s1-BETA-F2-e1-m12` | 1.2 | 1.004903 | 1.004903 | 1.0000 | +0.00784 | 0.1962 |
| `supply_etas_s1-BETA-F2-e1-m13` | 1.3 | 1.006925 | 1.006925 | 1.0000 | +0.01111 | 0.2688 |
| `supply_etas_s1-BETA-F2-e2-m11` | 1.1 | 1.005240 | 1.002617 | 2.0000 | +0.00680 | 0.1084 |
| `supply_etas_s1-BETA-F2-e2-m12` | 1.2 | 1.009830 | 1.004903 | 2.0000 | +0.01278 | 0.1962 |
| `supply_etas_s1-BETA-F2-e2-m13` | 1.3 | 1.013897 | 1.006925 | 2.0000 | +0.01811 | 0.2688 |
| `supply_etas_s1-BETA-F2-e5-m11` | 1.1 | 1.013152 | 1.002617 | 5.0000 | +0.01472 | 0.1084 |
| `supply_etas_s1-BETA-F2-e5-m12` | 1.2 | 1.024756 | 1.004903 | 5.0000 | +0.02775 | 0.1962 |
| `supply_etas_s1-BETA-F2-e5-m13` | 1.3 | 1.035107 | 1.006925 | 5.0000 | +0.03941 | 0.2688 |
| `supply_etas_s1-BETA-F3-e05-m11` | 1.1 | 1.001307 | 1.002617 | 0.5000 | +0.00286 | 0.1084 |
| `supply_etas_s1-BETA-F3-e05-m12` | 1.2 | 1.002448 | 1.004903 | 0.5000 | +0.00538 | 0.1962 |
| `supply_etas_s1-BETA-F3-e05-m13` | 1.3 | 1.003456 | 1.006925 | 0.5000 | +0.00763 | 0.2688 |
| `supply_etas_s1-BETA-F3-e1-m11` | 1.1 | 1.002617 | 1.002617 | 1.0000 | +0.00417 | 0.1084 |
| `supply_etas_s1-BETA-F3-e1-m12` | 1.2 | 1.004903 | 1.004903 | 1.0000 | +0.00784 | 0.1962 |
| `supply_etas_s1-BETA-F3-e1-m13` | 1.3 | 1.006925 | 1.006925 | 1.0000 | +0.01111 | 0.2688 |
| `supply_etas_s1-BETA-F3-e2-m11` | 1.1 | 1.005240 | 1.002617 | 2.0000 | +0.00680 | 0.1084 |
| `supply_etas_s1-BETA-F3-e2-m12` | 1.2 | 1.009830 | 1.004903 | 2.0000 | +0.01278 | 0.1962 |
| `supply_etas_s1-BETA-F3-e2-m13` | 1.3 | 1.013897 | 1.006925 | 2.0000 | +0.01811 | 0.2688 |
| `supply_etas_s1-BETA-F3-e5-m11` | 1.1 | 1.013152 | 1.002617 | 5.0000 | +0.01472 | 0.1084 |
| `supply_etas_s1-BETA-F3-e5-m12` | 1.2 | 1.024756 | 1.004903 | 5.0000 | +0.02775 | 0.1962 |
| `supply_etas_s1-BETA-F3-e5-m13` | 1.3 | 1.035107 | 1.006925 | 5.0000 | +0.03941 | 0.2688 |

## Table 3 — The control and the robustness row (F2 shown; F3 identical to F2 by financing neutrality, ADR-0019)

| Cell | A1 | Employment L | Wage | Real GDP rel. | max abs(p-1) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `supply_etas_s1-ALPHA-F2-m11` | 1.1 | 1.000000 | 1.002617 | +0.00155 | 0.1084 |
| `supply_etas_s1-ALPHA-F2-m12` | 1.2 | 1.000000 | 1.004903 | +0.00292 | 0.1962 |
| `supply_etas_s1-ALPHA-F2-m13` | 1.3 | 1.000000 | 1.006925 | +0.00416 | 0.2688 |
| `supply_etas_s1-BETA-F2-sec-e05-m11` | 1.1 | 1.002428 | 1.005257 | +0.00400 | 0.1281 |
| `supply_etas_s1-BETA-F2-sec-e05-m12` | 1.2 | 1.003440 | 1.007311 | +0.00639 | 0.2284 |
| `supply_etas_s1-BETA-F2-sec-e05-m13` | 1.3 | 1.004324 | 1.009123 | +0.00853 | 0.3094 |
| `supply_etas_s1-BETA-F2-sec-e2-m11` | 1.1 | 1.006292 | 1.003247 | +0.00786 | 0.1164 |
| `supply_etas_s1-BETA-F2-sec-e2-m12` | 1.2 | 1.010117 | 1.005159 | +0.01307 | 0.2095 |
| `supply_etas_s1-BETA-F2-sec-e2-m13` | 1.3 | 1.013499 | 1.006853 | +0.01772 | 0.2858 |

## Notes

- **Identification is exact and magnitude-invariant.** The implied elasticity equals the
  input to four decimals in every scalar BETA cell, and the spread across A1 = 1.1/1.2/1.3
  is below 1e-6: under a supply shock the wage–employment response identifies `eta_s`.
- **ALPHA is the control.** Employment is pinned at exactly 1 and the real wage moves
  (w = 1.004903 at A1 = 1.2), i.e. the shock separates the rungs only for BETA.
- **Financing neutrality extends to supply shocks.** F2 and F3 agree in every metric to
  all printed decimals; the F1 column is distinct (the programme tilt).
- **Prices move through technology.** max abs(p-1) reads 0.196 (A1 = 1.2) for the scalar
  rows; the sectoral 3N+1 rows carry their own wage dispersion (w = 1.007 at A1 = 1.2,
  max abs(p-1) = 0.228 at eta_s = 0.5).
- **The canary under A != 1.** The ADR-0019 external-account identity is asserted on every
  cell (all 63 pass; `canary_diff` at solver noise), recording the ETAs gate that had only
  ever been tested at p = 1.

## Status

63/63 `executed`, all gates pass (residual, budget, labour; ADR-0019 acceptance).
Generation design commit `202837a`, batch commit below. Designs `supply_etas_prog`
(the programme-own sectors) and `supply_etas_unif` (uniform) remain to be preregistered
and run.
