# workstation-bootstrap

Takes a fresh **Ubuntu** install (the stock GNOME desktop) to my working
desktop, with my dotfiles.

Who does what:

| Tool | Job | Needs sudo |
| --- | --- | --- |
| this repo (`setup.sh`) | apt packages, including Brave, VS Code, mise and Claude Desktop from their vendors' repos; automatic security updates; Bitwarden's polkit action; runs chezmoi (through mise) | yes, once |
| Bitwarden | holds the SSH keys and is the SSH agent, for pushing (both repos are public, so nothing needs it to install) | no |
| chezmoi ([dotfiles](https://github.com/michellhuaman/dotfiles)) | dotfiles, flatpaks, CLI tools (mise), fonts, GNOME settings and shortcuts, Catppuccin theme, user services | no |
| distrobox and podman (installed here) | containers you make by hand, for anything that doesn't belong on the host | no |
| QEMU/KVM, libvirt and virt-manager (installed here) | virtual machines: Virtual Machine Manager's "QEMU/KVM" connection, or `virsh` and `virt-install` | no, once you're in the libvirt group |
| VirtualBox (installed here, from Ubuntu's multiverse) | virtual machines in VirtualBox Manager or `VBoxManage`; not at the same time as a KVM VM (virt-manager's, or Claude Desktop's Cowork), since only one can hold AMD-V/VT-x | no (USB passthrough needs the vboxusers group) |

Nothing secret lives here or in the dotfiles, so both repos are public:
a new machine downloads this one and clones the dotfiles over HTTPS, with
no key. Pushes go over SSH, through Bitwarden's agent.

## Layout

```
autoinstall.yaml                answers for the Ubuntu installer ("Automated installation")
setup.sh                        the one script to run, after the first login
update-pins.sh                  bumps the dotfiles' pinned Nerd Font, on a branch
lists/apt.txt                   apt packages setup.sh makes sure are installed
lists/apt-sources/              vendor repos (Brave, VS Code, mise, Claude Desktop), copied to /etc/apt/sources.list.d/
lists/apt-keys.txt              their signing keys, checked by fingerprint, saved to /etc/apt/keyrings/
lists/groups.txt                groups setup.sh adds your user to (libvirt, kvm, vboxusers)
system/com.bitwarden.Bitwarden.policy  Bitwarden's polkit action (installed to /etc/polkit-1/actions)
```

## How it works

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
in the dotfiles).

To add a system package: add it to `lists/apt.txt` (and, for a vendor's
repo, its `.sources` file to `lists/apt-sources/` and its key to
`lists/apt-keys.txt`), push, then re-run `setup.sh`. A repo dropped from
`apt-sources/` isn't removed from the machine; delete its file in
`/etc/apt/sources.list.d/` by hand.

## Updating the pinned versions

The Nerd Font the dotfiles download is pinned to an exact version and
checksum. `update-pins.sh` moves it to the latest stable release:

| Repo | Pin | Latest from |
| --- | --- | --- |
| dotfiles | Nerd Font, `fonts.nerd_fonts` and its checksum `fonts.nerd_fonts_sha256` in `.chezmoidata/packages.yaml` | ryanoasis/nerd-fonts' latest release (the checksum from its `SHA-256.txt`) |
| this one | Bitwarden's polkit action, `system/` | only compared with upstream; a difference is shown, never copied in |

"Latest" never means a pre-release or beta. The CLI tools aren't pinned
(mise installs their latest release, and `update` in `.bashrc` upgrades
them), and neither is mise itself: it's an apt package from its own repo,
updated with the rest of the system. The Catppuccin theme files in the dotfiles are copies, not pins;
re-copy them from catppuccin/<app> by hand if you ever want to.

Do this before moving to a new machine, and every couple of months
otherwise, so each round is small. All of it happens on branches: `main`
and the dotfiles in use don't change until the last step.

1. **Bump** (the script fetches both repos first):

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

2. **Push the branches** (only the branches; `main` stays as it is), so the
   VM can download them from GitHub:

   ```bash
   b=pins-YYYY-MM-DD
   git -C ~/repos/workstation-bootstrap-$b push -u origin "$b"
   git -C ~/repos/dotfiles-$b push -u origin "$b"
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
   wget -qO- https://github.com/michellhuaman/workstation-bootstrap/archive/refs/heads/$b.tar.gz | tar -xz
   bash workstation-bootstrap-$b/setup.sh --branch "$b"
   ```

   (For a repo that got no branch: download `main` instead, or leave out
   `--branch`.) Reboot the VM, and check: `Super+Shift+T` switches
   light/dark (GNOME, Alacritty, bat, starship), the font is the new
   version (`fc-list | grep JetBrainsMono`), `git commit` opens vim, Brave and VS Code start, the Nerd Font
   icons show in starship, Bitwarden starts at login, and its unlock with
   system authentication works.

4. **If a bump breaks something**, undo just that commit in its worktree,
   push that branch again and re-test from the fresh install (step 3):

   ```bash
   git -C ~/repos/dotfiles-pins-YYYY-MM-DD revert <commit>
   git -C ~/repos/dotfiles-pins-YYYY-MM-DD push
   ```

5. **Merge, push and clean up**, once the VM is fine:

   ```bash
   b=pins-YYYY-MM-DD
   git -C ~/repos/workstation-bootstrap merge --ff-only "$b" && git -C ~/repos/workstation-bootstrap push
   git -C ~/repos/workstation-bootstrap push origin --delete "$b"
   chezmoi git -- merge --ff-only "$b" && chezmoi git -- push && chezmoi apply
   chezmoi git -- push origin --delete "$b"
   git -C ~/repos/workstation-bootstrap worktree remove ~/repos/workstation-bootstrap-$b
   git -C ~/repos/workstation-bootstrap branch -d "$b"
   chezmoi git -- worktree remove ~/repos/dotfiles-$b
   chezmoi git -- branch -d "$b"
   ```

   (Skip the lines for a repo that got no branch.) Then shut the VM down:
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

## Before leaving the old machine

1. **Update the pins** and test them (previous section), so the new machine
   starts from current versions that a VM has already run.
2. **Push everything** in both repos: the new machine gets them from GitHub.

## Setting up a new machine

1. **Install Ubuntu.** Connect to Wi-Fi or Ethernet when the installer
   asks, and at "Type of installation" pick **Automated installation** with
   this URL:

   ```
   https://raw.githubusercontent.com/michellhuaman/workstation-bootstrap/main/autoinstall.yaml
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
   wget -qO- https://github.com/michellhuaman/workstation-bootstrap/archive/refs/heads/main.tar.gz | tar -xz
   bash workstation-bootstrap-main/setup.sh
   ```

   It only asks for your **sudo password**, once, for the system step. It
   also clones this repo into `~/repos/workstation-bootstrap` (pulls over
   HTTPS, pushes over SSH once step 5 is done), so the downloaded
   `workstation-bootstrap-main` folder can be deleted afterwards.

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

## If something goes wrong

- **A package name is wrong, or a step fails**: fix it in the matching repo,
  push, and run `setup.sh` again. A rerun only changes what differs from the
  list, and an existing dotfiles clone is updated rather than cloned again.
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

## Testing a dotfiles branch

```bash
bash setup.sh --branch bootstrap-test
```

This only matters on the first run; after that chezmoi stays on that branch.
Without `--branch`, `setup.sh` clones the dotfiles' `main`.
