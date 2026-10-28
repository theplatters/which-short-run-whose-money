#!/usr/bin/env python3
import csv, tomllib, os, hashlib
from functools import lru_cache

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WD_CSVS = [
    os.path.join(REPO, "revision/tables/table6_wd.csv"),
    os.path.join(REPO, "revision/tables/table7_wd.csv"),
    os.path.join(REPO, "revision/tables/tableA8_wd.csv"),
]
PRICES_CSV = os.path.join(REPO, "revision/tables/pricing_prices.csv")
OUT_CAP = os.path.join(REPO, "revision/tables/table6_pricing-capacity.tex")
OUT_MK = os.path.join(REPO, "revision/tables/table7_pricing-markup.tex")
OUT_TABLE_APP = os.path.join(REPO, "revision/tables/tableA8_pricing-profiles.tex")

FIN = ["F1", "F2", "F3"]

# Labor rows in the order and with the names of the results matrix.
ROWS = [
    ("BF", "No-reallocation"),
    ("ALPHA", "Standard CGE"),
    ("BETA", r"Elastic labor supply ($\eta_s = 0.5$)"),
    ("GAMMA", "Employment adjustment"),
    ("DELTA", "Leontief closure"),
]

# Numeraire of each labour row (ADR-0058): the CPI in the three flexible-wage
# closures, the money wage in the two wage-pinned ones. The printed level
# column, the average real consumption wage, is the same statistic on every
# row; the split only selects the normalization gate.
FLEXIBLE_ROWS = {"BF", "ALPHA", "BETA"}
PINNED_ROWS = {"GAMMA", "DELTA"}


def cap_id(row, v):
    if row == "GAMMA":
        return "pricing_capacity-GAMMA-{f}-" + v
    if row == "ALPHA" and v != "d0":
        return "pricing_mobile-ALPHA-{f}-" + v
    return "pricing_capacity_rows-" + row + "-{f}-" + v


def per_row(rows_of):
    return [(name, rows_of(row)) for row, name in ROWS]


MK_PANELS = per_row(
    lambda row: [
        # The no-extension reference row: the same closure with a zero profit bill, i.e. the
        # Table 4 cell. It makes the markup's own contribution readable (the smallest
        # sectoral price deviation is 0 in four of the five panels but 22--28 percent
        # in the no-reallocation panel, where it comes from the wage vector) and it
        # restores the shading convention of the earlier tables (baseline shaded).
        (
            r"$\kappa = 0$ (no extension)",
            "matrix_5x3-" + row + "-{f}" + ("-etas05" if row == "BETA" else ""),
        ),
        (r"retained, $\kappa = 0.25$", "pricing_markup-" + row + "-{f}-k025"),
        (r"retained, $\kappa = 0.5$", "pricing_markup-" + row + "-{f}-k05"),
        (
            r"distributed, $\kappa = 0.5$, $s_\pi = 0.5$",
            "pricing_profit-" + row + "-{f}-k05-spi05",
        ),
        (
            r"distributed, $\kappa = 0.5$, $s_\pi = 0$",
            "pricing_profit-" + row + "-{f}-k05-spi0",
        ),
    ]
)

APP_PANELS = [
    (
        "Capacity effects on all sectors: " + name,
        [
            (r"$\delta = +0.5$", cap_id(row, "dp05")),
            (r"$\delta = -0.5$", cap_id(row, "dm05")),
        ],
    )
    for row, name in ROWS
]


@lru_cache(maxsize=None)
def manifest(rid):
    with open(f"{REPO}/runs/{rid}/manifest.toml", "rb") as fh:
        d = tomllib.load(fh)
    assert d["status"] == "executed" and d["gates"]["overall"] == "pass", rid
    # pricing_profit runs on the numerically identical v0.5.4 pin (ADR-0045, ADR-0046).
    # Keep historical run pins when verifying with v0.6.2 (ADR-0054).
    gen = "v0.5.4" if rid.startswith("pricing_profit-") else "v0.5.0"
    assert d["provenance"]["opencge"]["repo_rev"] == gen, (
        f"wrong kernel generation: {rid}"
    )
    return d


def load_wd():
    out = {}
    for path in WD_CSVS:
        with open(path, newline="") as fh:
            for r in csv.DictReader(fh):
                rid = r["run_id"]
                assert rid not in out, f"duplicate run_id across sidecars: {rid}"
                out[rid] = float(r["w_d"])
    return out


