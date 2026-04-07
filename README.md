# Local AUR Repo DB Auto-Heal

This setup ensures a local `file://` pacman repo (e.g., `/var/lib/repo/aur`) always has a valid `aur.db` before you run `pacman -Sy` or install packages. It works alongside `paru` and handles cases where the repo DB goes missing.

## Files

- `fix_local_aur.bash`: Idempotent script to create `aur.db` when missing.
- `fix-aurdb.service`: Systemd user service (oneshot).
- `fix-aurdb.path`: Systemd path watcher for the repo directory.
- `fix-aurdb.timer`: Systemd timer (runs on boot + hourly).
- `fix-aurdb-failure-notify.service`: Desktop notification on failure.

## Prerequisites

- `repo-add` (part of `pacman-contrib`/`pacman`): used to build the repo DB.
- The AUR repo directory exists: `/var/lib/repo/aur`.
- Your user must have read/write permissions in the AUR repo directory (standard with `paru`).
- This repo checked out:

  ```bash
  cd /tmp
  git clone https://github.com/ftschindler/fix-local-aur.git
  cd fix-local-aur
  ```

## Installation

### Quick install

From the repo root, run:

```bash
make install
```

This will install the script, systemd units, and enable the path and timer units.

### Manual installation

1. Install the fixer script into your PATH:

   ```bash
   install -m 0755 fix_local_aur.bash ~/.local/bin/fix-local-aur-db
   ```

1. Install the systemd user units (path watcher + timer + notification):

   ```bash
   install -Dm 0644 fix-aurdb.service ~/.config/systemd/user/fix-aurdb.service
   install -Dm 0644 fix-aurdb.path ~/.config/systemd/user/fix-aurdb.path
   install -Dm 0644 fix-aurdb.timer ~/.config/systemd/user/fix-aurdb.timer
   install -Dm 0644 fix-aurdb-failure-notify.service ~/.config/systemd/user/fix-aurdb-failure-notify.service
   systemctl --user daemon-reload
   systemctl --user enable --now fix-aurdb.path
   systemctl --user enable --now fix-aurdb.timer
   ```

   The path unit watches for directory changes (new packages added) while the timer ensures the DB exists on boot and provides hourly checks as a safety net. If the service fails, you'll receive a desktop notification.

### Post-installation (optional)

1. Run once immediately:

   ```bash
   systemctl --user start fix-aurdb.service
   ```

2. Persist user services across reboots without login:

   ```bash
   sudo loginctl enable-linger "$USER"
   ```

## Verification

After installation, verify everything is working:

1. Check that units are active and enabled:

   ```bash
   systemctl --user status fix-aurdb.path fix-aurdb.timer
   ```

   Both should show `Active: active (waiting)` and `Loaded: ... enabled`.

2. Check the timer schedule:

   ```bash
   systemctl --user list-timers | grep aurdb
   ```

   Should show the next scheduled run time.

3. Test the script manually:

   ```bash
   systemctl --user start fix-aurdb.service
   systemctl --user status fix-aurdb.service
   ```

   Should show `Active: inactive (dead)` with a recent successful completion.

4. Verify the script is in your PATH:

   ```bash
   which fix-local-aur-db
   ```

   Should output `~/.local/bin/fix-local-aur-db`.

## Behaviour

- **Path unit**: Triggers when the repo directory is modified (new packages added/removed).
- **Timer unit**: Runs 30s after login/boot and hourly thereafter as a safety net.
- The script exits immediately if:
  - No packages are present (cannot create a DB without content).
  - `aur.db` and `aur.db.tar.gz` already exist.
- Both units can run concurrently safely (the script uses locking).

## Troubleshooting

- Missing DB but no packages:
  - Create or copy at least one `*.pkg.*` into `/var/lib/repo/aur` or temporarily comment out the local repo in `pacman.conf` until packages exist.
- Permissions:
  - Ensure your user can write to `/var/lib/repo/aur`.
- Verify units:

```bash
systemctl --user status fix-aurdb.path fix-aurdb.timer fix-aurdb.service
```

## Why not pacman hooks?

Pacman hooks run during transactions (pre/post) and do not run before the `-Sy` database refresh. A missing `aur.db` needs to be fixed earlier. Systemd path/timer units provide a proactive fix.
