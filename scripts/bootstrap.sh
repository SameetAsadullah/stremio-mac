#!/usr/bin/env bash
# Downloads the Node.js runtime that runs Stremio's streaming server into Vendor/node/ (gitignored).
# Skips the download when the pinned version is already there. Safe to run again.
# The binary is for Apple Silicon only.
set -euo pipefail
cd "$(dirname "$0")/.."

NODE="v24.22.2"
# From https://nodejs.org/dist/$NODE/SHASUMS256.txt
NODE_SHA256="aa9549349e47dffaa42dcf95d6e06ade8c4bdafc980979883b88767670df385a"

verify() { echo "$1  $2" | shasum -a 256 -c - >/dev/null || { echo "Checksum mismatch: $2" >&2; rm -f "$2"; exit 1; }; }

if [ "$(uname -m)" != "arm64" ]; then
  echo "Only Apple Silicon is supported." >&2
  exit 1
fi

if [ "$(Vendor/node/node --version 2>/dev/null || true)" = "$NODE" ]; then
  echo "Node.js $NODE is ready."
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
name="node-$NODE-darwin-arm64"
echo "Downloading Node.js $NODE (about 45 MB)..."
curl -fL --silent --show-error -o "$work/node.tar.gz" "https://nodejs.org/dist/$NODE/$name.tar.gz"
verify "$NODE_SHA256" "$work/node.tar.gz"
tar -xzf "$work/node.tar.gz" -C "$work" "$name/bin/node"
mkdir -p Vendor/node
mv "$work/$name/bin/node" Vendor/node/node
echo "Node.js $NODE is ready."
