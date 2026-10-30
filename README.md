# workstation-bootstrap

Takes a fresh **Fedora Workstation** or **Ubuntu desktop** install to a working
GNOME desktop with my dotfiles.

Who does what:

| Tool | Job | Needs sudo |
| --- | --- | --- |
| this repo (`setup.sh`) | native packages, COPR/universe, snaps, i2c access; installs Bitwarden and chezmoi | yes, once |
| Bitwarden | holds the SSH keys and is the SSH agent | no |
| chezmoi ([dotfiles](https://github.com/michellhuaman/dotfiles)) | dotfiles, flatpaks, starship, fonts, theme, user services | no |

Nothing secret lives here, so the flash drive can be any filesystem (exFAT,
Ventoy, ...) and losing it costs nothing.

## Layout

```
setup.sh              the one script to run
fedora/packages.txt   dnf packages
fedora/copr.txt       COPR repos enabled first
ubuntu/packages.txt   apt packages (universe is enabled if missing)
ubuntu/snaps.txt      snaps, with their flags
```

To add a system package later: add it to the list for your distro, push, then
re-run `setup.sh` (or install it by hand). Everything else (configs, flatpaks,
user tools) goes in the dotfiles repo, and `chezmoi apply` installs it.

## Before leaving the old machine

Refresh the copy on the drive:

```bash
git -C "/run/media/$USER/<drive>/workstation-bootstrap" pull
```

## Setting up a new machine

1. **Install the distro.**
   - Fedora: the Fedora Workstation image. Under **User Creation**, create your
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
