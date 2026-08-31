# Kuiper package template

This is a small, working template for a project built on
[Kuiper](https://github.com/FStarLang/kuiper). It downloads one pinned Kuiper
binary package, verifies local F*/Pulse modules against its checked library,
extracts concrete entry points to CUDA, and keeps reproducible generated output
under `dist/`.

The template includes a verified increment kernel so the entire pipeline works
before you add project code.

## Requirements

- A 64-bit Linux or macOS machine supported by the selected Kuiper package
- GNU Make 4.4 or newer (`gmake` on macOS)
- Bash, curl, tar, Python 3, and standard Unix build tools

CUDA and an NVIDIA GPU are not needed for verification or extraction. They are
needed only when your project compiles or executes the generated CUDA.
For code that does not use tensor cores, define `KUIPER_CFG_TENSORCORES=0` when
compiling if the installed CUDA toolkit does not expose WMMA.

## Quick start

```bash
make -j$(nproc) prepare
make -j$(nproc)
make -j$(nproc) dist
```

On macOS, use `gmake -j$(sysctl -n hw.ncpu)` instead. The first command installs
the date pinned in `kuiper-version.txt` into the ignored `.kuiper/` directory
and installs the exact clang-format used for generated CUDA into `.tools/`.

Useful targets:

```bash
make -j$(nproc) verify       # verify all .fst and .fsti files under src/
make -j$(nproc) extract-all  # extract src/extract/*.fst into obj/
make -j$(nproc) dist         # synchronize checked-in dist/ with obj/
make -j$(nproc) dist-check   # update dist/ and fail if Git sees a difference
make -j$(nproc) lint         # check text hygiene and script permissions
make -j$(nproc) list-admits  # report explicit trust-related identifiers
```

Set `V=1` to show tool commands. Set `KUIPER_HOME=/path/to/kuiper-package` to
use an existing package without modifying it. `ADMIT=1` permits admitted SMT
queries for development, but must never be used for a final build.

## Adapting the template

1. Rename `src/extract/KuiperTemplate.Increment.fst` and its module declaration
   to a namespace owned by your project.
2. Keep concrete, monomorphic extraction roots in `src/extract/`; supporting
   modules may live anywhere below `src/`.
3. Run `make -j$(nproc) verify extract-all dist` and commit the resulting
   sources in `dist/`.
4. Replace this README text and add the license appropriate for your project.

F* dependency generation automatically discovers every local `.fst` and
`.fsti`. Extraction automatically discovers implementations directly or
recursively under `src/extract/`. Module filenames must follow F* module naming
and should not contain underscores, because extracted filenames encode module
dots as underscores. When adding another source subdirectory, also list it in
the nearest `fstar.include` so F* can resolve and cache its modules correctly.

After preparation, consult `.kuiper/README.md`, `.kuiper/FOOTGUNS.txt`, and the
matching sources under `.kuiper/src/`. Those files are the authority for the
pinned compiler and Kuiper API; this repository deliberately does not copy the
Kuiper source tree.

## Reproducibility and CI

`dist/` is formatted with clang-format 19.1.7 using `.clang-format`. The
formatter wheel is selected by platform and checked against a recorded SHA-256
digest. `dist/BUILD_INFO` records the Kuiper commit used when generated CUDA
changes.

GitHub Actions in `.github/workflows/ci.yml` caches the package by its nightly
date, lints, verifies without admissions, extracts, and fails if `dist/` is
stale. `.github/workflows/advance.yml` checks weekly for a newer nightly,
verifies it in an uncredentialed job, and opens or refreshes a pull request with
the new pin and generated-output patch. Review those pull requests before
merging; package updates can change proofs or generated code.

The included CI verifies and extracts but does not run GPU tests. Add a separate
CUDA runner or build job for project-specific compilation and runtime tests.

## Layout

- `src/extract/`: verified concrete entry points selected for CUDA extraction
- `dist/`: checked-in, reproducibly generated `.cu` and `.h` files
- `scripts/`: pinned installers, linter, and dist synchronizer; the trust
  scanner comes from the selected Kuiper package
- `.kuiper/`: ignored Kuiper binary package selected by `kuiper-version.txt`
- `.tools/`: ignored pinned formatter
- `obj/`: ignored verification cache and intermediate extraction output
