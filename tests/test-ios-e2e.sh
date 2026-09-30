#!/usr/bin/env bash
# Exercises tools/ios-e2e.sh with a stand-in for flutter and simctl: a run
# that passes, one that hangs and then passes, one that hangs twice, and one
# that fails - which must be reported rather than retried, or a red test
# would be run until it went green.
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

# A flutter that behaves differently on each attempt: the script reads the
# next behaviour from a file and writes down that it was called.
cat > "${WORK}/flutter" <<'FAKE'
#!/usr/bin/env bash
echo "$@" >> "${WORK}/flutter.calls"
behaviour="$(head -n1 "${WORK}/behaviour")"
sed -i '1d' "${WORK}/behaviour"
case "${behaviour}" in
  pass) echo "00:05 +1: a test"; exit 0 ;;
  fail) echo "00:05 +0 -1: a test [E]"; exit 1 ;;
  hang) sleep 60 ;;
esac
FAKE

cat > "${WORK}/simctl" <<'FAKE'
#!/usr/bin/env bash
echo "$@" >> "${WORK}/simctl.calls"
FAKE

chmod +x "${WORK}/flutter" "${WORK}/simctl"

run() { # behaviour...
  printf '%s\n' "$@" > "${WORK}/behaviour"
  : > "${WORK}/flutter.calls"
  : > "${WORK}/simctl.calls"
  set +e
  WORK="${WORK}" FLUTTER="${WORK}/flutter" SIMCTL="${WORK}/simctl" \
    ATTEMPT_SECONDS=2 "${SRC}/tools/ios-e2e.sh" THE-UDID > "${WORK}/out.log" 2>&1
  status=$?
  set -e
}

attempts() { grep -c . "${WORK}/flutter.calls" || true; }

echo "🧪 ios-e2e.sh — a run that works is run once"
run pass
check "exit status" "${status}" "0"
check "attempts" "$(attempts)" "1"
check "the device is the one it was given" \
  "$(grep -c -- '-d THE-UDID' "${WORK}/flutter.calls")" "1"
check "the simulator is left alone" "$(grep -c . "${WORK}/simctl.calls" || true)" "0"

echo "🧪 ios-e2e.sh — a hang is started over on a fresh simulator"
run hang pass
check "exit status" "${status}" "0"
check "attempts" "$(attempts)" "2"
check "it says why it started over" \
  "$(grep -c 'starting over on a freshly erased simulator' "${WORK}/out.log")" "1"
check "the simulator was shut down, erased and booted" \
  "$(grep -c -e 'shutdown THE-UDID' -e 'erase THE-UDID' -e 'boot THE-UDID' "${WORK}/simctl.calls")" "3"
check "and the script waited for it to come up" \
  "$(grep -c 'bootstatus THE-UDID -b' "${WORK}/simctl.calls")" "1"

echo "🧪 ios-e2e.sh — hanging twice is reported as a hang"
run hang hang
check "exit status" "${status}" "137"
check "attempts" "$(attempts)" "2"
check "it says the simulator hung" \
  "$(grep -c 'hung on every attempt' "${WORK}/out.log")" "1"

echo "🧪 ios-e2e.sh — a failing test is never retried"
run fail pass
check "exit status" "${status}" "1"
check "attempts" "$(attempts)" "1"
check "the failure is passed through" \
  "$(grep -c 'a test \[E\]' "${WORK}/out.log")" "1"

if (( failures )); then
  echo "❌ ios-e2e.sh tests failed"
  exit 1
fi
echo "✅ ios-e2e.sh tests passed"
