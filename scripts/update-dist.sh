#!/usr/bin/env bash

# Synchronize checked-in CUDA with obj/ without creating timestamp-only diffs.
set -euo pipefail
shopt -s nullglob

generated=(obj/*.cu obj/*.h)
if (( ${#generated[@]} == 0 )); then
  echo "Error: obj/ contains no extracted CUDA; run make extract-all." >&2
  exit 1
fi

mkdir -p dist
changed=0
for source in "${generated[@]}"; do
  name=$(basename "$source")
  if [[ ! -f "dist/$name" ]] || ! cmp -s "$source" "dist/$name"; then
    changed=1
    break
  fi
done

existing=(dist/*.cu dist/*.h)
if (( changed == 0 )); then
  for destination in "${existing[@]}"; do
    name=$(basename "$destination")
    if [[ ! -f "obj/$name" ]]; then
      changed=1
      break
    fi
  done
fi

if (( changed == 0 )); then
  echo "dist/ is up to date."
  exit 0
fi

if (( ${#existing[@]} > 0 )); then
  rm -f -- "${existing[@]}"
fi
cp -- "${generated[@]}" dist/

kuiper_home=${KUIPER_HOME:-$PWD/.kuiper}
kuiper_build=unknown
if [[ -f "$kuiper_home/BUILD_INFO" ]]; then
  kuiper_build=$(sed -n \
    's/^Kuiper commit:[[:space:]]*//p' "$kuiper_home/BUILD_INFO")
fi

{
  echo "Generated using the selected Kuiper binary package"
  echo "Kuiper commit: $kuiper_build"
} > dist/BUILD_INFO

echo "dist/ updated."
