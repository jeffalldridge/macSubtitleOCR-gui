# Public-Release Audit

**Status:** findings + decisions needed before we flip the repo public
**Date:** 2026-04-30
**Author:** Jeff Alldridge / Tent Studios, LLC (with Claude)

---

## TL;DR

Three things need decisions from you before I touch a single file. Everything else is mechanical cleanup I can execute once you call those three.

1. **License decision (blocking).** MKVToolNix is GPL-2.0-or-later. The current `.app` bundles its binaries, which legally drags our distribution under GPL. Options below.
2. **Distribution shape (blocking).** Pure source release vs. signed-and-notarized `.app` on GitHub Releases. You have the Apple Developer account so the second is on the table.
3. **What to do with the planning docs** (`docs/superpowers/`, `docs/roadmap/`, `CLAUDE.md`). Show or hide? My recommendation is below.

After those three, the rest is: write a real `LICENSE` file, polish `README`, add `CONTRIBUTING.md` / `CHANGELOG.md` / `SECURITY.md`, set up GitHub Actions for CI + Releases, harden `.gitignore`, scrub `.DS_Store` files, and stage the first tag.

---

## 1. The license problem (read this first)

Confirmed via Homebrew metadata:

| Component | License | Notes |
|---|---|---|
| `macSubtitleOCR-gui` (this app) | currently MIT in README, no LICENSE file in repo | |
| `macSubtitleOCR` (vendored as submodule, bundled binary) | **MIT** (Ethan Dye) | compatible with anything |
| `mkvmerge`, `mkvextract`, plus all bundled dylibs (libmatroska, libebml, Qt, …) | **GPL-2.0-or-later** | the problem |

**Why this matters.** GPL is "viral" — when you distribute a combined work that includes GPL code (even as separate-but-bundled binaries inside a single `.app`), the combined work has to be available under GPL-compatible terms, and you have to offer the source of the GPL components on request. Calling our app MIT while shipping GPL bundled inside is a real license violation, not a paperwork issue.

You have three honest paths:

### Path A — Stop bundling MKVToolNix in the public `.app` (recommended)

- Public `.app` ships **only** our SwiftUI binary + the embedded `macSubtitleOCR` binary. ~5 MB instead of 68 MB.
- The app already has a "MKVToolNix is required" banner in `DropView` with a one-click copy of `brew install mkvtoolnix`. We just lean into that.
- We can keep MIT, no GPL entanglement.
- Tradeoff: end users have to `brew install mkvtoolnix` once. Most macOS power users already have Homebrew; the people who don't get a clear install card.
- **My recommendation.**

### Path B — Embrace GPL for the bundled `.app`

- License our app **GPL-2.0-or-later** (or GPL-3.0-or-later). Add `LICENSE` accordingly.
- Ship the 68 MB self-contained bundle with proper attribution and an offer of source.
- Include the MKVToolNix `COPYING` text and a `THIRD_PARTY_LICENSES.md` listing every bundled dylib with its license.
- Tradeoff: more legal homework; slight friction for forks since GPL is more restrictive than MIT for downstream reuse.

### Path C — Both

- Two release artifacts on every GitHub release:
  - `macSubtitleOCR-gui-<version>.dmg` (MIT, slim, requires Homebrew mkvtoolnix)
  - `macSubtitleOCR-gui-<version>-bundled.dmg` (GPL, self-contained, no install)
- Source repo licensed MIT; the bundled binary distribution is labeled GPL-aggregate.
- Tradeoff: maintenance overhead, need to clearly explain to users which to download.

> **Decision needed: A, B, or C?**
> If unsure, **A**. It's the most-trodden path for Mac apps that depend on Homebrew toolchains, and we already have the UX for the missing-deps case.

---

## 2. Apple Developer account — yes, this changes things

You have an Apple Developer membership. Two things that account unlocks for distribution:

### 2.1 Developer ID signing

Right now the `.app` is **ad-hoc signed** (`codesign --sign -`), which means:
- Gatekeeper shows the "downloaded from the internet" warning
- First launch requires right-click → Open (or `xattr -dr com.apple.quarantine`)
- macOS treats it as "unidentified developer"

With a **Developer ID Application** certificate (free with your $99/yr membership):
- App is signed with your verified identity
- Gatekeeper trusts the app; no warning *if you also notarize*

To set up, one-time:

