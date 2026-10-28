#!/usr/bin/env python3
import csv, tomllib, os

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT  = os.path.join(REPO, "revision/tables/table4_results-5x3.tex")
# consumption-unit sidecar (ADR-0037); only its kappa = 0 twins are used here
with open(os.path.join(REPO, "revision/tables/pricing_prices.csv"), newline="") as fh:
    PRICES = {r["run_id"]: r for r in csv.DictReader(fh)}

# run-id variant suffix per column ("" = the plain matrix cell)
variant = {"BETA": "-etas05"}

# the bracket: executed sectoral cells, low end first (0.5 = headline value)
ETA_BRACKET = [("0.5", "-etas05"), ("1", "-etas1"), ("2", "-etas2")]
ETA_LO, ETA_HI = ETA_BRACKET[0][0], ETA_BRACKET[-1][0]

# column order matches table3 (no-reallocation leftmost)
cols = [("BF",    "No-reallocation",      "immobile labor, sectoral wages"),
        ("ALPHA", "Standard CGE",         "one flexible wage, mobile labor"),
        ("BETA",  "Elastic labor supply","sectoral supply on the real wage"),
        ("GAMMA", "Employment adjustment", "wage pinned, employment uncapped"),
        ("DELTA", "Leontief closure",     "wage pinned, quantities absorb")]
fin = [("F1", "repurposing of consumption"),
       ("F2", "refinancing via taxes"),
       ("F3", "external finance")]

# the two collapses, as printed: rows that share a solution, columns that share one
FLEX_COLS = ("BF", "ALPHA", "BETA")   # the three flexible-wage columns
SHARED_ROWS = ("F2", "F3")           # coincide in FLEX_COLS
SHARED_COLS = ("GAMMA", "DELTA")     # coincide in every financing row

# merged width of the GAMMA+DELTA pair: 2.1 + 2*\tabcolsep(3pt) + 2.1
MERGED_W = "4.35cm"

# The row span of the shared F2/F3 block, in \multirow's own units.
# \multirow does NOT take the number of table rows here: its vertical offset
# moves ~5.9pt per unit while the block must travel half a row pitch per line,
# so the logical span (2 rows x 5 outcomes = 10 lines) places the block a full
# line too LOW -- the top gap came out 52.4pt against a bottom gap of 11.5pt.
# Measured span sweep (shim, everything else fixed):
#   n=4: -18.2pt (and overfull), n=6: -6.4pt, n=7: -0.5pt, n=8: +17.2pt,
#   n=10: +40.9pt, n=12: +64.6pt   [difference = top gap - bottom gap]
# n=7 centres the block; re-measure it if an outcome row or the font size
# changes (build a shim with the table alone and compare the two gaps).

# Set to False to emit the plain 15-cell matrix (no \multirow, no \multicolumn).
# Use it on a TeX installation without multirow.sty -- and then also comment out
# the \usepackage{multirow} line in main.tex, which is what would fail first.
COLLAPSE_LAYOUT = True


def get(c, f, suffix=None):
    suffix = variant.get(c, "") if suffix is None else suffix
    d = tomllib.load(open(f"{REPO}/runs/matrix_5x3-{c}-{f}{suffix}/manifest.toml", "rb"))
    assert d["status"] == "executed" and d["gates"]["overall"] == "pass"
    # Historical run provenance; the v0.6.2 verification pin is separate (ADR-0054).
    assert d["provenance"]["opencge"]["repo_rev"] == "v0.5.0"
    m = d["metrics"]
    # Average real consumption wage (ADR-0058). The matrix manifests record no
    # CPI, but it is one in every demand-only cell: the numeraire in the
    # flexible-wage closures, pinned prices in the wage-pinned ones. Gate it
    # on the recorded kappa = 0 twin wherever the pricing sidecar has one.
    twin = PRICES.get(f"pricing_markup-{c}-{f}-k0")
    if twin is not None and suffix == variant.get(c, ""):
        assert abs(float(twin["cpi_raw"]) / float(twin["cpi_reference"]) - 1.0) < 1e-8, (c, f)
    assert c not in ("GAMMA", "DELTA") or m["max_abs_price_dev"] < 1e-8, (c, f)
    return dict(Y=100 * m["gdp_rel"], L=100 * (m["employment"] - 1.0),
                P=100 * (m["wage"] - 1.0),
                D=100 * m["external_position"], WC=100 * m["consumption_rel"])


