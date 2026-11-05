# workstation

Takes a fresh **Ubuntu** install (the stock GNOME desktop) to my working
desktop: the installer's answers, the system packages and settings, and my
dotfiles (managed with [chezmoi](https://www.chezmoi.io/), themed with
Catppuccin).

The dividing line inside the repo is **sudo**. `setup.sh` and its lists, at
the root, are the system half and run with sudo once. `home/` is the
dotfiles: chezmoi only reads that folder (`.chezmoiroot`), and everything in
it installs into the home folder, so `chezmoi apply` never asks for a
password. Anything that needs root goes in `setup.sh`, never under `home/`.

Who does what:

| Tool | Job | Needs sudo |
| --- | --- | --- |
| `setup.sh` | apt packages, including Brave, VS Code, mise and Claude Desktop from their vendors' repos; automatic security updates; Bitwarden's polkit action; runs chezmoi (through mise) | yes, once |
| chezmoi (`home/`) | dotfiles, flatpaks, CLI tools (mise), fonts, GNOME settings and shortcuts, Catppuccin theme, user services | no |
| Bitwarden | holds the SSH keys and is the SSH agent, for pushing (the repo is public, so nothing needs it to install) | no |
| distrobox and podman (apt) | containers you make by hand, for anything that doesn't belong on the host | no |
| QEMU/KVM, libvirt and virt-manager (apt) | virtual machines: Virtual Machine Manager's "QEMU/KVM" connection, or `virsh` and `virt-install` | no, once you're in the libvirt group |
| VirtualBox (apt, from Ubuntu's multiverse) | virtual machines in VirtualBox Manager or `VBoxManage`; not at the same time as a KVM VM (virt-manager's, or Claude Desktop's Cowork), since only one can hold AMD-V/VT-x | no (USB passthrough needs the vboxusers group) |

Nothing secret lives here, so the repo is public: a new machine downloads it
and chezmoi clones it over HTTPS, with no key. Pushes go over SSH, through
Bitwarden's agent.

The clone lives where chezmoi keeps it, `~/.local/share/chezmoi`
(`chezmoi cd` goes there). That's where you change `setup.sh` too.

This repo used to be two, `workstation-bootstrap` (the root files) and
`dotfiles` (now `home/`); both histories are kept. The setup before Ubuntu,
Fedora Sway Atomic (sway, waybar, rofi, dunst, swaylock, Thunar's helpers),
is kept as the tag `fedora-sway-atomic`: `git checkout fedora-sway-atomic`
to look at it.

## Layout

```
README.md                       this file
.chezmoiroot                    tells chezmoi its source is home/, so it never reads the rest
autoinstall.yaml                answers for the Ubuntu installer ("Automated installation")
setup.sh                        the one script to run, after the first login (sudo)
update-pins.sh                  bumps the pinned Nerd Font, on a branch
lists/apt.txt                   apt packages setup.sh makes sure are installed
lists/apt-sources/              vendor repos (Brave, VS Code, mise, Claude Desktop), copied to /etc/apt/sources.list.d/
lists/apt-keys.txt              their signing keys, checked by fingerprint, saved to /etc/apt/keyrings/
lists/groups.txt                groups setup.sh adds your user to (libvirt, kvm, vboxusers)
system/com.bitwarden.Bitwarden.policy  Bitwarden's polkit action (installed to /etc/polkit-1/actions)
home/                           the dotfiles: chezmoi's source
  .chezmoiremove          files earlier versions put in ~, deleted on apply
  .chezmoidata/
    packages.yaml         flatpaks, Nerd Font version and checksum, systemd user units
  .chezmoiscripts/        run by `chezmoi apply`, in number order
    run_onchange_after_20-install-flatpaks.sh.tmpl    reruns when the flatpak list changes
    run_onchange_after_25-install-cli-tools.sh.tmpl   mise install + prune; reruns when the mise config changes
    run_onchange_after_30-install-fonts.sh.tmpl       Nerd Font (checked against its checksum)
    run_onchange_after_40-enable-services.sh.tmpl     enables the user units in packages.yaml
    run_once_after_50-default-theme.sh.tmpl           dark theme on the first apply only
    run_onchange_after_55-theme-links.sh.tmpl         points Alacritty's theme link at the current flavor
    run_onchange_after_60-gnome-settings.sh.tmpl      Ubuntu only: GNOME keyboard, touchpad, night light, shortcuts
  dot_bash_profile, dot_bashrc
  dot_gitconfig           Git name, email, editor
  private_dot_ssh/        ~/.ssh/config: Bitwarden's agent for every host
  dot_config/             ~/.config (Alacritty, bat, mise, starship, tmux, systemd, ...)
    autostart/            apps started at login: Bitwarden (the SSH agent), Brave and Claude Desktop (apt packages)
  dot_local/bin/          theme-toggle.sh, ddc-brightness.sh, powermenu.sh,
                          vm (start a course's VirtualBox VMs + a tmux session with an SSH pane per VM;
                              `vm` lists the groups, `vm <group> keys|stop|--gui`; VMs listed at the top of the script),
                          random-wallpaper.sh (random light and dark GNOME wallpapers from ~/Pictures/wallpapers; daily via random-wallpaper.timer),
                          wallpaper-reject.sh (Super+Shift+W: trash the wallpaper on screen, or move it to light/ or dark/)
```

## Setting up a new machine

1. **Install Ubuntu.** Connect to Wi-Fi or Ethernet when the installer
   asks, and at "Type of installation" pick **Automated installation** with
   this URL:

   ```
   https://raw.githubusercontent.com/michellhuaman/workstation/main/autoinstall.yaml
   ```

   `autoinstall.yaml` answers the language, keyboard, timezone, the
   minimized desktop, drivers, codecs and updates. The installer still asks
   for the disk (Erase disk, advanced: LVM with encryption, and a
   passphrase) and for your name, username, hostname and password, so
   nothing is wiped unasked and no password hash is in this public repo.
   (Without the file, the normal interactive install with the same choices
   works too.) The user you create is an administrator, so it has sudo.
2. **Log in, open a terminal (`Ctrl+Alt+T`) and run** (wget comes with
   Ubuntu; curl and git may not yet):

   ```bash
   wget -qO- https://github.com/michellhuaman/workstation/archive/refs/heads/main.tar.gz | tar -xz
   bash workstation-main/setup.sh
   ```

   It only asks for your **sudo password**, once, for the system step.
   chezmoi clones this repo into `~/.local/share/chezmoi` (pulls over
   HTTPS, pushes over SSH once step 5 is done), so the downloaded
   `workstation-main` folder can be deleted afterwards.

3. **If Secure Boot is on, enroll the key VirtualBox's modules are signed
   with**, so VirtualBox VMs can start. `virtualbox-dkms` signs its kernel
   modules with the machine's MOK key, but the firmware only loads them once
   that key is enrolled, and `setup.sh` installs packages non-interactively,
   so nothing asks you to do it. Check first:

   ```bash
   mokutil --sb-state
   mokutil --test-key /var/lib/shim-signed/mok/MOK.der
   ```

   If it says "SecureBoot enabled" and the key "is not enrolled", import it:

   ```bash
   sudo mokutil --import /var/lib/shim-signed/mok/MOK.der
   ```

   It asks for a one-time password you make up. At the next boot (step 4) a
   blue MOK Manager screen appears: pick **Enroll MOK**, then **Continue**,
   **Yes**, type that password and **Reboot**. If the screen goes by, run
   the import again and reboot. Secure Boot off, or the key already
   enrolled: skip this step.
4. **Reboot** (`systemctl reboot`) and log in. Flatpak apps are in the app
   grid, and `Super+Return` opens Alacritty.
5. **In Bitwarden**, log in (it starts at login), then:
   - File > Settings > App settings (all accounts) > turn on **Enable SSH
     agent**, so `git push` works. Check with `ssh -T git@github.com`
     (approve the request in Bitwarden).
   - File > Settings > Security > turn on **Unlock with system
     authentication**. Bitwarden then unlocks with your
   login password (or a fingerprint, if the machine has a reader) instead of
   the master password. After Bitwarden starts, the first unlock still needs
   the master password. This one can't be automated: Bitwarden keeps it in
   each account's own settings.

## Before leaving the old machine

1. **Update the pins** and test them (previous section), so the new machine
   starts from current versions that a VM has already run.
2. **Push everything**: the new machine gets it from GitHub.

## If something goes wrong

- **A package name is wrong, or a step fails**: fix it in the repo, push,
  and run `bash ~/.local/share/chezmoi/setup.sh` again. A rerun only changes
  what differs from the list, and an existing clone is updated (`chezmoi
  update`) rather than cloned again.
  If only the dotfiles part failed, add `--no-system` to skip the system step.
- **"Could not get lock /var/lib/dpkg/lock-frontend"**: the automatic
  updater (or the App Center) is busy; wait a minute and run `setup.sh`
  again.
- **"can't reach github.com"**: right after boot the network can take a
  moment (downloads retry for about 30 seconds on their own); connect and
  run `setup.sh` again.
- **`git push` fails with "Permission denied (publickey)"**: Bitwarden is
  locked, its SSH agent switch is off, the vault has no SSH key items, or
  the key isn't added to your GitHub account.
- **`<your-user> is not in the sudoers file`**: the user isn't an
  administrator. From an administrator account, run
  `sudo usermod -aG sudo <your-user>`, then log out and back in.

## The system half: setup.sh

`setup.sh`:

- adds the vendor repos in `apt-sources/` (Brave's, Microsoft's, mise's
  and Anthropic's, for Brave, VS Code, mise and Claude Desktop), with their keys from `apt-keys.txt`. A key file must
  hold exactly the fingerprints listed there, or `setup.sh` stops. Brave
  publishes no fingerprints; the ones listed are the keys shown on
  https://brave.com/signing-keys/, which match its apt host's keyring.
  Microsoft's is its well-known package signing key. VS Code's package is
  told (through debconf) not to add its own copy of the repo. Claude
  Desktop's package leaves its copy out when the repo is already there, and
  an earlier copy (`claude-desktop.list`, from the package or Anthropic's
  manual install steps) is deleted, since apt won't take both;
- installs the packages in `apt.txt` that are missing, and remembers which
  ones it installed (in `/var/lib/workstation-bootstrap/apt-installed.txt`).
  A package dropped from the list is removed only if `setup.sh` installed
  it, so nothing Ubuntu came with is ever removed (Firefox, the snaps and
  the rest stay);
- adds your user to the groups in `groups.txt` (libvirt, so virt-manager
  manages VMs without sudo; kvm, for Claude Desktop's Cowork VM; vboxusers, for USB devices in
  VirtualBox VMs), effective after a reboot (logging out isn't
  enough: your systemd user manager keeps the old groups). A group dropped
  from the list isn't removed: `sudo gpasswd -d "$USER" <group>`;
- makes sure libvirt's default NAT network (`virbr0`, 192.168.122.0/24)
  exists, starts at boot and is running, so new VMs get network access
  (the package normally does this itself);
- keeps Ubuntu's automatic security updates (unattended-upgrades) on. They
  are on by default; this only makes sure;
- installs Bitwarden's polkit action, which its "Unlock with system
  authentication" (biometrics on Linux) needs. Bitwarden's
  [guide](https://bitwarden.com/help/biometrics/#set-up-biometrics-for-desktop-app)
  copies it into `/usr/share/polkit-1/actions`, which belongs to the
  packages, so it goes to `/etc/polkit-1/actions` (polkit reads both). The
  file in `system/` is a copy of Bitwarden's `com.bitwarden.desktop.policy`,
  so nothing unpinned gets installed as root; `update-pins.sh` compares it
  with upstream and shows any difference for review.

Keep `apt.txt` short: CLI tools come from mise and apps from Flathub (both
in `home/`).

To add a system package: add it to `lists/apt.txt` (and, for a vendor's
repo, its `.sources` file to `lists/apt-sources/` and its key to
`lists/apt-keys.txt`), push, then re-run `setup.sh` on each machine:
`chezmoi update` pulls the change but doesn't run it. A repo dropped from
`apt-sources/` isn't removed from the machine; delete its file in
`/etc/apt/sources.list.d/` by hand.

## The dotfiles: home/

The source of truth is `home/` in the clone,
`~/.local/share/chezmoi/home`. Files in `~` (`~/.bashrc`, `~/.config/...`)
are output: chezmoi writes them from here and
overwrites them on apply. So changes are made here, never directly in `~`.

`run_onchange_after_60-gnome-settings.sh.tmpl` sets GNOME's keyboard
layouts, tap to click and traditional scrolling, night light, 10 fixed
workspaces and shortcuts (Super+Return Alacritty, Super+Shift+Return
Brave, Super+Shift+T theme-toggle, Super+Shift+B monitor brightness,
Super+1-9/0 workspace 1-10, Super+Shift+1-9/0 move the window there; the
script's header lists them all).

### The workflow

**1. Edit and apply**, using the file's real path in your home folder:

```bash
edot ~/.config/alacritty/alacritty.toml
```

`edot` (an alias in `.bashrc` for `chezmoi edit --apply`) opens the source
file in `$EDITOR` and applies the change when you quit.

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

then continue from step 2. `re-add` skips templates; for those, copy the
change into the template with `edot` instead.
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
| a keyboard shortcut | `.chezmoiscripts/run_onchange_after_60-gnome-settings.sh.tmpl` | `chezmoi apply` |
| a CLI tool | `edot ~/.config/mise/config.toml` (as `"latest"`) | applied on save: installed, and anything no longer listed is pruned |
| a new Nerd Font release | `fonts.nerd_fonts` in `.chezmoidata/packages.yaml`, and `fonts.nerd_fonts_sha256` next to it (that release's `SHA-256.txt` line for `JetBrainsMono.tar.xz`) | `chezmoi apply` downloads it and checks it |
| a systemd user unit | the unit in `dot_config/systemd/user/`, its name in `services.user` | `chezmoi apply` enables it |
| a script, template or anything else in the repo | `chezmoi cd`, then edit the file (e.g. `vim home/.chezmoidata/packages.yaml`) | `chezmoi apply`, `exit` |
| a system (apt) package | `lists/apt.txt` at the repo root (see "The system half") | re-run `setup.sh` |

Each of these then goes through step 2 like any other change.

**A new Nerd Font release, tested first**: `update-pins.sh` bumps it to the
latest stable release on a branch, to test in a VM before merging
("Updating the pinned versions" below).

chezmoi turns source names into real ones: `dot_` becomes `.`, `private_`
means only you can read it, `executable_` makes it executable, and `.tmpl`
means it's a template.

### Themes

`theme-toggle.sh` (`Super+Shift+T`) switches between light and dark: it sets
the desktop's color scheme (which GTK4/libadwaita apps and Brave follow), the
GTK and icon themes (Ubuntu's Yaru), and Alacritty's Catppuccin flavor (Latte
for light, Mocha for dark). A new machine starts on Mocha, matching the dark
theme `run_once_after_50-default-theme.sh.tmpl` sets.

Alacritty reads `~/.config/alacritty/themes/catppuccin-current.toml`, a link
that `theme-toggle.sh` points at `catppuccin-latte.toml` or
`catppuccin-mocha.toml` (copies of catppuccin/alacritty's files), then
touches `alacritty.toml` so open windows reload. chezmoi tracks the theme
files but not the link, so a toggle never shows up as a difference. On a new
machine, `run_onchange_after_55-theme-links.sh.tmpl` creates the link
(`theme-toggle.sh links`) for the current mode.

starship and bat use the terminal's 16 ANSI colors instead of a theme of
their own, so they follow Alacritty: starship's colors are ANSI names, and
bat has `--theme=ansi`.

The wallpaper follows the theme without `theme-toggle.sh`: GNOME keeps one
wallpaper per mode (`picture-uri` for light, `picture-uri-dark` for dark) and
shows the matching one. `random-wallpaper.sh` (daily, via
`random-wallpaper.timer`) picks the light one from `~/Pictures/wallpapers/light`
and the dark one from `~/Pictures/wallpapers/dark`; a mode whose folder is
missing or empty picks from the whole folder. `Super+Shift+W`
(`wallpaper-reject.sh`) asks what to do with the wallpaper on screen: move it
to the Trash (Restore it from the Trash in Files to undo), or to `light/` or
`dark/`. When it leaves the current mode's folder, the mode gets a new one.

### SSH and Git

Bitwarden (Flatpak) holds the SSH keys and is the SSH agent.
`~/.ssh/config` points every host at its socket, and `.bash_profile` sets
`SSH_AUTH_SOCK` to the same place, so Bitwarden must be unlocked for
`git push` and `ssh`. This repo is public, so it's pulled over HTTPS
(`chezmoi update` needs no key) and pushed over SSH: `setup.sh` sets
origin's push URL to `git@github.com:...`.

- It starts at login from `~/.config/autostart/com.bitwarden.desktop.desktop`
  (Brave from the file next to it). That file is exactly what the desktop
  portal writes when Bitwarden asks to start at login (on desktops whose
  portal can, such as GNOME), so it has no
  comments: if a portal ever rewrites it, nothing changes.
- `~/.local/share/flatpak/overrides/com.bitwarden.desktop` lets it show its
  tray icon: the Flatpak may talk to the tray but not claim the D-Bus name the
  icon needs (always `org.freedesktop.StatusNotifierItem-2-1` inside the
  sandbox).
- To run in the tray, turn on "Keep Bitwarden running in the background" in
  its settings (stored with the vault data, so not tracked here).

Git's name and email are in `dot_gitconfig`, the same on every machine.

### CLI tools

Command-line tools (chezmoi itself, bat, starship) come from
[mise](https://mise.jdx.dev), not the distro, so they're newer than Ubuntu's.
mise itself is an apt package from its own repo (`setup.sh`), updated
with the system. They're listed in `~/.config/mise/config.toml` as
`"latest"`, and that file is the whole set: on each change chezmoi installs
what's listed and prunes what isn't. mise puts them on `PATH` through its
shims (`~/.local/share/mise/shims`, set in `.bash_profile`), ahead of any
distro copy. `update` (in `.bashrc`) upgrades them with `mise upgrade`.

### Terminal

Alacritty is the terminal (an apt package, from `setup.sh`).
Each launcher finds it its own way:

| From | How |
| --- | --- |
| `Super+Return` | a custom shortcut in `run_onchange_after_60-gnome-settings.sh.tmpl` |
| terminal apps such as vim, from the app grid or "Open With" | `xdg-terminal-exec` (apt) reads `dot_config/xdg-terminals.list`. GLib's own fallback list has no Alacritty, so without it these fail |

vim is an apt package from `setup.sh` (Ubuntu's own `vim-tiny`
has no `vim` command), with Ubuntu's app entry; it's `EDITOR` (`.bash_profile`)
and Git's editor (`dot_gitconfig`). It has no config here.

## Updating the pinned versions

The Nerd Font the dotfiles download is pinned to an exact version and
checksum. `update-pins.sh` moves it to the latest stable release:

| Repo | Pin | Latest from |
| --- | --- | --- |
| `home/` | Nerd Font, `fonts.nerd_fonts` and its checksum `fonts.nerd_fonts_sha256` in `home/.chezmoidata/packages.yaml` | ryanoasis/nerd-fonts' latest release (the checksum from its `SHA-256.txt`) |
| root | Bitwarden's polkit action, `system/` | only compared with upstream; a difference is shown, never copied in |

"Latest" never means a pre-release or beta. The CLI tools aren't pinned
(mise installs their latest release, and `update` in `.bashrc` upgrades
them), and neither is mise itself: it's an apt package from its own repo,
updated with the rest of the system. The Catppuccin theme files in `home/` are copies, not pins;
re-copy them from catppuccin/<app> by hand if you ever want to.

Do this before moving to a new machine, and every couple of months
otherwise, so each round is small. All of it happens on a branch: `main`
and the dotfiles in use don't change until the last step.

1. **Bump** (the script fetches `main` from GitHub first):

   ```bash
   bash ~/.local/share/chezmoi/update-pins.sh
   ```

   It makes a branch `pins-YYYY-MM-DD` in the worktree
   `~/repos/workstation-pins-YYYY-MM-DD`, with one commit per bump, and
   prints what it changed, what failed, and what to review (the polkit
   action). With nothing to bump, it keeps no branch. If GitHub's rate
   limit runs out, set `GITHUB_TOKEN` and run it again (after deleting the
   branch and worktree it made).

2. **Push the branch** (only the branch; `main` stays as it is), so the VM
   can download it from GitHub:

   ```bash
   b=pins-YYYY-MM-DD
   git -C ~/repos/workstation-$b push -u origin "$b"
   ```

3. **Test in the VM** ("The test VM" below). Go back to the fresh install
   and start it:

   ```bash
   virsh -c qemu:///system snapshot-revert ws-test fresh-install
   virsh -c qemu:///system start ws-test
   ```

   Then open it in Virtual Machine Manager, unlock the disk, log in, and in
   a terminal (`Ctrl+Alt+T`):

   ```bash
   b=pins-YYYY-MM-DD
   wget -qO- https://github.com/michellhuaman/workstation/archive/refs/heads/$b.tar.gz | tar -xz
   bash workstation-$b/setup.sh --branch "$b"
   ```

   Reboot the VM, and check: `Super+Shift+T` switches
   light/dark (GNOME, Alacritty, bat, starship), the font is the new
   version (`fc-list | grep JetBrainsMono`), `git commit` opens vim, Brave and VS Code start, the Nerd Font
   icons show in starship, Bitwarden starts at login, and its unlock with
   system authentication works.

4. **If a bump breaks something**, undo just that commit in the worktree,
   push the branch again and re-test from the fresh install (step 3):

   ```bash
   git -C ~/repos/workstation-pins-YYYY-MM-DD revert <commit>
   git -C ~/repos/workstation-pins-YYYY-MM-DD push
   ```

5. **Merge, push and clean up**, once the VM is fine:

   ```bash
   b=pins-YYYY-MM-DD
   chezmoi git -- merge --ff-only "$b" && chezmoi git -- push && chezmoi apply
   chezmoi git -- push origin --delete "$b"
   chezmoi git -- worktree remove ~/repos/workstation-$b
   chezmoi git -- branch -d "$b"
   ```

   Then shut the VM down:
   `virsh -c qemu:///system shutdown ws-test`.

### The test VM

`ws-test` is a libvirt VM (QEMU/KVM, the system connection) with a fresh
Ubuntu installed from `autoinstall.yaml` and the snapshot `fresh-install`
of it, taken shut off, after the first login and before `setup.sh`.
Reverting to it throws away everything since. Its disks live in `~/vms`,
the libvirt storage pool `vms`; libvirt's QEMU user (`libvirt-qemu`) may
enter your home folder and use that one, through ACLs (your home is
otherwise closed to other users).

To make it again (for a new Ubuntu release, say), on a machine that doesn't
have them yet, set up `~/vms` and put the ISO in libvirt's image folder,
which the VM can read (USB drives it can't):

```bash
mkdir -p ~/vms
setfacl -m u:libvirt-qemu:x ~ && setfacl -m u:libvirt-qemu:rwx ~/vms
virsh -c qemu:///system pool-define-as vms dir --target ~/vms
virsh -c qemu:///system pool-start vms && virsh -c qemu:///system pool-autostart vms
iso=ubuntu-26.04.1-desktop-amd64.iso
virsh -c qemu:///system vol-create-as default "$iso" "$(stat -c %s "/path/to/$iso")" --format raw
virsh -c qemu:///system vol-upload --pool default "$iso" "/path/to/$iso"
virt-install --connect qemu:///system --name ws-test --osinfo ubuntu25.10 \
  --memory 6144 --vcpus 4 --cpu host-passthrough --boot uefi \
  --disk pool=vms,size=40,format=qcow2,bus=virtio \
  --cdrom "/var/lib/libvirt/images/$iso" \
  --network network=default,model=virtio --graphics spice --video virtio \
  --noautoconsole
```

(`--osinfo` is the newest Ubuntu that `virt-install --osinfo list` knows;
it only picks defaults.) Install it like a real machine ("Setting up a new
machine", step 1, with the automated installation), log in once, shut it
down, and snapshot it:

```bash
virsh -c qemu:///system shutdown ws-test
virsh -c qemu:///system snapshot-create-as ws-test fresh-install --disk-only --atomic
```

The snapshot is disk-only (external): libvirt can't take the usual
internal snapshots of a VM with UEFI firmware.

## Testing a branch

```bash
bash setup.sh --branch bootstrap-test
```

Use the branch you downloaded `setup.sh` from, so both halves match. This
only matters on the first run; after that chezmoi stays on that branch.
Without `--branch`, `setup.sh` clones `main`.
