#!/usr/bin/env bash
set -euo pipefail

resource=${1:?Usage: publish-resource.sh RESOURCE OSS_DIRECTORY}
oss_directory=${2:?Usage: publish-resource.sh RESOURCE OSS_DIRECTORY}

case "$resource" in
  scripts|vllm-recipes|featured-models) ;;
  *) printf 'Unsupported resource: %s\n' "$resource" >&2; exit 1 ;;
esac

if [[ ! "$oss_directory" =~ ^oss://[a-z0-9][a-z0-9-]+[a-z0-9]/[^[:space:]]+/$ ]]; then
  printf 'OSS directory must be oss://bucket/path/ with no whitespace and a trailing slash.\n' >&2
  exit 1
fi

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source_dir="$repo_dir/$resource"
test -s "$source_dir/data.yaml"
command -v ossutil >/dev/null

upload_dir=$(mktemp -d)
trap 'rm -rf "$upload_dir"' EXIT
cp "$source_dir/data.yaml" "$upload_dir/data.yaml"

if [[ "$resource" == scripts ]]; then
  # Existing clients read scripts/sh/<key>.sh inside scripts.tar.gz.
  mkdir -p "$upload_dir/package/scripts/sh"
  cp "$source_dir/"*.sh "$upload_dir/package/scripts/sh/"
  COPYFILE_DISABLE=1 tar -czf "$upload_dir/scripts.tar.gz" -C "$upload_dir/package" scripts
fi

if [[ "$resource" == vllm-recipes ]]; then
  # Clients read vllm-recipes/sh/<key>.sh inside vllm-recipes.tar.gz.
  mkdir -p "$upload_dir/package/vllm-recipes/sh"
  cp "$source_dir/"*.sh "$upload_dir/package/vllm-recipes/sh/"
  # Strip a leading UTF-8 BOM from packaged scripts, preserving all other bytes.
  python3 - "$upload_dir/package/vllm-recipes/sh" <<'PY'
import codecs
import sys
from pathlib import Path

for script in Path(sys.argv[1]).glob("*.sh"):
    content = script.read_bytes()
    if content.startswith(codecs.BOM_UTF8):
        script.write_bytes(content[len(codecs.BOM_UTF8):])
PY
  COPYFILE_DISABLE=1 tar -czf "$upload_dir/vllm-recipes.tar.gz" -C "$upload_dir/package" vllm-recipes
fi

# Preserve the existing Unix timestamp version format, without a trailing newline.
version=$(date +%s)
printf '%s' "$version" > "$upload_dir/version.txt"

if [[ "$resource" == scripts ]]; then
  ossutil cp -f "$upload_dir/scripts.tar.gz" "${oss_directory}scripts.tar.gz"
fi
if [[ "$resource" == vllm-recipes ]]; then
  ossutil cp -f "$upload_dir/vllm-recipes.tar.gz" "${oss_directory}vllm-recipes.tar.gz"
fi
ossutil cp -f "$upload_dir/data.yaml" "${oss_directory}data.yaml"
# A failed payload upload must not publish a new version marker.
ossutil cp -f "$upload_dir/version.txt" "${oss_directory}version.txt"

printf 'Published %s version %s to %s\n' "$resource" "$version" "$oss_directory"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf 'Published **%s** version `%s` to `%s`.\n' \
    "$resource" "$version" "$oss_directory" >> "$GITHUB_STEP_SUMMARY"
fi
