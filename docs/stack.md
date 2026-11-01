# CourseMate for iOS in the Innotel Platform Stack

**Role: Mobile capture** — the phone end of the CourseMate study agent.

Part of the [Innotel Platform Stack](https://github.com/innotelinc/innotel-platform-stack).
The canonical definition of the stack, its shared layers and their owners lives
there; this file records only what this repository does inside it.

## Owns

- the ReplayKit broadcast extension: frame sampling, audio chunking, uploads
- the SwiftUI app: session control, answer cards, grading, review
- the Live Activity and its widget
- App Group state shared between the app and the extension
- signing, archiving and the TestFlight upload

## Provides

- frames and audio to the server, from any app on the device
- a lock-screen answer the operator can act on without opening the app
- corrections back to the server, which become lessons

## Consumes

- the [CourseMate server](https://github.com/innotelinc/coursemate) over HTTP
- the Apple Developer programme: one App Store Connect key for release, a
  separate APNs key for push
- Unity tokens on the landing page (`web/landing/`)

## Explicitly does NOT own

- classification, drafting or memory (that is the server)
- identity (Authentik, server side)
- secrets (build credentials are repository secrets, never in the tree)

## Service map

| Component | Technology | Job |
| --- | --- | --- |
| CourseMate | SwiftUI, iOS 17+ | sessions, answer cards, grading |
| CourseMateBroadcast | ReplayKit, App Groups | capture and upload |
| CourseMateWidget | ActivityKit | the Live Activity card |
| release.yml | xcodebuild + altool | archive, export, TestFlight |

## In the ecosystem

| Flow | Path |
| --- | --- |
| Capture | broadcast extension → `POST /api/frame` and `POST /api/audio` |
| Answers | `GET /api/decisions` → cards → Live Activity |
| Push | server → APNs → device token registered by the app |
| Release | tag `v*` → App Store Connect API key → TestFlight |

The capture path is the whole reason this exists: iOS has no supported way to
read another app's screen, so a broadcast extension is the only route that keeps
working while the course app is in front.
