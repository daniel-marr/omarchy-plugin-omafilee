#!/usr/bin/env bash
# Development install: copy this checkout into Omarchy's user plugin folder
# (the shell refuses symlinked plugin folders) and enable it in the bar.
# End users install with `omarchy plugin add <repo-url>` instead (README.md).
set -euo pipefail

id="daniel-marr.omafilee"
src=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
dest="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$id"
files=(manifest.json BarWidget.qml Converter.qml FileeModel.js LICENSE NOTICE.md README.md)

mkdir -p "$dest"
for f in "${files[@]}"; do install -m 644 "$src/$f" "$dest/$f"; done
[[ -f "$src/preview.png" ]] && install -m 644 "$src/preview.png" "$dest/preview.png"
omarchy plugin validate "$dest"

if ! command -v filee >/dev/null && [[ ! -x "$HOME/.local/bin/filee" ]]; then
  echo "Note: the filee CLI is not installed yet; see README.md." >&2
fi

enabled() {
  omarchy plugin list --json | python3 -c \
    'import json, sys; sys.exit(0 if any(p.get("id") == sys.argv[1] and p.get("enabled") for p in json.load(sys.stdin)) else 1)' "$id"
}

if [[ "${1:-}" != "--no-enable" ]] && ! enabled; then
  omarchy plugin enable "$id"
fi
echo "Installed to $dest"
