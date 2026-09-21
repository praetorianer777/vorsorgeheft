#!/usr/bin/env bash
# Compares every source document of the catalogs against the text it had when
# last seen, and says what changed.
#
# The catalogs are maintained by hand; nothing here parses a guideline. What
# this does is turn "the G-BA changed a 40-page PDF" into the three paragraphs
# that changed, so the person maintaining the catalog reads a diff instead of
# the whole document. The last known text of each source lives under
# tools/catalog-sources/<id>.txt; the workflow commits it after each run.
#
# Usage: tools/catalog-watch.sh <out-dir>
#   Writes <out-dir>/summary.md   one table row per source
#          <out-dir>/changed.md   the issue body fragment, empty when nothing changed
#   and updates the snapshots in place. Exit status 0 unless the sources file
#   is unreadable; an unreachable document is a row, not a failure, because an
#   outage at the G-BA must not look like a change.
#
# FETCH can name a command that takes <url> <target-file> in place of curl,
# which is how the tests feed it local files.
set -euo pipefail

SOURCES="${SOURCES:-tools/catalog-sources.json}"
SNAPSHOTS="${SNAPSHOTS:-tools/catalog-sources}"
FETCH="${FETCH:-fetch_with_curl}"
# A diff longer than this is cut in the issue; the full text is in the commit.
MAX_DIFF_LINES="${MAX_DIFF_LINES:-300}"

out="${1:?usage: catalog-watch.sh <out-dir>}"
mkdir -p "$out" "$SNAPSHOTS"
summary="$out/summary.md"
changed="$out/changed.md"
: > "$summary"
: > "$changed"

fetch_with_curl() {
  curl -fsSL --retry 3 --max-time 120 -o "$2" "$1"
}

# Text as a person would read it, with the noise that differs between two
# extractions of the same document taken out: page breaks, trailing blanks,
# runs of blank lines.
extract_text() { # file
  local mime
  mime="$(file --brief --mime-type "$1")"
  case "$mime" in
    application/pdf)
      pdftotext -layout -enc UTF-8 "$1" - ;;
    text/html|application/xhtml+xml)
      python3 - "$1" <<'PY'
import html, re, sys
raw = open(sys.argv[1], encoding="utf-8", errors="replace").read()
raw = re.sub(r"(?is)<(script|style|noscript).*?</\1>", " ", raw)
raw = re.sub(r"(?i)<br\s*/?>|</(p|div|li|tr|h[1-6]|td|th)>", "\n", raw)
text = html.unescape(re.sub(r"<[^>]+>", " ", raw))
print("\n".join(line.strip() for line in text.splitlines()))
PY
      ;;
    *)
      cat "$1" ;;
  esac | sed -e 's/\f//g' -e 's/[[:space:]]*$//' | cat -s
}

{
  echo "| Source | Status |"
  echo "|---|---|"
} >> "$summary"

while IFS=$'\t' read -r id name url; do
  body="$(mktemp)"
  if ! "$FETCH" "$url" "$body" || [[ ! -s "$body" ]]; then
    echo "| $name | ⚠️ unreachable |" >> "$summary"
    rm -f "$body"; continue
  fi
  text="$(mktemp)"
  if ! extract_text "$body" > "$text" || [[ ! -s "$text" ]]; then
    echo "| $name | ⚠️ no text could be extracted |" >> "$summary"
    rm -f "$body" "$text"; continue
  fi
  rm -f "$body"
  snapshot="$SNAPSHOTS/$id.txt"

  if [[ ! -f "$snapshot" ]]; then
    cp "$text" "$snapshot"
    echo "| $name | 🆕 first snapshot recorded |" >> "$summary"
  elif cmp -s "$text" "$snapshot"; then
    echo "| $name | ✅ unchanged |" >> "$summary"
  else
    # diff exits 1 on a difference, which pipefail would turn into an abort.
    lines="$(diff -u --label "before" --label "after" "$snapshot" "$text" | wc -l || true)"
    echo "| $name | ❗ changed ($lines diff lines) |" >> "$summary"
    {
      echo "### $name"
      echo
      echo "$url"
      echo
      echo '```diff'
      diff -u --label "before" --label "after" "$snapshot" "$text" | head -n "$MAX_DIFF_LINES" || true
      if (( lines > MAX_DIFF_LINES )); then
        echo "... ($(( lines - MAX_DIFF_LINES )) more lines; the full text is in $snapshot)"
      fi
      echo '```'
      echo
    } >> "$changed"
    cp "$text" "$snapshot"
  fi
  rm -f "$text"
done < <(jq -r '.sources[] | [.id, .name, .url] | @tsv' "$SOURCES")
