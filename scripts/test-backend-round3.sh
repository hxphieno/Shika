#!/bin/bash
# Freeze production sources and run independent algorithm/routing acceptance.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:?usage: test-backend-round3.sh output-directory}"
mkdir -p "$output/sources"
cp ShikaKeyBoard/Core/SKInputConfiguration.swift ShikaKeyBoard/Core/SKInputEngine.swift \
  ShikaKeyBoard/Engine/SKSpellingCorrector.swift ShikaKeyBoard/Engine/SKCorrectionCandidates.swift \
  ShikaKeyBoard/Engine/SKLearnedSpellingIndex.swift Tests/BackendRound3*Checks.swift "$output/sources/"
shasum -a 256 "$output/sources/"* > "$output/source-hashes.txt"
shared=("$output/sources/SKInputConfiguration.swift" "$output/sources/SKInputEngine.swift"
  "$output/sources/SKSpellingCorrector.swift" "$output/sources/SKCorrectionCandidates.swift"
  "$output/sources/SKLearnedSpellingIndex.swift")
for name in SearchOracle LearnedOracle Candidate; do
  xcrun swiftc -O -whole-module-optimization -module-cache-path "$output/module-cache" -parse-as-library \
    "${shared[@]}" "$output/sources/BackendRound3${name}Checks.swift" -o "$output/$name-runner"
  if [[ "$name" == Candidate ]]; then
    "$output/$name-runner" "$output/$name-fixtures" "$output/$name.json" --memoized
  else
    "$output/$name-runner" "$output/$name-fixtures" "$output/$name.json"
  fi
done
