#!/bin/bash
set -e

TARGET="${1:-.}"
mkdir -p "$TARGET"
cd "$TARGET"

echo "=== Cloning AaveAPY repos to $(pwd) ==="

repos=(
  "https://github.com/0xPabloLI/aaveapy.git"
  "https://github.com/0xPabloLI/aave-protocol-analysis.git"
  "https://github.com/0xPabloLI/aaveapy-doc.git"
)

for url in "${repos[@]}"; do
  dir=$(basename "$url" .git)
  if [ -d "$dir" ]; then
    echo "[skip] $dir already exists"
  else
    echo "[clone] $url"
    git clone "$url"
  fi
done

echo ""
echo "=== Done ==="
echo "Directory structure:"
ls -d */ 2>/dev/null
echo ""
echo "Verify symlinks:"
for d in aaveapy aave-protocol-analysis; do
  if [ -L "$d/aaveapy-doc" ]; then
    echo "  $d/aaveapy-doc -> $(readlink "$d/aaveapy-doc")"
  else
    echo "  WARNING: $d/aaveapy-doc is not a symlink"
  fi
done