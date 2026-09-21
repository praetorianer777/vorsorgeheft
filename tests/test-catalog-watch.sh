#!/usr/bin/env bash
# Exercises tools/catalog-watch.sh against local files in place of the web:
# the first run records snapshots, an unchanged document is reported as such,
# a changed one produces a readable diff, and an outage is a row rather than
# a change. HTML goes through the tag stripper; the PDF path runs only where
# pdftotext is installed, which the workflow guarantees and a laptop may not.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

failures=0
check() { # description actual expected
  if [[ "$2" == "$3" ]]; then
    echo "   ✅ $1"
  else
    echo "   ❌ $1"
    echo "      expected: $3"
    echo "      actual:   $2"
    failures=$((failures + 1))
  fi
}

# The fake web: a url maps to a file under $WORK/web by its last path segment.
mkdir -p "${WORK}/web" "${WORK}/snapshots"
cat > "${WORK}/fetch.sh" <<'EOF'
#!/usr/bin/env bash
file="$WEB/$(basename "$1")"
[[ -f "$file" ]] && cp "$file" "$2"
EOF
chmod +x "${WORK}/fetch.sh"

cat > "${WORK}/sources.json" <<'EOF'
{"sources": [
  {"id": "guideline", "name": "A guideline", "url": "https://example.org/guideline.html"},
  {"id": "calendar", "name": "The calendar", "url": "https://example.org/calendar.txt"}
]}
EOF
cat > "${WORK}/web/guideline.html" <<'EOF'
<html><head><title>Richtlinie</title><style>p{color:red}</style></head>
<body><h1>Kinder-Richtlinie</h1><script>alert(1)</script>
<p>U6: 10. bis 12. Lebensmonat, Toleranz bis Ende des 14. Monats.</p>
<p>U7: 21. bis 24. Lebensmonat.</p></body></html>
EOF
printf 'Impfkalender 2026\nTd-Auffrischung alle 10 Jahre\n' > "${WORK}/web/calendar.txt"

run() {
  rm -rf "${WORK}/out"
  WEB="${WORK}/web" FETCH="${WORK}/fetch.sh" SOURCES="${WORK}/sources.json" \
    SNAPSHOTS="${WORK}/snapshots" "${SRC}/tools/catalog-watch.sh" "${WORK}/out"
}
status() { grep "| $1 |" "${WORK}/out/summary.md" | sed 's/.*| \(.*\) |$/\1/'; }

echo "🧪 catalog-watch.sh"

run
check "the first run records a snapshot" "$(status 'A guideline')" "🆕 first snapshot recorded"
check "nothing changed means no issue text" "$(wc -c < "${WORK}/out/changed.md")" "0"
check "html is reduced to its text" \
  "$(grep -c 'alert\|color:red\|<p>' "${WORK}/snapshots/guideline.txt" || true)" "0"
check "the readable lines survive" \
  "$(grep -c 'U6: 10. bis 12. Lebensmonat' "${WORK}/snapshots/guideline.txt")" "1"

run
check "an unchanged document is reported unchanged" "$(status 'A guideline')" "✅ unchanged"
check "the calendar too" "$(status 'The calendar')" "✅ unchanged"

sed -i 's/Toleranz bis Ende des 14. Monats/Toleranz bis Ende des 15. Monats/' "${WORK}/web/guideline.html"
run
check "a changed document is reported changed" "$(status 'A guideline' | cut -d' ' -f1)" "❗"
check "the diff shows the old line" "$(grep -c '^-.*14. Monats' "${WORK}/out/changed.md")" "1"
check "the diff shows the new line" "$(grep -c '^+.*15. Monats' "${WORK}/out/changed.md")" "1"
check "the diff names the document and its url" \
  "$(grep -c 'A guideline\|https://example.org/guideline.html' "${WORK}/out/changed.md")" "2"
check "the unchanged document is not in the issue text" \
  "$(grep -c 'The calendar' "${WORK}/out/changed.md" || true)" "0"
check "the snapshot moved on" \
  "$(grep -c '15. Monats' "${WORK}/snapshots/guideline.txt")" "1"

rm "${WORK}/web/calendar.txt"
run
check "an outage is a row, not a change" "$(status 'The calendar')" "⚠️ unreachable"
check "an outage leaves the snapshot alone" \
  "$(grep -c 'Td-Auffrischung' "${WORK}/snapshots/calendar.txt")" "1"
check "an outage produces no issue text" "$(wc -c < "${WORK}/out/changed.md")" "0"

: > "${WORK}/web/calendar.txt"
run
check "an empty download is an outage too" "$(status 'The calendar')" "⚠️ unreachable"

if command -v pdftotext >/dev/null 2>&1; then
  # The smallest PDF that carries text: pdftotext reads it despite the
  # hand-written cross-reference table being approximate.
  cat > "${WORK}/web/guideline.html" <<'EOF'
%PDF-1.1
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj
4 0 obj << /Length 60 >> stream
BT /F1 18 Tf 20 100 Td (U6 bis Ende des 14. Monats) Tj ET
endstream endobj
5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj
trailer << /Root 1 0 R >>
EOF
  run
  check "a pdf is read as text" "$(status 'A guideline' | cut -d' ' -f1)" "❗"
  check "the pdf text lands in the snapshot" \
    "$(grep -c 'U6 bis Ende des 14. Monats' "${WORK}/snapshots/guideline.txt")" "1"
else
  echo "   ⏭️  pdftotext not installed, pdf case skipped"
fi

if (( failures )); then
  echo "❌ ${failures} catalog-watch check(s) failed"
  exit 1
fi
echo "✅ catalog-watch tests passed"
