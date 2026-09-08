# ELAN 04f3:0c00 Fingerprint Sensor — Fedora 43 Setup Guide

This document explains **what was done** to make the built-in fingerprint sensor work on this
laptop running Fedora 43, and **what to do when a Fedora update breaks it**.

---

## 1. Overview

| Item | Value |
| ---- | ----- |
| Laptop | HP Pavilion |
| OS | Fedora 43 (KDE Plasma) |
| Kernel | 7.1.13-100.fc43.x86_64 |
| Fingerprint sensor | `04f3:0c00` Elan Microelectronics **ELAN:ARM-M4** (Match-on-Chip 2) |
| Fingerprint service | `fprintd` |
| Driver library | `libfprint` (custom `elanmoc2` build) |

---

## 2. The Problem

The fingerprint sensor (`04f3:0c00`) is detected by the OS (`lsusb` shows it), but it does not work.

**Why:** The stock Fedora `libfprint` package does **not** include a driver for this sensor.
`fprintd` (the fingerprint daemon) runs fine, but it reports *"No devices available"* because no
driver module in the library knows how to talk to this hardware.

```text
$ lsusb | grep 04f3
Bus 003 Device 003: ID 04f3:0c00 Elan Microelectronics Corp. ELAN:ARM-M4
```

The sensor uses a **proprietary protocol** (USB vendor-specific class, not standard HID), so it
needs a special driver. A Linux developer (Depau) wrote one on a branch of `libfprint` called
**`elanmoc2`** ("Match-on-Chip 2"). This branch is not yet merged into the official `libfprint`,
so we have to build and install it ourselves.

---

## 3. What Was Done (Step by Step)

### 3.1 Installed build dependencies

These packages are required to compile `libfprint` from source:

```bash
sudo dnf install -y \
    git gcc gcc-c++ meson ninja-build pkgconf-pkg-config cmake \
    openssl-devel systemd-devel glib2-devel gobject-introspection-devel \
    cairo-devel pixman-devel gusb-devel libusb1-devel json-glib-devel
```

### 3.2 Cloned the driver source

The driver lives in a fork of `libfprint` on the `elanmoc2` branch:

```bash
mkdir -p ~/Repositories
cd ~/Repositories
git clone --branch elanmoc2 https://gitlab.freedesktop.org/Depau/libfprint.git elanmoc2
```

> **Note:** The installer script from the `elanmoc2-fedora-installer` repo contained a bug
> (`cd ~/Repositories/elanmoc2/libfprint` — a wrong path). We built at the correct repo root:
> `~/Repositories/elanmoc2`.

### 3.3 Built and installed the driver

```bash
cd ~/Repositories/elanmoc2
rm -rf build
meson setup build --prefix=/usr/local
ninja -C build
sudo ninja -C build install
sudo ldconfig
```

This installs the custom library to **`/usr/local/lib64/libfprint-2.so.2.0.0`**.

### 3.4 Made `fprintd` load the custom library

`fprintd` normally loads Fedora's `libfprint` from `/usr/lib64`. We created a systemd override
that tells `fprintd` to also look in `/usr/local/lib64` (where our custom library is):

```bash
sudo mkdir -p /etc/systemd/system/fprintd.service.d
sudo tee /etc/systemd/system/fprintd.service.d/override.conf >/dev/null <<'EOF'
[Service]
Environment="LD_LIBRARY_PATH=/usr/local/lib64"
EOF
sudo systemctl daemon-reload
sudo systemctl restart fprintd
```

The override file (contents):

```text
/etc/systemd/system/fprintd.service.d/override.conf
[Service]
Environment="LD_LIBRARY_PATH=/usr/local/lib64"
```

### 3.5 Verified the sensor was detected

```bash
fprintd-list $USER
```

Expected output:

```text
found 1 devices
Device at /net/reactivated/Fprint/Device/0
Using device /net/reactivated/Fprint/Device/0
Fingerprints for user krxsna on ELAN Match-on-Chip 2 (press):
 - #0: right-index-finger
```

### 3.6 Enrolled a fingerprint

**In KDE:** System Settings → Users → enable *Fingerprint Login* → Add Fingerprint.
Follow the prompts, touching the sensor when it lights up.

> **Important quirk:** This driver can **hang near the end of enrollment (~95–100%)**.
> If that happens, click **Cancel** — the fingerprint is **still saved** on cancel.
> This is a known quirk of the `elanmoc2` driver, not a real failure.

**Alternative (CLI):**

```bash
fprintd-enroll
```

### 3.7 Verified authentication works

```bash
fprintd-verify $USER
```

Expected output:

```text
Verify started!
Verifying: right-index-finger
Verify result: verify-match (done)
```

---

## 4. What Is Enabled

Because `/etc/pam.d/sudo` includes `system-auth`, and `system-auth` contains:

```text
auth        sufficient    pam_fprintd.so
```

fingerprint authentication is active for:

| Use case | How to test |
| -------- | ----------- |
| **sudo** in a terminal | `sudo -v` → place finger on sensor |
| **KDE screen unlock** | Press `Super+L`, then place finger |
| **KDE login** | At the login screen, place finger |

---

## 5. What to Do When a Fedora Update Breaks It

### Why updates break it

The custom driver is installed in **`/usr/local/lib64`** — *outside* the package manager.
When Fedora updates `libfprint` / `fprintd`:

