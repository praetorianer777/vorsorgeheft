#!/usr/bin/env bash
# The one entry point for the whole suite: the branch-guard hook runs this
# before every push, and ci.yml has no other step.
set -euo pipefail
cd "$(dirname "$0")"

echo "🐚 Shell tests"
[[ -x tests/test-release.sh ]] && ./tests/test-release.sh
./.claude/hooks/tests/branch-guard-test.sh

if ! command -v flutter >/dev/null 2>&1; then
  echo "❌ flutter not found — see README 'Building' for the toolchain setup" >&2
  exit 1
fi

echo "🎨 Formatting"
# Only tracked files: the localisation sources and drift tables generate Dart
# that is gitignored, and formatting a build artifact fails the gate for
# something nobody can fix by hand.
git ls-files '*.dart' | xargs -r dart format --output=none --set-exit-if-changed

echo "🔍 Analyzer"
flutter analyze --fatal-infos

echo "🧪 Unit tests"
flutter test

# The emulator is slow and needs KVM, so it stays opt-in here and runs nightly
# in CI rather than gating every push.
if [[ "${ANDROID_E2E:-0}" == "1" ]]; then
  echo "📱 Integration tests"
  flutter test integration_test/
fi

echo "✅ All tests passed"
