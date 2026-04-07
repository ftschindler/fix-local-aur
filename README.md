# Local AUR Repo DB Auto-Heal

This setup ensures a local `file://` pacman repo (e.g., `/var/lib/repo/aur`) always has a valid `aur.db` before you run `pacman -Sy` or install packages. It works alongside `paru` and handles cases where the repo DB goes missing.

## Files

- `fix_local_aur.bash`: Idempotent script to create `aur.db` when missing.
- `systemd-user/fix-aurdb.service`: User-mode oneshot service.
- `systemd-user/fix-aurdb.path`: User-mode path watcher for the repo dir.
- `systemd-user/fix-aurdb.timer`: User-mode timer (boot + hourly checks).
- `systemd-user/fix-aurdb-failure-notify.service`: Desktop notification on failure (user).
- `systemd/fix-aurdb.service`: System-mode oneshot service.
- `systemd/fix-aurdb.path`: System-mode path watcher.
- `systemd/fix-aurdb.timer`: System-mode timer (boot + hourly checks).
- `systemd/fix-aurdb-failure-notify.service`: Desktop notification on failure (system).

## Prerequisites

- `repo-add` (part of `pacman-contrib`/`pacman`): used to build the repo DB.
- The aur repo directory exists: `/var/lib/repo/aur`.
- The user or system service must have read/write permissions in the aur repo dir.
- This repo checked out:

  ```bash
  cd /tmp
  git clone https://github.com/ftschindler/fix-local-aur.git
  cd fix-local-aur
  ```

## User-mode installation (recommended when the user writes the repo)

Use this if the repo directory is writable by your user (common with `paru`).

1) Install the fixer script into your PATH:

```bash
install -m 0755 fix_local_aur.bash ~/.local/bin/fix-local-aur-db
```

1) Install the user systemd units (path watcher + timer + notification):

```bash
install -Dm 0644 systemd-user/fix-aurdb.service ~/.config/systemd/user/fix-aurdb.service
install -Dm 0644 systemd-user/fix-aurdb.path ~/.config/systemd/user/fix-aurdb.path
install -Dm 0644 systemd-user/fix-aurdb.timer ~/.config/systemd/user/fix-aurdb.timer
install -Dm 0644 systemd-user/fix-aurdb-failure-notify.service ~/.config/systemd/user/fix-aurdb-failure-notify.service
systemctl --user daemon-reload
systemctl --user enable --now fix-aurdb.path
systemctl --user enable --now fix-aurdb.timer
```

The path unit watches for directory changes (new packages added) while the timer ensures the DB exists on boot and provides hourly checks as a safety net. If the service fails, you'll receive a desktop notification.

1) Optional: run once immediately

```bash
systemctl --user start fix-aurdb.service
```

1) Optional: persist user services across reboots without login

```bash
sudo loginctl enable-linger "$USER"
```

## System-mode installation (when the system manages the repo)

Use this if the repo directory is managed by root/system services. Ensure the service user can write to `/var/lib/repo/aur`.

1) Install the fixer script:

```bash
sudo install -m 0755 fix_local_aur.bash /usr/local/sbin/fix-local-aur-db
```

1) Install the system units (path watcher + timer + notification):

```bash
sudo install -m 0644 systemd/fix-aurdb.service /etc/systemd/system/fix-aurdb.service
sudo install -m 0644 systemd/fix-aurdb.path /etc/systemd/system/fix-aurdb.path
sudo install -m 0644 systemd/fix-aurdb.timer /etc/systemd/system/fix-aurdb.timer
sudo install -m 0644 systemd/fix-aurdb-failure-notify.service /etc/systemd/system/fix-aurdb-failure-notify.service
sudo systemctl daemon-reload
sudo systemctl enable --now fix-aurdb.path
sudo systemctl enable --now fix-aurdb.timer
```

The path unit watches for directory changes (new packages added) while the timer ensures the DB exists on boot and provides hourly checks as a safety net. If the service fails, you'll receive a desktop notification.

1) Optional: run once immediately

```bash
sudo systemctl start fix-aurdb.service
```

## Behavior

- **Path unit**: Triggers when the repo directory is modified (new packages added/removed).
- **Timer unit**: Runs 30s-1min after boot and hourly thereafter as a safety net.
- The script exits immediately if:
  - No packages are present (cannot create a DB without content).
  - `aur.db` and `aur.db.tar.gz` already exist.
- Both units can run concurrently safely (the script uses locking).

## Troubleshooting

- Missing DB but no packages:
  - Create or copy at least one `*.pkg.*` into `/var/lib/repo/aur` or temporarily comment out the local repo in `pacman.conf` until packages exist.
- Permissions:
  - Ensure your user (user-mode) or root (system-mode) can write to `/var/lib/repo/aur`.
- Verify units:

```bash
systemctl --user status fix-aurdb.path fix-aurdb.timer fix-aurdb.service
# or system-mode
sudo systemctl status fix-aurdb.path fix-aurdb.timer fix-aurdb.service
```

## Why not pacman hooks?

Pacman hooks run during transactions (pre/post) and do not run before the `-Sy` database refresh. A missing `aur.db` needs to be fixed earlier. Systemd path/timer units provide a proactive fix.
