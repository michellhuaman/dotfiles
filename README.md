# dotfiles

My GNOME setup for Fedora Workstation and Ubuntu, managed with
[chezmoi](https://www.chezmoi.io/).

This repo is the user half of the setup. The system half (native packages,
COPR/universe, snaps, i2c access, and installing Bitwarden and chezmoi) is in
[workstation-bootstrap](https://github.com/michellhuaman/workstation-bootstrap),
whose `setup.sh` clones and applies this repo on a new machine.

The dividing line is **sudo**: everything here installs into the home folder,
so `chezmoi apply` never asks for a password.

## Layout

```
.chezmoi.toml.tmpl      per-machine settings, asked once by `chezmoi init` (Git name/email)
.chezmoiignore          repo files that are not copied to ~ (this README)
.chezmoidata/
  packages.yaml         flatpaks, Nerd Font version, systemd user units
.chezmoiscripts/        run by `chezmoi apply`, in number order
  run_onchange_after_20-install-flatpaks.sh.tmpl    reruns when the flatpak list changes
  run_onchange_after_30-install-user-tools.sh.tmpl  starship, Nerd Font, bat/fd names, bat cache
  run_onchange_after_40-enable-services.sh.tmpl     enables the user units in packages.yaml
  run_once_after_50-default-theme.sh.tmpl           dark theme on the first apply only
.chezmoitemplates/      the four themed configs (see "Themes" below)
dot_bash_profile, dot_bashrc
dot_gitconfig.tmpl      uses the name/email from .chezmoi.toml.tmpl
private_dot_ssh/        ~/.ssh/config: Bitwarden's agent for every host
dot_config/             ~/.config (Alacritty, bat, btop, Neovim, starship, tmux, systemd, ...)
dot_local/bin/          theme-toggle.sh, ddc-brightness.sh, powermenu.sh
```

chezmoi turns source names into real ones: `dot_` becomes `.`, `private_`
means only you can read it, `executable_` makes it executable, `.tmpl` means
it's a template, and `modify_` means a template that edits the existing file
(see "Themes").

## Making changes

The source of truth is this repo, at `~/.local/share/chezmoi`. Files in
`~/.config` and the rest of `~` are output: chezmoi overwrites them on apply.

**Usual workflow:** edit here, apply, commit, push.

```bash
chezmoi edit --apply ~/.bashrc          # opens the source file for ~/.bashrc
# or work in the repo directly:
chezmoi cd
vim dot_config/tmux/tmux.conf
chezmoi diff                            # what apply would change
chezmoi apply
git add -A && git commit -m "..." && git push
exit
```

On the other machines: `chezmoi update` (pull and apply).

**When a change started in `~` instead**, for example a setting changed from
inside an app:

```bash
chezmoi status        # files that differ from the source
chezmoi diff          # how they differ
chezmoi re-add        # copy changed plain files back into the source
chezmoi add ~/.config/newapp/config     # start tracking a new file
```

`re-add` skips templates and `modify_` files; edit those in the source.

**What goes where:**

| Change | Where |
| --- | --- |
| a config file | its file under `dot_config/`, or `.chezmoitemplates/` for the four themed ones |
| a Flatpak app | `packages.flatpak` in `.chezmoidata/packages.yaml` |
| a new Nerd Font release | `fonts.nerd_fonts` in `.chezmoidata/packages.yaml` |
| a systemd user unit | the unit in `dot_config/systemd/user/`, its name in `services.user` |
| a dnf/apt package, COPR, snap | not here: workstation-bootstrap's package lists |

Editing a list in `packages.yaml` makes the matching `run_onchange_` script run
again on the next `chezmoi apply`.

## Themes

`theme-toggle.sh` switches GNOME between light and dark several times a day and
changes the Catppuccin flavor (Latte for light, Mocha for dark) inside four
configs:

| Config | Line it changes |
| --- | --- |
| `~/.config/alacritty/alacritty.toml` | `import = [".../catppuccin-mocha.toml"]` |
| `~/.config/starship.toml` | `palette = "catppuccin_mocha"` |
| `~/.config/btop/btop.conf` | `color_theme = ".../catppuccin_mocha.theme"` |
| `~/.config/bat/config` | `--theme="Catppuccin Mocha"` |

If these were plain files, every toggle would be a difference: `chezmoi diff`
would show it, `apply` would undo it, and `re-add` would commit whichever
flavor was active. So the configs are split in two:

- **`.chezmoitemplates/<name>`**: the full config, with the flavor left as a
  blank (`{{ .flavor }}`). **This is the file to edit.**
- **`dot_config/.../modify_<name>`**: a few lines that build the file. chezmoi
  passes it the current file from `~/.config`; it finds which flavor is active
  there, defaulting to `mocha` if the file doesn't exist yet, and fills it into
  the template.

The result is always your config with whatever flavor is already on disk. A
toggle never shows up in `chezmoi diff`, `apply` never undoes it, and a real
edit (say, a new font size) still goes through. A new machine starts on Mocha,
matching the dark theme `run_once_after_50-default-theme.sh.tmpl` sets.

To change one of these configs:

```bash
vim ~/.local/share/chezmoi/.chezmoitemplates/alacritty.toml
chezmoi apply
```

Only the theme line is protected. Anything else changed in `~/.config` (btop,
for example, rewrites `btop.conf` with all its settings when it quits) shows up
in `chezmoi diff`. To keep it, copy the line into the template.

GTK and icon themes are set by `theme-toggle.sh` and the default-theme script:
Yaru on Ubuntu, Adwaita everywhere else.

## SSH and Git

Bitwarden (Flatpak) holds the SSH keys and is the SSH agent.
`~/.ssh/config` points every host at its socket, and `.bashrc` sets
`SSH_AUTH_SOCK` to the same place, so Bitwarden must be unlocked for
`git push` and `ssh`. Git's name and email are asked once per machine by
`chezmoi init`; to change them, run `chezmoi init` again.

## Terminal

`dot_config/xdg-terminals.list` makes GNOME open terminal apps (htop, btop,
Neovim from the app grid) in Alacritty. It's read by `xdg-terminal-exec`, which
workstation-bootstrap installs on both distros. Nautilus's "Open in Terminal"
ignores it on Fedora and always opens Ptyxis.
