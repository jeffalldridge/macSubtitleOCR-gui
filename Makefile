.PHONY: build run app dmg notarize release update clean test

SWIFT       ?= swift
VENDOR      := Vendor/macSubtitleOCR
EMBEDDED    := Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR
APP_NAME    := macSubtitleOCR-gui
APP_BUNDLE  := build/$(APP_NAME).app
DMG_PATH    := build/$(APP_NAME).dmg

# Read the version from Info.plist so `make release` tags consistently.
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist 2>/dev/null || echo "0.0.0")

# Notarization profile name (created via `xcrun notarytool store-credentials`).
# Override per-environment if needed.
NOTARY_PROFILE ?= macSubtitleOCR-gui

# ---------------------------------------------------------------------------
# Build pipeline
# ---------------------------------------------------------------------------

build: $(EMBEDDED)
	$(SWIFT) build -c release

$(EMBEDDED): $(VENDOR)/Package.swift
	@echo "==> Building upstream macSubtitleOCR"
	cd $(VENDOR) && $(SWIFT) build -c release
	@mkdir -p $(dir $(EMBEDDED))
	cp $(VENDOR)/.build/release/macSubtitleOCR $(EMBEDDED)
	@echo "==> Embedded binary at $(EMBEDDED)"

run: build
	$(SWIFT) run -c release $(APP_NAME)

test:
	$(SWIFT) test

# ---------------------------------------------------------------------------
# `.app` bundle (3.6 MB, MIT-licensed). Pass DEV_ID to sign with a Developer
# ID Application certificate ready for notarization; without it, ad-hoc.
# ---------------------------------------------------------------------------

app: build Scripts/make-app.sh
	bash Scripts/make-app.sh "$(APP_BUNDLE)"

# ---------------------------------------------------------------------------
# DMG packaging — drag-to-/Applications layout.
# ---------------------------------------------------------------------------

dmg: app
	@rm -f "$(DMG_PATH)"
	@echo "==> Building $(DMG_PATH)"
	@mkdir -p build/dmg-staging
	@rm -rf build/dmg-staging/*
	@cp -R "$(APP_BUNDLE)" build/dmg-staging/
	@ln -sf /Applications "build/dmg-staging/Applications"
	hdiutil create -volname "$(APP_NAME) $(VERSION)" \
	               -srcfolder build/dmg-staging \
	               -ov -format UDZO \
	               "$(DMG_PATH)"
	@rm -rf build/dmg-staging
	@echo "==> Built $(DMG_PATH) ($$(du -sh "$(DMG_PATH)" | awk '{print $$1}'))"

# ---------------------------------------------------------------------------
# Notarization — submits the .app to Apple's notarization service, waits for
# the result, and staples the ticket so the bundle launches without the
# "downloaded from internet" warning offline.
#
# One-time setup on the developer's machine:
#   1) Apple Developer ID Application cert installed in login keychain.
#   2) An App Store Connect API key (.p8) saved somewhere safe.
#   3) Run once:
#        xcrun notarytool store-credentials "$(NOTARY_PROFILE)" \
#          --key /path/to/AuthKey_XXXX.p8 \
#          --key-id XXXXXXXXXX \
#          --issuer YYYYYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY
#   4) export DEV_ID="Developer ID Application: Your Name (TEAMID)"
# Then:
#   make notarize
# ---------------------------------------------------------------------------

notarize: app
	@if [[ -z "$$DEV_ID" ]]; then \
	    echo "Error: DEV_ID must be set to a Developer ID Application identity." >&2; \
	    echo "Example: make notarize DEV_ID=\"Developer ID Application: Jeff Alldridge (TEAMID)\"" >&2; \
	    exit 1; \
	fi
	@echo "==> Re-building app signed with Developer ID + hardened runtime"
	DEV_ID="$$DEV_ID" bash Scripts/make-app.sh "$(APP_BUNDLE)"
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
	@rm -f build/notarize.zip
	@echo "==> Notarized $(APP_BUNDLE)"

# ---------------------------------------------------------------------------
# Full release pipeline: clean build, notarize, build .dmg.
# ---------------------------------------------------------------------------

release: clean notarize
	$(MAKE) dmg
	@echo "==> Release artifact: $(DMG_PATH)"
	@echo "Tag with:  git tag -a v$(VERSION) -m 'v$(VERSION)' && git push --tags"

# ---------------------------------------------------------------------------
# Maintenance
# ---------------------------------------------------------------------------

update:
	@echo "==> Fetching latest macSubtitleOCR"
	git -C $(VENDOR) fetch --tags origin
	git -C $(VENDOR) checkout origin/main
	@rm -f $(EMBEDDED)
	$(MAKE) build
	@echo "==> Submodule bumped. Review and commit:"
	@git status -- $(VENDOR)

clean:
	$(SWIFT) package clean
	rm -rf .build build
	rm -f $(EMBEDDED)
	-cd $(VENDOR) && $(SWIFT) package clean 2>/dev/null || true