def num(x):
    if abs(x) < 5e-5:
        return r"$0.00$"
    return ("$+%.2f$" % x) if x > 0 else ("$%.2f$" % x)


def num_range(lo, hi):
    if abs(hi - lo) < 5e-5:
        return num(lo)
    return r"$[" + num(lo)[1:-1] + r",\ " + num(hi)[1:-1] + r"]$"


def cell(v):
    return (r"\begin{tabular}{@{}l@{\hspace{3pt}}r@{}}" "\n"
            r"$\Delta Y$ & " + num(v["Y"]) + r" \\" "\n"
            r"$\Delta L$ & " + num(v["L"]) + r" \\" "\n"
            r"$\Delta\omega$ & " + num(v["P"]) + r" \\" "\n"
            r"$\Delta D$ & " + num(v["D"]) + r" \\" "\n"
            r"$\Delta W_C$ & " + num(v["WC"]) + r"\end{tabular}")


OUTCOMES = [("Y", r"$\Delta Y$"), ("L", r"$\Delta L$"), ("P", r"$\Delta\omega$"),
            ("D", r"$\Delta D$"), ("WC", r"$\Delta W_C$")]
# inner layout of the elastic-supply column: outcome label + one bracketed column
ETAS_SPEC = r"@{}>{\raggedright\arraybackslash}p{0.85cm}@{\hspace{3pt}}>{\raggedleft\arraybackslash}p{2.2cm}@{}"


def etas_head():
    return (r"{\footnotesize\begin{tabular}{" + ETAS_SPEC + "}\n"
            r"& $\eta_s \in [" + ETA_LO + r"," + ETA_HI + r"]$\end{tabular}}")


def etas_cell(f):
    vs = [get("BETA", f, suf) for _, suf in ETA_BRACKET]
    rows = [lab + " & " + num_range(min(v[k] for v in vs), max(v[k] for v in vs))
            for k, lab in OUTCOMES]
    return (r"\begin{tabular}{" + ETAS_SPEC + "}\n"
            + " \\\\\n".join(rows) + r"\end{tabular}")


def cellstr(c, f):
    return etas_cell(f) if c == "BETA" else cell(get(c, f))


def check_collapses():
    for c in FLEX_COLS:
        a, b = cellstr(c, SHARED_ROWS[0]), cellstr(c, SHARED_ROWS[1])
        assert a == b, f"F2 != F3 in column {c}: the row merge would print a wrong value"
    for f, _ in fin:
        a, b = cellstr(SHARED_COLS[0], f), cellstr(SHARED_COLS[1], f)
        assert a == b, f"GAMMA != DELTA in row {f}: the column merge would print a wrong value"


BLOCK_LINES = len(OUTCOMES)                       # lines in the shared block
BAND_LINES  = len(OUTCOMES) * len(SHARED_ROWS)    # lines the block spans

# The row span of the shared F2/F3 block, in \multirow's OWN units.
# \multirow does not take the number of table rows here: its vertical offset
# moves ~5.9pt per unit while the block travels half a row pitch per line, so
# the logical span (BAND_LINES = 10) places the block a full line too LOW --
# the top gap came out 52.4pt against a bottom gap of 11.5pt. Measured sweep
# (shim with the table alone, everything else fixed), difference = top - bottom:
#   n=4: -18.2pt (and overfull), n=6: -6.4pt, n=7: -0.5pt,
#   n=8: +17.2pt, n=10: +40.9pt, n=12: +64.6pt
# n=7 centres the block. Re-measure it if an outcome row or the font size
# changes (build a shim with the table alone and compare the two gaps).
SPAN = BAND_LINES - BLOCK_LINES + 2
# \multirow's unit here is HALF a row pitch (it counts the stretched strut), and
# it centres on the current row, which adds two units -- hence the +2 above and
# the quarter-baselineskip nudge below, which takes the residual from +5.4pt to
# the measured +0.7pt (d_top 32.3 vs d_bot 31.6).
VMOVE = r"[\dimexpr\baselineskip/4\relax]"


