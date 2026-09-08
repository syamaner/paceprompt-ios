#!/bin/bash

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 <derived-data-path> <output-lcov-path>" >&2
  exit 64
fi

derived_data_path=${1%/}
output_lcov_path=$2
profile_data_root="$derived_data_path/Build/ProfileData"
production_app="$derived_data_path/Build/Products/Debug-iphonesimulator/PacePrompt.app"

profile_data_paths=()
while IFS= read -r -d '' profile_data_path; do
  profile_data_paths+=("$profile_data_path")
done < <(find "$profile_data_root" -type f -name Coverage.profdata -print0)

if [[ "${#profile_data_paths[@]}" -ne 1 ]]; then
  echo "expected exactly one Coverage.profdata under $profile_data_root; found ${#profile_data_paths[@]}" >&2
  exit 1
fi

coverage_objects=()
for candidate in \
  "$production_app/PacePrompt.debug.dylib" \
  "$production_app/PacePrompt"; do
  if [[ -f "$candidate" ]] && xcrun llvm-cov show \
    -instr-profile "${profile_data_paths[0]}" \
    "$candidate" >/dev/null 2>&1; then
    coverage_objects+=("$candidate")
  fi
done

if [[ "${#coverage_objects[@]}" -ne 1 ]]; then
  echo "expected exactly one instrumented production coverage object; found ${#coverage_objects[@]}" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_lcov_path")"
xcrun llvm-cov export \
  -format=lcov \
  -instr-profile "${profile_data_paths[0]}" \
  -ignore-filename-regex='(^|/)(PacePromptTests|PacePromptUITests|Evaluation|design|docs)/|(^|/)PacePrompt/Presentation/(Home|Plans)UITestSupport\.swift$' \
  "${coverage_objects[0]}" > "$output_lcov_path"

if [[ ! -s "$output_lcov_path" ]]; then
  echo "coverage export is empty: $output_lcov_path" >&2
  exit 1
fi

if ! grep -Eq '^SF:.*/PacePrompt/.*\.swift$' "$output_lcov_path"; then
  echo "coverage export contains no production PacePrompt Swift sources" >&2
  exit 1
fi

if grep -Eq '^SF:.*(/PacePromptTests/|/PacePromptUITests/|/Evaluation/|/design/|/docs/|/PacePrompt/Presentation/(Home|Plans)UITestSupport\.swift$)' "$output_lcov_path"; then
  echo "coverage export contains an excluded source path" >&2
  exit 1
fi

echo "exported production coverage to $output_lcov_path"
