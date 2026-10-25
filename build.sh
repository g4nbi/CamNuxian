#!/bin/bash
# Builds com.nyxian.camera_<ver>_iphoneos-arm64e.deb  (run on macOS with Xcode)
set -euo pipefail
cd "$(dirname "$0")"
VER=$(grep '^Version:' layout/DEBIAN/control | awk '{print $2}')
OUT=build
rm -rf "$OUT" && mkdir -p "$OUT"
cp -R layout "$OUT/pkg"
APP="$OUT/pkg/Applications/NyxCamera.app"

xcrun --sdk iphoneos clang -fobjc-arc -O2 \
  -arch arm64 -miphoneos-version-min=15.0 \
  -framework Foundation -framework UIKit -framework AVFoundation -framework Photos \
  src/main.m -o "$APP/NyxCamera"

# fake-sign (Nyxian re-signs on install, this just keeps the Mach-O well-formed)
if command -v ldid >/dev/null; then ldid -S "$APP/NyxCamera"; fi

chmod 755 "$APP/NyxCamera" "$OUT/pkg/DEBIAN/postinst" "$OUT/pkg/DEBIAN/postrm"
export COPYFILE_DISABLE=1
dpkg-deb -Zgzip --root-owner-group -b "$OUT/pkg" "$OUT/com.nyxian.camera_${VER}_iphoneos-arm64e.deb"
ls -l "$OUT"/*.deb
