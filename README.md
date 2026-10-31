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
5. Swipe back to CourseMate to read the **Answers** list — newest first, with a
   Copy button — while the broadcast keeps running.

Or from Control Centre at any time: long-press the record control → CourseMate
→ Start. That path needs a session id already stored in the App Group, so start
one from the app first.

## Switching courses mid-broadcast

Starting a new session while broadcasting does **not** need a restart. The app
writes the new session to `control.json` in the App Group with a bumped
revision; the extension checks that file's modification date (a throttled
`stat`, twice a second) and adopts the change on the next sample buffer. When
the session changes it also clears the frame hash and the buffered PCM, because
both belong to the previous session.

The `Answers` section shows whether this worked: the dot turns green when the
extension's last report names the session selected in the app, and the line
under it says how long ago the last frame was accepted.

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

## Grading from the phone

Every answer row has **Right** / **Wrong**. Right posts `{"correct": true}`.
Wrong opens a field for the actual answer and posts
`{"correct": false, "truth": "..."}`, which makes the server write a lesson
straight away (`recordCorrection`) so the next similar screen is answered with
it. Same loop as the dashboard, reachable without leaving the lecture.

## Notifications

`Notify on new answers` asks iOS for permission the first time you switch it on,
and switches itself back off if the answer is no rather than pretending to work.
It announces decisions that are **not** flagged `needs_human` and score at least
0.6, and it primes on first load — opening the app mid-lecture does not fire
twenty notifications for history.

What actually reaches you while you are in another app:

| Situation | Delivered? |
| --- | --- |
| App on screen | Yes — the delegate returns `.banner` |
| Just backgrounded | Usually; a background task keeps the poll alive briefly |
| Minutes later | `BGAppRefreshTask`, **when iOS decides to run it** |
| Phone locked, hours in | No |

A reliable ping forty minutes into a lecture needs APNs and a push-capable
server. That is not faked here. `BGTaskSchedulerPermittedIdentifiers` and
`UIBackgroundModes: fetch` cover the best-effort path that does exist.

## Review

`Review past sessions` lists recent sessions from `GET /api/me`, and each one
opens its decisions grouped into answers, notes and other — which is how the
lecture notes taken during a session are readable afterwards. The same screen
shows what the agent has learned for this course and its accuracy per screen
type, so a low number tells you where to double-check. Grading works there too,
so a bad answer found during review still becomes a lesson.

## Live Activity

A notification demands attention you may not want to give mid-lecture. A Live
Activity does not: `AnswerActivity.swift` starts one per session and updates it,
so the newest answer sits in the Dynamic Island and on the Lock Screen while the
course app stays in front. One activity is reused rather than stacked, its
stale date is ten minutes, and switching sessions ends it because it described
the old one. It follows the same `Notify on new answers` switch as banners.

## Push (APNs)

Registration is wired end to end and **off by default**, because delivering it
needs an Apple provider key:

