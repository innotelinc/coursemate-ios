# CourseMate for iOS

A screen-and-audio capture client for [CourseMate](../coursemate): it sends
frames from whatever course you are looking at — a web LMS, a native app, a
lecture playing in Safari — plus the app's audio, to the CourseMate server,
which classifies the screen and drafts answers, notes and essays.

iOS will not let an app read another app's screen. The only supported route is
a **ReplayKit broadcast extension**: you start it once, and it keeps receiving
frames and audio while you use anything else. That is what this project is.

```
CourseMate (SwiftUI app)          CourseMateBroadcast (ReplayKit extension)
  creates a session                 receives every frame + audio buffer
  stores config in App Group  ───▶  reads the same App Group
  starts the broadcast              downsamples, hashes, uploads
```

## Requirements

| | |
| --- | --- |
| Xcode | 15 or newer |
| Device | iPhone or iPad on iOS 17+ |
| Apple ID | free is enough to run; a paid team is needed for App Groups |
| Server | a running CourseMate server reachable from the phone |

ReplayKit broadcasts do **not** work in the simulator. The app runs there, the
extension does not.

## 1. Start the server where the phone can see it

CourseMate binds `127.0.0.1` by default, which a phone cannot reach:

```bash
cd ../coursemate
COURSEMATE_HOST=0.0.0.0 npm start
```

Find the host's LAN address (`ip addr`, `ifconfig`, or `hostname -I`) and confirm
from the phone's browser that `http://<host>:8790/api/health` answers. If the
server has `COURSEMATE_TOKEN` set, you will also need that token in the app.

## 2. Open, sign, run

```bash
open CourseMate.xcodeproj
```

1. Select the project → **CourseMate** target → *Signing & Capabilities*.
2. Pick your team. If someone else already owns `us.innotel.coursemate`, change
   the bundle id here **and** the App Group in three places:
   `CourseMate/CourseMate.entitlements`,
   `CourseMateBroadcast/CourseMateBroadcast.entitlements`, and
   `AppGroup.identifier` in `Shared/Settings.swift`.
3. Repeat the team selection for the **CourseMateBroadcast** target.
4. Run on the device (not the simulator).

## 3. Use it

1. Enter the server URL (`http://192.168.1.20:8790` is accepted without the
   scheme) and tap **Test connection**.
2. Name the course and tap **Start new session**.
3. Tap **Start broadcast** — the system sheet asks you to confirm, and a red
   status bar appears.
4. Switch to the course. Frames and audio keep flowing.

Or from Control Centre at any time: long-press the record control → CourseMate
→ Start. That path needs a session id already stored in the App Group, so start
one from the app first.

## How the extension behaves

- **One frame every 2.5 s**, and only when the screen actually changed: an 8×8
  greyscale average hash must differ by more than 2 bits. A static slide costs
  one vision call, not one per second.
- Frames are resized to 1280 px wide and JPEG-encoded at 0.7 before upload.
- **Audio** is accumulated from ReplayKit's LinearPCM buffers, downmixed to
  16-bit mono, wrapped in a WAV header and sent every ~12 s (and once more when
  the broadcast stops). Audio arrives only if the source is playing something.
- **Two uploads in flight at most.** A slow network drops frames instead of
  stalling ReplayKit's sample queue, which would stutter the broadcast itself.

## Configuration

The app writes these keys to the App Group; the extension reads them:

| Key | Meaning |
| --- | --- |
| `cm_url` | server base URL |
| `cm_token` | optional bearer token |
| `cm_session` | session created via `POST /api/session` |
| `cm_course` | course label |

With a free Apple ID the App Group container is not provisioned. The app tells
you when this happens, and the extension falls back to the commented-out
`cm_url` / `cm_session` keys in `CourseMateBroadcast/Info.plist` — uncomment,
fill in, rebuild the extension target.

## Wire protocol

```http
POST /api/session        {"course": "BIOL 201"}                -> {"session_id": "ses_..."}
POST /api/ingest/frame   {"session_id": "...", "image_b64": "<jpeg>",
                          "mime": "image/jpeg", "hash": "<hex>"}
POST /api/ingest/audio   {"session_id": "...", "audio_b64": "<wav>",
                          "mime": "audio/wav"}
GET  /api/health
```

## Source map

| Path | What it does |
| --- | --- |
| `CourseMate/ContentView.swift` | session, broadcast state, server status |
| `CourseMate/SettingsView.swift` | endpoint, token, course, App Group diagnosis |
| `CourseMate/AppModel.swift` | session creation, persistence, health check |
| `CourseMate/BroadcastLauncher.swift` | presents the system broadcast sheet |
| `CourseMateBroadcast/SampleHandler.swift` | ReplayKit entry point, upload queue |
| `CourseMateBroadcast/FrameSampler.swift` | throttle, perceptual hash, JPEG |
| `CourseMateBroadcast/AudioChunker.swift` | PCM → 16-bit mono WAV |
| `Shared/Settings.swift` | App Group storage with Info.plist fallback |
| `Shared/CourseMateAPI.swift` | the three HTTP calls, shared by both targets |
| `tools/gen-project.py` | regenerates the Xcode project and scheme |

The project file is generated, because two targets sharing five sources makes
it painful to maintain by hand. After adding a file:

```bash
python3 tools/gen-project.py
```

## Troubleshooting

**Broadcast does not appear in Control Centre.** The *extension* target must be
installed, not just the app, and you must be on a device.

**Frames never arrive.** Check the app's App Group note first; then that the
server is bound to `0.0.0.0`; then Console.app filtered on `CourseMate:` for
upload errors. iOS asks for Local Network permission on first use — declining it
blocks every request silently.

**HTTP is blocked.** Both Info.plists allow arbitrary loads on purpose, because
a LAN server speaks plain HTTP. Tighten it to `NSExceptionDomains` for your host
once you are past development.

**Session replaced but the extension still posts to the old one.** The extension
reads the App Group in `broadcastStarted`; stop and restart the broadcast after
changing sessions.

## Status

Written against iOS 17 SDK and ReplayKit's sample-buffer broadcast API. The
Xcode project is generated by `tools/gen-project.py` and structurally checked
(plist parsing, object-graph integrity, JSON assets), but this repository was
produced on Linux without Xcode, so no build or on-device run has been performed
here. Expect to fix signing identifiers on first open, nothing more.
