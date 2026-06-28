#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PYTHON_BIN="${PYTHON:-}"
if [ -z "$PYTHON_BIN" ] && [ -x ".venv/bin/python" ]; then
  PYTHON_BIN=".venv/bin/python"
fi
if [ -z "$PYTHON_BIN" ]; then
  PYTHON_BIN="python3"
fi

"$PYTHON_BIN" -m PyInstaller \
  --name "SDJI Rename Tool" \
  --windowed \
  --noconfirm \
  --clean \
  --icon "pic_rename_tool/assets/icons/app.icns" \
  --collect-data pic_rename_tool \
  --osx-bundle-identifier cn.ijoyer.sdjirename \
  pic_rename_tool/gui.py

echo "Built: dist/SDJI Rename Tool.app"
