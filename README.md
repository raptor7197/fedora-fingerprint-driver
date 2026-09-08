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