1. In Xcode → Settings → Accounts, sign in with your Apple ID
2. Manage Certificates → "+" → **Developer ID Application**
3. Note the cert's identity string (e.g. `Developer ID Application: Jeff Alldridge (TEAMID12345)`)
4. Add to `make-app.sh` so the codesign step uses it instead of `-`

I'll add a `DEV_ID` env var to the script:

```sh
make app DEV_ID="Developer ID Application: Jeff Alldridge (TEAMID12345)"
```

Falls back to ad-hoc when unset (local dev).

### 2.2 Notarization

A signed app can still be flagged by Gatekeeper if it isn't **notarized** — Apple's automated malware scan. Notarization runs on Apple's servers, takes 1–10 minutes, and produces a "ticket" that gets stapled into the `.app`.

Once stapled, your app launches with no warning whatsoever, including offline.

To set up, one-time:

1. Generate an **App Store Connect API Key** (App Store Connect → Users and Access → Keys → "+"). Save the `.p8` file somewhere safe; note the Key ID and Issuer ID.
2. Store credentials in your Keychain:
   ```sh
   xcrun notarytool store-credentials "macSubtitleOCR-gui" \
     --key /path/to/AuthKey_XXXXXX.p8 \
     --key-id "XXXXXXXX" \
     --issuer "yyyyyyyy-..."
   ```
3. After build:
   ```sh
   ditto -c -k --keepParent build/macSubtitleOCR-gui.app /tmp/app.zip
   xcrun notarytool submit /tmp/app.zip --keychain-profile "macSubtitleOCR-gui" --wait
   xcrun stapler staple build/macSubtitleOCR-gui.app
   ```

I'll add `make notarize` to the Makefile.

### 2.3 Hardened Runtime + entitlements

Notarization requires the binary be built with **hardened runtime**. We need to add `--options runtime` to the codesign call AND a minimal entitlements file (`com.apple.security.cs.disable-library-validation` so we can load our bundled dylibs; this is unavoidable for an app that bundles its own toolchain).

### 2.4 What this enables

- Users download the `.dmg`, drag to `/Applications`, double-click. No warnings, no friction.
- Auto-update path opens up later (Sparkle works much better with notarized apps).
- This is the bar Mac users expect from a polished tool.

> **Decision needed:** do we set up Developer ID signing + notarization? Strongly yes if you're shipping a `.app` for download. Skip only if going pure-source-release (Path A bundled-less still wants this for the public release; same answer).

---

## 3. Distribution shape

Three cuts:

| Distribution model | What user does | What you ship | Effort |
|---|---|---|---|
| **Source-only** | `git clone && make app && open …` | Code + tagged versions on GitHub | Low |
| **GitHub Releases** | Download `.dmg` from Releases page, drag to /Applications | `.dmg` per tag, signed + notarized | Medium |
| **Homebrew tap** | `brew install --cask jeffalldridge/macSubtitleOCR-gui` | Cask manifest pointing at GitHub Release | Higher |

**My recommendation:** start with **Source + GitHub Releases**. Cask later if there's interest. Here's why:
- "Download the `.dmg`" is a 1-click experience for non-developers
- Releases let you publish a CHANGELOG and version bumps cleanly
- Cask makes sense once you have at least one external user asking for it; premature otherwise

> **Decision needed:** confirm the Releases path, or pick something else.

---

## 4. Repo cleanup — file-by-file

Audit findings against the current tree:

### 4.1 Root

| File / dir | Status | Action |
|---|---|---|
| `.DS_Store` | **present in repo root** | delete + rely on `.gitignore` |
| `.gitignore` | minimal, has the basics | expand (see §4.5) |
| `.gitmodules` | OK | keep |
| `LICENSE` | **missing** | add (text depends on §1 decision) |
| `README.md` | needs polish for public | rewrite (see §5) |
| `CHANGELOG.md` | missing | add, keep conventional |
| `CONTRIBUTING.md` | missing | add (short, friendly) |
| `SECURITY.md` | missing | add (one paragraph) |
| `THIRD_PARTY_LICENSES.md` | missing | add (lists bundled deps) |
| `Makefile` | works | tweak for `notarize`, `release` targets |
| `Package.swift` | works | leave |
| `CLAUDE.md` | **internal Claude Code instructions** | see §4.4 |

### 4.2 `Sources/`, `Tests/`, `Vendor/`, `Resources/`, `Scripts/`

