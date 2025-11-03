#!/usr/bin/env bash
#
# Main test runner for build verification system
#

set -eu

anyFailed=0

runTest() {
  local testPath="$1"
  local testName=$(basename "$testPath" .sh)

  echo ""
  echo "========================================"
  echo "Running: $testName"
  echo "========================================"

  if ${testPath}; then
    echo "✅ PASS: ${testName}"
  else
    echo "❌ FAIL: ${testName}"
    anyFailed=1
  fi
}

scriptPath=$(dirname "$0")
cd "${scriptPath}"

echo "╔══════════════════════════════════════════╗"
echo "║  Build Verification System Test Suite   ║"
echo "╚══════════════════════════════════════════╝"

runTest ./test-deterministic-tar.sh
runTest ./test-signer.sh
runTest ./test-verifier.sh
runTest ./test-end-to-end.sh

echo ""
echo "========================================"
if [ ${anyFailed} -eq 0 ]; then
    echo "✅ All tests passed!"
else
    echo "❌ Some tests failed"
fi
echo "========================================"

exit ${anyFailed}
