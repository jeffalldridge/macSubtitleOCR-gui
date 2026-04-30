.PHONY: build run app update clean test

SWIFT       ?= swift
VENDOR      := Vendor/macSubtitleOCR
EMBEDDED    := Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR
APP_NAME    := macSubtitleOCR-gui
APP_BUNDLE  := build/$(APP_NAME).app

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

update:
	@echo "==> Fetching latest macSubtitleOCR"
	git -C $(VENDOR) fetch origin
	git -C $(VENDOR) checkout origin/main
	@rm -f $(EMBEDDED)
	$(MAKE) build
	@echo "==> Submodule bumped. Review and commit:"
	@git status -- $(VENDOR)

app: build Scripts/make-app.sh
	bash Scripts/make-app.sh "$(APP_BUNDLE)"

clean:
	$(SWIFT) package clean
	rm -rf .build build
	rm -f $(EMBEDDED)
	-cd $(VENDOR) && $(SWIFT) package clean 2>/dev/null || true
