#!/usr/bin/env bash
#
# theme-switch.sh
# Pick a Catppuccin flavor + accent with fuzzel, apply it to
# alacritty, btop, fuzzel, mako, waybar, sway, bat, starship,
# swaylock, and GTK/GNOME (light/dark from flavor, theme color from
# accent via a Yaru mapping), then reload what can be reloaded live.

set -euo pipefail

CONFIG_DIR="$HOME/.config"

FLAVORS=(latte mocha macchiato frappe)
ACCENTS=(rosewater flamingo pink mauve red maroon peach yellow green teal sky sapphire blue lavender)

flavor=$(printf '%s\n' "${FLAVORS[@]}" | fuzzel --dmenu --prompt="Flavor: ")
[[ -z "${flavor:-}" ]] && exit 0

accent=$(printf '%s\n' "${ACCENTS[@]}" | fuzzel --dmenu --prompt="Accent: ")
[[ -z "${accent:-}" ]] && exit 0

# --- Alacritty (flavor only) ---
sed -i "s#themes/catppuccin-[a-z]*\.toml#themes/catppuccin-${flavor}.toml#" \
  "$CONFIG_DIR/alacritty/alacritty.toml"

# --- btop (flavor only) ---
sed -i "s#themes/catppuccin_[a-z]*\.theme#themes/catppuccin_${flavor}.theme#" \
  "$CONFIG_DIR/btop/btop.conf"

# --- fuzzel (flavor + accent) ---
sed -i "s#themes/catppuccin-[a-z]*/[a-z]*\.ini#themes/catppuccin-${flavor}/${accent}.ini#" \
  "$CONFIG_DIR/fuzzel/fuzzel.ini"

# --- mako (flavor + accent) ---
sed -i "s#themes/catppuccin-[a-z]*/catppuccin-[a-z]*-[a-z]*#themes/catppuccin-${flavor}/catppuccin-${flavor}-${accent}#" \
  "$CONFIG_DIR/mako/config"

# --- waybar (flavor only) ---
sed -i "s#themes/[a-z]*\.css#themes/${flavor}.css#" \
  "$CONFIG_DIR/waybar/style.css"

# --- sway (flavor only) ---
sed -i "s#themes/catppuccin-[a-z]*#themes/catppuccin-${flavor}#" \
  "$CONFIG_DIR/sway/config"

# --- bat (flavor only; theme names are capitalized in bat's --list-themes) ---
declare -A BAT_FLAVOR=(
  [latte]="Latte"
  [mocha]="Mocha"
  [macchiato]="Macchiato"
  [frappe]="Frappe"
)
sed -i "s#--theme=\"Catppuccin [A-Za-z]*\"#--theme=\"Catppuccin ${BAT_FLAVOR[$flavor]}\"#" \
  "$CONFIG_DIR/bat/config"

# --- starship (flavor only) ---
sed -i "s#palette = \"catppuccin_[a-z]*\"#palette = \"catppuccin_${flavor}\"#" \
  "$CONFIG_DIR/starship.toml"

# --- swaylock (flavor only) ---
# swaylock's config has no include directive, so we keep any base
# settings (e.g. "daemonize") above a marker line, and replace
# everything below the marker with the chosen theme's colors.
SWAYLOCK_CONF="$CONFIG_DIR/swaylock/config"
SWAYLOCK_MARKER="# --- theme (managed by catppuccin-switch.sh) ---"

awk -v marker="$SWAYLOCK_MARKER" '$0==marker{exit} {print}' "$SWAYLOCK_CONF" >"${SWAYLOCK_CONF}.tmp"
{
  cat "${SWAYLOCK_CONF}.tmp"
  echo "$SWAYLOCK_MARKER"
  cat "$CONFIG_DIR/swaylock/themes/${flavor}.conf"
} >"$SWAYLOCK_CONF"
rm -f "${SWAYLOCK_CONF}.tmp"

# --- GTK / GNOME (light for latte, dark otherwise; accent maps to closest Yaru variant) ---
declare -A ACCENT_YARU=(
  [rosewater]="wartybrown"
  [flamingo]="red"
  [pink]="magenta"
  [mauve]="purple"
  [red]="red"
  [maroon]="red"
  [peach]=""
  [yellow]="yellow"
  [green]="sage"
  [teal]="prussiangreen"
  [sky]="blue"
  [sapphire]="prussiangreen"
  [blue]="blue"
  [lavender]="purple"
)

yaru_suffix="${ACCENT_YARU[$accent]}"
if [[ -n "$yaru_suffix" ]]; then
  base_theme="Yaru-${yaru_suffix}"
else
  base_theme="Yaru"
fi

if [[ "$flavor" == "latte" ]]; then
  gtk_theme="$base_theme"
  icon_theme="$base_theme"
  gsettings set org.gnome.desktop.interface color-scheme 'default'
else
  gtk_theme="${base_theme}-dark"
  icon_theme="${base_theme}-dark"
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
fi

gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
gsettings set org.gnome.desktop.interface icon-theme "$icon_theme"

# --- Reload what supports it live ---

# alacritty: reloads on its own if live_config_reload isn't disabled

# mako: reload its config via systemd (unit's ExecReload runs makoctl reload)
systemctl --user reload mako.service 2>/dev/null || true

# waybar: restart whichever compositor variant is active
if systemctl --user is-active --quiet waybar-niri.service; then
  systemctl --user restart waybar-niri.service
elif systemctl --user is-active --quiet waybar-sway.service; then
  systemctl --user restart waybar-sway.service
fi

# sway: reload config live if the compositor in use is sway (not niri)
if [[ "${XDG_CURRENT_DESKTOP:-}" == "sway" ]] || pgrep -x sway >/dev/null 2>&1; then
  swaymsg reload 2>/dev/null || true
fi

# btop has no reload signal; it picks up the new theme next launch

# bat needs no reload; it re-reads its config on every invocation

# starship needs no reload; it re-reads starship.toml on every prompt

# swaylock needs no reload; it reads config fresh each time it's launched

# GTK/GNOME: gsettings changes apply immediately, no reload needed

notify-send "Catppuccin" "Switched to ${flavor} / ${accent}" 2>/dev/null || true
