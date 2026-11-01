# workstation-bootstrap

Takes a fresh **Fedora Workstation**, **Fedora Silverblue** or **Ubuntu desktop**
install to a working GNOME desktop with my dotfiles.

Who does what:

| Tool | Job | Needs sudo |
| --- | --- | --- |
| this repo (`setup.sh`) | removes unwanted preinstalled apps; native packages, COPR/universe, vendor repos, snaps, i2c access; installs Bitwarden and chezmoi | yes, once |
| Bitwarden | holds the SSH keys and is the SSH agent | no |
| chezmoi ([dotfiles](https://github.com/michellhuaman/dotfiles)) | dotfiles, flatpaks, starship, fonts, theme, user services | no |

Nothing secret lives here, so the flash drive can be any filesystem (exFAT,
Ventoy, ...) and losing it costs nothing.

## Layout

```
setup.sh                   the one script to run
fedora/remove.txt          preinstalled packages to remove (globs work)
fedora/packages.txt        dnf packages
fedora/copr.txt            COPR repos enabled first
fedora/repos/              vendor repo files (Brave, VS Code), copied to /etc/yum.repos.d/
ubuntu/remove.txt          preinstalled apt packages to purge
ubuntu/remove-snaps.txt    preinstalled snaps to remove
ubuntu/repos/              vendor repo files (Brave, VS Code, Claude Desktop), copied to /etc/apt/sources.list.d/
ubuntu/keys.txt            their signing keys, saved to /usr/share/keyrings/ (optionally fingerprint-checked)
ubuntu/debconf.txt         answers for packages that ask questions while installing
ubuntu/packages.txt        apt packages (universe is enabled if missing)
ubuntu/snaps.txt           snaps, with their flags
ubuntu/groups.txt          groups your user joins (kvm, for Claude Desktop's Cowork)
silverblue/layered.txt     RPMs layered with rpm-ostree (the whole set: unlisted ones are uninstalled)
silverblue/override-remove.txt  base-image RPMs to remove (the whole set: unlisted removals are undone)
silverblue/flatpak-remove.txt   preinstalled system Flatpaks to uninstall
silverblue/repos/          vendor repo files, copied to /etc/yum.repos.d/
silverblue/keys.txt        their signing keys, saved to /etc/pki/rpm-gpg/ (rpm-ostree can't fetch https keys)
```

Removals run before installs, and only touch what is actually installed.
On Ubuntu, a package is left alone (with a warning) if purging it would also
remove something else, such as the desktop metapackage.

To add an app from a vendor's own repository: put the vendor's repo file in
`fedora/repos/` and `ubuntu/repos/` (on Ubuntu, also its key in
`ubuntu/keys.txt`, under the name its `Signed-By` line expects), then add the
package to both `packages.txt` files.

To add a system package later: add it to the list for your distro, push, then
re-run `setup.sh` (or install it by hand). Everything else (configs, flatpaks,
user tools) goes in the dotfiles repo, and `chezmoi apply` installs it.

## Silverblue

Silverblue boots from a read-only image, so there is no `dnf` on the host.
`setup.sh` detects it (`/run/ostree-booted`) and, instead of installing
packages:

- makes the **layered packages** match `silverblue/layered.txt`: missing ones
  are layered, layered ones no longer listed are uninstalled;
- makes the **base-image removals** match `silverblue/override-remove.txt`,
  undoing removals you've taken off the list;
- uninstalls the preinstalled system Flatpaks in `flatpak-remove.txt`;
- turns on automatic updates (`AutomaticUpdatePolicy=stage`), which download
  new images in the background and apply them at the next reboot.

So the lists are the full layered state: don't `rpm-ostree install` by hand,
or the next run removes it. Try things in a toolbox first. CLI tools come
from mise and apps from Flathub (both in the dotfiles), which keeps the
layered list short. Layering changes take effect after a reboot, and a bad
update is undone by picking the previous entry in the boot menu
(or `rpm-ostree rollback`).

If `rpm-ostree` says a transaction is already in progress, GNOME Software or
the automatic updater is busy; wait a minute and run `setup.sh` again.

## Before leaving the old machine

Refresh the copy on the drive:

```bash
git -C "/run/media/$USER/<drive>/workstation-bootstrap" pull
```

## Setting up a new machine

1. **Install the distro.**
   - Fedora (Workstation or Silverblue): the matching image. Under **User Creation**, create your
     user and tick **Make this user administrator**, or you won't have sudo.
   - Ubuntu: the regular desktop image. The first user always has sudo.
   - Connect to Wi-Fi or Ethernet in the installer.
2. **Log into GNOME, plug in the drive, open a terminal and run:**

   ```bash
   bash "/run/media/$USER/<drive>/workstation-bootstrap/setup.sh"
   ```

   GNOME mounts the drive under `/run/media/$USER/` on both Fedora and Ubuntu.

   It asks for:
   - your **sudo password**, once, for the system packages;
   - to **log into Bitwarden** and turn on **File > Settings > App settings
     (all accounts) > Enable SSH agent**, then press Enter;
   - to **approve the key** in Bitwarden when it checks GitHub and clones the
     dotfiles;
   - your **Git name and email**, the first time chezmoi runs.
3. **Reboot** (`systemctl reboot`) and log in. Flatpak apps appear in the app
   grid, and `ddc-brightness.sh` gets its i2c access.

## If something goes wrong

- **A package name is wrong, or a step fails**: fix it in the matching repo,
  push, and run `setup.sh` again. Installed packages are skipped, and an
  existing dotfiles clone is updated rather than cloned again. If only the
  dotfiles part failed, add `--no-system` to skip the package step.
- **"The agent isn't answering yet, or has no keys"**: Bitwarden is locked, the
  SSH agent switch is off, or the vault has no SSH key items.
- **"GitHub didn't accept a key"**: the key in Bitwarden isn't added to your
  GitHub account, or you denied the request in Bitwarden.
- **`<your-user> is not in the sudoers file`** (Fedora): the administrator box
  wasn't ticked. Reinstall and tick it, or, if you set a root password, log in
  as root and run `usermod -aG wheel <your-user>`.
- **Ubuntu waits on "Could not get lock"**: it's installing updates in the
  background right after installation. `setup.sh` waits up to 15 minutes.

## Testing a dotfiles branch

```bash
bash setup.sh --branch bootstrap-test
```

This only matters on the first run; after that chezmoi stays on that branch.
