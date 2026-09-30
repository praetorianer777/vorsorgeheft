#!/usr/bin/env bash
# Runs the integration specs on a booted iOS simulator, starting over once
# when a run hangs rather than fails.
#
# About one nightly run in three never reaches its first test: the Xcode
# build finishes, and nothing is heard from the app again until the job
# times out. No test has started when that happens, which is what makes
# another attempt worth having - and what makes retrying a *failure* wrong,
# because that would be running a red test until it passes.
#
# The attempt is capped on total time rather than on silence. Silence would
# be the sharper signal, since a healthy run prints a line every few
# seconds, but reading the output to notice it costs the exit status of the
# run, and knowing whether this was a hang or a failure is the whole point.
#
# Thirty-five minutes: a green run takes about twenty-eight, and the job it
# runs in allows a hundred - enough for one hung attempt, the reset, and a
# second attempt that works.
#
# Usage: tools/ios-e2e.sh <udid>
#
# FLUTTER, SIMCTL, ATTEMPT_SECONDS and ATTEMPTS can be overridden, which is
# how tests/test-ios-e2e.sh drives this without a Mac.
set -uo pipefail

FLUTTER="${FLUTTER:-flutter}"
SIMCTL="${SIMCTL:-xcrun simctl}"
ATTEMPT_SECONDS="${ATTEMPT_SECONDS:-2100}"
ATTEMPTS="${ATTEMPTS:-2}"

udid="${1:?usage: ios-e2e.sh <udid>}"

# Unquoted on purpose: SIMCTL is a command with an argument ("xcrun simctl").
reset_simulator() {
    $SIMCTL shutdown "$udid" || true
    $SIMCTL erase "$udid" || return 1
    $SIMCTL boot "$udid" || return 1
    $SIMCTL bootstatus "$udid" -b
}

run_specs() {
    $FLUTTER test integration_test/ --reporter expanded -d "$udid" &
    local pid=$!
    ( sleep "${ATTEMPT_SECONDS}"; kill -9 "${pid}" 2>/dev/null ) &
    local watchdog=$!
    local status=0
    wait "${pid}" || status=$?
    kill "${watchdog}" 2>/dev/null || true
    wait "${watchdog}" 2>/dev/null || true
    return "${status}"
}

for (( attempt = 1; attempt <= ATTEMPTS; attempt++ )); do
    status=0
    run_specs || status=$?
    (( status == 0 )) && exit 0
    # 137 is the watchdog's SIGKILL and nothing else: the run hung.
    if (( status != 137 )) || (( attempt == ATTEMPTS )); then
        (( status == 137 )) && echo "::error::the simulator hung on every attempt"
        exit "${status}"
    fi
    echo "::warning::no test in ${ATTEMPT_SECONDS}s; starting over on a freshly erased simulator"
    reset_simulator || { echo "::error::could not bring the simulator back"; exit 1; }
done
