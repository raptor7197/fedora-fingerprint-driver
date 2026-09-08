#!/usr/bin/env bash
# Rebuild and reinstall the ELAN 04f3:0c00 elanmoc2 libfprint driver
# and re-create the fprintd systemd override. Safe to re-run.
set -e

echo "==> Building elanmoc2 libfprint..."

cd ~/Repositories/elanmoc2
git fetch
git checkout elanmoc2
git pull

rm -rf build
meson setup build --prefix=/usr/local
ninja -C build
sudo ninja -C build install
sudo ldconfig

echo "==> Creating fprintd systemd override..."

sudo mkdir -p /etc/systemd/system/fprintd.service.d
sudo tee /etc/systemd/system/fprintd.service.d/override.conf >/dev/null <<'EOF'
[Service]
Environment="LD_LIBRARY_PATH=/usr/local/lib64"
EOF

sudo systemctl daemon-reload
sudo systemctl restart fprintd

echo "==> Done. Verifying..."

sleep 1
fprintd-list "$USER"

echo
echo "If no devices are shown, run fprintd-enroll to (re)enroll a fingerprint."