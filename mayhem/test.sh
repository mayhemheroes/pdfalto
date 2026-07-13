#!/usr/bin/env bash
#
# mayhem/test.sh — functional oracle for pdfalto.
#
# Upstream ships NO test suite (no ctest targets, no test scripts — only sample
# *outputs* under samples/), so this is an AUTHORED known-answer oracle: it runs
# the normal-flags binary that mayhem/build.sh produced (build-test/pdfalto) on
# a committed input (mayhem/testdata/hello.pdf) and asserts the CONTENT of the
# generated ALTO XML — not just the exit status. A neutered exit(0) binary
# produces no/empty output and fails every assertion.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN="$SRC/build-test/pdfalto"
if [ ! -x "$BIN" ]; then
  echo "FATAL: $BIN missing — mayhem/build.sh must build it (test.sh never compiles)" >&2
  emit_ctrf "pdfalto-known-answer" 0 1
  exit 1
fi

PASS=0; FAIL=0
check() {  # check <name> <cmd...>
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "PASS: $name"
  else FAIL=$((FAIL+1)); echo "FAIL: $name"; fi
}

OUT=/tmp/pdfalto-oracle
rm -rf "$OUT"; mkdir -p "$OUT"
"$BIN" "$SRC/mayhem/testdata/hello.pdf" "$OUT/hello.xml" > "$OUT/stdout.log" 2>&1
RC=$?

check "pdfalto exits 0 on a valid single-page PDF" test "$RC" -eq 0
check "ALTO XML output file is produced"           test -s "$OUT/hello.xml"
check "output is an ALTO document"                 grep -q "<alto" "$OUT/hello.xml"
check "extracts the string 'Hello'"                grep -q 'CONTENT="Hello"' "$OUT/hello.xml"
check "extracts the string 'World'"                grep -q 'CONTENT="World"' "$OUT/hello.xml"
check "reports the Helvetica font in styles"       grep -qi 'FONTFAMILY="Helvetica"' "$OUT/hello.xml"
check "page geometry matches the MediaBox (612)"   grep -q 'WIDTH="612' "$OUT/hello.xml"
check "metadata sidecar file is produced"          test -s "$OUT/hello_metadata.xml"

emit_ctrf "pdfalto-known-answer" "$PASS" "$FAIL"
