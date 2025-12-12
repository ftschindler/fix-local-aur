# Local AUR Repo DB Auto-Heal

This setup ensures a local `file://` pacman repo (e.g., `/var/lib/repo/aur`) always has a valid `aur.db` before you run `pacman -Sy` or install packages. It works alongside `paru` and handles cases where the repo DB goes missing.

## Files

- `fix_local_aur.bash`: Idempotent script to create `aur.db` when missing.
- `systemd-user/fix-aurdb.service`: User-mode oneshot service.
- `systemd-user/fix-aurdb.path`: User-mode path watcher for the repo dir.
- `systemd/fix-aurdb.service`: System-mode oneshot service.
- `systemd/fix-aurdb.path`: System-mode path watcher.

## Prerequisites

- `repo-add` (part of `pacman-contrib`/`pacman`): used to build the repo DB.
- The repo directory exists: `/var/lib/repo/aur`.
- The user or system service must have read/write permissions in the repo dir.

## User-mode installation (recommended when the user writes the repo)

Use this if the repo directory is writable by your user (common with `paru`).

1) Install the fixer script into your PATH:

```bash
install -m 0755 /home/felix/Projects/self/fix_local_aur.bash ~/.local/bin/fix-local-aur-db
```

1) Install the user systemd units:

```bash
install -Dm 0644 /home/felix/Projects/self/systemd-user/fix-aurdb.service ~/.config/systemd/user/fix-aurdb.service
install -Dm 0644 /home/felix/Projects/self/systemd-user/fix-aurdb.path ~/.config/systemd/user/fix-aurdb.path
systemctl --user daemon-reload
systemctl --user enable --now fix-aurdb.path
```

1) Optional: run once immediately and/or add a timer

```bash
systemctl --user start fix-aurdb.service
# Optional timer to run on login and hourly
cat > ~/.config/systemd/user/fix-aurdb.timer <<'EOF'
[Unit]
Description=Rebuild local AUR DB (user timer)

[Timer]
OnBootSec=30s
OnUnitActiveSec=1h
Unit=fix-aurdb.service

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now fix-aurdb.timer
```

1) Optional: persist user services across reboots without login

```bash
sudo loginctl enable-linger "$USER"
```

## System-mode installation (when the system manages the repo)

Use this if the repo directory is managed by root/system services. Ensure the service user can write to `/var/lib/repo/aur`.

1) Install the fixer script:

```bash
sudo install -m 0755 /home/felix/Projects/self/fix_local_aur.bash /usr/local/sbin/fix-local-aur-db
```

1) Install the system units:

```bash
sudo install -m 0644 /home/felix/Projects/self/systemd/fix-aurdb.service /etc/systemd/system/fix-aurdb.service
sudo install -m 0644 /home/felix/Projects/self/systemd/fix-aurdb.path /etc/systemd/system/fix-aurdb.path
sudo systemctl daemon-reload
sudo systemctl enable --now fix-aurdb.path
```

1) Optional: run once immediately

```bash
sudo systemctl start fix-aurdb.service
```

## Behavior

- The path unit triggers the service:
  - At login (user-mode) or boot (system-mode) if `*.pkg.*` exists in the repo dir.
  - Whenever the repo directory changes (new packages or adjustments).
- The script exits fast if:
  - No packages are present (cannot create a DB without content).
  - `aur.db` and `aur.db.tar.gz` already exist.

## Troubleshooting

- Missing DB but no packages:
  - Create or copy at least one `*.pkg.*` into `/var/lib/repo/aur` or temporarily comment out the local repo in `pacman.conf` until packages exist.
- Permissions:
  - Ensure your user (user-mode) or root (system-mode) can write to `/var/lib/repo/aur`.
- Verify units:

```bash
systemctl --user status fix-aurdb.path fix-aurdb.service
# or system-mode
sudo systemctl status fix-aurdb.path fix-aurdb.service
```

## Why not pacman hooks?

Pacman hooks run during transactions (pre/post) and do not run before the `-Sy` database refresh. A missing `aur.db` needs to be fixed earlier. Systemd path/timer units provide a proactive fix.
