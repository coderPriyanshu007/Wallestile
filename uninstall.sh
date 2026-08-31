#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BEGIN_LUA="-- BEGIN CUSTOMWALLPAPER (managed by install.sh)"
END_LUA="-- END CUSTOMWALLPAPER"
BEGIN_CONF="# BEGIN CUSTOMWALLPAPER (managed by install.sh)"
END_CONF="# END CUSTOMWALLPAPER"

strip_block() {
    local file="$1" begin="$2" end="$3" tmp
    [[ -f "$file" ]] || return 0
    tmp="$(mktemp)"
    awk -v begin="$begin" -v end="$end" '
        $0 == begin { skipping=1; next }
        $0 == end { skipping=0; next }
        !skipping { print }
    ' "$file" > "$tmp"
    chmod --reference="$file" "$tmp" 2>/dev/null || true
    mv -- "$tmp" "$file"
}

strip_block "$CONFIG_HOME/caelestia/hypr-user.lua" "$BEGIN_LUA" "$END_LUA"
strip_block "$CONFIG_HOME/hypr/hyprland.conf" "$BEGIN_CONF" "$END_CONF"

# Deliberately preserve ~/.local/share/custom-wallpaper/current selection: it may
# still be the desktop wallpaper. Pass --purge to remove it as well.
if [[ ${1:-} == "--purge" ]]; then
    rm -rf -- "${XDG_DATA_HOME:-$HOME/.local/share}/custom-wallpaper"
fi

install_dir="$CONFIG_HOME/quickshell/CustomWallpaper"
if [[ -d "$install_dir" ]]; then
    rm -rf -- "$install_dir"
fi

if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null; then
    hyprctl reload >/dev/null || true
fi
printf 'CustomWallpaper uninstalled. Configuration backups were preserved.\n'
