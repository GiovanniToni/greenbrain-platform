#!/bin/bash
# Install systemd unit files from this directory to /etc/systemd/system/
# Usage: sudo bash infra/systemd/install.sh
set -e

UNIT_DIR=/etc/systemd/system
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing units from $SRC_DIR to $UNIT_DIR ..."
cp "$SRC_DIR"/*.service "$UNIT_DIR/"
cp "$SRC_DIR"/*.timer "$UNIT_DIR/"

systemctl daemon-reload
echo "Done. Installed $(ls "$SRC_DIR"/*.service "$SRC_DIR"/*.timer | wc -l) unit files."
