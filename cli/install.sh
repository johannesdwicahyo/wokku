#!/bin/bash
# Wokku CLI Installer
# Usage: curl -sL https://wokku.dev/cli/install.sh | bash

set -e

INSTALL_DIR="/usr/local/bin"
CLI_URL="https://raw.githubusercontent.com/johannesdwicahyo/wokku/main/cli/wokku"

echo "Installing Wokku CLI..."

if [ ! -d "$INSTALL_DIR" ]; then
  echo "Creating $INSTALL_DIR..."
  sudo mkdir -p "$INSTALL_DIR"
fi

sudo curl -sL "$CLI_URL" -o "$INSTALL_DIR/wokku"
sudo chmod +x "$INSTALL_DIR/wokku"

echo "Wokku CLI installed to $INSTALL_DIR/wokku"
echo ""
echo "Get started:"
echo "  wokku auth:login"
echo "  wokku apps"
echo "  wokku help"
