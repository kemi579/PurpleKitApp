# PurpleKit

Multi-tool utility app for iPhone (SwiftUI, iOS 16+).

Dark purple theme, modular tools architecture, builds unsigned `.ipa` via GitHub Actions for AltStore / SideStore / Sideloadly.

## Tools

| Category | Tools |
|----------|-------|
| Text | Base64, URL Encode/Decode, JSON Formatter, Character Counter, Case Converter |
| Hash | MD5 / SHA-1 / SHA-256 (text + files) |
| Generator | Password, UUID, Random Number |
| QR | Generator + Scanner (camera) |
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
xcodegen generate
open PurpleKit.xcodeproj
```

## Architecture

- XcodeGen (`project.yml`) — no fragile `.xcodeproj` in repo
- Protocol `Tool` + `ToolRegistry` — add new tool = one file + register
- Zero third-party dependencies
- No paid capabilities / private APIs
