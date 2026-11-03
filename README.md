# workstation-bootstrap

Takes a fresh **Ubuntu** install (the stock GNOME desktop) to my working
desktop, with my dotfiles.

Who does what:

| Tool | Job | Needs sudo |
| --- | --- | --- |
| this repo (`setup.sh`) | apt packages, including Brave and VS Code from their vendors' repos; automatic security updates; Bitwarden's polkit action; installs Bitwarden and chezmoi | yes, once |
| Bitwarden | holds the SSH keys and is the SSH agent | no |
| chezmoi ([dotfiles](https://github.com/michellhuaman/dotfiles)) | dotfiles, flatpaks, CLI tools (mise), fonts, GNOME settings and shortcuts, Catppuccin theme, user services | no |
| distrobox (installed here) | a `dev` container for everything else (htop, btop), defined and built by the dotfiles; its apps show up in the app grid | no |

Nothing secret lives here, so the flash drive can be any filesystem (exFAT,
Ventoy, ...) and losing it costs nothing.

## Layout

```
setup.sh                        the one script to run
update-pins.sh                  bumps every pinned version in the dotfiles, on a branch
lists/apt.txt                   apt packages setup.sh makes sure are installed
lists/apt-sources/              vendor repos (Brave, VS Code), copied to /etc/apt/sources.list.d/
lists/apt-keys.txt              their signing keys, checked by fingerprint, saved to /etc/apt/keyrings/
system/com.bitwarden.Bitwarden.policy  Bitwarden's polkit action (installed to /etc/polkit-1/actions)
```

## How it works

`setup.sh`:

- adds the vendor repos in `apt-sources/` (Brave's and Microsoft's, for
  Brave and VS Code), with their keys from `apt-keys.txt`. A key file must
  hold exactly the fingerprints listed there, or `setup.sh` stops. Brave
  publishes no fingerprints; the ones listed are the keys shown on
  https://brave.com/signing-keys/, which match its apt host's keyring.
  Microsoft's is its well-known package signing key. VS Code's package is
  told (through debconf) not to add its own copy of the repo;
- installs the packages in `apt.txt` that are missing, and remembers which
  ones it installed (in `/var/lib/workstation-bootstrap/apt-installed.txt`).
  A package dropped from the list is removed only if `setup.sh` installed
  it, so nothing Ubuntu came with is ever removed (Firefox, the snaps and
  the rest stay);
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
in the dotfiles), and everything else goes in the dotfiles' distrobox
container.

To add a system package: add it to `lists/apt.txt` (and, for a vendor's
repo, its `.sources` file to `lists/apt-sources/` and its key to
`lists/apt-keys.txt`), push, then re-run `setup.sh`. A repo dropped from
`apt-sources/` isn't removed from the machine; delete its file in
`/etc/apt/sources.list.d/` by hand.

## Updating the pinned versions

Everything the dotfiles download is pinned to an exact version, so every
machine gets what was tested. `update-pins.sh` moves all the pins to the
latest stable release at once:

| Repo | Pin | Latest from |
| --- | --- | --- |
| dotfiles | mise, version and checksums in `.chezmoidata/packages.yaml` | jdx/mise's latest release and its `SHASUMS256.txt` |
| dotfiles | Nerd Font, `fonts.nerd_fonts` in `.chezmoidata/packages.yaml` | ryanoasis/nerd-fonts' latest release |
| dotfiles | CLI tools, `dot_config/mise/config.toml` | `mise outdated --bump` |
| dotfiles | Neovim plugins, `dot_config/nvim/lazy-lock.json` | `:Lazy sync`, run in a scratch folder |
| dotfiles | the distrobox container's Fedora, `fedora-toolbox:NN` in `assemble.ini` | Fedora's newest stable release |
| this one | Bitwarden's polkit action, `system/` | only compared with upstream; a difference is shown, never copied in |

"Latest" never means a pre-release or beta. mise's checksums come from its
release. The Catppuccin theme files in the dotfiles are copies, not pins;
re-copy them from catppuccin/<app> by hand if you ever want to.

Do this before moving to a new machine, and every couple of months
otherwise, so each round is small. All of it happens on branches: `main`
and the dotfiles in use don't change until the last step.

1. **Bump.** With Bitwarden unlocked (the script fetches both repos first):

   ```bash
   bash ~/repos/workstation-bootstrap/update-pins.sh
   ```

   It makes a branch `pins-YYYY-MM-DD` in both repos, in the worktrees
   `~/repos/workstation-bootstrap-pins-YYYY-MM-DD` and
   `~/repos/dotfiles-pins-YYYY-MM-DD`, with one commit per bump, and prints
   what it changed, what failed, and what to review (the polkit action). A
   repo with nothing to bump gets no branch. If GitHub's rate limit runs
   out, set `GITHUB_TOKEN` and run it again (after deleting the branches and
   worktrees it made).

2. **Make the branches reachable from a VM.** `setup.sh --branch` clones
   the dotfiles branch from GitHub, so push that one (only the branch):

   ```bash
   git -C ~/repos/dotfiles-pins-YYYY-MM-DD push -u origin pins-YYYY-MM-DD
   ```

   and serve this repo to the VM:

   ```bash
   mkdir -p ~/vm-share
   git -C ~/repos/workstation-bootstrap archive \
     --prefix=workstation-bootstrap/ -o ~/vm-share/bootstrap.tar.gz HEAD
   python3 -m http.server -d ~/vm-share -b 127.0.0.1 8000
   ```

3. **Test in a VM** (GNOME Boxes), installed from the Ubuntu release you run;
   reverting to a snapshot of a fresh install is quicker. Then, in the VM:

   ```bash
   curl -O http://10.0.2.2:8000/bootstrap.tar.gz && tar -xzf bootstrap.tar.gz
   bash workstation-bootstrap/setup.sh --branch pins-YYYY-MM-DD
   ```

   (A fresh Ubuntu may not have curl yet: `sudo apt install curl` first, or
   use `wget`.) Follow "Setting up a new machine" from step 2, and check:
   `Super+Shift+T` switches light/dark (GNOME, Alacritty, btop, bat,
   starship), `nvim` starts with its plugins and no errors, `mise ls` shows
   the new versions, `btop` opens from the `dev` container, Brave and VS Code start, the
   Nerd Font icons show in starship, and Bitwarden's unlock with system
   authentication works.

4. **If a bump breaks something**, undo just that commit in its worktree,
   push the dotfiles branch again and re-test:

   ```bash
   git -C ~/repos/dotfiles-pins-YYYY-MM-DD revert <commit>
   ```

5. **Merge, push and clean up**, once the VM is fine:

   ```bash
   b=pins-YYYY-MM-DD
   git -C ~/repos/workstation-bootstrap merge --ff-only "$b" && git -C ~/repos/workstation-bootstrap push
   chezmoi git -- merge --ff-only "$b" && chezmoi git -- push && chezmoi apply
   chezmoi git -- push origin --delete "$b"
   git -C ~/repos/workstation-bootstrap worktree remove ~/repos/workstation-bootstrap-$b
   git -C ~/repos/workstation-bootstrap branch -d "$b"
   chezmoi git -- worktree remove ~/repos/dotfiles-$b
   chezmoi git -- branch -d "$b"
   ```

   (Skip the lines for a repo that got no branch.) If this repo changed,
   refresh the drive (next section).

## Before leaving the old machine

1. **Update the pins** and test them (previous section), so the new machine
   starts from current versions that a VM has already run.
2. **Copy `~/Pictures/wallpapers`** to the new machine; the images aren't
   in the dotfiles.
3. **Refresh the copy on the drive:**

   ```bash
   git -C "/media/$USER/<drive>/workstation-bootstrap" pull
   ```

## Setting up a new machine

1. **Install Ubuntu** (the normal desktop install). The user you create in
   the installer is an administrator, so it has sudo. Connect to Wi-Fi or
   Ethernet.
2. **Log in, plug in the drive, open a terminal (`Ctrl+Alt+T`) and run:**

   ```bash
   bash "/media/$USER/<drive>/workstation-bootstrap/setup.sh"
   ```

   It asks for:
   - your **sudo password**, once, for the system step;
   - to **log into Bitwarden** and turn on **File > Settings > App settings
     (all accounts) > Enable SSH agent**, then press Enter;
   - to **approve the key** in Bitwarden when it checks GitHub and clones the
     dotfiles;
   - your **Git name and email**, the first time chezmoi runs.

   The dotfiles also build the distrobox container (htop, btop),
   which takes a few minutes.
3. **Reboot** (`systemctl reboot`) and log in. Flatpak apps are in the app
   grid, and `Super+Return` opens Alacritty.
4. **Copy `~/Pictures/wallpapers`** back and run `chezmoi apply`, which
   sets the wallpaper.
5. **In Bitwarden**, after logging in: File > Settings > Security > turn on
   **Unlock with system authentication**. Bitwarden then unlocks with your
   login password (or a fingerprint, if the machine has a reader) instead of
   the master password. After Bitwarden starts, the first unlock still needs
   the master password. This one can't be automated: Bitwarden keeps it in
   each account's own settings.

## If something goes wrong

- **A package name is wrong, or a step fails**: fix it in the matching repo,
  push, and run `setup.sh` again. A rerun only changes what differs from the
  list, and an existing dotfiles clone is updated rather than cloned again.
  If only the dotfiles part failed, add `--no-system` to skip the system step.
- **"Could not get lock /var/lib/dpkg/lock-frontend"**: the automatic
  updater (or the App Center) is busy; wait a minute and run `setup.sh`
  again.
- **"Network not ready"**: right after boot the network can take a moment;
  `setup.sh` retries for a minute on its own.
- **"The agent isn't answering yet, or has no keys"**: Bitwarden is locked, the
  SSH agent switch is off, or the vault has no SSH key items.
- **"GitHub didn't accept a key"**: the key in Bitwarden isn't added to your
  GitHub account, or you denied the request in Bitwarden.
- **`<your-user> is not in the sudoers file`**: the user isn't an
  administrator. From an administrator account, run
  `sudo usermod -aG sudo <your-user>`, then log out and back in.

## Testing a dotfiles branch

```bash
bash setup.sh --branch bootstrap-test
```

This only matters on the first run; after that chezmoi stays on that branch.
Without `--branch`, `setup.sh` clones the dotfiles' `main`.