All structurally fine. The `Vendor/macSubtitleOCR` submodule is the right pattern. `Resources/icon.icon/` will stay (it's the design source).

### 4.3 `build/`

Already gitignored. No issue. Will need to be the publish target for `.dmg` artifacts.

### 4.4 The planning docs question

| Path | Public/private call | Reasoning |
|---|---|---|
| `docs/superpowers/specs/2026-04-30-macSubtitleOCR-gui-design.md` | **keep** | Useful "design rationale" for newcomers; standard practice for serious open-source projects to ship a `docs/design.md` or similar |
| `docs/superpowers/plans/2026-04-30-macSubtitleOCR-gui.md` | **move** to `docs/internal/` (not committed to public branch) | Step-by-step build plan with TDD details — useful while building, noise once built |
| `docs/roadmap/track-preview-scrubber.md` | **keep** | Forward-looking work, transparency is a feature |
| `docs/audit/public-release-audit.md` (this file) | **move out before flipping public** | Internal planning; once we've executed the audit, archive it |
| `CLAUDE.md` | **rename to `AGENTS.md`** OR delete | `CLAUDE.md` exposes that this was Claude-assisted, which is fine but feels personal. `AGENTS.md` is becoming a community standard for "instructions to AI assistants working on this repo." If you'd rather keep it, fine; if you'd rather strip it entirely, also fine — the codebase is well-structured enough to navigate without it. |

> **Decision needed:** what to do with `CLAUDE.md`? My pick: **rename to `AGENTS.md` and clean up tone for a public audience.** Drop any session-specific bits.

> **Decision needed:** keep `docs/superpowers/plans/` and `docs/audit/` in the public repo, or move them to a private `docs/internal/`? My pick: **move to private** (gitignored), preserves the working history without cluttering the public face.

### 4.5 `.gitignore` audit

Current is minimal. For a public Swift/Mac project, we want:

```gitignore
# Build artifacts
.build/
.swiftpm/
build/
*.xcodeproj/
*.xcworkspace/
DerivedData/

# macOS
.DS_Store
*.AppleDouble
*.LSOverride
Icon?
._*
.Spotlight-V100
.Trashes

# Editors
.idea/
.vscode/
*.swp
*~
*.tmp

# Embedded binary (built by make build, not source-controlled)
Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR

# Internal planning (if §4.4 decision is "move out")
docs/internal/

# Notarization scratch
*.zip
notarization-output/

# Secrets — defensive, even if we don't expect them
.env
.env.*
*.p8
*.p12
*.cer
*.pem
secrets/
```

### 4.6 Scrubbing for accidental leaks

I'll grep the working tree and history for:
- Email addresses other than yours
- File paths under `/Users/jeffalldridge/` (a few exist in temp-dir code — those are fine; absolute paths in committed code that point to your home would be bad)
- Anything that looks like an API token (40-character hex, GitHub PAT pattern, AWS key pattern)

I already know the bundle ID is now `com.tentstudios.macSubtitleOCR-gui`, and `Info.plist` mentions you by name, which is intentional and fine.

---

## 5. README upgrade

Current README is functional but not "drop into the world" polished. For a public repo, the gold standard structure:

1. **Title + tagline** — one line that explains the why
2. **Hero screenshot or animated GIF** — show the drop → preview → done flow
3. **Badges** — license, build status, latest release, supported macOS, "made with Swift"
4. **What it does** in 2–3 sentences
5. **Install** — bold, top-of-fold
   - "Download from Releases" button
   - "Or build from source: `make app`"
6. **Requirements** — macOS 14+, Apple Silicon (or Intel?)
7. **Usage** — 4-step happy path with screenshots
8. **Architecture** — link to `docs/superpowers/specs/` design doc
9. **Building** — `make build` / `make run` / `make test` / `make app`
10. **Roadmap** — link to `docs/roadmap/`
11. **Credits** — Ethan Dye for macSubtitleOCR, MKVToolNix authors, Apple's Vision framework, you/Tent Studios
12. **License** — MIT (or GPL, see §1)

I'll write the new README once the §1 decision is made (license affects the badges and the credits paragraph).

> **Decision needed:** do you want screenshots in the README? If yes, I need you to take them once the app is in a state you like — I can't take screenshots from here. We can ship without them and add later.

---

## 6. CI/CD with GitHub Actions

Two workflows worth setting up:

### 6.1 `ci.yml` — runs on every push / PR

```yaml
on:
  push: { branches: [main] }
  pull_request:
jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive }
      - run: brew install mkvtoolnix dylibbundler
      - run: make build
      - run: make test
```

A green checkmark next to commits is a small thing that signals "this project is alive and tested."

### 6.2 `release.yml` — runs when you push a tag like `v0.1.0`

```yaml
on:
  push:
    tags: ['v*.*.*']
jobs:
  build-and-release:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive }
      - run: brew install mkvtoolnix dylibbundler
      - run: make build && make app  # or `make app-mit` for slim Path A
      - name: Sign + notarize
        env:
          DEV_ID: ${{ secrets.DEV_ID }}
          NOTARY_PROFILE: ${{ secrets.NOTARY_PROFILE }}
          # ...
        run: make notarize
      - name: Build .dmg
        run: hdiutil create -srcfolder build/macSubtitleOCR-gui.app
                            -volname "macSubtitleOCR" build/macSubtitleOCR-gui.dmg
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: build/macSubtitleOCR-gui.dmg
          generate_release_notes: true
```

This needs **GitHub Secrets** set up:
- `DEV_ID` — the cert identity string
- `NOTARY_PROFILE` — App Store Connect API key
- The `.p8` file as a secret variable
- The cert imported into the runner's keychain (workflow step using `apple-actions/import-codesign-certs`)

I can write this once you've set up the cert + API key. Until then, releases are manual via `make app && make notarize` on your machine.

> **Decision needed:** automate releases via GitHub Actions, or do them manually for now? I'd say **manual to start**, automate when v0.2 is ready.

---

## 7. Versioning + first release

You're at `0.1.0` per `Info.plist`. For the first public release I'd cut **`v0.1.0`**:

- Tag: `v0.1.0`
- Title: "v0.1.0 — initial public release"
- Body: bullet list of features (drop, multi-track pick, OCR, SRT preview cards, language-aware filename, persistent options, track filter)
- Asset: `macSubtitleOCR-gui-0.1.0.dmg` (signed + notarized)
- Plus a `SHA256SUMS` text file for transparency

Adopt **Conventional Commits** going forward (you mostly already do — `Add foo`, `Polish bar`, etc. — just slightly more rigorous). Then `git cliff` or `release-please` can auto-generate `CHANGELOG.md` from commit history.

---

## 8. Things I'd add for "I don't look foolish"

These are the things experienced open-source maintainers expect to see:

- [ ] `LICENSE` file at root
- [ ] `README.md` with install + usage + screenshots + credits
- [ ] `CHANGELOG.md` with a `[0.1.0]` section
- [ ] `CONTRIBUTING.md` — even one paragraph saying "PRs welcome, please run `make test` first"
- [ ] `SECURITY.md` — "for security issues, email me, don't open public issues"
- [ ] `THIRD_PARTY_LICENSES.md` — every dylib + library in the bundle, with link to its license
- [ ] `.github/ISSUE_TEMPLATE/bug_report.md` and `feature_request.md`
- [ ] `.github/PULL_REQUEST_TEMPLATE.md` — short
- [ ] `.github/workflows/ci.yml` — at minimum
- [ ] Branch protection on `main` once you have a release out (no force-push, require PR for changes — easy to set in GitHub UI)
- [ ] Enable issues + discussions on the repo
- [ ] A topic tag list on the repo: `macos`, `swiftui`, `subtitles`, `ocr`, `pgs`, `vobsub`, `srt`
- [ ] Repo description set: "Drop a Blu-ray rip into a SwiftUI window, get clean .srt files. Powered by Vision and macSubtitleOCR."
- [ ] Pin the upstream submodule to a specific tag, not `main`, so a clone is reproducible

Things you'd see in *bigger* projects but I'd skip for v0.1:
- ~~CODE_OF_CONDUCT.md~~ (overkill for a single-maintainer tool)
- ~~Sponsors / Open Collective~~ (worry about it if/when there's traction)
- ~~Crowdin / translations~~
- ~~Auto-update via Sparkle~~ (worth doing later if there's a v2)

---

## 9. Edge cases worth thinking about

Things you might not have considered:

- **`.app` bundle identifier collision.** `com.tentstudios.macSubtitleOCR-gui` is yours; make sure it stays consistent across releases or LaunchServices may register multiple copies.
- **Quarantine attribute on download.** Even with notarization, a `.dmg` downloaded via `curl` (not Safari) may not have the quarantine bit set, so testing notarization needs Safari-style download or `xattr -w com.apple.quarantine` to simulate.
- **Intel Mac users.** Right now upstream's release page only ships arm64 binaries. Our build pipeline DOES compile for whatever the host arch is, so an Intel user building from source gets an Intel app. But if your release pipeline runs on M-series GitHub runners, the `.dmg` is arm64-only. Note this in the README; consider a universal binary later.
- **macOS version drift.** `LSMinimumSystemVersion` is 14.0. macOS 14 (Sonoma) is what's in `Info.plist`. Confirm that's the floor you want — most "modern" tools target 14+ now.
- **License of the icon SVG.** It's derived from Apple's SF Symbol `captions.bubble`. SF Symbols are usable in apps but Apple's license technically restricts using them as standalone artwork. The Icon Composer source treats it as a layer in your composition, which is how Apple expects you to use them — fine for shipping. Don't use it standalone outside the app.
- **GitHub repo name.** Consider naming carefully: `macSubtitleOCR-gui` is descriptive but visually similar to the upstream's `macSubtitleOCR` — risks confusion. Alternatives: `subtitle-ocr-mac`, `pgs-to-srt-gui`, `caption-bubble`. `macSubtitleOCR-gui` is fine if you're OK with the upstream-derivative naming.
- **Submodule HTTPS vs SSH.** Currently `.gitmodules` uses HTTPS — good for clones. Don't switch to SSH; it'll break for users without GitHub SSH set up.
- **What if upstream macSubtitleOCR disappears.** If the upstream repo gets archived/deleted, your submodule clones break. Not an immediate concern but worth knowing — solution if it happens is to fork it under your account and re-point.
- **Reproducible builds.** Submodule pinned to a specific commit (we do this), Package.resolved committed (we should — let me verify). That gets us close.
- **Crash reporting / telemetry.** Don't add any. A privacy-respecting Mac tool gets quiet adoption. If you want crash reports later, it's `os_log` + asking users to send the log.

---

## 10. The decision matrix

Here's everything that needs your call, in priority order. Everything else I can execute without further input.

| # | Decision | Recommendation | Blocking? |
|---|---|---|---|
| 1 | License + bundle MKVToolNix? (§1) | **Path A: MIT, drop bundle, require Homebrew** | yes |
| 2 | Set up Developer ID signing + notarization? (§2) | **Yes, set it up** | mostly yes |
| 3 | Distribution model? (§3) | **Source + GitHub Releases** | yes |
| 4 | Keep `CLAUDE.md` as `AGENTS.md`, or delete? (§4.4) | **Rename to `AGENTS.md`** | no |
| 5 | Hide planning docs (`plans/`, `audit/`)? (§4.4) | **Move to gitignored `docs/internal/`** | no |
| 6 | Automate releases via Actions, or manual? (§6) | **Manual for v0.1, automate for v0.2** | no |
| 7 | Repo name change from `macSubtitleOCR-gui`? (§9) | **Keep current, it's clear** | no |
| 8 | Universal binary or arm64-only first release? (§9) | **arm64-only for v0.1** | no |
| 9 | Take screenshots for README? (§5) | **Yes, but ship without if you'd rather move fast** | no |

---

## 11. Recommended action sequence

Once you've answered #1, #2, and #3, here's the rough order I'd execute. Each line is roughly 30–90 minutes.

1. Add `LICENSE` file (text per §1 decision)
2. Add `THIRD_PARTY_LICENSES.md` (everything bundled, with upstream license links)
3. Add `CHANGELOG.md` with a `[Unreleased]` section, plus a stub `[0.1.0]` we'll fill in at tag time
4. Add `CONTRIBUTING.md` and `SECURITY.md` (short)
5. Rename `CLAUDE.md` → `AGENTS.md`, clean for public audience (or delete)
6. Move planning docs to `docs/internal/`, add to `.gitignore`
7. Expand `.gitignore` per §4.5
8. Scrub `.DS_Store` files; add a `find . -name .DS_Store -delete` to a Makefile target
9. Rewrite `README.md` per §5
10. If Path A: refactor `make app` to skip MKVToolNix bundling, keep `make app-bundled` as private target
11. Add `make notarize` and `make release` Makefile targets
12. Add `.github/workflows/ci.yml`
13. Add `.github/ISSUE_TEMPLATE/` and `PULL_REQUEST_TEMPLATE.md`
14. Set up your Developer ID cert + notarytool credentials (one-time, on your machine)
15. Tag `v0.1.0`; build, sign, notarize, package as `.dmg`; create GitHub Release
16. Flip the repo to public

That's the plan. Tell me 1–3 and I start.
