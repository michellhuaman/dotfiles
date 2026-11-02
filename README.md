# workstation-bootstrap

Takes a fresh Fedora atomic desktop (image-based Fedora) to my working
desktop, with my dotfiles:

- **Fedora Sway Atomic**: sway, preconfigured by Fedora. My main setup.
- **Fedora Silverblue**: GNOME, optionally with a **niri** session (and
  DankMaterialShell) next to it: `setup.sh --niri`.

The same script and lists serve both; the dotfiles adapt to what's
installed.

Who does what:

| Tool | Job | Needs sudo |
| --- | --- | --- |
| this repo (`setup.sh`) | third-party repos, COPRs; layered packages and base-image removals; removes preinstalled Flatpaks; automatic updates; installs Bitwarden and chezmoi | yes, once |
| Bitwarden | holds the SSH keys and is the SSH agent | no |
| chezmoi ([dotfiles](https://github.com/michellhuaman/dotfiles)) | dotfiles, flatpaks, CLI tools (mise), fonts, sway/niri/GNOME keybindings, Catppuccin theme, user services | no |
| toolbox | everything else (VS Code, htop, btop, dev tools), set up by hand | no |

Nothing secret lives here, so the flash drive can be any filesystem (exFAT,
Ventoy, ...) and losing it costs nothing.

## Layout

```
setup.sh                        the one script to run
lists/layered.txt               RPMs layered with rpm-ostree
lists/override-remove.txt       base-image RPMs to remove (none)
lists/flatpak-remove.txt        preinstalled system Flatpaks to uninstall (none)
lists/copr.txt                  COPR repos (owner/project) added before layering (none)
lists/repos/                    vendor repo files, if any (none yet), copied to /etc/yum.repos.d/
lists/keys.txt                  optional: vendor keys to pin by fingerprint, saved to /etc/pki/rpm-gpg/
lists/niri/                     added to the lists above with --niri: niri, DMS and its COPR
```

## How it works

Fedora's atomic desktops boot from a read-only image, so there is no `dnf`
on the host.
Instead, `setup.sh`:

- enables Fedora's third-party repositories (`fedora-third-party enable`),
  the same ones the first-boot setup offers, and the COPRs in `copr.txt`;
- makes the **layered packages** match `layered.txt`: missing ones are
  layered, layered ones no longer listed are uninstalled;
- makes the **base-image removals** match `override-remove.txt`, undoing
  removals you've taken off the list (entries not in the image are skipped);
- uninstalls the preinstalled system Flatpaks in `flatpak-remove.txt`;
- turns on automatic updates (`AutomaticUpdatePolicy=stage`), which download
  new images in the background and apply them at the next reboot.

So the lists are the full state: don't `rpm-ostree install` by hand, or the
next run removes it. Keep `layered.txt` short: CLI tools come from mise and
apps from Flathub (both in the dotfiles), and everything else goes in a
toolbox. Layering changes take effect after a reboot, and a bad update is
undone by picking the previous entry in the boot menu (or `rpm-ostree rollback`).

To add a system package: add it to `lists/layered.txt` (and its COPR to
`lists/copr.txt`, or its repo file to `lists/repos/`), push, then re-run
`setup.sh` and reboot. For niri-only packages, use the files in `lists/niri/`.

## Before leaving the old machine

Refresh the copy on the drive:

```bash
git -C "/run/media/$USER/<drive>/workstation-bootstrap" pull
```

## Setting up a new machine

1. **Install Fedora Sway Atomic or Silverblue**, and make your user an
   administrator, or you won't have sudo. On Sway Atomic, create the user
   **in the installer**: there is no first-boot setup to do it later. On
   Silverblue, GNOME's first-boot setup makes the first user an
   administrator. Connect to Wi-Fi or Ethernet.
2. **Log in, plug in the drive, open a terminal and run:**

   ```bash
   bash "/run/media/$USER/<drive>/workstation-bootstrap/setup.sh"
   ```

   On sway the terminal is `Super+Return` (foot, until Alacritty is
   layered); on GNOME, Ptyxis from the app grid. For a niri session next to
   GNOME on Silverblue, add `--niri`.

   It asks for:
   - your **sudo password**, once, for the system step;
   - to **log into Bitwarden** and turn on **File > Settings > App settings
     (all accounts) > Enable SSH agent**, then press Enter;
   - to **approve the key** in Bitwarden when it checks GitHub and clones the
     dotfiles;
   - your **Git name and email**, the first time chezmoi runs.
3. **Reboot** (`systemctl reboot`) and log in. The layered packages are
   there and the Flatpak apps are in the launcher: rofi (`Super+D`) on sway,
   the app grid on GNOME. With `--niri`, pick **GNOME** or **Niri** with the
   gear on the login screen.

## niri on Silverblue

`setup.sh --niri` adds `lists/niri/` (niri, DankMaterialShell and its COPR)
to the lists; `setup.sh --no-niri` takes them away again. Without either, a
rerun keeps the current state, so niri stays once it's layered.

## If something goes wrong

- **A package name is wrong, or a step fails**: fix it in the matching repo,
  push, and run `setup.sh` again. A rerun only changes what differs from the
  lists, and an existing dotfiles clone is updated rather than cloned again.
  If only the dotfiles part failed, add `--no-system` to skip the system step.
- **"A transaction is already in progress"**: the automatic updater (or
  GNOME Software) is busy; wait a minute and run `setup.sh` again.
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
