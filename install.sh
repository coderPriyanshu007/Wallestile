#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="CustomWallpaper"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
INSTALL_DIR="$CONFIG_HOME/quickshell/$APP_NAME"
CAELESTIA_USER="$CONFIG_HOME/caelestia/hypr-user.lua"
HYPR_USER="$CONFIG_HOME/hypr/hyprland.conf"
BEGIN_MARK="-- BEGIN CUSTOMWALLPAPER (managed by install.sh)"
END_MARK="-- END CUSTOMWALLPAPER"
BEGIN_CONF="# BEGIN CUSTOMWALLPAPER (managed by install.sh)"
END_CONF="# END CUSTOMWALLPAPER"
BACKUP_SUFFIX=".customwallpaper-backup-$(date +%Y%m%d-%H%M%S)"

info() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }

install_arch_package() {
    local package="$1"
    if has paru; then paru -S --needed "$package"
    elif has yay; then yay -S --needed "$package"
    else sudo pacman -S --needed "$package"
    fi
}

ensure_dependencies() {
    local missing=()
    has python3 || missing+=(python)
    has hyprctl || missing+=(hyprland)
    has qs || missing+=(quickshell-git)
    has caelestia || missing+=(caelestia-cli)
    ((${#missing[@]} == 0)) && return

    printf 'Missing required packages: %s\n' "${missing[*]}"
    [[ -t 0 ]] || die "Run this installer interactively to approve dependency installation."
    read -r -p "Install them now? [Y/n] " answer
    [[ ! "$answer" =~ ^[Nn]$ ]] || die "Dependencies were not installed."
    has pacman || die "Automatic dependency installation currently supports Arch/CachyOS. Install Python 3, Hyprland, Quickshell, and caelestia-cli, then rerun."
    local package
    for package in "${missing[@]}"; do
        info "Installing $package"
        install_arch_package "$package" || die "Could not install $package. Install it manually and rerun."
    done
}

remove_managed_block() {
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

configure_hyprland() {
    local target
    if [[ -f "$CONFIG_HOME/hypr/hyprland.lua" || -f "$CAELESTIA_USER" ]]; then
        target="$CAELESTIA_USER"
        mkdir -p -- "$(dirname -- "$target")"
        touch -- "$target"
        cp -- "$target" "$target$BACKUP_SUFFIX"
        remove_managed_block "$target" "$BEGIN_MARK" "$END_MARK"
        if grep -Eiq 'SUPER[[:space:]]*\+[[:space:]]*B' "$target"; then
            warn "An existing Super+B binding remains in $target. Remove or change it if Hyprland reports a conflict."
        fi
        {
            printf '\n%s\n' "$BEGIN_MARK"
            printf 'hl.bind("SUPER + B", hl.dsp.exec_cmd("qs -c CustomWallpaper"), { description = "Open Custom Wallpaper Selector" })\n'
            printf 'hl.layer_rule({ match = { namespace = "custom-wallpaper" }, animation = "fade", blur = true })\n'
            printf '%s\n' "$END_MARK"
        } >> "$target"
    else
        target="$HYPR_USER"
        [[ -f "$target" ]] || die "No Caelestia Lua or standard Hyprland configuration was found."
        cp -- "$target" "$target$BACKUP_SUFFIX"
        remove_managed_block "$target" "$BEGIN_CONF" "$END_CONF"
        if grep -Eiq 'bind[^#]*SUPER[^#]*,[[:space:]]*B[[:space:]]*,' "$target"; then
            warn "An existing Super+B binding remains in $target. Remove or change it if Hyprland reports a conflict."
        fi
        {
            printf '\n%s\n' "$BEGIN_CONF"
            printf 'bind = SUPER, B, exec, qs -c CustomWallpaper\n'
            printf 'layerrule = blur, namespace:custom-wallpaper\n'
            printf 'layerrule = animation fade, namespace:custom-wallpaper\n'
            printf '%s\n' "$END_CONF"
        } >> "$target"
    fi
    info "Configured Hyprland in $target (backup: $target$BACKUP_SUFFIX)"
}

install_files() {
    mkdir -p -- "$INSTALL_DIR"
    local file
    for file in shell.qml App.qml Selector.qml LayoutIcon.qml WallCard.qml fetch_wallpapers.py README.md uninstall.sh; do
        [[ -f "$SOURCE_DIR/$file" ]] || die "Installation source is incomplete: missing $file"
        if [[ "$SOURCE_DIR/$file" != "$INSTALL_DIR/$file" ]]; then
            install -m 0644 -- "$SOURCE_DIR/$file" "$INSTALL_DIR/$file"
        fi
    done
    chmod +x -- "$INSTALL_DIR/fetch_wallpapers.py" "$INSTALL_DIR/uninstall.sh"
}

main() {
    [[ ${EUID:-$(id -u)} -ne 0 ]] || die "Run as your desktop user, not root."
    ensure_dependencies
    install_files
    python3 -m py_compile "$INSTALL_DIR/fetch_wallpapers.py"
    if has qmllint; then
        local lint_output lint_status=0
        lint_output="$(qmllint "$INSTALL_DIR/shell.qml" "$INSTALL_DIR/App.qml" "$INSTALL_DIR/Selector.qml" "$INSTALL_DIR/LayoutIcon.qml" "$INSTALL_DIR/WallCard.qml" 2>&1)" || lint_status=$?
        if ((lint_status != 0)); then
            # Some Quickshell builds return 255 because qmllint cannot resolve
            # runtime-provided QML modules, while reporting no actual diagnostic.
            [[ -z "$lint_output" ]] || die "QML validation failed:\n$lint_output"
            warn "qmllint could not resolve the Quickshell runtime modules; no QML diagnostic was reported."
        fi
    else
        warn "qmllint is unavailable; runtime QML validation was skipped."
    fi
    configure_hyprland
    if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        hyprctl reload >/dev/null || warn "Hyprland reload failed; log out and back in to activate the binding."
    else
        warn "Hyprland is not running in this terminal; the binding activates next session."
    fi
    info "Installed successfully. Press Super+B to open CustomWallpaper."
}

main "$@"