WD = load_wd()
with open(PRICES_CSV, newline="") as fh:
    PRICES = {r["run_id"]: r for r in csv.DictReader(fh)}


def sha256(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


@lru_cache(maxsize=None)
def reported_prices(rid):
    if rid.startswith("matrix_5x3-"):
        # The new no-extension rows use matrix W_D, with prices checked against
        # their recorded kappa=0 twins in the pricing sidecar.
        baseline = manifest(rid)
        scenario = baseline["scenario"]
        twin = f"pricing_markup-{scenario['labour']}-{scenario['financing']}-k0"
        for key in ("gdp_deflator", "max_abs_price_dev", "wage"):
            assert (
                abs(baseline["metrics"][key] - manifest(twin)["metrics"][key]) < 1e-8
            ), rid
        return reported_prices(twin)
    assert rid in PRICES, (
        f"missing prices for {rid}; run experiments/make_pricing_prices.jl"
    )
    r = PRICES[rid]
    man = manifest(rid)
    for path, key in (
        (f"runs/{rid}/manifest.toml", "manifest_sha256"),
        (f"experiments/designs/{man['design']}.toml", "design_sha256"),
    ):
        assert sha256(os.path.join(REPO, path)) == r[key], f"stale prices: {path}"
    # Solutions and the IO table are machine-local. Verify when available;
    # the committed sidecar also supports table builds in a clean clone.
    for path, key in (
        (f"runs/{rid}/solution.csv", "solution_sha256"),
        ("data/I-O_DE2019_formatiert.csv", "io_sha256"),
    ):
        full = os.path.join(REPO, path)
        if os.path.isfile(full):
            assert sha256(full) == r[key], f"stale prices: {path}"
    assert (
        r["io_sha256"]
        == man["provenance"]["data_sha256"]["data/I-O_DE2019_formatiert.csv"]
    )
    return r


@lru_cache(maxsize=None)
def profit_share(rid):
    man = manifest(rid)
    if "profit_share" in man["metrics"]:
        return float(man["metrics"]["profit_share"])
    if rid.startswith("matrix_5x3-"):
        s = man["scenario"]
        twin = f"pricing_markup-{s['labour']}-{s['financing']}-k0"
        t = manifest(twin)["metrics"]
        assert t.get("profit_share") == 0.0, f"twin {twin} does not record a zero profit_share"
        return 0.0
    raise KeyError(f"missing profit_share: {rid}")


def values(rid):
    man = manifest(rid)
    m = man["metrics"]
    prices = reported_prices(rid)
    labour = man["scenario"]["labour"]
    cpi = float(prices["cpi_raw"]) / float(prices["cpi_reference"])
    if labour in FLEXIBLE_ROWS:
        # CPI gate (ADR-0037 machinery): in the flexible panels the CPI is the
        # numeraire; a nonzero CPI change here means the normalization broke.
        assert abs(cpi - 1.0) < 1e-8, (
            f"CPI gate: {rid} (flexible {labour} cell must keep CPI = reference)"
        )
    else:
        assert labour in PINNED_ROWS, f"unknown labour row: {rid}"
        # Wage gate: the money wage is the numeraire, so omega = P0/P exactly.
        assert abs(float(m["wage"]) - 1.0) < 1e-12, f"wage gate: {rid}"
    # Average real consumption wage (ADR-0058): `wage` is the employment-weighted
    # money wage (the common wage where there is one), deflated by the CPI.
    P = 100 * (float(m["wage"]) / cpi - 1.0)
    # Canary: the sidecar's deflator/CPI ratio and the manifest's raw deflator
    # must be mutually consistent (D_hat * C/C0 == D).
    assert abs(float(prices["gdp_deflator_cpi"]) * cpi
               - float(m["gdp_deflator"])) < 1e-8, (
        f"deflator/CPI inconsistency: {rid}"
    )
    return dict(P=P,
                D=100 * float(prices["max_abs_price_dev_cpi"]),
                L=100 * (m["employment"] - 1.0), W=100 * m["consumption_rel"],
                Y=100 * float(m["gdp_rel"]),
                WD=WD.get(rid, float("nan")), S=100 * profit_share(rid))


def num(x, signed=True):
    assert x == x, "missing value (rerun experiments/make_table6_wd.jl?)"
    if abs(x) < 5e-3:
        return r"$0.00$"
    if not signed:
        return "$%.2f$" % x
    return ("$+%.2f$" % x) if x > 0 else ("$%.2f$" % x)


# The two main-text pricing tables print real GDP (manifest gdp_rel), the same
# object as the Delta Y column of Tables 3 and 4; the appendix table keeps W_D,
# the quantity index of demand over c^h + g^G + g.
COLS_CAP = [
    ("P", r"$\Delta\omega$", True),
    ("D", r"$\max|\Delta\hat p|$", False),
    ("L", r"$\Delta L$", True),
    ("Y", r"$\Delta Y$", True),
]
COLS_MK = [
    ("P", r"$\Delta\omega$", True),
    ("D", r"$\max|\Delta\hat p|$", False),
    ("L", r"$\Delta L$", True),
    ("Y", r"$\Delta Y$", True),
    ("S", r"$\frac{\Delta\Pi}{Y}$", False),
]
# The appendix table keeps W_D (the quantity index of demand over c^h + g^G + g),
# which Tables 6 and 7 no longer print. Its sidecar is tableA8_wd.csv
# (experiments/make_tableA8_wd.jl), gated against the same manifests.
COLS_MK_APP = [
    ("P", r"$\Delta\omega$", True),
    ("D", r"$\max|\Delta\hat p|$", False),
    ("L", r"$\Delta L$", True),
    ("WD", r"$\Delta W_D$", True),
    ("S", r"$\frac{\Delta\Pi}{Y}$", False),
]


def hdr_body(h):
    if r"\max|\Delta\hat p|" in h:
        return r"\shortstack{$\max$\\$|\Delta\hat p|$}"
    return h


def hdr_cell(h):
    return r"\multicolumn{1}{c}{" + hdr_body(h) + "}"


def build_table(panels, cols, caption_lines, label, comment_lines, fit=False):
    k = len(cols)
    ncol = 1 + k * len(FIN)
    L = []
    A = L.append
    for line in comment_lines:
        A(line)
    A(r"\begin{table}[htbp]")
    A(r"\centering")
    A(r"\scriptsize")
    A(r"\setlength{\tabcolsep}{1.6pt}")
    A(r"\renewcommand{\arraystretch}{1.15}")
    if fit:
        A(r"\resizebox{\textwidth}{!}{%")
    A(
        r"\begin{tabular}{@{}l"
        + "".join([r"@{\hspace{6pt}}" + "r" * k for _ in FIN])
        + r"@{}}"
    )
    A(r"\toprule")
    A(
        " & "
        + " & ".join([r"\multicolumn{%d}{c}{\textbf{%s}}" % (k, f) for f in FIN])
        + r" \\"
    )
    A(
        "".join(
            [
                r"\cmidrule(lr){%d-%d}" % (2 + k * i, 1 + k * (i + 1))
                for i in range(len(FIN))
            ]
        )
    )
    sub = " & ".join(hdr_cell(h) for _, h, _ in cols)
    A(
        r"\multicolumn{1}{c}{Labor closure and $\delta$} & "
        + " & ".join([sub] * len(FIN))
        + r" \\"
    )
    for panel, rows in panels:
        A(r"\midrule")
        A(r"\multicolumn{%d}{@{}l}{\textit{%s}} \\" % (ncol, panel))
        for rowlabel, tmpl in rows:
            cells = []
            for f in FIN:
                v = values(tmpl.format(f=f))
                cells += [num(v[key], signed) for key, _, signed in cols]
            A(r"\quad " + rowlabel + " & " + " & ".join(cells) + r" \\")
    A(r"\bottomrule")
    A(r"\end{tabular}" + ("}" if fit else ""))
    A(r"\caption{" + caption_lines[0])
    for line in caption_lines[1:-1]:
        A(line)
    A(caption_lines[-1] + "}")
    A(label)
    A(r"\end{table}")
    return "\n".join(L) + "\n"


FIN_NOTE = {
    "F1": "repurposing of consumption",
    "F2": "refinancing via taxes",
    "F3": "external finance",
}


def build_guided_table(
    panels,
    cols,
    stub,
    caption_lines,
    label,
    comment_lines,
    fit=False,
    collapse_panels=(),
    row_collapse_panels=(),
    row_collapse_rows=(),
    row_collapse_label=None,
    flex_label_overrides=None,
):
    k = len(cols)
    ncol = 1 + (k + 1) * len(FIN)
    L = []
    A = L.append
    for line in comment_lines:
        A(line)
    A(r"\begin{table}[htbp]")
    A(r"\centering")
    A(r"\footnotesize")
    A(r"\definecolor{tableguide}{gray}{0.92}")
    A(r"\definecolor{tableline}{gray}{0.72}")
    A(r"\setlength{\tabcolsep}{3pt}")
    A(r"\renewcommand{\arraystretch}{1.2}")
    if fit:
        A(r"\resizebox{\textwidth}{!}{%")
    guide = r"!{\color{tableline}\vrule width 0.3pt}"
    # Column widths are measured by LaTeX, per column, as the wider of its header
    # and its widest printed value, and every data column --- in the full rows and
    # inside the cell that spans F2 and F3 --- uses the same width, so the merged
    # block repeats the geometry of a financing block whatever the columns hold
    # (the fixed em widths of the first version broke when omega was added).
    def printed(tmpl, f):
        v = values(tmpl.format(f=f))
        return [num(v[key], signed) for key, _, signed in cols]

    allvals = [printed(tmpl, f) for _, rows in panels for _, tmpl in rows for f in FIN]
    widths = [r"\pdw" + "ABCDEFGH"[c] for c in range(k)]
    for c, (w, (_, h, _)) in enumerate(zip(widths, cols)):
        widest = max((vals[c] for vals in allvals), key=len)
        A(r"\ifdefined%s\else\newlength{%s}\fi" % (w, w))
        A(
            r"\settowidth{%s}{%s}\settowidth{\dimen0}{%s}"
            r"\ifdim\dimen0>%s\setlength{%s}{\dimen0}\fi" % (w, widest, hdr_body(h), w, w)
        )
    block = guide.join(r">{\raggedleft\arraybackslash}p{%s}" % w for w in widths)
    A(
        r"\begin{tabular}{l"
        + "".join([r"@{\hspace{3pt}}p{2pt}@{\hspace{3pt}}" + block for _ in FIN])
        + r"}"
    )
    A(r"\toprule")
    A(
        " & "
        + " & ".join([r"& \multicolumn{%d}{c}{\textbf{%s}}" % (k, f) for f in FIN])
        + r" \\"
    )
    A(
        " & "
        + " & ".join(
            [r"& \multicolumn{%d}{c}{\scriptsize %s}" % (k, FIN_NOTE[f]) for f in FIN]
        )
        + r" \\"
    )
    A(
        "".join(
            [
                r"\cmidrule(lr){%d-%d}" % (3 + (k + 1) * i, 2 + (k + 1) * i + k)
                for i in range(len(FIN))
            ]
        )
    )
    sub = " & ".join(hdr_cell(h) for _, h, _ in cols)
    A(
        r"\multicolumn{1}{c}{"
        + stub
        + "} & "
        + " & ".join(["& " + sub] * len(FIN))
        + r" \\"
    )
    A(r"\midrule")
    # Collapse grammar: in the panels named by collapse_panels the F2 and F3
    # groups coincide, so their k values are printed once, in one cell spanning
    # both groups --- the horizontal analogue of the \multirow used in Tables 3
    # and 4. The nested block reuses the measured widths and the guide rules, and
    # a broken coincidence aborts the build on the PRINTED strings.
    # The row colour is cleared inside the spanning cell, or the nested cells
    # paint over their own guide rules; on a shaded row the spanning cell is
    # painted as a whole instead, through its column colour.
    def nested(shaded):
        return (
            r"\multicolumn{%d}{%sc}{\expandafter\let\csname CT@row@color\endcsname\relax"
            r"\renewcommand{\arraystretch}{1}\begin{tabular}{@{}%s@{}}"
            % (2 * k + 1, r">{\columncolor{tableguide}}" if shaded else "", block)
        )
    for i, (panel, rows) in enumerate(panels):
        if i:
            A(r"\addlinespace[6pt]")
        A(r"\multicolumn{%d}{l}{\textbf{%s}} \\" % (ncol, panel))
        collapsing_rows = row_collapse_panels and i in row_collapse_panels
        for j, (rowlabel, tmpl) in enumerate(rows):
            if collapsing_rows and j in row_collapse_rows[1:]:
                continue
            if collapsing_rows and j == row_collapse_rows[0]:
                # the group of routings printed as one row: assert they coincide
                base = {f: printed(tmpl, f) for f in FIN}
                for jj in row_collapse_rows[1:]:
                    for f in FIN:
                        assert printed(rows[jj][1], f) == base[f], (
                            "routing collapse broken in %r between rows %r and %r"
                            % (panel, row_collapse_rows[0], jj)
                        )
                rowlabel = (
                    r"\begin{tabular}{@{}l@{}}"
                    + row_collapse_label
                    + r"\end{tabular}"
                )
            if (
                flex_label_overrides
                and i in collapse_panels
                and j in flex_label_overrides
            ):
                rowlabel = flex_label_overrides[j]
            cells = []
            per_fin = {}
            for f in FIN:
                per_fin[f] = printed(tmpl, f)
                cells += [""] + per_fin[f]
            shade = r"\rowcolor{tableguide}" if j == 0 else ""
            if i in collapse_panels:
                assert per_fin["F2"] == per_fin["F3"], (
                    "F2/F3 coincidence broken in %r, %r: %r vs %r"
                    % (panel, rowlabel, per_fin["F2"], per_fin["F3"])
                )
                head = cells[: 1 + k + 1]  # spacer, F1 values, spacer
                body = nested(j == 0) + " & ".join(per_fin["F2"]) + r"\end{tabular}}"
                cells = head + [body]
            A(shade + r"\quad " + rowlabel + " & " + " & ".join(cells) + r" \\")
    A(r"\bottomrule")
    A(r"\end{tabular}" + ("}" if fit else ""))
    A(r"\caption{" + caption_lines[0])
    for line in caption_lines[1:-1]:
        A(line)
    A(caption_lines[-1] + "}")
    A(label)
    A(r"\end{table}")
    return "\n".join(L) + "\n"


CAP_GUIDED_PANELS = per_row(
    lambda row: [
        (r"$0$ (no extension)", cap_id(row, "d0")),
        (r"$+0.5$", cap_id(row, "dp05-s0")),
        (r"$-0.5$", cap_id(row, "dm05-s0")),
    ]
)


def build_cap_table():
    return build_guided_table(
        CAP_GUIDED_PANELS, COLS_CAP, r"$\delta$",
        [r"Integrating a Kaldor--Verdoorn term in the general closure matrix. Each block reports",
         r"the average real consumption wage ($\Delta\omega$, the employment-weighted money wage deflated by",
         r"the consumer price index, Section~\ref{subsec:optimization}), the largest sectoral deviation from the",
         r"consumption basket ($\max|\Delta\hat p| = \max_i |p_i/\mathcal{P}-1|$), employment ($\Delta L$) and real GDP",
         r"($\Delta Y$, the wage bill plus the surplus, as in Table~\ref{tab:results-matrix}), all in percent against",
         r"the baseline. Both price statistics are independent of the numeraire and comparable across all",
         r"five panels. The shaded $\delta = 0$ rows (no extension) reproduce",
         r"results from Table~\ref{tab:results-matrix}.",
         r"The incremental effect of the extension is the difference between a row and that",
         r"shaded baseline."],
        r"\label{tab:pricing-kaldor}",
        [
            r"% =====================================================================",
            r"% Table 6 --- the capacity extension by labor closure and financing (GENERATED)",
            r"% ---------------------------------------------------------------------",
            r"% Do NOT edit by hand. Regenerate with:  make_pricing_door.py",
            r"% OpenCGE tag v0.5.0 (ADR-0044); source run ids are listed below.",
            r"% Sources: pricing_capacity_rows-<row>-<fin>-<variant>,",
            r"% pricing_capacity-GAMMA-<fin>-<variant>, pricing_mobile-ALPHA-<fin>-<variant>.",
            r"% Goods-only profile (the main-text calibration), all five labor rows",
            r"% (ADR-0032). The all-sector counterfactual lives in tableA8_pricing-profiles.tex.",
            r"% COLLAPSED CELLS: in the three flexible-wage panels (no-reallocation,",
            r"% standard CGE, elastic supply) tax finance (F2) and external finance (F3)",
            r"% coincide, so their entries are printed once, in one cell spanning both",
            r"% groups; the two wage-pinned panels print them separately. The generator",
            r"% asserts the coincidence on the PRINTED strings, so a broken equivalence",
            r"% aborts the build.",
            r"% =====================================================================",
        ],
        # panels 0-2 are the flexible-wage blocks (see CAP_GUIDED_PANELS order)
        collapse_panels=(0, 1, 2),
        fit=True,
    )


def build_mk_table():
    return build_guided_table(
        MK_PANELS, COLS_MK, "Routing of profits",
        [r"Introducing markup pricing in the context of a demand-only program for all closure scenarios.",
         r"Columns, real-wage and dispersion conventions as in Table~\ref{tab:pricing-kaldor}, including real",
         r"GDP ($\Delta Y$, the wage bill plus the surplus); the final",
         r"column, $\Delta\Pi/Y$, is the surplus the extension creates as a share of value added, in",
         r"percent (the model core prices at marginal",
         r"cost, so the baseline surplus is zero). As the shading indicates, the $\kappa = 0$ rows",
         r"reproduce the real-wage and employment cells of Table~\ref{tab:results-matrix} together with",
         r"the $\Delta Y$ column of Table~\ref{tab:pricing-kaldor}. The incremental effect of",
         r"the extension is the difference between a row and that shaded baseline."],
        r"\label{tab:pricing-markup}",
        [
            r"% =====================================================================",
            r"% Table 7 --- the markup extension by labor closure and financing (GENERATED)",
            r"% ---------------------------------------------------------------------",
            r"% Do NOT edit by hand. Regenerate with:  make_pricing_door.py",
            r"% OpenCGE tag v0.5.0 (ADR-0044); source run ids are listed below.",
            r"% Sources: matrix_5x3-<row>-<fin>[-etas05],",
            r"% pricing_markup-<row>-<fin>-<k025|k05>,",
            r"% pricing_profit-<row>-<fin>-k05-<spi05|spi0>.",
            r"% No-extension kappa = 0 reference row, then retained and distributed profit,",
            r"% kappa in {0.25, 0.5}, all five labor rows (ADR-0032). kappa = 0.25",
            r"% distributed: tableE.",
            r"% NOTE (JK, resolved): the shading now marks the kappa = 0 baseline row, which",
            r"% restores the convention of Tables 4 and 6 (the baseline row is shaded).",
            r"% COLLAPSED CELLS: as in Table 6, F2 = F3 is printed once in the three",
            r"% flexible-wage panels, asserted on the PRINTED strings.",
            r"% =====================================================================",
        ],
        fit=True,
        # panels 0-2 are the flexible-wage blocks (see MK_PANELS order)
        collapse_panels=(0, 1, 2),
        # in the same panels the three kappa = 0.5 routings coincide (retained;
        # distributed with s_pi = 0.5 and 0), so they share one row
        row_collapse_panels=(0, 1, 2),
        row_collapse_rows=(2, 3, 4),
        row_collapse_label=(
            r"retained, $\kappa = 0.5$\\"
            r"distributed, $\kappa = 0.5$, $s_\pi = 0.5$\\"
            r"distributed, $\kappa = 0.5$, $s_\pi = 0$"
        ),
    )


def build_app_table():
    return build_table(
        APP_PANELS,
        COLS_MK_APP,
        [
            r"Kaldor--Verdoorn effects extended to every sector ---",
            r"the all-sector counterfactual of Table~\ref{tab:pricing-kaldor} --- on all five",
            r"labor closures. Conventions, including the real-wage and dispersion conventions",
            r"of Table~\ref{tab:pricing-kaldor}, as in Table~\ref{tab:pricing-markup}.",
        ],
        r"\label{tab:pricing-profiles}",
        [
            r"% =====================================================================",
            r"% Table E --- pricing-door profiles not carried in the main text (GENERATED)",
            r"% ---------------------------------------------------------------------",
            r"% Do NOT edit by hand. Regenerate with:  make_pricing_door.py",
            r"% OpenCGE tag v0.5.0 (ADR-0044); source run ids are listed below.",
            r"% Sources: pricing_capacity_rows-<row>-<fin>-<dp05|dm05>,",
            r"% pricing_capacity-GAMMA-<fin>-<dp05|dm05>,",
            r"% pricing_mobile-ALPHA-<fin>-<dp05|dm05>.",
            r"% One panel: the all-sector capacity counterfactual; the kappa = 0.25",
            r"% distributed-profit rows were dropped from the paper on 2026-10-24",
            r"% (they repeated the invariance Section 6.2 already states).",
            r"% =====================================================================",
        ],
        fit=True,
    )


if __name__ == "__main__":
    for path, build in (
        (OUT_CAP, build_cap_table),
        (OUT_MK, build_mk_table),
        (OUT_TABLE_APP, build_app_table),
    ):
        with open(path, "w") as fh:
            fh.write(build())
        print("wrote", path)
