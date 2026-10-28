#!/bin/bash
# Regenerate Resources/AppIcon.icns and docs/icon.png from scripts/make-icon.swift
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -O scripts/make-icon.swift -o build/make-icon
iconset="$(build/make-icon)"
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
echo "✓ Icon regenerated"
