.PHONY: build run test app dmg package-dmg notarize submit-dmg-notarization notarize-dmg release diff-upstream clean

SWIFT       ?= swift
APP_NAME    := macSubtitleOCR-gui
APP_BUNDLE  := build/$(APP_NAME).app
DMG_PATH    := build/$(APP_NAME).dmg
ARCHS       := --arch arm64 --arch x86_64

# Read the version from Info.plist so `make release` tags consistently.
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist 2>/dev/null || echo "0.0.0")

# Notarization profile name (created via `xcrun notarytool store-credentials`).
NOTARY_PROFILE ?= macSubtitleOCR-gui

# ---------------------------------------------------------------------------
# Build
#
# Everything is Swift: the Matroska reader, the PGS and VobSub decoders, and
# the Vision recognition all live in the SubtitleEngine target. There is no
# submodule to build and no binary to embed.
# ---------------------------------------------------------------------------

build:
	$(SWIFT) build -c release $(ARCHS)

run:
	$(SWIFT) run $(APP_NAME)

test:
	$(SWIFT) test

# ---------------------------------------------------------------------------
# `.app` bundle. Pass DEV_ID to sign with a Developer ID Application identity
# ready for notarization; without it the bundle is ad-hoc signed.
# ---------------------------------------------------------------------------

app: build Scripts/make-app.sh
	bash Scripts/make-app.sh "$(APP_BUNDLE)"

# ---------------------------------------------------------------------------
# DMG packaging — drag-to-/Applications layout.
# ---------------------------------------------------------------------------

dmg: app package-dmg

package-dmg:
	@rm -f "$(DMG_PATH)"
	@echo "==> Building $(DMG_PATH)"
	@mkdir -p build/dmg-staging
	@rm -rf build/dmg-staging/*
	@cp -R "$(APP_BUNDLE)" build/dmg-staging/
	@ln -sf /Applications "build/dmg-staging/Applications"
	hdiutil create -volname "macSubtitleOCR $(VERSION)" \
	               -srcfolder build/dmg-staging \
	               -ov -format UDZO \
	               "$(DMG_PATH)"
	@rm -rf build/dmg-staging
	@if [[ -n "$$DEV_ID" ]]; then \
	    echo "==> Signing $(DMG_PATH) with Developer ID"; \
	    codesign --force --sign "$$DEV_ID" --timestamp "$(DMG_PATH)"; \
	fi
	@echo "==> Built $(DMG_PATH) ($$(du -sh "$(DMG_PATH)" | awk '{print $$1}'))"

# ---------------------------------------------------------------------------
# Notarization — submits to Apple, waits, staples the ticket.
#
# One-time setup on the developer's machine:
#   1) Developer ID Application certificate in the login keychain.
#   2) An App Store Connect API key (.p8).
#   3) xcrun notarytool store-credentials "$(NOTARY_PROFILE)" \
#        --key /path/to/AuthKey_XXXX.p8 --key-id XXXXXXXXXX --issuer UUID
#   4) export DEV_ID="Developer ID Application: Your Name (TEAMID)"
# ---------------------------------------------------------------------------

notarize: app
	@if [[ -z "$$DEV_ID" ]]; then \
	    echo "Error: DEV_ID must be set to a Developer ID Application identity." >&2; \
	    echo "Example: make notarize DEV_ID=\"Developer ID Application: Jeff Alldridge (TEAMID)\"" >&2; \
	    exit 1; \
	fi
	@rm -f build/notarize.zip
	@echo "==> Zipping for notarytool"
	ditto -c -k --keepParent "$(APP_BUNDLE)" build/notarize.zip
	@echo "==> Submitting to Apple notary service (this can take a few minutes)"
	xcrun notarytool submit build/notarize.zip \
	    --keychain-profile "$(NOTARY_PROFILE)" \
	    --wait
	@echo "==> Stapling notarization ticket"
	xcrun stapler staple "$(APP_BUNDLE)"
	xcrun stapler validate "$(APP_BUNDLE)"
	@echo "==> Verifying Gatekeeper acceptance (must pass once stapled)"
	spctl --assess --type execute --verbose=1 "$(APP_BUNDLE)"
	@rm -f build/notarize.zip
	@echo "==> Notarized $(APP_BUNDLE)"

# Notarize and staple the .dmg itself, so even macOS Sequoia's
# "verify before opening" sheet is skipped.
notarize-dmg: dmg submit-dmg-notarization

submit-dmg-notarization:
	@if [[ -z "$$DEV_ID" ]]; then \
	    echo "Error: DEV_ID must be set." >&2; exit 1; \
	fi
	@echo "==> Submitting $(DMG_PATH) to Apple notary service"
	xcrun notarytool submit "$(DMG_PATH)" \
	    --keychain-profile "$(NOTARY_PROFILE)" \
	    --wait
	@echo "==> Stapling notarization ticket to DMG"
	xcrun stapler staple "$(DMG_PATH)"
	xcrun stapler validate "$(DMG_PATH)"
	@echo "==> Notarized $(DMG_PATH)"

# Full release pipeline: clean build, notarize, package, notarize the dmg.
release: clean notarize
	$(MAKE) package-dmg
	$(MAKE) submit-dmg-notarization
	@echo "==> Release artifact: $(DMG_PATH) (signed + notarized + stapled)"
	@echo "Tag with:  git tag -a v$(VERSION) -m 'v$(VERSION)' && git push --tags"

# ---------------------------------------------------------------------------
# Maintenance
# ---------------------------------------------------------------------------

# Show what upstream macSubtitleOCR has changed in the decoders since the
# commit this engine was ported from. Override the ref with REF=v1.1.0.
diff-upstream:
	bash Scripts/diff-upstream.sh $(REF)

clean:
	$(SWIFT) package clean
	rm -rf .build build
