#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
target="$config_root/omarchy/plugins/developer.workspace"
for dependency in python3 omarchy omarchy-shell; do
  command -v "$dependency" >/dev/null || { echo "Missing dependency: $dependency" >&2; exit 1; }
done
if [[ -d "$target" ]]; then
  backup="$config_root/omarchy/backups/developer-workspace-$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$(dirname "$backup")"
  cp -a "$target" "$backup"
  echo "Previous version backed up to $backup"
fi
mkdir -p "$target"
for name in Developer.qml ListSync.js backend.py manifest.json; do
  install -m 644 "$source_dir/plugin/$name" "$target/$name"
done
# Retain the user's project roots on updates.
if [[ ! -f "$target/config.json" ]]; then
  install -m 644 "$source_dir/plugin/config.json" "$target/config.json"
fi
omarchy-shell shell rescanPlugins
omarchy plugin enable developer.workspace
printf '\nInstalled. Open projects:\n  omarchy-shell shell summon developer.workspace\n'
printf "\nOpen services:\n  omarchy-shell shell summon developer.workspace '{\"mode\":\"services\"}'\n"
printf '\nSee README.md for optional keyboard shortcuts and a bar launcher.\n'
