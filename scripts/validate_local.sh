#!/bin/bash

set -euo pipefail

repository_root=$(git rev-parse --show-toplevel)
cd "$repository_root"

simulator_destination=${PACEPROMPT_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5}
if [[ -n "${PACEPROMPT_VALIDATION_ROOT:-}" ]]; then
  validation_root=$PACEPROMPT_VALIDATION_ROOT
  mkdir -p "$validation_root"
else
  validation_root=$(mktemp -d "${TMPDIR:-/tmp}/paceprompt-local-validation.XXXXXX")
fi

production_derived_data="$validation_root/PacePromptDerivedData"
production_result="$validation_root/PacePrompt.xcresult"
production_coverage="$validation_root/PacePrompt.lcov"
release_derived_data="$validation_root/PacePromptReleaseDerivedData"
analysis_derived_data="$validation_root/PacePromptAnalyzeDerivedData"
evaluation_derived_data="$validation_root/PacePromptEvaluationDerivedData"
evaluation_result="$validation_root/PacePromptEvaluation.xcresult"

echo "PacePrompt complete local validation"
echo "  revision: $(git rev-parse HEAD)"
echo "  destination: $simulator_destination"
echo "  evidence: $validation_root"

test "$(xcodebuild -version | sed -n '1p')" = "Xcode 26.6"
test "$(xcodebuild -version | sed -n '2p')" = "Build version 17F113"
test "$(xcrun --sdk iphonesimulator --show-sdk-version)" = "26.5"

if rg -n '\.writeValue\(|submitRequestControlDiagnosticOnce|CoreBluetoothFTMSControlPointLink' PacePrompt; then
  echo "App source unexpectedly contains an executable Control Point write path" >&2
  exit 1
fi

python3 -B scripts/verify_import_resources.py
python3 -B Evaluation/WorkoutImport/Scoring/scorer.py \
  --root Evaluation/WorkoutImport verify-corpus
python3 -B -m unittest discover \
  -s Evaluation/WorkoutImport/Tests -v
python3 -B -m unittest discover \
  -s Evaluation/WorkoutImport/Summaries -p 'test_*.py' -v

uv run \
  --directory Evaluation/WorkoutImport/HostEval \
  --frozen \
  --python 3.13 \
  python -B -m unittest discover -s tests -v

xcodebuild \
  -project PacePrompt.xcodeproj \
  -scheme PacePrompt \
  -destination "$simulator_destination" \
  -derivedDataPath "$production_derived_data" \
  -resultBundlePath "$production_result" \
  -enableCodeCoverage YES \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  test

scripts/export_xcode_coverage.sh \
  "$production_derived_data" \
  "$production_coverage"

assert_read_only_binary() {
  local configuration=$1
  local binary=$2
  if nm -j "$binary" | rg 'CoreBluetoothFTMSControlPointLink|submitRequestControlDiagnosticOnce' >/dev/null; then
    echo "$configuration binary unexpectedly contains a Control Point diagnostic symbol" >&2
    exit 1
  fi
  if strings "$binary" | rg 'writeValue:forCharacteristic:type:|PACEPROMPT_ISSUE51|Send one Request Control' >/dev/null; then
    echo "$configuration binary unexpectedly contains a Control Point write path" >&2
    exit 1
  fi
}

debug_binary="$production_derived_data/Build/Products/Debug-iphonesimulator/PacePrompt.app/PacePrompt"
assert_read_only_binary "Debug" "$debug_binary"

xcodebuild \
  -project PacePrompt.xcodeproj \
  -scheme PacePrompt \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$release_derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

release_binary="$release_derived_data/Build/Products/Release-iphonesimulator/PacePrompt.app/PacePrompt"
assert_read_only_binary "Release" "$release_binary"

xcodebuild \
  -project PacePrompt.xcodeproj \
  -scheme PacePrompt \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$analysis_derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  analyze

xcodebuild \
  -project PacePrompt.xcodeproj \
  -scheme PacePromptEvaluation \
  -destination "$simulator_destination" \
  -derivedDataPath "$evaluation_derived_data" \
  -resultBundlePath "$evaluation_result" \
  CODE_SIGNING_ALLOWED=NO \
  test

python3 -B -m unittest discover \
  -s .agents/skills/codex-phase-accounting/tests -v

git diff --check

echo "Complete local validation passed."
echo "Evidence retained at: $validation_root"
