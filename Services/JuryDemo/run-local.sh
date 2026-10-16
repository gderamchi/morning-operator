#!/bin/sh
set -eu

service_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
env_file=${1:-"$service_dir/.env"}
if [ ! -r "$env_file" ]; then
  printf '%s\n' 'Private environment file missing. Copy .env.example to .env and fill the connections.' >&2
  exit 1
fi
env_dir=$(CDPATH= cd -- "$(dirname -- "$env_file")" && pwd)
env_file="$env_dir/$(basename -- "$env_file")"
if ! command -v node >/dev/null 2>&1; then
  printf '%s\n' 'Node.js 22.9 or later is required.' >&2
  exit 1
fi
node --eval 'const [major, minor] = process.versions.node.split(".").map(Number); if (major < 22 || (major === 22 && minor < 9)) { console.error("Node.js 22.9 or later is required."); process.exit(1); }'
cd "$service_dir"
exec node --env-file="$env_file" "$service_dir/server.mjs"
