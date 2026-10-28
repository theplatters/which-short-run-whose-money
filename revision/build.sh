#!/usr/bin/env bash
# =====================================================================
# revision/build.sh --- build the manuscript and the response letter.
#
#   bash build.sh              # both PDFs
#   bash build.sh main         # manuscript only
#   bash build.sh refresponse  # response letter only
#
# Both roots need biber (`biber --version`); the response letter cites
# references.bib, the manuscript adds its own bibliography. Builds happen
# IN PLACE, exactly as the manual recipe does, so that `main.synctex.gz`
# keeps pointing at `main.pdf` for the editor. Prints a verification line
# per PDF and exits non-zero if anything is unresolved.
# =====================================================================
set -u
cd "$(dirname "$0")" || exit 2

target="${1:-all}"

command -v latexmk >/dev/null || { echo "latexmk not found on PATH"; exit 2; }
command -v biber   >/dev/null || echo "warning: biber not found -- the bibliography will be empty"

fail=0

build_one() {
  local root="$1"
  printf '=== %s ===\n' "$root"
  # clear stale aux so a moved label cannot be inherited from an earlier build
  rm -f "$root.aux" "$root.bcf" "$root.run.xml" "$root.bbl" "$root.synctex.gz"
  # -synctex=1 keeps $root.synctex.gz in step with $root.pdf (the editor's sync)
  latexmk -pdf -synctex=1 -interaction=nonstopmode "$root.tex" >/dev/null 2>&1
  local rc=$?

  [ -f "$root.pdf" ] || { echo "  FAILED: no $root.pdf (see $root.log)"; fail=1; return; }

  local pages errors undefref undefcit over
  pages=$(pdfinfo "$root.pdf" 2>/dev/null | awk '/^Pages:/{print $2}')
  errors=$(grep -c '^!' "$root.log" || true)
  undefref=$(grep -c 'LaTeX Warning: Reference' "$root.log" || true)
  undefcit=$(grep -c 'LaTeX Warning: Citation' "$root.log" || true)
  over=$(grep -c 'Overfull \\hbox' "$root.log" || true)

  printf '  %s pp | errors %s | undefined refs %s | undefined cites %s | overfull boxes %s\n' \
         "${pages:-?}" "$errors" "$undefref" "$undefcit" "$over"
  printf '  latexmk exit %s\n' "$rc"

  # the response letter's own canary: an unbraced \loc call renders as
  # "Location. S" and starts a new paragraph with "ec. 1; ..."
  if [ "$root" = "refresponse" ]; then
    local badbreak
    badbreak=$(pdftotext -layout "$root.pdf" - 2>/dev/null | grep -c 'Location\. [A-Z]$' || true)
    printf '  broken Location. lines: %s (must be 0)\n' "$badbreak"
    [ "$badbreak" = "0" ] || fail=1
  fi

  [ "$rc" = "0" ] || fail=1
  [ "$errors" = "0" ] || fail=1
  [ "$undefref" = "0" ] || fail=1
  [ "$undefcit" = "0" ] || fail=1
}

case "$target" in
  all)        build_one main; build_one refresponse ;;
  main)       build_one main ;;
  refresponse|response) build_one refresponse ;;
  *)          echo "usage: bash build.sh [all|main|refresponse]"; exit 2 ;;
esac

[ "$fail" = "0" ] && echo "OK" || echo "PROBLEMS -- read the lines above"
exit "$fail"
