#!/bin/zsh
# Builds "Emulsion 98.app" into ./dist using only the Swift command-line tools.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Emulsion 98.app"
swift build -c release --product Emulsion98
swift build -c release --product Emulsion98PhotosExt

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Emulsion98 "$APP/Contents/MacOS/Emulsion98"
# UNIVERSAL=1 ./scripts/build_app.sh also builds for Intel and merges both architectures (for releases).
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  swift build -c release --product Emulsion98 --triple x86_64-apple-macosx15.0 --scratch-path .build-x86 >/dev/null
  swift build -c release --product Emulsion98PhotosExt --triple x86_64-apple-macosx15.0 --scratch-path .build-x86 >/dev/null
  lipo -create .build/release/Emulsion98 .build-x86/release/Emulsion98 -output "$APP/Contents/MacOS/Emulsion98"
fi

# Icon
ICONWORK=$(mktemp -d)
swift scripts/make_icon.swift "$ICONWORK/icon.png" >/dev/null
mkdir -p "$ICONWORK/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONWORK/icon.png" --out "$ICONWORK/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$ICONWORK/icon.png" --out "$ICONWORK/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONWORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONWORK"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Emulsion 98</string>
  <key>CFBundleDisplayName</key><string>Emulsion 98</string>
  <key>CFBundleIdentifier</key><string>local.emulsion98.app</string>
  <key>CFBundleExecutable</key><string>Emulsion98</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.7.0</string>
  <key>CFBundleVersion</key><string>8</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPicturesFolderUsageDescription</key><string>Emulsion 98 saves imported originals and developed photos in your Pictures folder.</string>
  <key>NSPhotoLibraryUsageDescription</key><string>Emulsion 98 imports your photos (including RAW originals) from Photos and saves developed film versions back.</string>
  <key>NSPhotoLibraryAddUsageDescription</key><string>Emulsion 98 saves developed photos to an “Emulsion 98” album in Photos.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>Emulsion 98 imports photos from your camera's memory card.</string>
</dict>
</plist>
PLIST

# Photos editing extension: Photos ▸ Edit ▸ ⋯ ▸ Emulsion 98.
EXT="$APP/Contents/PlugIns/Emulsion 98 Film.appex"
mkdir -p "$EXT/Contents/MacOS"
cp .build/release/Emulsion98PhotosExt "$EXT/Contents/MacOS/Emulsion98PhotosExt"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  lipo -create .build/release/Emulsion98PhotosExt .build-x86/release/Emulsion98PhotosExt -output "$EXT/Contents/MacOS/Emulsion98PhotosExt"
fi
cat > "$EXT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Emulsion 98</string>
  <key>CFBundleDisplayName</key><string>Emulsion 98</string>
  <key>CFBundleIdentifier</key><string>local.emulsion98.app.photos-editing</string>
  <key>CFBundleExecutable</key><string>Emulsion98PhotosExt</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>1.7.0</string>
  <key>CFBundleVersion</key><string>8</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHumanReadableCopyright</key><string>Film emulation for Photos</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionAttributes</key>
    <dict>
      <key>PHSupportedMediaTypes</key><array><string>Image</string></array>
    </dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.photo-editing</string>
    <key>NSExtensionPrincipalClass</key><string>PhotoEditingViewController</string>
  </dict>
</dict>
</plist>
PLIST
ENT=$(mktemp -d)/ext.entitlements
cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
</dict>
</plist>
PLIST

# Sign inside-out: the extension (sandboxed, as all app extensions must be), then the app.
# iCloud Drive's file provider can re-tag bundle folders with Finder info at any moment, which codesign
# rejects, so sign a copy outside the synced folder and zip that copy for releases.
STAGE=$(mktemp -d)
ditto --norsrc --noextattr "$APP" "$STAGE/Emulsion 98.app"
SAPP="$STAGE/Emulsion 98.app"; SEXT="$SAPP/Contents/PlugIns/Emulsion 98 Film.appex"
xattr -cr "$SAPP"
codesign --force --sign - --entitlements "$ENT" "$SEXT"
codesign --force --sign - "$SAPP"
codesign --verify --deep --strict "$SAPP"
VERSION=$(defaults read "$SAPP/Contents/Info.plist" CFBundleShortVersionString)
rm -f "dist/Emulsion98-$VERSION-macOS.zip"
ditto -c -k --norsrc --keepParent "$SAPP" "dist/Emulsion98-$VERSION-macOS.zip"
rm -rf "$APP"; ditto --norsrc --noextattr "$SAPP" "$APP"
rm -rf "$STAGE"
echo "app signature ok; zipped dist/Emulsion98-$VERSION-macOS.zip"
# Register with Launch Services so Photos finds the editing extension after every rebuild.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$APP" || true
pluginkit -a "$PWD/$EXT" || true
sleep 2; pluginkit -a "$PWD/$EXT" || true   # registration can lag right after lsregister
echo "Built $APP"
