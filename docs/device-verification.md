# Proving the answer card on a real iPhone

CI compiles the app, the widget extension and the broadcast extension, and its
tests pin the JSON decoders. None of that can show a card on a Lock Screen. This
is the ordered list of checks that can, and what each failure actually looks
like — because every one of them is silent: no crash, no log, no error the app
surfaces.

Work through them in order. A failure early makes the later ones meaningless.

## What CI already proves, and what it cannot

| Already proved by `.github/workflows/ios-build.yml` | Needs a device |
| --- | --- |
| both targets and the extension compile | the card renders at all |
| `tools/gen-project.py` matches the checked-in project | iOS accepts `Activity.request` |
| the plists and entitlements lint | Copy reaches the pasteboard |
| `NSSupportsLiveActivities` and the URL scheme are declared | a tap routes to the right answer |

## 0. Install the build, and prove the phone reached the server

A TestFlight install is the only way to exercise a broadcast: ReplayKit's
broadcast picker does not exist in the Simulator, so none of the checks below
can be done there.

1. In TestFlight, install the newest build of `us.innotel.coursemate`.
2. Open CourseMate once and allow notifications. That launch is also what
   registers the phone — the app posts its APNs token to `/api/devices`.
3. Confirm the server saw it. `devices` counts registered phones:

   ```bash
   curl -s -H "Authorization: Bearer $COURSEMATE_TOKEN" \
     https://cm.innotel.us/api/health | python3 -m json.tool | sed -n '/push/,/}/p'
   ```

   `"devices": 1` means push can reach this phone. `0` means the app never
   registered: a simulator never yields a real token, and a build whose App ID
   lacks Push Notifications cannot obtain one either.
4. `"environment"` must match how the build was signed — `production` for
   TestFlight, `sandbox` for a build installed from Xcode. The wrong value is
   `BadDeviceToken` on every phone, which reads exactly like a broken key.

## Before you start

1. **Server reachable from the phone.** In the app, *Test connection* must answer
   `HTTP 200`. A Mac on the same Wi-Fi is enough; a wrong IP is the most common
   cause of "nothing happens".
2. **A session.** *Open console* — that tap is what creates one, and the
   extension refuses to send frames without it. Nothing is restored from a
   previous launch, so a broadcast left running across a relaunch stays silent
   until the console is opened again: that is the fix, not a fault.
3. **A broadcast.** *Start broadcast*, then leave CourseMate and open the course
   in the app or browser you are actually studying from.
4. **Notifications allowed.** Settings → CourseMate → Notifications → Allow,
   then turn on *Notify on new answers* in the app. This is not incidental: the
   Live Activity lives inside the same gate, so with the toggle off there is no
   card either. If permission is refused the toggle springs back off and the app
   says so.

## The six checks

### 1. A card appears at all

Stay in the course app. When the screen changes enough to produce a decision
worth showing, a card slides into the Dynamic Island (or onto the Lock Screen if
locked).

The app shows a card only when **all** of these hold, so a quiet lecture is not
a bug:

- the decision is **new** since the app opened (the first poll only primes — old
  answers never fire a card),
- `confidence >= 0.6`,
- `needs_human` is false,
- the answer text is not empty.

To force one, submit a quiz answer on screen that the agent is confident about,
or lock the phone and watch the Lock Screen.

### 2. The Lock Screen card

Lock the phone. The card shows the course, the kind, the confidence, the
question stem, the answer, and the two buttons. After ten minutes the card goes
**stale** and dims — that is the `staleDate`, not a failure.

### 3. Copy

Tap **Copy**. The app must stay in the background — no switch, no bounce. Paste
into Notes; you should get exactly the answer text.

If Copy appears to do nothing: the intent runs in the app's process, so a
force-quit app cannot run it. The card still draws (the widget extension does
that) but the button does nothing until the app has been launched once.

### 4. End

Tap **End**. The card must disappear **immediately**, not after a linger. Then
trigger a new answer and confirm a fresh card appears — this is the check that
matters, because End runs in the same process that tracks the current activity.
If `show` ever updated a finished card instead of starting a new one, nothing
would appear again for the rest of the lecture.

### 5. Tap-through

Tap the card's body — not either button. The app opens onto a sheet for *that*
decision: stem, answer, options with the chosen one checked, working, evidence,
and Right/Wrong grading.

Then the harder case, which is what the fetch-by-id route exists for:

1. Force-quit CourseMate.
2. With a card still on the Lock Screen, tap it.
3. The app cold-launches and the sheet still appears — the decision is fetched by
   id over `/api/decision?id=`, not looked up in a list the app no longer has.

### 6. The scheme, without a card

If a tap does nothing, prove the routing separately. In Shortcuts, add **Open
URLs** with `coursemate://decision/<any-id>`:

- App opens and shows *Could not open that answer: HTTP 404* → the scheme and
  routing work, and the id simply does not exist. Check the card's own id.
- Nothing at all happens → the scheme is not registered by the installed build.

In the Simulator the same check is `xcrun simctl openurl booted
"coursemate://decision/dec_x"`.

## When it fails

| What you see | What it means |
| --- | --- |
| No card, ever, and the toggle is on | Live Activities are off in iOS Settings → CourseMate, or `Activity.request` threw. Console.app filtered on `CourseMate:` shows `Live Activity not started: …`. |
| No card, and the toggle will not stay on | Notification permission was refused. The toggle is honest about it rather than staying on while nothing is delivered. |
| Card appears but never updates | The app is force-quit; the widget keeps drawing the last state it was handed. Relaunch it. |
| A second card next to the first | Only possible if the adoption path in `AnswerActivity.show` is bypassed. After a relaunch the app adopts the live activity rather than asking for another. |
| Copy does nothing, End works | Unlikely but diagnostic: End ends *all* activities, Copy reads the first one's state. A card not owned by an `Activity` in this process has no state for Copy to read. |
| Tap opens the app to no sheet | The URL did not parse. The route is `coursemate://decision/<id>`; anything else is ignored on purpose rather than guessed at. |
| Tap opens the app, footnote says `HTTP 404` | The decision is not on this server — usually a different data directory, or the app points at another host than the one that produced the card. |
| Tap opens the app, footnote says `No HTTP response` | The server is unreachable from the phone at that moment. The app keeps working; the answer cannot be fetched. |
| Card shows the kind label instead of the question | A decoding regression in `Decisions.swift`. CI's decoder tests exist precisely because this happened once and was invisible. |

## Reporting a failure usefully

Note which of the six checks passed, the decision id on the card, and the
`/api/health` body from the app's *Test connection*. Those three distinguish a
delivery problem from a rendering one from a routing one, which is otherwise
guesswork.
