#!/usr/bin/env bash

# Install a Kuiper binary package from GitHub releases.
main() {

set -euo pipefail

release_repo=FStarLang/kuiper
nightly_repo=FStarLang/kuiper

usage() {
  cat <<'EOF'
Usage: install-kuiper.sh [OPTIONS]

Source:
  --release            Install an official release (default)
  --nightly            Install a nightly build

Version:
  --version VER        Select a tag (release) or YYYY-MM-DD (nightly)

Destination:
  --dest DIR           Install into DIR (default: ~/.local/kuiper)
  --link-dir DIR       Link bundled tools into DIR (default: ~/.local/bin)
  --no-link            Do not create tool links

Other:
  --list               List available versions and exit
  -v, --verbose        Trace commands
  -h, --help           Show this help
EOF
}

source_kind=release
version=latest
dest="$HOME/.local/kuiper"
link_dir="$HOME/.local/bin"
do_link=true
verbose=false
list=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) source_kind=release; shift ;;
    --nightly) source_kind=nightly; shift ;;
    --version)
      [[ $# -ge 2 ]] || { echo "Error: --version requires a value" >&2; exit 2; }
      version=$2
      shift 2
      ;;
    --dest)
      [[ $# -ge 2 ]] || { echo "Error: --dest requires a value" >&2; exit 2; }
      dest=$2
      shift 2
      ;;
    --link-dir)
      [[ $# -ge 2 ]] || { echo "Error: --link-dir requires a value" >&2; exit 2; }
      link_dir=$2
      shift 2
      ;;
    --no-link) do_link=false; shift ;;
    --list) list=true; shift ;;
    -v|--verbose) verbose=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if $verbose; then
  set -x
fi

github_curl() {
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

json_field() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" |
    head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true
}

json_fields() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" |
    sed 's/.*:[[:space:]]*"//;s/"$//' || true
}

list_versions() {
  local repository json tags count page
  case "$source_kind" in
    release) repository=$release_repo ;;
    nightly) repository=$nightly_repo ;;
  esac

  echo "Available versions ($source_kind):"
  echo
  for page in 1 2 3; do
    json=$(github_curl \
      "https://api.github.com/repos/$repository/releases?per_page=30&page=$page")
    tags=$(printf '%s' "$json" | json_fields tag_name)
    if [[ "$source_kind" == nightly ]]; then
      tags=$(printf '%s\n' "$tags" | grep '^nightly-' || true)
    fi
    [[ -n "$tags" ]] || break
    printf '%s\n' "$tags"
    count=$(printf '%s' "$json" | grep -c '"tag_name"' || true)
    (( count >= 30 )) || break
  done
}

if $list; then
  list_versions
  exit 0
fi

for tool in curl tar; do
  command -v "$tool" >/dev/null || {
    echo "Error: '$tool' is required." >&2
    exit 1
  }
done

kernel=$(uname -s)
case "$kernel" in
  CYGWIN*|MINGW*|MSYS*) kernel=Windows_NT ;;
esac
arch=$(uname -m)

asset_filename() {
  local selected_tag=$1
  case "$source_kind" in
    release) echo "kuiper-${selected_tag}-${kernel}-${arch}.tar.gz" ;;
    nightly) echo "kuiper-${kernel}-${arch}.tar.gz" ;;
  esac
}

asset_url() {
  local selected_tag=$1 repository filename
  case "$source_kind" in
    release) repository=$release_repo ;;
    nightly) repository=$nightly_repo ;;
  esac
  filename=$(asset_filename "$selected_tag")
  echo "https://github.com/${repository}/releases/download/${selected_tag}/${filename}"
}

resolve_tag() {
  if [[ "$version" != latest ]]; then
    case "$source_kind" in
      release) tag=$version ;;
      nightly)
        [[ "$version" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
          echo "Error: nightly versions must use YYYY-MM-DD." >&2
          exit 2
        }
        tag=nightly-$version
        ;;
    esac
    return
  fi

  local repository json
  case "$source_kind" in
    release)
      repository=$release_repo
      json=$(github_curl \
        "https://api.github.com/repos/$repository/releases/latest")
      tag=$(printf '%s' "$json" | json_field tag_name)
      ;;
    nightly)
      repository=$nightly_repo
      json=$(github_curl \
        "https://api.github.com/repos/$repository/releases?per_page=50")
      tag=$(printf '%s' "$json" | json_fields tag_name |
        grep '^nightly-' | head -1)
      ;;
  esac
  [[ -n "$tag" ]] || {
    echo "Error: could not resolve the latest $source_kind package." >&2
    exit 1
  }
}

echo "Looking for Kuiper $source_kind ($version) for ${kernel}-${arch}..."
tag=
resolve_tag
url=$(asset_url "$tag")
asset_name=$(basename "$url")
echo "Downloading $tag ($asset_name)..."

workdir=$(mktemp -d)
cleanup() {
  rm -rf -- "$workdir"
}
trap cleanup EXIT

curl -fL "$url" -o "$workdir/$asset_name" || {
  echo "Error: no Kuiper package was found at $url" >&2
  exit 1
}

case "$dest" in
  ''|/) echo "Error: refusing unsafe installation destination '$dest'." >&2; exit 2 ;;
esac

stage=$workdir/stage
mkdir -p "$stage"
tar xzf "$workdir/$asset_name" --strip-components=1 -C "$stage"
[[ -x "$stage/inst/bin/fstar.exe" && -f "$stage/.packaged" ]] || {
  echo "Error: downloaded archive is not a packaged Kuiper tree." >&2
  exit 1
}

if [[ -e "$dest" ]]; then
  echo "Replacing the package at $dest..."
  rm -rf -- "$dest"
fi
mkdir -p "$(dirname -- "$dest")"
mv "$stage" "$dest"
echo "Installed Kuiper $tag in $dest."

if $do_link; then
  mkdir -p "$link_dir"
  for binary in "$dest/inst/bin/"*; do
    [[ -f "$binary" ]] || continue
    name=$(basename "$binary")
    ln -sf "$(realpath "$binary")" "$link_dir/$name"
  done
  echo "Linked bundled tools into $link_dir."
fi

} # main

main "$@"