1. Enable the Push Notifications capability on the app id and both extensions.
2. Put `AuthKey_XXXX.p8` somewhere the server can read.
3. Set on the server: `COURSEMATE_PUSH=1`, `APNS_KEY_PATH`, `APNS_KEY_ID`,
   `APNS_TEAM_ID`, and `APNS_TOPIC` (the app's bundle id). Use
   `APNS_ENVIRONMENT=production` for TestFlight and the App Store.

The app registers at launch, posts its 64-hex token to `POST /api/devices`, and
the server pushes decisions that are not `needs_human` and score at least
`COURSEMATE_PUSH_MIN_CONFIDENCE` (0.6). `src/push.js` speaks APNs over HTTP/2
with an ES256 provider JWT signed by `node:crypto` — no dependency — and drops
tokens Apple reports as `410 Unregistered`.

Two deliberate choices. The app does **not** declare `aps-environment` in its
entitlements, because that forces every signing profile to have push enabled and
would break installs for anyone who just wants local notifications; registration
is attempted at runtime and failing is harmless. And `push.js` reports
"not configured" instead of pretending, so a missing key is visible.

## Tests

`CourseMateTests` hosts the app and covers both decoders with 8 XCTest cases:
multiple choice and free response payloads, `needs_human` arriving as a SQLite
integer or a Bool, a row with nothing but an id, and the review decoder's
sessions, lessons, epoch dates and empty input. CI runs them on every push.

They are not decoration. The first run failed with `"quiz_answer" != "Which
organelle makes ATP?"` — the decoder looked for `text`/`prompt` while the server
sends `{stem, kind, options}`, so **every quiz headline was falling back to the
kind label**. That is a silent bug no compiler or structural check would catch.

## Configuration

The app writes these keys to the App Group; the extension reads them:

| Key | Meaning |
| --- | --- |
| `cm_url` | server base URL |
| `cm_token` | optional bearer token |
| `cm_session` | session created via `POST /api/session` |
| `cm_course` | course label |

They are stored twice: in `UserDefaults` (for the Control Centre path and for
debugging with `defaults read`) and in `control.json`, which is what the running
extension actually polls.

With a free Apple ID the App Group container is not provisioned. The app tells
you when this happens, and the extension falls back to the commented-out
`cm_url` / `cm_session` keys in `CourseMateBroadcast/Info.plist` — uncomment,
fill in, rebuild the extension target. That fallback is static: without the
container, a session switch cannot reach a running broadcast.

## What CI cannot check

The unsigned build proves the project graph and that both targets compile. It
does not prove signing, installation, or that a broadcast actually runs — those
need a team, a device, and a session on a reachable server.

## Wire protocol

```http
POST /api/session        {"course": "BIOL 201"}                -> {"session_id": "ses_..."}
POST /api/ingest/frame   {"session_id": "...", "image_b64": "<jpeg>",
                          "mime": "image/jpeg", "hash": "<hex>"}
POST /api/ingest/audio   {"session_id": "...", "audio_b64": "<wav>",
                          "mime": "audio/wav"}
GET  /api/desk?session_id=ses_...&limit=20                      -> {"decisions": [...]}
POST /api/correct       {"decision_id": "dec_...", "correct": false,
                         "truth": "42 kJ/mol"}                  -> {"stats": [...], "totals": {...}}
GET  /api/me?course=BIOL%20201                                  -> {"sessions": [...], "lessons": [...], "stats": [...]}
GET  /api/health
```

`/api/desk` rows carry `kind`, `screen_type`, `confidence`, `needs_human` and a
per-kind `payload` (`quiz_answer` has `question`, `chosen_text`, `answer_text`,
`work`; `essay` has `prose`; `error` has `error`). `Decisions.swift` decodes it
defensively, so an unrecognised kind still renders its label and confidence.

## Source map

| Path | What it does |
| --- | --- |
| `CourseMate/ContentView.swift` | session, broadcast state, answers, server status |
| `CourseMate/SettingsView.swift` | endpoint, token, course, App Group diagnosis |
| `CourseMate/AppModel.swift` | session creation, persistence, health, decision polling |
| `CourseMate/Decisions.swift` | `/api/desk` decoding, correction posting, answer rows |
| `CourseMate/ReviewView.swift` | session replay, lessons, per-screen accuracy |
| `CourseMate/AnswerNotifier.swift` | local notifications and background refresh |
| `CourseMate/AnswerActivity.swift` | starts and updates the Live Activity |
| `CourseMate/PushRegistration.swift` | APNs registration and the app delegate |
| `Shared/AnswerActivityAttributes.swift` | Live Activity attributes, app + widget |
| `CourseMateWidget/CourseMateWidgetBundle.swift` | the widget extension drawing the activity |
| `CourseMateTests/DecoderTests.swift` | 8 tests pinning the server JSON shapes |
| `CourseMate/BroadcastLauncher.swift` | presents the system broadcast sheet |
| `CourseMateBroadcast/SampleHandler.swift` | ReplayKit entry point, live session switch, upload queue |
| `CourseMateBroadcast/FrameSampler.swift` | throttle, perceptual hash, JPEG |
| `CourseMateBroadcast/AudioChunker.swift` | PCM → 16-bit mono WAV |
| `Shared/Settings.swift` | App Group storage with Info.plist fallback |
| `Shared/ControlChannel.swift` | control/status files: live switching and upload feedback |
| `Shared/CourseMateAPI.swift` | the HTTP calls, shared by both targets |
| `tools/gen-project.py` | regenerates the Xcode project and scheme |
| `.github/workflows/ios-build.yml` | CI: project drift check, lint, unsigned build |

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

**The answer card never appears, or tapping it does nothing.**
`docs/device-verification.md` runs the six checks in order and says what each
failure looks like. Two are easy to miss: the card is gated on the notification
toggle, and a tap needs the `coursemate://` scheme registered by the installed
build.

**HTTP is blocked.** Both Info.plists allow arbitrary loads on purpose, because
a LAN server speaks plain HTTP. Tighten it to `NSExceptionDomains` for your host
once you are past development.

**Session replaced but the extension still posts to the old one.** That should
not need a restart: the extension re-reads `control.json` continuously and the
`Answers` header shows which session it is actually posting to. If it stays on
the old one, the App Group is not shared — check the note in Settings, and that
both targets use `group.us.inotnel.coursemate`.

**Frames arrive but `Answers` stays empty.** `/api/desk` is what fills it; if
`deskError` shows an HTTP status, the server rejected the request — usually a
missing bearer token, since the same token guards ingest and desk.

## CI

`.github/workflows/ios-build.yml` runs on `macos-15` for both configurations and
fails on any of four things:

1. `CourseMate.xcodeproj` disagrees with `tools/gen-project.py` — a hand-edited
   or stale generated project.
2. A plist or entitlements file does not lint.
3. An asset catalog `Contents.json` does not parse.
4. The unsigned simulator build fails.
5. The unit tests fail (Debug only — Release is not built with testability).

Both configurations build clean on `macos-15` with Xcode 16.4, embedding both
extensions into `CourseMate.app/PlugIns`, and the 8 unit tests pass.

Signing is disabled (`CODE_SIGNING_ALLOWED=NO`), so CI needs no certificate or
provisioning profile. That means **CI proves the project graph and that the Swift
compiles — not that the app signs, installs or broadcasts.** Those still need a
real team and a device.

## Status

Written against iOS 17 SDK and ReplayKit's sample-buffer broadcast API. The
Xcode project is generated by `tools/gen-project.py` and structurally checked
(plist parsing, object-graph integrity, JSON assets) before being committed, and
CI compiles it unsigned on macOS. This repository was authored on Linux without
Xcode, so no build has been run in this working copy and nothing has been
exercised on a device. Expect to fix signing identifiers on first open.
