#!/bin/zsh
set -eu
task_dir="${0:A:h}"
app_dir="${task_dir:h}/定位助手.app"
task_swiftc="$(xcrun --find swiftc)"
task_sdk="$(xcrun --sdk macosx --show-sdk-path)"
task_cache="${TMPDIR:-/tmp}/iphone-location-helper-swift-cache"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$task_dir/Assets"
mkdir -p "$task_cache"
cp "$task_dir/Info.plist" "$app_dir/Contents/Info.plist"
# Keep the optional duplicate SwiftBridging module-map workaround portable.
task_python="${PYTHON:-python3}"
"$task_python" "$task_dir/build-support/make_overlay.py" "$task_dir/build-support/empty.modulemap" "$task_cache/overlay.json"
"$task_swiftc" \
  -sdk "$task_sdk" \
  -swift-version 5 -O -framework AppKit -framework MapKit -framework CoreLocation \
  -module-cache-path "$task_cache" \
  -vfsoverlay "$task_cache/overlay.json" \
  "$task_dir/App.swift" "$task_dir/MapCanvas.swift" "$task_dir/TrackGeometry.swift" "$task_dir/TrackGeometryCheck.swift" "$task_dir/PlaceSearch.swift" "$task_dir/IconPainter.swift" -o "$app_dir/Contents/MacOS/LocationHelper"
"$app_dir/Contents/MacOS/LocationHelper" --make-icon "$task_dir/Assets/AppIcon.iconset"
/usr/bin/iconutil -c icns "$task_dir/Assets/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
cp "$task_dir/Assets/AppIcon.iconset/icon_512x512@2x.png" "$task_dir/Assets/AppIcon.png"
rm -rf "$task_dir/Assets/AppIcon.iconset"
/usr/bin/codesign --force --sign - "$app_dir"
print "已生成：$app_dir"