def multirow(n, w, content):
    return r"\multirow{%d}{%s}%s{\centering %s}" % (n, w, VMOVE, content)


def multicol(content):
    return (r"\multicolumn{2}{|>{\centering\arraybackslash}p{" + MERGED_W + r"}}{"
            + content + "}")



def plain_caption():
    return (r"\caption{Estimated impacts of a transformational stimulus in the German residential" "\n"
            r"sector across the closure matrix. Each cell reports the change in real GDP" "\n"
            r"($\Delta Y$), employment ($\Delta L$, the composite primary-factor input," "\n"
            r"i.e.\ all value added), the average real consumption wage ($\Delta\omega$, the employment-weighted money wage deflated by the consumer price index, which equals one in every cell of this demand-only design)," "\n"
            r"the net external position ($\Delta D = F + B_{\mathrm{gov}}$, positive = net external" "\n"
            r"financing received, i.e.\ external debt, in percentage points of baseline GDP) and household consumption welfare" "\n"
            r"($\Delta W_C$), all other entries in percent against the baseline. The" "\n"
            r"elastic-supply column is bracketed: each entry is the interval over the executed" "\n"
            r"$\eta_s \in \{" + r",\ ".join(e for e, _ in ETA_BRACKET) + r"\}$, with" "\n"
            r"$\eta_s = " + ETA_LO + r"$ the headline point value. The employment-adjustment and" "\n"
            r"Leontief columns coincide, and F2 and F3 coincide in the three flexible-wage" "\n"
            r"columns, so the fifteen cells describe nine distinct economies.}")


