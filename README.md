# workstation-bootstrap

Takes a fresh **Fedora Sway Atomic** install (image-based Fedora with sway,
preconfigured by Fedora) to my working desktop, with my dotfiles.

Who does what:

| Tool | Job | Needs sudo |
| --- | --- | --- |
| this repo (`setup.sh`) | third-party repos, COPRs; layered packages; automatic updates; Catppuccin login screen; Bitwarden's polkit action; installs Bitwarden and chezmoi | yes, once |
| Bitwarden | holds the SSH keys and is the SSH agent | no |
| chezmoi ([dotfiles](https://github.com/michellhuaman/dotfiles)) | dotfiles, flatpaks, CLI tools (mise), fonts, sway keybindings, Catppuccin theme, user services | no |
| distrobox (layered here) | a `dev` container for everything else (VS Code, htop, btop), defined and built by the dotfiles; its apps show up in the launcher | no |

Nothing secret lives here, so the flash drive can be any filesystem (exFAT,
Ventoy, ...) and losing it costs nothing.

## Layout

```
setup.sh                        the one script to run
lists/layered.txt               RPMs layered with rpm-ostree
lists/copr.txt                  COPR repos (owner/project) added before layering (none)
lists/repos/                    vendor repo files, if any (none yet), copied to /etc/yum.repos.d/
lists/keys.txt                  optional: vendor keys to pin by fingerprint, saved to /etc/pki/rpm-gpg/
system/sddm-flavor              switches the login screen between Latte and Mocha (installed to /usr/local/bin)
system/com.bitwarden.Bitwarden.policy  Bitwarden's polkit action (installed to /etc/polkit-1/actions)
```

## How it works

Sway Atomic boots from a read-only image, so there is no `dnf` on the host.
Instead, `setup.sh`:

- enables Fedora's third-party repositories (`fedora-third-party enable`),
  the same ones the first-boot setup offers, and the COPRs in `copr.txt`;
- makes the **layered packages** match `layered.txt`: missing ones are
  layered, layered ones no longer listed are uninstalled;
- turns on automatic updates (`AutomaticUpdatePolicy=stage`), which download
  new images in the background and apply them at the next reboot;
- gives the login screen (SDDM) Catppuccin's theme: Latte and Mocha from a
  pinned [catppuccin/sddm](https://github.com/catppuccin/sddm) release
  (checked by SHA-256) go to `/usr/local/share/sddm/themes`, and
  `/etc/sddm.conf.d/10-catppuccin.conf` points SDDM at the
  `catppuccin-current` link there. `sddm-flavor latte|mocha` repoints the
  link, and `/etc/sudoers.d/sddm-flavor` lets you run it, with just those
  two arguments, without a password, so the dotfiles' `theme-toggle.sh`
  switches the login screen too. To pin a newer release, change
  `sddm_version` and the checksums in `setup.sh`;
- installs Bitwarden's polkit action, which its "Unlock with system
  authentication" (biometrics on Linux) needs. Bitwarden's
  [guide](https://bitwarden.com/help/biometrics/#set-up-biometrics-for-desktop-app)
  copies it into `/usr/share/polkit-1/actions`, which is read-only here, so it
  goes to `/etc/polkit-1/actions` (polkit reads both). The file in `system/`
  is a copy of Bitwarden's `com.bitwarden.desktop.policy`, so nothing
  unpinned gets installed as root; compare it with upstream now and then.

Nothing is ever removed from the base image (Firefox and the rest stay).

So the lists are the full state: don't `rpm-ostree install` by hand, or the
next run removes it. Keep `layered.txt` short: CLI tools come from mise and
apps from Flathub (both in the dotfiles), and everything else goes in the
dotfiles' distrobox container. Layering changes take effect after a
reboot, and a bad update is undone by picking the previous entry in the boot
menu (or `rpm-ostree rollback`).

To add a system package: add it to `lists/layered.txt` (and its COPR to
`lists/copr.txt`, or its repo file to `lists/repos/`), push, then re-run
`setup.sh` and reboot.

## Before leaving the old machine

Refresh the copy on the drive:

```bash
git -C "/run/media/$USER/<drive>/workstation-bootstrap" pull
```

## Setting up a new machine

1. **Install Fedora Sway Atomic.** Create your user **in the installer** and
   make it an administrator: there is no first-boot setup to do it later, and
   without it you won't have sudo. Connect to Wi-Fi or Ethernet.
2. **Log into sway, plug in the drive, open a terminal (`Super+Return`) and run:**

   ```bash
   bash "/run/media/$USER/<drive>/workstation-bootstrap/setup.sh"
   ```

   (The terminal is foot until Alacritty is layered.)

   It asks for:
   - your **sudo password**, once, for the system step;
   - to **log into Bitwarden** and turn on **File > Settings > App settings
     (all accounts) > Enable SSH agent**, then press Enter;
   - to **approve the key** in Bitwarden when it checks GitHub and clones the
     dotfiles;
   - your **Git name and email**, the first time chezmoi runs.
3. **Reboot** (`systemctl reboot`) and log into sway. The layered packages
   are there, Flatpak apps are in rofi (`Super+D`), and `Super+Return` opens
   Alacritty.
4. **Run `chezmoi apply` once.** It builds the dotfiles' distrobox container
   (VS Code, htop, btop), which needs the distrobox layered in step 2 and so
   can't be built before the reboot. It takes a few minutes.
5. **In Bitwarden**, after logging in: File > Settings > Security > turn on
   **Unlock with system authentication**. Bitwarden then unlocks with your
   login password (or a fingerprint, if the machine has a reader) instead of
   the master password. After Bitwarden starts, the first unlock still needs
   the master password. This one can't be automated: Bitwarden keeps it in
   each account's own settings.

## If something goes wrong

- **A package name is wrong, or a step fails**: fix it in the matching repo,
  push, and run `setup.sh` again. A rerun only changes what differs from the
  lists, and an existing dotfiles clone is updated rather than cloned again.
  If only the dotfiles part failed, add `--no-system` to skip the system step.
- **"A transaction is already in progress"**: the automatic updater is busy;
  wait a minute and run `setup.sh` again.
- **"Network not ready"**: right after boot the network can take a moment;
  `setup.sh` retries for a minute on its own.
- **"The agent isn't answering yet, or has no keys"**: Bitwarden is locked, the
  SSH agent switch is off, or the vault has no SSH key items.
- **"GitHub didn't accept a key"**: the key in Bitwarden isn't added to your
  GitHub account, or you denied the request in Bitwarden.
- **`<your-user> is not in the sudoers file`**: the user isn't an
  administrator. Reinstall and make it one, or, if you set a root password,
  log in as root and run `usermod -aG wheel <your-user>`.

## Testing a dotfiles branch

```bash
bash setup.sh --branch bootstrap-test
```

This only matters on the first run; after that chezmoi stays on that branch.
