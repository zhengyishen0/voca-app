# Swift macOS App Development Skill

A comprehensive guide for building, signing, and distributing macOS menu bar apps, compiled from frost-app and voca-app projects.

---

## Table of Contents

1. [Project Structure](#1-project-structure)
2. [GitHub Actions Workflows](#2-github-actions-workflows)
3. [Code Signing & Notarization](#3-code-signing--notarization)
4. [App Bundling Script](#4-app-bundling-script)
5. [Icon Generation](#5-icon-generation)
6. [Homebrew Cask Distribution](#6-homebrew-cask-distribution)
7. [Menu Bar App Patterns](#7-menu-bar-app-patterns)
8. [README Template](#8-readme-template)
9. [Landing Page](#9-landing-page)
10. [Localization](#10-localization)
11. [KMP Integration](#11-kmp-integration-cross-platform)
12. [Useful Utilities](#12-useful-utilities)
13. [Quick Start Checklist](#13-quick-start-checklist)

---

## 1. Project Structure

### Choosing the Right Approach

| Project Type | Recommended Approach |
|--------------|---------------------|
| Pure Swift (no external frameworks) | **Thin Wrapper** - Xcode imports SPM package |
| With `.xcframework` | **Thin Wrapper** - Use SPM `binaryTarget` |
| With `.framework` (e.g., KMP) | **Parallel Project** - Both reference source files |

### IMPORTANT: Thin Wrapper Limitation

The thin wrapper approach (Xcode imports local SPM package) **does NOT work** with external `.framework` files.

**Why it breaks:**
- SPM's `unsafeFlags` (like `-F Frameworks`) are ignored when Xcode builds local packages
- SPM's `binaryTarget` only supports `.xcframework`, not regular `.framework`
- KMP typically outputs `.framework` format by default

**Solutions:**
1. Convert `.framework` to `.xcframework` (if possible)
2. Use the **Parallel Project** approach instead

---

### Option A: Thin Wrapper (Pure Swift or .xcframework)

Best for: Apps without external frameworks, or with `.xcframework` dependencies.

```
my-app/
├── Package.swift                 # Defines everything (AI-friendly)
├── MyApp.xcodeproj/              # Thin wrapper - just imports the SPM package
│
├── MyApp/Sources/                # All source code
└── MyApp/Resources/              # Assets, localization
```

**How it works:** Xcode project imports Package.swift as a local package. Adding new files only requires updating Package.swift.

---

### Option B: Parallel Project (With .framework / KMP)

Best for: Apps using KMP or external `.framework` files.

```
my-app/
├── Package.swift                 # For: swift build, CI, AI editing
├── MyApp.xcodeproj/              # For: signing, release, framework linking
│
├── MyApp/
│   ├── App/
│   │   └── AppDelegate.swift     # Main entry point
│   ├── Views/
│   │   ├── StatusBarController.swift
│   │   ├── AboutWindow.swift
│   │   └── SettingsWindow.swift
│   ├── Services/
│   │   └── ...
│   ├── Settings/
│   │   └── AppSettings.swift
│   └── Resources/
│       ├── AppIcon.icns
│       ├── Info.plist
│       ├── en.lproj/Localizable.strings
│       └── zh-Hans.lproj/Localizable.strings
│
├── Frameworks/                   # External frameworks (KMP, etc.)
│   └── MyFramework.framework
│
├── scripts/
│   ├── bundle-app.sh             # Create .app bundle
│   ├── setup-secrets.sh          # Upload signing certs to GitHub
│   └── generate-icon.swift       # Generate app icon
│
├── .github/workflows/
│   ├── build.yml                 # CI build
│   └── release.yml               # Release pipeline
│
├── README.md
├── index.html                    # Landing page
├── CNAME                         # Custom domain
└── MyApp.entitlements            # App capabilities
```

**How it works:** Both Package.swift and .xcodeproj reference the same source files.
- Package.swift uses `unsafeFlags` for framework linking (works in terminal)
- Xcode links frameworks via GUI (works for signing/release)

**Tradeoff:** When adding new files, you must add to BOTH Package.swift AND drag into Xcode.

---

### Converting .framework to .xcframework

If your KMP build can output `.xcframework`, the thin wrapper approach becomes viable:

```bash
# Convert existing framework to xcframework
xcodebuild -create-xcframework \
    -framework Frameworks/MyFramework.framework \
    -output Frameworks/MyFramework.xcframework
```

Then use SPM's `binaryTarget`:
```swift
targets: [
    .binaryTarget(
        name: "MyFramework",
        path: "Frameworks/MyFramework.xcframework"
    ),
    .executableTarget(
        name: "MyApp",
        dependencies: ["MyFramework"]
    )
]
```

---

### Package.swift Template (Parallel Project with .framework)

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MyApp", targets: ["MyApp"])
    ],
    targets: [
        .executableTarget(
            name: "MyApp",
            path: "MyApp",
            resources: [.copy("Resources")],
            linkerSettings: [
                // If using external frameworks:
                .unsafeFlags(["-F", "Frameworks"]),
                .unsafeFlags(["-framework", "MyFramework"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
```

---

## 2. GitHub Actions Workflows

### Build Workflow (CI)

**File:** `.github/workflows/build.yml`

```yaml
name: Build

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-14

    steps:
      - uses: actions/checkout@v4

      - name: Show Swift version
        run: swift --version

      - name: Build
        run: swift build -c release

      - name: Prepare artifact
        run: |
          mkdir -p artifact
          cp .build/release/MyApp artifact/
          # If using frameworks:
          cp -R Frameworks/MyFramework.framework artifact/

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: MyApp
          path: artifact/
```

### Release Workflow (Full Pipeline)

**File:** `.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: macos-14

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Get version from tag
        id: version
        run: |
          VERSION=${GITHUB_REF#refs/tags/v}
          BUILD_NUMBER=$(git rev-list --count HEAD)
          echo "version=$VERSION" >> $GITHUB_OUTPUT
          echo "build_number=$BUILD_NUMBER" >> $GITHUB_OUTPUT

      - name: Install certificate
        env:
          CERTIFICATE_BASE64: ${{ secrets.CERTIFICATE_BASE64 }}
          CERTIFICATE_PASSWORD: ${{ secrets.CERTIFICATE_PASSWORD }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          # Create keychain
          security create-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
          security set-keychain-settings -lut 21600 build.keychain

          # Import certificate
          echo "$CERTIFICATE_BASE64" | base64 --decode > certificate.p12
          security import certificate.p12 -k build.keychain -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" build.keychain
          rm certificate.p12

      - name: Build
        run: swift build -c release

      - name: Bundle app
        run: |
          chmod +x scripts/bundle-app.sh
          ./scripts/bundle-app.sh ${{ steps.version.outputs.version }} ${{ steps.version.outputs.build_number }}

      - name: Sign app
        env:
          SIGNING_IDENTITY: "Developer ID Application: Your Name (TEAM_ID)"
        run: |
          # Sign frameworks first (inside out)
          codesign --force --options runtime --timestamp \
            --sign "$SIGNING_IDENTITY" \
            "dist/MyApp.app/Contents/Frameworks/MyFramework.framework"

          # Sign main executable with entitlements
          codesign --force --options runtime --timestamp \
            --sign "$SIGNING_IDENTITY" \
            --entitlements MyApp.entitlements \
            "dist/MyApp.app"

          # Verify
          codesign --verify --deep --strict "dist/MyApp.app"

      - name: Notarize app
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_ID_PASSWORD: ${{ secrets.APPLE_ID_PASSWORD }}
          TEAM_ID: "YOUR_TEAM_ID"
        run: |
          # Create zip for notarization
          ditto -c -k --keepParent "dist/MyApp.app" "MyApp.zip"

          # Submit for notarization
          xcrun notarytool submit "MyApp.zip" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_ID_PASSWORD" \
            --team-id "$TEAM_ID" \
            --wait

          # Staple ticket
          xcrun stapler staple "dist/MyApp.app"

      - name: Create DMG
        run: |
          brew install create-dmg
          create-dmg \
            --volname "MyApp" \
            --window-pos 200 120 \
            --window-size 600 400 \
            --icon-size 100 \
            --icon "MyApp.app" 150 185 \
            --app-drop-link 450 185 \
            "MyApp-${{ steps.version.outputs.version }}.dmg" \
            "dist/MyApp.app"

      - name: Sign and notarize DMG
        env:
          SIGNING_IDENTITY: "Developer ID Application: Your Name (TEAM_ID)"
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_ID_PASSWORD: ${{ secrets.APPLE_ID_PASSWORD }}
          TEAM_ID: "YOUR_TEAM_ID"
        run: |
          codesign --force --sign "$SIGNING_IDENTITY" "MyApp-${{ steps.version.outputs.version }}.dmg"
          xcrun notarytool submit "MyApp-${{ steps.version.outputs.version }}.dmg" \
            --apple-id "$APPLE_ID" --password "$APPLE_ID_PASSWORD" --team-id "$TEAM_ID" --wait
          xcrun stapler staple "MyApp-${{ steps.version.outputs.version }}.dmg"

      - name: Calculate SHA256
        id: sha
        run: |
          SHA256=$(shasum -a 256 "MyApp-${{ steps.version.outputs.version }}.dmg" | cut -d ' ' -f 1)
          echo "sha256=$SHA256" >> $GITHUB_OUTPUT

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          files: MyApp-${{ steps.version.outputs.version }}.dmg
          body: |
            ## Installation

            **Download:** [MyApp-${{ steps.version.outputs.version }}.dmg](https://github.com/${{ github.repository }}/releases/download/v${{ steps.version.outputs.version }}/MyApp-${{ steps.version.outputs.version }}.dmg)

            **Homebrew:**
            ```bash
            brew install --cask yourname/tap/myapp
            ```

            **SHA256:** `${{ steps.sha.outputs.sha256 }}`

      - name: Update Homebrew Cask
        env:
          GH_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}
        run: |
          git clone https://x-access-token:${GH_TOKEN}@github.com/yourname/homebrew-tap.git
          cd homebrew-tap

          cat > Casks/myapp.rb << EOF
          cask "myapp" do
            version "${{ steps.version.outputs.version }}"
            sha256 "${{ steps.sha.outputs.sha256 }}"

            url "https://github.com/${{ github.repository }}/releases/download/v#{version}/MyApp-#{version}.dmg"
            name "MyApp"
            desc "Your app description"
            homepage "https://github.com/${{ github.repository }}"

            depends_on macos: ">= :ventura"

            app "MyApp.app"

            zap trash: [
              "~/Library/Preferences/com.yourname.myapp.plist",
              "~/Library/Application Support/MyApp",
            ]
          end
          EOF

          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          git add Casks/myapp.rb
          git commit -m "Update MyApp to ${{ steps.version.outputs.version }}"
          git push
```

---

## 3. Code Signing & Notarization

### Setup Secrets Script

**File:** `scripts/setup-secrets.sh`

```bash
#!/bin/bash
set -e

echo "=== GitHub Secrets Setup for macOS Code Signing ==="
echo ""

# Check gh CLI
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is required. Install with: brew install gh"
    exit 1
fi

# Check authentication
if ! gh auth status &> /dev/null; then
    echo "Error: Not authenticated with GitHub CLI. Run: gh auth login"
    exit 1
fi

# Detect repository
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
if [ -z "$REPO" ]; then
    echo "Error: Not in a GitHub repository directory"
    exit 1
fi
echo "Repository: $REPO"
echo ""

# Collect credentials
read -p "Apple ID (email): " APPLE_ID
read -s -p "App-specific password: " APPLE_ID_PASSWORD
echo ""
read -s -p "Certificate export password: " CERT_PASSWORD
echo ""

# Generate keychain password
KEYCHAIN_PASSWORD="build-$(date +%s)"

# Find Developer ID certificate
echo ""
echo "Finding Developer ID Application certificate..."
CERT_NAME=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')

if [ -z "$CERT_NAME" ]; then
    echo "Error: No Developer ID Application certificate found in keychain"
    exit 1
fi
echo "Found: $CERT_NAME"

# Export certificate
CERT_FILE=$(mktemp).p12
security export -k login.keychain-db -t identities -f pkcs12 -P "$CERT_PASSWORD" -o "$CERT_FILE" || {
    echo "Error: Failed to export certificate. Make sure the password is correct."
    rm -f "$CERT_FILE"
    exit 1
}

# Base64 encode
CERT_BASE64=$(base64 -i "$CERT_FILE")
rm -f "$CERT_FILE"

# Upload secrets
echo ""
echo "Uploading secrets to GitHub..."
gh secret set APPLE_ID --body "$APPLE_ID" --repo "$REPO"
gh secret set APPLE_ID_PASSWORD --body "$APPLE_ID_PASSWORD" --repo "$REPO"
gh secret set CERTIFICATE_PASSWORD --body "$CERT_PASSWORD" --repo "$REPO"
gh secret set CERTIFICATE_BASE64 --body "$CERT_BASE64" --repo "$REPO"
gh secret set KEYCHAIN_PASSWORD --body "$KEYCHAIN_PASSWORD" --repo "$REPO"

echo ""
echo "Done! Secrets uploaded:"
echo "  - APPLE_ID"
echo "  - APPLE_ID_PASSWORD"
echo "  - CERTIFICATE_PASSWORD"
echo "  - CERTIFICATE_BASE64"
echo "  - KEYCHAIN_PASSWORD"
```

### Entitlements Templates

**Basic App (sandbox + network):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

**Voice/Audio App (microphone access):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

**Accessibility App (paste simulation):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```

---

## 4. App Bundling Script

**File:** `scripts/bundle-app.sh`

```bash
#!/bin/bash
set -e

VERSION="${1:-1.0.0}"
BUILD_NUMBER="${2:-1}"
APP_NAME="MyApp"
BUNDLE_ID="com.yourname.myapp"

echo "Bundling $APP_NAME $VERSION ($BUILD_NUMBER)..."

# Clean and create directories
rm -rf dist
mkdir -p "dist/$APP_NAME.app/Contents/MacOS"
mkdir -p "dist/$APP_NAME.app/Contents/Resources"
mkdir -p "dist/$APP_NAME.app/Contents/Frameworks"

# Copy executable
cp ".build/release/$APP_NAME" "dist/$APP_NAME.app/Contents/MacOS/"

# Copy resources (SPM resource bundle)
if [ -d ".build/release/${APP_NAME}_${APP_NAME}.bundle" ]; then
    cp -R ".build/release/${APP_NAME}_${APP_NAME}.bundle" "dist/$APP_NAME.app/Contents/Resources/"
fi

# Copy app icon
if [ -f "$APP_NAME/Resources/AppIcon.icns" ]; then
    cp "$APP_NAME/Resources/AppIcon.icns" "dist/$APP_NAME.app/Contents/Resources/"
fi

# Copy frameworks (if any)
if [ -d "Frameworks" ]; then
    cp -R Frameworks/* "dist/$APP_NAME.app/Contents/Frameworks/"
fi

# Fix rpath for frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "dist/$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# Generate Info.plist
cat > "dist/$APP_NAME.app/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "dist/$APP_NAME.app/Contents/PkgInfo"

echo "Bundle created: dist/$APP_NAME.app"
```

---

## 5. Icon Generation

### Swift Script (SF Symbols)

**File:** `scripts/generate-icon.swift`

```swift
#!/usr/bin/env swift

import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDir = "AppIcon.iconset"

// Create output directory
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for size in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // Draw black circle background
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.black.setFill()
    NSBezierPath(ovalIn: rect).fill()

    // Draw SF Symbol (white)
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.5, weight: .regular)
    if let symbol = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let symbolSize = symbol.size
        let x = (CGFloat(size) - symbolSize.width) / 2
        let y = (CGFloat(size) - symbolSize.height) / 2
        symbol.draw(in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height),
                    from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()

    // Save PNG
    if let tiffData = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        let filename = "icon_\(size)x\(size).png"
        try? pngData.write(to: URL(fileURLWithPath: "\(outputDir)/\(filename)"))
        print("Generated: \(filename)")

        // Also generate @2x for half sizes
        if size <= 512 {
            let filename2x = "icon_\(size/2)x\(size/2)@2x.png"
            try? pngData.write(to: URL(fileURLWithPath: "\(outputDir)/\(filename2x)"))
        }
    }
}

print("\nConvert to icns with:")
print("iconutil -c icns \(outputDir)")
```

### Python Script (PIL/Pillow)

**File:** `scripts/generate_icon.py`

```python
#!/usr/bin/env python3
from PIL import Image, ImageDraw
import os

SIZES = [16, 32, 64, 128, 256, 512, 1024]
OUTPUT_DIR = "AppIcon.iconset"

os.makedirs(OUTPUT_DIR, exist_ok=True)

for size in SIZES:
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Draw rounded square (macOS squircle style)
    corner_radius = int(size * 0.22)
    draw.rounded_rectangle(
        [(0, 0), (size-1, size-1)],
        radius=corner_radius,
        fill=(0, 0, 0, 255)
    )

    # Draw your icon shape here (example: circle)
    padding = size // 4
    draw.ellipse(
        [(padding, padding), (size-padding, size-padding)],
        fill=(255, 255, 255, 255)
    )

    # Save
    img.save(f"{OUTPUT_DIR}/icon_{size}x{size}.png")
    if size <= 512:
        img.save(f"{OUTPUT_DIR}/icon_{size//2}x{size//2}@2x.png")

print(f"Icons generated in {OUTPUT_DIR}/")
print("Convert to icns: iconutil -c icns AppIcon.iconset")
```

---

## 6. Homebrew Cask Distribution

### Cask Template

**File:** `Casks/myapp.rb` (in homebrew-tap repo)

```ruby
cask "myapp" do
  version "1.0.0"
  sha256 "abc123..."

  url "https://github.com/yourname/myapp/releases/download/v#{version}/MyApp-#{version}.dmg"
  name "MyApp"
  desc "Your app description"
  homepage "https://github.com/yourname/myapp"

  depends_on macos: ">= :ventura"

  app "MyApp.app"

  zap trash: [
    "~/Library/Preferences/com.yourname.myapp.plist",
    "~/Library/Application Support/MyApp",
  ]
end
```

### Installation Command

```bash
# Add tap
brew tap yourname/tap

# Install
brew install --cask yourname/tap/myapp
```

---

## 7. Menu Bar App Patterns

### Status Bar Controller

```swift
import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Use SF Symbol
            if let image = NSImage(systemSymbolName: "waveform.circle.fill",
                                   accessibilityDescription: "MyApp") {
                image.isTemplate = true  // Adapts to menu bar (light/dark)
                button.image = image
            }
        }

        setupMenu()
    }

    private func setupMenu() {
        menu = NSMenu()

        // Hint/status item
        let hintItem = NSMenuItem(title: "Press ⌥ to start", action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        menu.addItem(hintItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        menu.addItem(NSMenuItem(title: NSLocalizedString("Settings...", comment: ""),
                                action: #selector(openSettings), keyEquivalent: ","))

        menu.addItem(NSMenuItem.separator())

        // Check for Updates
        menu.addItem(NSMenuItem(title: NSLocalizedString("Check for Updates...", comment: ""),
                                action: #selector(checkForUpdates), keyEquivalent: ""))

        // About
        menu.addItem(NSMenuItem(title: NSLocalizedString("About MyApp", comment: ""),
                                action: #selector(showAbout), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(title: NSLocalizedString("Quit", comment: ""),
                                action: #selector(quit), keyEquivalent: "q"))

        // Set targets
        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() {
        // Open GitHub releases page
        if let url = URL(string: "https://github.com/yourname/myapp/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showAbout() {
        AboutWindow.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
```

### About Window

```swift
import AppKit

class AboutWindow: NSWindowController {
    static let shared = AboutWindow()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About MyApp"
        window.center()

        super.init(window: window)
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupContent() {
        let contentView = NSView(frame: window!.contentView!.bounds)

        // Icon
        let iconView = NSImageView(frame: NSRect(x: 110, y: 240, width: 80, height: 80))
        iconView.image = NSImage(named: "AppIcon")
        contentView.addSubview(iconView)

        // App name
        let nameLabel = NSTextField(labelWithString: "MyApp")
        nameLabel.font = .boldSystemFont(ofSize: 24)
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: 0, y: 200, width: 300, height: 30)
        contentView.addSubview(nameLabel)

        // Version
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: "Version \(version) (\(build))")
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.frame = NSRect(x: 0, y: 175, width: 300, height: 20)
        contentView.addSubview(versionLabel)

        // Description
        let descLabel = NSTextField(labelWithString: "Your app tagline here")
        descLabel.font = .systemFont(ofSize: 13)
        descLabel.alignment = .center
        descLabel.frame = NSRect(x: 0, y: 140, width: 300, height: 20)
        contentView.addSubview(descLabel)

        // Author link button
        let authorButton = NSButton(title: "by @yourname", target: self, action: #selector(openAuthor))
        authorButton.bezelStyle = .inline
        authorButton.frame = NSRect(x: 100, y: 100, width: 100, height: 24)
        contentView.addSubview(authorButton)

        // GitHub link
        let githubButton = NSButton(title: "GitHub", target: self, action: #selector(openGitHub))
        githubButton.bezelStyle = .inline
        githubButton.frame = NSRect(x: 100, y: 70, width: 100, height: 24)
        contentView.addSubview(githubButton)

        // License
        let licenseLabel = NSTextField(labelWithString: "MIT License")
        licenseLabel.font = .systemFont(ofSize: 11)
        licenseLabel.textColor = .tertiaryLabelColor
        licenseLabel.alignment = .center
        licenseLabel.frame = NSRect(x: 0, y: 30, width: 300, height: 16)
        contentView.addSubview(licenseLabel)

        window?.contentView = contentView
    }

    @objc private func openAuthor() {
        NSWorkspace.shared.open(URL(string: "https://x.com/yourname")!)
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/yourname/myapp")!)
    }
}
```

### Settings Storage

```swift
import Foundation

class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // Settings keys
    private enum Keys {
        static let isEnabled = "isEnabled"
        static let startAtLogin = "startAtLogin"
        static let selectedOption = "selectedOption"
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }

    var startAtLogin: Bool {
        get { defaults.bool(forKey: Keys.startAtLogin) }
        set {
            defaults.set(newValue, forKey: Keys.startAtLogin)
            updateLoginItem()
        }
    }

    private func updateLoginItem() {
        // Use ServiceManagement for login item
        // SMAppService.mainApp.register() / unregister()
    }
}
```

---

## 8. README Template

```markdown
<p align="center">
  <img src="misc/icon.png" width="128" height="128" alt="MyApp Icon">
</p>

<h1 align="center">MyApp</h1>
<p align="center">Your tagline here</p>

<p align="center">
  <a href="https://github.com/yourname/myapp/releases/latest">
    <img src="https://img.shields.io/github/v/release/yourname/myapp" alt="Release">
  </a>
  <img src="https://img.shields.io/badge/macOS-13%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Apple%20Silicon-Ready-green" alt="Apple Silicon">
  <img src="https://img.shields.io/github/downloads/yourname/myapp/total" alt="Downloads">
</p>

## Features

- Feature 1
- Feature 2
- Feature 3

## Installation

### Download

Download the latest DMG from [Releases](https://github.com/yourname/myapp/releases/latest).

### Homebrew

```bash
brew install --cask yourname/tap/myapp
```

## Usage

1. Launch MyApp from Applications
2. Click the menu bar icon
3. ...

## Requirements

- macOS 13.0+
- Apple Silicon (M1/M2/M3)

## Privacy

All processing happens locally on your device. No data is sent to any server.

## License

MIT License - see [LICENSE](LICENSE) for details.

---

Made by [@yourname](https://x.com/yourname)
```

---

## 9. Landing Page

**File:** `index.html`

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MyApp - Your Tagline</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #0a1628 0%, #1a2f4a 100%);
            color: white;
            min-height: 100vh;
        }
        .container { max-width: 1200px; margin: 0 auto; padding: 2rem; }
        .hero {
            text-align: center;
            padding: 4rem 0;
        }
        .hero h1 {
            font-size: 3rem;
            margin-bottom: 1rem;
        }
        .hero p {
            font-size: 1.25rem;
            opacity: 0.8;
            margin-bottom: 2rem;
        }
        .cta {
            display: inline-block;
            background: white;
            color: #0a1628;
            padding: 1rem 2rem;
            border-radius: 8px;
            text-decoration: none;
            font-weight: 600;
            transition: transform 0.2s;
        }
        .cta:hover { transform: scale(1.05); }
        .features {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 2rem;
            padding: 4rem 0;
        }
        .feature {
            background: rgba(255,255,255,0.1);
            padding: 2rem;
            border-radius: 12px;
        }
        .feature h3 { margin-bottom: 0.5rem; }
        .feature p { opacity: 0.8; }
        footer {
            text-align: center;
            padding: 2rem;
            opacity: 0.6;
        }
        footer a { color: white; }
    </style>
</head>
<body>
    <div class="container">
        <div class="hero">
            <h1>MyApp</h1>
            <p>Your compelling tagline here</p>
            <a href="https://github.com/yourname/myapp/releases/latest" class="cta">
                Download for macOS
            </a>
        </div>

        <div class="features">
            <div class="feature">
                <h3>Feature One</h3>
                <p>Description of your first amazing feature.</p>
            </div>
            <div class="feature">
                <h3>Feature Two</h3>
                <p>Description of your second amazing feature.</p>
            </div>
            <div class="feature">
                <h3>Feature Three</h3>
                <p>Description of your third amazing feature.</p>
            </div>
        </div>

        <footer>
            <p>
                <a href="https://github.com/yourname/myapp">GitHub</a> ·
                <a href="https://x.com/yourname">Twitter</a> ·
                MIT License
            </p>
        </footer>
    </div>
</body>
</html>
```

**File:** `CNAME`
```
myapp.yourdomain.com
```

---

## 10. Localization

### Directory Structure

```
Resources/
├── en.lproj/
│   └── Localizable.strings
├── zh-Hans.lproj/
│   └── Localizable.strings
├── ja.lproj/
│   └── Localizable.strings
└── ...
```

### Localizable.strings Template

**English (`en.lproj/Localizable.strings`):**
```
/* Menu items */
"Settings..." = "Settings...";
"Check for Updates..." = "Check for Updates...";
"About MyApp" = "About MyApp";
"Quit" = "Quit";

/* Settings */
"Enabled" = "Enabled";
"Start at Login" = "Start at Login";
```

**Chinese (`zh-Hans.lproj/Localizable.strings`):**
```
/* Menu items */
"Settings..." = "设置...";
"Check for Updates..." = "检查更新...";
"About MyApp" = "关于 MyApp";
"Quit" = "退出";

/* Settings */
"Enabled" = "已启用";
"Start at Login" = "登录时启动";
```

### Usage in Code

```swift
let text = NSLocalizedString("Settings...", comment: "Menu item")
```

---

## 11. KMP Integration (Cross-Platform)

For apps with heavy backend logic that need cross-platform support.

### IMPORTANT: Project Structure for KMP

KMP typically outputs `.framework` format, which means you **must use the Parallel Project approach** (Option B from Section 1).

The thin wrapper approach does NOT work because:
- Xcode ignores SPM's `unsafeFlags` when building local packages
- SPM's `binaryTarget` only supports `.xcframework`, not `.framework`

**If your KMP build can output `.xcframework`**, you can use the thin wrapper approach with `binaryTarget`. Check your KMP gradle configuration.

### Structure

```
my-app/
├── shared/                      # Kotlin Multiplatform module
│   ├── src/commonMain/         # Shared business logic
│   ├── src/iosMain/            # iOS-specific
│   └── build.gradle.kts
│
├── ios-app/                    # SwiftUI wrapper (if needed)
└── macos-app/                  # Swift wrapper
    ├── Package.swift           # For swift build (terminal/CI)
    ├── MyApp.xcodeproj/        # For signing/release (parallel, not wrapper!)
    └── Frameworks/
        └── SharedLogic.framework   # Built from KMP
```

### Linking KMP Framework

**Package.swift (works for `swift build` in terminal):**
```swift
targets: [
    .executableTarget(
        name: "MyApp",
        linkerSettings: [
            .unsafeFlags(["-F", "Frameworks"]),
            .unsafeFlags(["-framework", "SharedLogic"]),
            .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
        ]
    )
]
```

**Xcode Project (for signing/release):**
- Add framework to "Frameworks, Libraries, and Embedded Content"
- Set "Embed & Sign" for the framework
- Link framework in Build Phases

### Alternative: Convert to XCFramework

If you can modify the KMP build, output `.xcframework` instead:

```kotlin
// build.gradle.kts
kotlin {
    macosArm64 {
        binaries.framework {
            baseName = "SharedLogic"
            isStatic = false
        }
    }
}

// Then convert:
// xcodebuild -create-xcframework -framework SharedLogic.framework -output SharedLogic.xcframework
```

Then use SPM's `binaryTarget` for a cleaner thin wrapper setup.

### Calling from Swift

```swift
import SharedLogic

let engine = SharedLogicEngine()
let result = engine.process(input: data)
```

### Signing KMP Frameworks

In your release workflow, sign frameworks **before** the main app (inside-out order):

```yaml
- name: Sign frameworks
  run: |
    # Sign KMP framework first
    codesign --force --options runtime --timestamp \
      --sign "$SIGNING_IDENTITY" \
      "dist/MyApp.app/Contents/Frameworks/SharedLogic.framework"

    # Then sign main app with entitlements
    codesign --force --options runtime --timestamp \
      --sign "$SIGNING_IDENTITY" \
      --entitlements MyApp.entitlements \
      "dist/MyApp.app"
```

---

## 12. Useful Utilities

### Auto-Paste (Hardened Runtime Compatible)

```swift
import Carbon

func simulatePaste() {
    // Create Cmd+V key event using cgSessionEventTap (works with hardened runtime)
    let source = CGEventSource(stateID: .combinedSessionState)

    // Key down
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
    keyDown?.flags = .maskCommand
    keyDown?.post(tap: .cgSessionEventTap)

    // Key up
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
    keyUp?.flags = .maskCommand
    keyUp?.post(tap: .cgSessionEventTap)
}
```

### Global Hotkey Monitoring

```swift
import Carbon

class HotkeyMonitor {
    private var eventMonitor: Any?

    func start(onHotkey: @escaping () -> Void) {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            if event.modifierFlags.contains(.option) {
                onHotkey()
            }
        }
    }

    func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
```

### Cursor Shake Detection

```swift
class CursorShakeDetector {
    private var positions: [(point: CGPoint, time: Date)] = []
    private var directionChanges = 0
    private var lastDirection: Int = 0

    var onShakeDetected: (() -> Void)?

    private let timeWindow: TimeInterval = 0.5
    private let minDirectionChanges = 3
    private let minVelocity: CGFloat = 300
    private let minDistance: CGFloat = 50

    func handleMouseMove(_ point: CGPoint) {
        let now = Date()

        // Remove old positions
        positions = positions.filter { now.timeIntervalSince($0.time) < timeWindow }

        // Calculate direction
        if let last = positions.last {
            let dx = point.x - last.point.x
            let direction = dx > 0 ? 1 : (dx < 0 ? -1 : 0)

            if direction != 0 && direction != lastDirection {
                directionChanges += 1
                lastDirection = direction
            }

            // Check for shake
            if directionChanges >= minDirectionChanges {
                let totalDistance = abs(point.x - positions.first!.point.x)
                let elapsed = now.timeIntervalSince(positions.first!.time)
                let velocity = totalDistance / CGFloat(elapsed)

                if totalDistance >= minDistance && velocity >= minVelocity {
                    onShakeDetected?()
                    reset()
                }
            }
        }

        positions.append((point, now))
    }

    private func reset() {
        positions = []
        directionChanges = 0
        lastDirection = 0
    }
}
```

### License Manager (Trial System)

```swift
class LicenseManager {
    static let shared = LicenseManager()

    private let defaults = UserDefaults.standard
    private let trialDays = 7

    private var firstLaunchDate: Date {
        if let date = defaults.object(forKey: "firstLaunchDate") as? Date {
            return date
        }
        let now = Date()
        defaults.set(now, forKey: "firstLaunchDate")
        return now
    }

    var isTrialActive: Bool {
        let elapsed = Date().timeIntervalSince(firstLaunchDate)
        return elapsed < Double(trialDays * 24 * 60 * 60)
    }

    var trialDaysRemaining: Int {
        let elapsed = Date().timeIntervalSince(firstLaunchDate)
        let remaining = trialDays - Int(elapsed / (24 * 60 * 60))
        return max(0, remaining)
    }

    var isLicensed: Bool {
        guard let key = defaults.string(forKey: "licenseKey") else { return false }
        return validateKey(key)
    }

    var canUseApp: Bool {
        return isLicensed || isTrialActive
    }

    func activate(key: String) -> Bool {
        if validateKey(key) {
            defaults.set(key, forKey: "licenseKey")
            return true
        }
        return false
    }

    private func validateKey(_ key: String) -> Bool {
        // Implement your validation logic
        return key.count > 10
    }
}
```

---

## 13. Quick Start Checklist

### New Project Setup

- [ ] Create `Package.swift` with target configuration
- [ ] Create directory structure (`App/`, `Views/`, `Services/`, `Resources/`)
- [ ] Add `AppDelegate.swift` with `@main`
- [ ] Add `StatusBarController.swift` for menu bar
- [ ] Add `AboutWindow.swift`
- [ ] Create `AppIcon.iconset/` and generate `.icns`
- [ ] Add `Info.plist` with `LSUIElement: true`
- [ ] Add `MyApp.entitlements` with required capabilities
- [ ] Create `scripts/bundle-app.sh`
- [ ] Add localization files (`en.lproj/Localizable.strings`)

### Release Setup

- [ ] Create GitHub repo
- [ ] Run `scripts/setup-secrets.sh` to upload signing certificates
- [ ] Add `.github/workflows/build.yml`
- [ ] Add `.github/workflows/release.yml`
- [ ] Create Homebrew tap repo (`homebrew-tap`)
- [ ] Add `Casks/myapp.rb` template
- [ ] Create `README.md`
- [ ] Create `index.html` landing page
- [ ] Add `CNAME` for custom domain
- [ ] Test release with `git tag v0.1.0 && git push --tags`

### Menu Bar Essentials

- [ ] SF Symbol icon with `isTemplate = true`
- [ ] Hint text showing current hotkey
- [ ] Settings window
- [ ] Check for Updates (link to GitHub releases)
- [ ] About window (version, author, links)
- [ ] Quit option with `⌘Q` shortcut

---

## Source Projects

This skill was compiled from:
- **frost-app** - Window blur/focus app (Xcode project)
- **voca-app** - Voice-to-text transcription (SPM project)

Both demonstrate production-ready macOS menu bar apps with proper signing, notarization, and distribution.