def build():
    if COLLAPSE_LAYOUT:
        check_collapses()
    L = []
    A = L.append
    A(r"% =====================================================================")
    A(r"% Table 4 --- results across the 5x3 closure matrix (GENERATED)")
    A(r"% ---------------------------------------------------------------------")
    A(r"% Do NOT edit by hand. Regenerate with:  make_table4_results.py")
    A(r"% Source: runs/matrix_5x3-<closure>-<fin>/manifest.toml (schema v2);")
    A(r"%   elastic-supply column: the executed sectoral cells")
    A(r"%   matrix_5x3-BETA-<fin>-etas{05,1,2}, reported as a min--max bracket.")
    A(r"% Columns in table3 order (no-reallocation leftmost). Five outcomes per cell:")
    A(r"%   \Delta Y real GDP, \Delta L employment, \Delta\omega average real consumption")
    A(r"%   wage (metrics.wage; the CPI is one in every demand-only cell, ADR-0058),")
    A(r"%   \Delta D net external position (= F + B_gov, 'external debt'),")
    A(r"%   \Delta W_C household consumption welfare.")
    A(r"% All in percent vs. the baseline; GDP at basic prices = 1.")
    A(r"% COLLAPSED CELLS: F2/F3 share one cell in the three flexible-wage columns")
    A(r"%   (\multirow{2}, the rule between those rows is a \cmidrule over the two")
    A(r"%   right-hand columns only); the employment-adjustment and Leontief columns share")
    A(r"%   one \multicolumn{2} cell per row. The generator asserts both coincidences")
    A(r"%   on the printed strings, so a broken equivalence aborts the build.")
    A(r"% =====================================================================")
    A(r"\begin{table}[htbp]")
    A(r"\centering")
    A(r"\footnotesize")
    A(r"\setlength{\tabcolsep}{3pt}")
    A(r"\setlength{\parindent}{0pt}")
    A(r"\setlength{\parskip}{2pt}")
    A(r"\renewcommand{\arraystretch}{1.25}")
    width = {"BETA": "3.2cm"}
    A(r"\begin{tabular}{@{}>{\raggedright\arraybackslash}p{1.6cm}"
      + "".join([r" >{\raggedright\arraybackslash}p{%s}" % width.get(c, "2.1cm") for c, _, _ in cols[:3]])
      + r" |" + "".join([r" >{\raggedright\arraybackslash}p{%s}" % width.get(c, "2.1cm") for c, _, _ in cols[3:]])
      + r"@{}}")
    A(r"\toprule")
    A(r"\textbf{Financing closure}")
    for c, name, desc in cols:
        A(r"& \textbf{" + name + r"}\newline \scriptsize " + desc
          + ((r"\newline " + etas_head()) if c == "BETA" else ""))
    A(r"\\")
    A(r"\midrule")

    def flex_cells(f):
        # An earlier wrap="multirow" branch was dead code with a wrong span
        # (2 where multirow needs SPAN lines); merged cells are built at the
        # call site below with multirow(SPAN, ...).
        return [r"& " + cellstr(c, f) for c in FLEX_COLS]

    if not COLLAPSE_LAYOUT:
        # plain matrix: fifteen cells, nothing merged (the fallback layout)
        for i, (f, fd) in enumerate(fin):
            A(r"\textbf{" + f + r"}\newline \scriptsize " + fd)
            for c, _, _ in cols:
                A(r"& " + cellstr(c, f))
            A(r"\\")
            if i < len(fin) - 1:
                A(r"\midrule")
        A(r"\bottomrule")
        A(r"\end{tabular}")
        A(plain_caption())
        A(r"\label{tab:results-matrix}")
        A(r"\end{table}")
        return "\n".join(L) + "\n"

    # --- row F1: nothing is shared, all five columns are separate cells
    A(r"\textbf{F1}\newline \scriptsize " + fin[0][1])
    for s in flex_cells("F1"):
        A(s)
    A(r"& " + multicol(cellstr(SHARED_COLS[0], "F1")))
    A(r"\\")
    # the rule separates the F1 row from the F2/F3 band in the left block and
    # restarts over the GAMMA/DELTA pair, so it marks the block boundary
    A(r"\cmidrule(lr){1-4}\cmidrule(lr){5-6}")

    # --- row F2: its first three cells are shared with F3 (\multirow), the
    #     GAMMA/DELTA pair is shared within the row (\multicolumn).
    #     NB \multirow counts LINES, not logical rows: both spanned rows are
    #     len(OUTCOMES) lines tall, so the span is len(OUTCOMES)*2 lines. Passing
    #     "2" here (the logical count) makes LaTeX size the box for two lines,
    #     overflow it by ~36pt and print nothing but an "Overfull \vbox".
    A(r"\textbf{F2}\newline \scriptsize " + fin[1][1])
    for c in FLEX_COLS:
        A(r"& " + multirow(SPAN, width.get(c, "2.1cm"), cellstr(c, "F2")))
    A(r"& " + multicol(cellstr(SHARED_COLS[0], "F2")))
    A(r"\\")
    # no full rule here: it would cut through the merged cells
    A(r"\cmidrule(lr){5-6}")

    # --- row F3: the flexible-wage columns are already printed (the F2 cells,
    #     whose values equal F3's); only the GAMMA/DELTA pair belongs to this row
    A(r"\textbf{F3}\newline \scriptsize " + fin[2][1])
    A(r"& & & & " + multicol(cellstr(SHARED_COLS[0], "F3")))
    A(r"\\")
    A(r"\bottomrule")
    A(r"\end{tabular}")
    A(r"\caption{Estimated impacts of a transformational stimulus in the German residential")
    A(r"sector across the closure matrix. Each cell reports the change in real GDP")
    A(r"($\Delta Y$), employment ($\Delta L$, the composite primary-factor input,")
    A(r"i.e.\ all value added), the average real consumption wage ($\Delta\omega$, the employment-weighted money wage deflated by the consumer price index, which equals one in every cell of this demand-only design),")
    A(r"the net external position ($\Delta D$, in percentage points of baseline GDP) and household consumption welfare")
    A(r"($\Delta W_C$), all other entries in percent against the baseline. The employment-adjustment and")
    A(r"Leontief columns coincide. Within each of the three flexible-wage columns, F2 and F3")
    A(r"coincide because the external transfer $F$ offsets the financing difference; the wage-pinned")
    A(r"columns impose $F=0$. The fifteen cells therefore characterize nine distinct economies.}")
    A(r"\label{tab:results-matrix}")
    A(r"\end{table}")
    return "\n".join(L) + "\n"


if __name__ == "__main__":
    open(OUT, "w").write(build())
    print("wrote", OUT)