1. The system package may overwrite `/usr/lib64/libfprint-2.so.2` (the stock one) — normally fine.
2. But a `fprintd` update may restart the daemon with a changed environment, or
   `LD_LIBRARY_PATH` handling may change, so the daemon stops loading the custom library.
3. Sometimes the system `libfprint` update is a **newer version number**, and the daemon loads
   that instead.

**Symptom after an update:** `fprintd-list $USER` reports "No devices available" even though the
sensor is still present in `lsusb`.

### Quick checks (diagnose first)

```bash
# 1. Is the sensor still there?
lsusb | grep 04f3

# 2. Is fprintd running?
systemctl status fprintd --no-pager

# 3. Is the override still present?
systemctl show fprintd | grep Environment
# Expected: Environment=LD_LIBRARY_PATH=/usr/local/lib64

# 4. Is the custom library still installed?
ls -la /usr/local/lib64/libfprint*

# 5. Does fprintd see any devices?
fprintd-list $USER
```

### How to fix it

#### Option A — Re-run the build (recommended, restores everything)

**One-liner:** a ready-made script lives next to this doc at `~/Repositories/elanmoc2/elanmoc2-reinstall.sh`:

```bash
~/Repositories/elanmoc2/elanmoc2-reinstall.sh
```

Or manually — the source is already cloned at `~/Repositories/elanmoc2`, so a rebuild is quick:

```bash
cd ~/Repositories/elanmoc2
git fetch
git checkout elanmoc2
git pull

rm -rf build
meson setup build --prefix=/usr/local
ninja -C build
sudo ninja -C build install
sudo ldconfig

# Re-create the systemd override (in case it was removed)
sudo mkdir -p /etc/systemd/system/fprintd.service.d
sudo tee /etc/systemd/system/fprintd.service.d/override.conf >/dev/null <<'EOF'
[Service]
Environment="LD_LIBRARY_PATH=/usr/local/lib64"
EOF

sudo systemctl daemon-reload
sudo systemctl restart fprintd

# Verify
fprintd-list $USER
```

If your fingerprints are still enrolled, they should still work after the rebuild.
If not, re-enroll (see section 3.6).

#### Option B — Just recreate the override

If only the override was removed (the library is still in `/usr/local/lib64`):

```bash
sudo mkdir -p /etc/systemd/system/fprintd.service.d
sudo tee /etc/systemd/system/fprintd.service.d/override.conf >/dev/null <<'EOF'
[Service]
Environment="LD_LIBRARY_PATH=/usr/local/lib64"
EOF
sudo systemctl daemon-reload
sudo systemctl restart fprintd
```

#### Option C — Full clean rebuild (if things are badly broken)

If the custom library is gone or corrupted:

```bash
# Remove old source and re-clone fresh
rm -rf ~/Repositories/elanmoc2
mkdir -p ~/Repositories
cd ~/Repositories
git clone --branch elanmoc2 https://gitlab.freedesktop.org/Depau/libfprint.git elanmoc2

cd ~/Repositories/elanmoc2
meson setup build --prefix=/usr/local
ninja -C build
sudo ninja -C build install
sudo ldconfig

# Override + restart (same as Option A)
sudo mkdir -p /etc/systemd/system/fprintd.service.d
sudo tee /etc/systemd/system/fprintd.service.d/override.conf >/dev/null <<'EOF'
[Service]
Environment="LD_LIBRARY_PATH=/usr/local/lib64"
EOF
sudo systemctl daemon-reload
sudo systemctl restart fprintd
```

---

## 6. How to Fully Revert (go back to stock)

If you ever want to remove the custom driver and go back to Fedora's default behavior:

```bash
# Remove the systemd override
sudo rm -f /etc/systemd/system/fprintd.service.d/override.conf
sudo systemctl daemon-reload

# Reinstall stock packages
sudo dnf reinstall -y libfprint fprintd
sudo ldconfig
sudo systemctl restart fprintd
```

---

## 7. Useful Diagnostic Commands

| Command | Purpose |
| ------- | ------- |
| `lsusb \| grep 04f3` | Confirm the sensor is connected |
| `fprintd-list $USER` | List detected readers + enrolled fingers |
| `fprintd-enroll` | Enroll a new fingerprint (CLI) |
| `fprintd-verify $USER` | Test a fingerprint match |
| `systemctl status fprintd` | Check the daemon is running |
| `systemctl show fprintd \| grep Environment` | Check the override is loaded |
| `journalctl -u fprintd` | View fprintd logs (e.g. "Device was already claimed") |
| `ls -la /usr/local/lib64/libfprint*` | Confirm the custom library exists |

---

## 8. Troubleshooting Tips

- **"Device was already claimed"** in logs → A previous enrollment window is still holding the
  sensor. Close System Settings (or restart fprintd: `sudo systemctl restart fprintd`) and retry.
- **Enrollment hangs near the end** → Click Cancel; the print is saved anyway (driver quirk).
- **"No devices available" after an update** → See section 5 (diagnose, then re-run the build).
- **Fingerprint not offered at sudo/login** → Check `grep fprint /etc/pam.d/system-auth` returns
  `auth sufficient pam_fprintd.so`. If missing, the PAM line was removed by an update; add it back:
  ```bash
  echo 'auth        sufficient    pam_fprintd.so' | sudo tee -a /etc/pam.d/system-auth
  ```

---

*Generated: 2026-09-08. Driver source: Depau/libfprint `elanmoc2` branch (stored at `~/Repositories/elanmoc2`). Sensor: ELAN 04f3:0c00.*
