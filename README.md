# PurpleKit

Multi-tool utility app for iPhone (SwiftUI, iOS 16+).

Minimal dark interface, modular tools architecture, builds unsigned `.ipa` via GitHub Actions for AltStore / SideStore / Sideloadly.

## Tools

| Category | Tools |
|----------|-------|
| Text | Base64, URL Encode/Decode, JSON Formatter, Character Counter, Case Converter |
| Hash | MD5 / SHA-1 / SHA-256 (text + files) |
| Generator | Password, UUID, Random Number |
| QR | Generator |
| Converter | Units (length, weight, temp, data) — offline |
| Network | My IP, DNS Lookup, Port Checker, HTTP Status |
| Device | Model, iOS, Battery, Memory, Disk |
| Notes | Quick Notes + Clipboard History (local) |

## Install via AltStore / SideStore

1. Download `PurpleKit.ipa` from the [latest Release](https://github.com/kemi579/PurpleKitApp/releases/latest).
2. Open AltStore / SideStore → My Apps → + → select the IPA.
3. Sign with your free Apple ID.
4. Refresh every 7 days (free Apple ID limit).

Sideloadly: connect device → choose IPA → Apple ID → Start.

## Build locally

```bash
brew install xcodegen
git clone --depth 1 --branch develop https://github.com/SideStore/minimuxer.git Dependencies/minimuxer
xcodegen generate
open PurpleKit.xcodeproj
```

## Architecture

- XcodeGen (`project.yml`) — no fragile `.xcodeproj` in repo
- Protocol `Tool` + `ToolRegistry` — add new tool = one file + register
- Existing signing/install dependencies: SideSign and Minimuxer; no UI dependencies
- No paid capabilities / private APIs

## Design

PurpleKit uses a minimal, dark-only interface inspired by iOS Settings: a pure black background, flat #1C1C1E groups, thin inset separators and a single purple accent (#7957D5). There are no gradients, shadows, glow effects or custom tab bars.

The interface uses system SF text styles, Dynamic Type, VoiceOver labels and touch targets of at least 44 pt. Secondary actions live in toolbars and context menus. Primary actions stay above the safe area and keyboard.

All colors and layout tokens are defined in `Sources/Core/Theme.swift`. Shared components (`SettingsGroup`, `SettingsRow`, `PrimaryButton`, `PillBadge`, fields and results) live in `Sources/UI/Components.swift`.

The four tabs are Tools, Notes, Device and Settings. The IPA Library is accessible from Settings. Tool calculations, storage, requests and the existing signing/install services are unchanged by this presentation refactor.

The white QR-code panel is functional contrast for scanning; it is not a light appearance mode.
