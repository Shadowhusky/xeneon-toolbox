---
name: release
description: Use when cutting a new Xeneon Toolbox release — bumps the version, builds/notarizes the app, and publishes a GitHub release whose notes follow the exact changelog format the in-app updater renders. Invoke whenever the user asks to "release", "ship a new version", "cut vX.Y.Z", or publish an update after implementing features.
---

# Releasing Xeneon Toolbox

The app has an in-app updater (`Sources/XeneonToolbox/UpdateChecker.swift`) that polls
the GitHub **latest release**, compares its tag to the running app's
`CFBundleShortVersionString`, and shows the release `body` as a Markdown changelog
modal. So every release MUST: (1) bump the bundle version, and (2) publish a GitHub
release whose tag is higher and whose notes use the format below.

## 1. Changelog format (the GitHub release body)

The updater renders the body with MarkdownUI (GFM). Write it for **end users** —
concise, benefit-first, no file names / internal jargon. Only include sections that
apply, in this order. Bold the feature/area name; one line each.

```markdown
## ✨ New
- **<Feature>** — <what it does for the user, one line>.

## 🛠 Improved
- <one concise line>

## 🐞 Fixed
- <one concise line>
```

Rules:
- Keep it tight: a handful of bullets, not a commit log. Merge minor items.
- Lead with what the user gains, not how it was built.
- No trailing "see commits" / version headers — the modal already shows `vOLD → vNEW`.
- Emoji section headers are intentional (they render and aid scanning). Don't add others.

## 2. Bump the version

Edit `scripts/make-app.sh`:
- `CFBundleShortVersionString` → the new semver `X.Y.Z` (MAJOR new direction, MINOR features, PATCH fixes).
- `CFBundleVersion` → increment the integer.

## 3. Build, sign, notarize

```bash
./scripts/make-app.sh                       # release build + bundle (ad-hoc signed)
APPLE_ID=… APPLE_APP_SPECIFIC_PASSWORD=… APPLE_TEAM_ID=… ./scripts/notarize-release.sh
```
`notarize-release.sh` Developer-ID signs (hardened runtime + entitlements), notarizes,
staples, and produces `XeneonToolbox.zip`. Read the APPLE_* values transiently from
the environment — never commit or print them.

## 4. Publish the GitHub release

Tag must be `vX.Y.Z` (the updater strips the leading `v`). Attach the notarized zip
so the updater's "Update" button can link straight to the download.

```bash
gh release create vX.Y.Z XeneonToolbox.zip \
  --repo Shadowhusky/xeneon-toolbox \
  --title "Xeneon Toolbox X.Y.Z" \
  --notes "$(cat <<'NOTES'
## ✨ New
- **…** — …
NOTES
)"
```

## 5. Verify

- `gh release view vX.Y.Z` shows the formatted notes and the zip asset.
- A user on the previous version sees the modal on next launch / within the 6h check.
- Test the changelog renders by previewing the modal locally:
  `XENEON_DISPLAY=full XENEON_UPDATE_DEMO=1 .build/debug/XeneonToolbox` (uses a sample;
  to preview the real notes, point the demo text at the new body).

Only publish after the build is actually tested. Don't release directly off the
default branch without the user's go-ahead.
