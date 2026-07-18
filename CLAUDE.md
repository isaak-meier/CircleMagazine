# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

This is a native Xcode project. Open `CircleMagazine.xcodeproj` in Xcode (Cmd+R to run, Cmd+U to test).

From the command line:
```bash
# Build
xcodebuild -project CircleMagazine.xcodeproj -scheme CircleMagazine -configuration Debug

# Run tests
xcodebuild test -project CircleMagazine.xcodeproj -scheme CircleMagazine
```

## Secrets Setup

Credentials are never committed. Create `CircleMagazine/Secrets.xcconfig` locally with:
```
SUPABASE_URL = https://your-project.supabase.co
SUPABASE_ANON_KEY = your-anon-key
```
`Config.xcconfig` (committed) includes this file and injects values into Info.plist at build time. `DatabaseService` reads them from the bundle at runtime. Xcode Preview mode is detected and uses dummy credentials to avoid crashes.

## Reuse First

Re-use existing code wherever possible. Before writing a new view, helper, or style, check whether one already exists (especially in `Views/Reused Components/` and `Style.swift`) and use or extend it instead of writing a parallel copy.

## Style Guide

`CircleMagazine/Style.swift` is the design system. Whenever it defines a token that fits — fonts, spacing (`Style.Space`), colors, radii — use it instead of literal values. Only fall back to literals for one-off values the style file doesn't cover.

## Architecture

**Stack:** Swift + SwiftUI + Supabase SDK (v2.5.1+), targeting iOS 26.2.

Three layers:

- **UI** — `Views/ContentView.swift`: SwiftUI view with a local `InsertState` enum (`idle → ready → loading → success`) driving the interface.
- **Service** — `Models/Supabase.swift`: `DatabaseService` class handles all async Supabase calls. Methods are grouped into Reads and Writes sections.
- **Models** — `Models/Boilerplate/Models.swift`: `Codable` structs for the seven DB entities: `User`, `Circle`, `CircleMember`, `Issue`, `Page`, `PageMedia`, `Engagement`, `Follow`. Snake_case DB columns map to camelCase Swift properties via custom `CodingKeys`.

**Domain concepts:**
- Users create/join **Circles** (communities)
- Circles publish **Issues** (magazine editions) composed of **Pages**
- Pages hold **PageMedia** (images/video)
- **Engagement** tracks watch percentage, scroll depth, and completion per user/page
- **Follow** tracks user follow relationships
