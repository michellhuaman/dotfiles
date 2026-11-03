# dotfiles

My Fedora Sway Atomic setup (Fedora's preconfigured sway, themed with
Catppuccin), managed with [chezmoi](https://www.chezmoi.io/).

This repo is the user half of the setup. The system half (layered packages,
COPRs, third-party repos, and installing Bitwarden and chezmoi) is in
[workstation-bootstrap](https://github.com/michellhuaman/workstation-bootstrap),
whose `setup.sh` clones and applies this repo on a new machine.

The dividing line is **sudo**: everything here installs into the home folder,
so `chezmoi apply` never asks for a password.

## Layout

```
.chezmoi.toml.tmpl      per-machine settings, asked once by `chezmoi init` (Git name/email)
.chezmoiignore          repo files that are not copied to ~ (this README)
.chezmoidata/
  packages.yaml         flatpaks, Nerd Font version, mise version and checksums, systemd user units
.chezmoiexternal.toml.tmpl  downloads mise itself (pinned, checksum-verified)
.chezmoiscripts/        run by `chezmoi apply`, in number order
  run_onchange_after_20-install-flatpaks.sh.tmpl    reruns when the flatpak list changes
  run_onchange_after_25-install-cli-tools.sh.tmpl   mise install + prune; reruns when the mise config changes
  run_onchange_after_30-install-fonts.sh.tmpl       Nerd Font, bat cache
  run_onchange_after_35-distrobox.sh.tmpl           builds the distrobox containers; reruns when assemble.ini changes
  run_onchange_after_40-enable-services.sh.tmpl     enables the user units in packages.yaml
  run_once_after_50-default-theme.sh.tmpl           dark theme on the first apply only
  run_onchange_after_55-theme-links.sh.tmpl         points the sway desktop's theme links at the current flavor
.chezmoitemplates/      starship.toml, the one config whose theme line is edited in place (see "Themes")
dot_bash_profile, dot_bashrc
dot_gitconfig.tmpl      uses the name/email from .chezmoi.toml.tmpl
private_dot_ssh/        ~/.ssh/config: Bitwarden's agent for every host
dot_config/             ~/.config (Alacritty, bat, btop, mise, Neovim, starship, tmux, systemd, ...)
  sway/config.d/        drop-ins on top of Fedora's sway config: keyboard layouts, workspaces per
                        monitor, thin borders, wallpaper, night light, floating blueman and Bitwarden, keybindings, Catppuccin colors
  autostart/            apps started at login: Bitwarden (the SSH agent) and Brave
  distrobox/assemble.ini  the distrobox containers (see "Containers")
  waybar/config.jsonc  Fedora's waybar config plus a few module settings
  waybar, dunst, rofi, swaylock   Catppuccin for the rest of the sway desktop
dot_local/bin/          theme-toggle.sh, ddc-brightness.sh, powermenu.sh
dot_local/private_share/themes/   Adwaita-dark for GTK3 apps (Thunar), missing on Sway Atomic
dot_local/private_share/applications/nvim.desktop   Neovim in rofi and "Open With" (mise installs no app entry)
dot_local/private_share/xfce4/helpers/, dot_config/xfce4/helpers.rc   Alacritty for Thunar's "Open Terminal Here"
```

chezmoi turns source names into real ones: `dot_` becomes `.`, `private_`
means only you can read it, `executable_` makes it executable, `.tmpl` means
it's a template, and `modify_` means a template that edits the existing file
(see "Themes").

## Editing dotfiles

The source of truth is this repo, at `~/.local/share/chezmoi`. Files in `~`
(`~/.bashrc`, `~/.config/...`) are output: chezmoi writes them from here and
overwrites them on apply. So changes are made here, never directly in `~`.

### The workflow

**1. Edit and apply**, using the file's real path in your home folder:

```bash
edot ~/.config/alacritty/alacritty.toml
```

`edot` (a function in `.bashrc`) opens the right source file in `$EDITOR` and
applies the change when you quit:

- for most files it runs `chezmoi edit --apply`;
- for `~/.config/starship.toml` it opens its template in `.chezmoitemplates/`
  instead, which is where that config lives (see "Themes"). Plain
  `chezmoi edit` would open the wrong file for it.

**2. Commit and push:**

```bash
chezmoi git -- diff                     # optional: review what you're committing
chezmoi git -- add -A && chezmoi git -- commit -m "What changed" && chezmoi git -- push
```

**3. Pull on the other machines:**

```bash
chezmoi update                          # git pull + apply
```

You can commit at any time: theme toggles never count as changes (see
"Themes"), so there's no need to switch to dark first.

### Other situations

**A change that started in `~`**, for example a tweak tested directly in
`~/.config` or a setting saved from inside an app:

```bash
chezmoi diff          # see what differs from the repo
chezmoi re-add        # copy the changed files into the repo
```

then continue from step 2. `re-add` skips templates and `starship.toml`; for
those, copy the change into the template with `edot` instead.
To throw a change away, run `chezmoi apply`, which puts the repo's version
back.

**A new file to track:**

```bash
chezmoi add ~/.config/newapp/config
```

then step 2.

**Something that isn't a single config file:**

| Change | Where | Then |
| --- | --- | --- |
| a Flatpak app | `packages.flatpak` in `.chezmoidata/packages.yaml` (the whole set: per-user apps not listed are uninstalled, their data kept) | `chezmoi apply` installs or uninstalls it |
| a sway keybinding | `dot_config/sway/config.d/70-bindings.conf` (replaces Fedora's binding for the same keys) | `chezmoi apply`, then `$mod+Shift+c` (reload) |
| a CLI tool, or a newer version of one | `edot ~/.config/mise/config.toml` (exact versions; `mise outdated --bump` lists newer ones) | applied on save: installed, and anything no longer listed is pruned |
| a new mise release | `mise.version` and both `mise.sha256` lines in `.chezmoidata/packages.yaml` | `chezmoi apply` downloads and verifies it |
| a new Nerd Font release | `fonts.nerd_fonts` in `.chezmoidata/packages.yaml` | `chezmoi apply` downloads it |
| a systemd user unit | the unit in `dot_config/systemd/user/`, its name in `services.user` | `chezmoi apply` enables it |
| a script, template or anything else in the repo | `chezmoi cd`, then edit the file (e.g. `vim .chezmoidata/packages.yaml`) | `chezmoi apply`, `exit` |
| an app or tool in the container | `edot ~/.config/distrobox/assemble.ini` (`additional_packages`, plus `exported_apps`/`exported_bins` to reach it from the host) | `chezmoi apply` rebuilds the container |
| a layered RPM or COPR | not here: workstation-bootstrap's lists | re-run its `setup.sh`, then reboot |

Each of these then goes through step 2 like any other change.

## Themes

`theme-toggle.sh` (`Super+Shift+T`) switches between light and dark: it sets
the desktop's color scheme (which GTK4/libadwaita apps and Brave follow) and
GTK theme, and switches every themed app between the Catppuccin flavors
(Latte for light, Mocha for dark). A new machine starts on Mocha, matching
the dark theme `run_once_after_50-default-theme.sh.tmpl` sets.

GTK and icon themes are set by `theme-toggle.sh` and the default-theme script:
Yaru on Ubuntu, Adwaita everywhere else (Fedora included). GTK3 apps (Thunar)
need the theme named `Adwaita-dark`, which Sway Atomic doesn't ship, so
`~/.local/share/themes/Adwaita-dark` provides it.

### Theme links

Most apps use Catppuccin's own theme files (copied from the catppuccin/i3,
waybar, dunst, rofi, swaylock, alacritty, btop and bat repos), one per
flavor, under each app's `themes/` folder. Each config reads a "current" link
instead of naming a flavor:

| Config | Reads |
| --- | --- |
| `~/.config/sway/config.d/80-catppuccin.conf` | `~/.config/sway/themes/catppuccin-current` |
| `~/.config/waybar/style.css` | `~/.config/waybar/themes/catppuccin-current.css` |
| `~/.config/rofi/themes/catppuccin-default.rasi` | `~/.config/rofi/themes/catppuccin-current.rasi` |
| `~/.config/alacritty/alacritty.toml` | `~/.config/alacritty/themes/catppuccin-current.toml` |
| `~/.config/btop/btop.conf` | `~/.config/btop/themes/catppuccin_current.theme`. That's its only line, and the file is read-only, so settings changed in btop's menu last only until it quits |
| `~/.config/dunst/dunstrc.d/80-catppuccin.conf` | is the link itself (`../themes/<flavor>.conf`); `~/.config/dunst/dunstrc` exists only so dunst reads `dunstrc.d/` |
| `~/.config/swaylock/config` | is the link itself (`themes/<flavor>.conf`) |
| `~/.config/bat/config` | is the link itself (`config-mocha` / `config-latte`, the same apart from the theme: change both) |

`theme-toggle.sh` points the links at the other flavor, reloads sway (which
restarts waybar) and stops dunst (D-Bus starts it again for the next
notification) and touches `alacritty.toml`, which makes open Alacritty windows reload; rofi,
swaylock and btop read theirs when they start, and bat its config on every
run. chezmoi tracks the theme files but not the links, so the configs are
plain files you can edit directly, and a toggle never shows up as a
difference. On a new machine, `run_onchange_after_55-theme-links.sh.tmpl`
creates the links (`theme-toggle.sh links`) for the current mode.

The login screen (SDDM) follows too. Its themes and link are system files,
installed by workstation-bootstrap together with `/usr/local/bin/sddm-flavor`
and a sudoers rule that lets you run it without a password; `theme_links`
calls `sudo -n sddm-flavor <flavor>` when that helper exists, and only warns
if it fails. The login screen shows the new flavor the next time it starts.

(bat could pick a light or dark theme by itself from the terminal's
background, but inside a tmux that was started before a toggle it keeps
seeing the old color, so it uses a link too.)

### starship

starship can't include another file, so its flavor is the line
`palette = "catppuccin_mocha"` inside `~/.config/starship.toml`, which
`theme-toggle.sh` edits in place. So that a toggle doesn't show up as a
difference, the config is split in two:

- **`.chezmoitemplates/starship.toml`**: the full config, with the flavor left
  as a blank (`{{ .flavor }}`). **This is the file to edit**: `edot
  ~/.config/starship.toml` opens it and applies when you quit.
- **`dot_config/modify_starship.toml`**: a few lines that build the file.
  chezmoi passes it the current file from `~/.config`; it finds which flavor
  is active there, defaulting to `mocha` if the file doesn't exist yet, and
  fills it into the template.

(`chezmoi edit ~/.config/starship.toml` would open the `modify_` file
instead, which is not where the config is.)

## SSH and Git

Bitwarden (Flatpak) holds the SSH keys and is the SSH agent.
`~/.ssh/config` points every host at its socket, and `.bash_profile` sets
`SSH_AUTH_SOCK` to the same place, so Bitwarden must be unlocked for
`git push` and `ssh`.

- It starts at login from `~/.config/autostart/com.bitwarden.desktop.desktop`
  (Brave from the file next to it). That file is exactly what the desktop
  portal writes when Bitwarden asks to start at login (on desktops whose
  portal can, such as GNOME; Fedora's sway portal can't), so it has no
  comments: if a portal ever rewrites it, nothing changes.
- `~/.local/share/flatpak/overrides/com.bitwarden.desktop` lets it show its
  tray icon: the Flatpak may talk to the tray but not claim the D-Bus name the
  icon needs (always `org.freedesktop.StatusNotifierItem-2-1` inside the
  sandbox).
- To run in the tray, turn on "Keep Bitwarden running in the background" in
  its settings (stored with the vault data, so not tracked here).

Git's name and email are asked once per machine by `chezmoi init`; to change
them, run `chezmoi init` again.

## CLI tools

Command-line tools (Neovim, lazygit, ripgrep, fd, bat, starship,
tree-sitter) come from [mise](https://mise.jdx.dev), not the distro, so every
machine gets the same versions whatever the distro. They're pinned in
`~/.config/mise/config.toml`, and that file is the whole set: on each change
chezmoi installs what's listed and prunes what isn't. mise puts them on `PATH`
through its shims (`~/.local/share/mise/shims`, set in `.bash_profile`), ahead
of any distro copy. `update` lists newer releases; to take one, bump the
version with `edot` and commit.

## Containers

Apps and tools that don't belong on the host (VS Code, htop, btop) live in a
[distrobox](https://distrobox.it) container named `dev`: a Fedora that shares
your home folder, user and desktop session, so its apps open as normal
windows. `~/.config/distrobox/assemble.ini` describes it completely, and chezmoi
rebuilds it from scratch with `distrobox assemble` whenever that file
changes. Anything installed in it by hand is lost on the next rebuild;
your home folder is never touched.

Its apps are exported: they're in rofi (as "... (on dev)"),
and `code`, `htop` and `btop` work from the host's terminal. For a shell
inside it: `distrobox enter dev`. distrobox itself is layered by
workstation-bootstrap, and podman, which runs the containers, is part of
Fedora's atomic images. On a new machine the container is built on the
first `chezmoi apply` after the reboot that follows `setup.sh`.

## Terminal

Alacritty is the terminal (layered by workstation-bootstrap, instead of
Fedora's foot). Each launcher finds it its own way:

| From | How |
| --- | --- |
| `Super+Return` | `$term` in `70-bindings.conf` |
| rofi (sway), for terminal apps such as Neovim | rofi's `-terminal alacritty` (`$menu` in `70-bindings.conf`) |
| GTK apps, e.g. Thunar's "Open With" | `xdg-terminal-exec` (layered) reads `dot_config/xdg-terminals.list`. GLib's own fallback list has no Alacritty, so without it these fail |
| Thunar's "Open Terminal Here" | Xfce's preferred terminal: `~/.config/xfce4/helpers.rc` and the helper in `~/.local/share/xfce4/helpers/` (Sway Atomic ships none) |

Neovim comes from mise, which installs no app entry, so
`~/.local/share/applications/nvim.desktop` adds one (rofi, "Open With").
