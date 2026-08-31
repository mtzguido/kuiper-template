# Kuiper project — agent instructions

This project verifies local F*/Pulse modules against a released Kuiper binary
package. Never vendor Kuiper, F*, Pulse, Karamel, or their source trees.

## Kuiper reference

The selected package is authoritative for Kuiper APIs and conventions. Run
`make -j$(nproc) prepare`, then read `.kuiper/README.md`,
`.kuiper/FOOTGUNS.txt`, and relevant examples under `.kuiper/src/` before
writing Kuiper code.

## Build and verify

Always run Make in parallel:

```bash
make -j$(nproc) prepare
make -j$(nproc) lint
make -j$(nproc) verify
make -j$(nproc) extract-all
make -j$(nproc) dist
```

`ADMIT=1` is for local exploration only. Final verification and CI must not use
it. Set `KUIPER_HOME=/path/to/package` to test with an existing packaged Kuiper
tree without replacing it.

## Source and generated output

- Put concrete CUDA extraction entry points in `src/extract/`.
- Put supporting specifications and implementations elsewhere under `src/`.
- List every source subdirectory in the nearest `fstar.include`.
- Use project-owned module names; do not shadow modules supplied by Kuiper.
- Treat `obj/`, `.kuiper/`, and `.tools/` as generated and untracked.
- Treat `dist/` as checked-in generated output; update it only with `make dist`.
- Run `make list-admits` and review every explicit trust marker.
