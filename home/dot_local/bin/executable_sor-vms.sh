#!/usr/bin/env bash
# sor-vms.sh — start the SOR VMs and open a tmux session with an SSH pane per server VM.
#
#   ./sor-vms.sh            start Ubuntu Server, Debian, CentOS (headless) + tmux
#   ./sor-vms.sh --desktop  same, and also start Ubuntu Desktop with its window
#   ./sor-vms.sh stop       ACPI shutdown of every running SOR VM
#   ./sor-vms.sh keys       copy ~/.ssh/sor_ed25519 to every server VM (asks each password once)
#
# Ports come from the SOR NAT network forwards (see SOR-VM-Setup-Guide.pdf, section 4).
set -euo pipefail

SESSION="sor"

# VM name | SSH port | SSH user  — default user mshf (override with SOR_USER=name).
VMS=(
  "Debian|2223|${SOR_USER:-mshf}"
  "CentOS|2224|${SOR_USER:-mshf}"
  "Ubuntu Server|2222|${SOR_USER:-mshf}"   # last = full-width bottom pane
)
DESKTOP_VM="Ubuntu Desktop"
KEY="$HOME/.ssh/sor_ed25519"

is_running() { VBoxManage list runningvms | grep -q "^\"$1\" "; }

start_vm() {  # $1 = name, $2 = gui|headless
  if is_running "$1"; then
    echo "· $1 already running"
  else
    echo "· starting $1 ($2)"
    VBoxManage startvm "$1" --type "$2" >/dev/null
  fi
}

if [[ "${1:-}" == "stop" ]]; then
  for vm in "Ubuntu Server" "Debian" "CentOS" "$DESKTOP_VM"; do
    if is_running "$vm"; then
      echo "· shutting down $vm"
      VBoxManage controlvm "$vm" acpipowerbutton
    fi
  done
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  exit 0
fi

wait_ssh() {  # $1 = name, $2 = port
  until ssh-keyscan -T 2 -p "$2" 127.0.0.1 >/dev/null 2>&1; do
    echo "Waiting for SSH on $1 (port $2)..."; sleep 3
  done
}

[[ "${1:-}" == "--desktop" ]] && start_vm "$DESKTOP_VM" gui
for entry in "${VMS[@]}"; do
  IFS='|' read -r name _ _ <<<"$entry"
  start_vm "$name" headless
done

if [[ "${1:-}" == "keys" ]]; then
  [[ -f "$KEY.pub" ]] || ssh-keygen -t ed25519 -N "" -C "sor-vms" -f "$KEY" -q
  for entry in "${VMS[@]}"; do
    IFS='|' read -r name port user <<<"$entry"
    wait_ssh "$name" "$port"
    echo "== $name: enter $user's password if asked"
    ssh-copy-id -i "$KEY.pub" -p "$port" "$user@127.0.0.1"
  done
  echo "Done. Run ./sor-vms.sh to open the tmux session."
  exit 0
fi

# Already open? Just attach to it.
if tmux has-session -t "$SESSION" 2>/dev/null; then
  exec tmux attach -t "$SESSION"
fi

# Each pane waits until sshd answers on its forwarded port, then connects.
# After you log out, the pane offers to reconnect.
pane_cmd() {  # $1 = name, $2 = port, $3 = user
  cat <<EOF
printf '\033]2;%s\033\\\\' '$1'
until ssh-keyscan -T 2 -p $2 127.0.0.1 >/dev/null 2>&1; do
  echo "Waiting for SSH on $1 (port $2)..."; sleep 3
done
while true; do
  ssh -p $2 -i "$KEY" -o ServerAliveInterval=30 $3@127.0.0.1
  read -rp "Disconnected from $1. Enter to reconnect, Ctrl-C to close: "
done
EOF
}

first=1
for entry in "${VMS[@]}"; do
  IFS='|' read -r name port user <<<"$entry"
  cmd="$(pane_cmd "$name" "$port" "$user")"
  if (( first )); then
    tmux new-session -d -s "$SESSION" -n vms bash -c "$cmd"
    first=0
  else
    tmux split-window -t "$SESSION:vms" bash -c "$cmd"
  fi
  tmux select-layout -t "$SESSION:vms" tiled >/dev/null
done

tmux set-option -t "$SESSION" pane-border-status top >/dev/null
tmux set-option -t "$SESSION" pane-border-format " #{pane_title} " >/dev/null
tmux bind-key -T prefix S setw synchronize-panes \; display "sync #{?synchronize-panes,ON,OFF}"

exec tmux attach -t "$SESSION"
