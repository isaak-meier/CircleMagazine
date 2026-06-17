# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

This is a native Xcode project. Open `CircleMagazine/CircleMagazine.xcodeproj` in Xcode (Cmd+R to run, Cmd+U to test).

From the command line:
```bash
# Build
xcodebuild -project CircleMagazine/CircleMagazine.xcodeproj -scheme CircleMagazine -configuration Debug

# Run tests
xcodebuild test -project CircleMagazine/CircleMagazine.xcodeproj -scheme CircleMagazine
```

## Secrets Setup

Credentials are never committed. Create `CircleMagazine/Secrets.xcconfig` locally with:
```
SUPABASE_URL = https://your-project.supabase.co
SUPABASE_ANON_KEY = your-anon-key
```
`Config.xcconfig` (committed) includes this file and injects values into Info.plist at build time. `DatabaseService` reads them from the bundle at runtime. Xcode Preview mode is detected and uses dummy credentials to avoid crashes.

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
