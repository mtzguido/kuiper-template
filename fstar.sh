#!/usr/bin/env bash

# Invoke F* with the same package and flags used by the Makefile.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
make_cmd=${MAKE:-make}
if command -v gmake >/dev/null 2>&1; then
    make_cmd=${MAKE:-gmake}
fi

fstar_output=$("$make_cmd" -sC "$script_dir" V=1 echo-fstar)
read -r -a fstar_command <<< "$fstar_output"
exec "${fstar_command[@]}" --already_cached '*' "$@"
