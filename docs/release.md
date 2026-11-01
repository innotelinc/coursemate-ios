# Shipping CourseMate

One credential does the whole job: an **App Store Connect API key**. It
authorises signing (Xcode asks Apple for the certificate and profile itself),
the archive export, and the TestFlight upload. No certificate, private key or
provisioning profile is ever committed.

## First, the thing this key cannot do

An App Store Connect key **is not an APNs key**, even though both are ES256
`.p8` files from the same account. Apple validates the APNs `kid` against keys
that were created with *Apple Push Notifications service (APNs)* ticked; an
App Store Connect key is not one of them, and signing a provider token with it
gets `403 InvalidProviderToken`.

So having this key means **release works and push still does not**. Push needs
a separate key — the page is developer.apple.com → *Keys* → **+** → tick
*Apple Push Notifications service (APNs)*. `docs/../README.md` §Push covers the
server variables; the short version is `APNS_KEY`, `APNS_KEY_ID`,
`APNS_TEAM_ID`, `APNS_TOPIC`, `COURSEMATE_PUSH=1`.

The app also does not declare `aps-environment` in its entitlements, so even a
perfect APNs key delivers nothing until the Push Notifications capability is
enabled for the app id. `GET /api/health` says which of these is missing under
`push.missing`, and names where the key came from under `push.key_source`.

## The four values

| Secret | What it is | Where |
| --- | --- | --- |
| `APP_STORE_CONNECT_KEY` | the `.p8` contents, PEM or base64 | download from *Integrations* |
| `APP_STORE_CONNECT_KEY_ID` | 10 chars, e.g. `ABC123DEFG` | on the key's page, or its filename |
| `APP_STORE_CONNECT_ISSUER_ID` | a UUID | *App Store Connect → Users and Access → Integrations* |
| `APPLE_TEAM_ID` | 10 chars | *Membership* |

Two notes that cost time:

- **The key id is not in the issuer id and not in the `.p8` body.** It is only
  the key's name and the 10 characters in `AuthKey_<KEYID>.p8`. Apple shows it
  once, on the page where you download the key.
- **The `.p8` cannot be downloaded twice.** A lost key is a revoked key.

Set them on the repository that runs this workflow:

```bash
gh secret set APP_STORE_CONNECT_KEY      -R innotelinc/coursemate-ios < AuthKey_XXXX.p8
gh secret set APP_STORE_CONNECT_KEY_ID   -R innotelinc/coursemate-ios --body ABC123DEFG
gh secret set APP_STORE_CONNECT_ISSUER_ID -R innotelinc/coursemate-ios --body 00000000-0000-0000-0000-000000000000
gh secret set APPLE_TEAM_ID              -R innotelinc/coursemate-ios --body TEAM123456
```

Organisation secrets on `innotelinc` work too, and are the better answer if the
server repo also ends up needing to sign anything — a secret set on one
repository is unreadable from another, which is the usual way a release job
turns red for no visible reason.

## Cutting a release

```bash
git tag v1.0.0 && git push origin v1.0.0
```

`.github/workflows/release.yml` then: checks the credentials (naming whichever
is absent), writes the key where `xcodebuild` and `altool` each look for it,
proves the material parses with `openssl pkey`, archives with automatic signing
and the API key, exports an `app-store-connect` IPA, uploads it to TestFlight,
and creates the GitHub release with the IPA and a dSYM zip attached.

The version comes from the tag and the build number from the run, so the binary
in TestFlight matches a commit without editing `tools/gen-project.py`.

Re-run by hand with **Run workflow** and an optional `version` input for a
TestFlight build that is not a tagged release.

## What a green run means, and does not

- It means Apple **accepted the upload**. Processing is asynchronous; the build
  appears in TestFlight minutes later, and can still be rejected for a missing
  privacy string or an invalid icon.
- It does **not** prove the app runs. Nothing in CI has ever exercised a
  broadcast, a Live Activity or a notification — see `device-verification.md`.
- `APNS_ENVIRONMENT` must match how the build was signed: `sandbox` for builds
  installed from Xcode, `production` for TestFlight and the App Store. Wrong
  here means `BadDeviceToken` on every device, which looks exactly like a
  broken key.

## If it fails

| Symptom | Cause |
| --- | --- |
| `Preflight` fails naming a secret | that value is not set on *this* repository |
| `openssl pkey` fails | the `.p8` was truncated, or base64 with newlines was pasted raw |
| `No signing certificate "iOS Distribution" found` | `APPLE_TEAM_ID` is wrong, or the app id is not registered |
| `Failed to register bundle identifier` | the app id exists under a different team |
| `entity_not_found` / 401 at upload | `APP_STORE_CONNECT_KEY_ID` and the key file disagree |
| `Invalid Provisioning Profile` for the broadcast extension | the extension's app id needs App Groups, which `CourseMateBroadcast.entitlements` requires |
| upload succeeds, nothing in TestFlight | export compliance: the build waits until answered |
