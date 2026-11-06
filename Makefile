PROJECT := Stremio.xcodeproj
SCHEME  := Stremio
DERIVED ?= build/DerivedData
APP     := $(DERIVED)/Build/Products/Debug/Stremio.app
RELEASE_APP := $(DERIVED)/Build/Products/Release/Stremio.app
VERSION := $(shell sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
ZIP     := build/Stremio-mac-$(VERSION).zip
SOURCES := Stremio Tests

.PHONY: bootstrap generate build release install dist test format lint open run clean

bootstrap:
	scripts/bootstrap.sh

generate:
	xcodegen generate --quiet

build: bootstrap generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' -derivedDataPath $(DERIVED) $(XCODEBUILD_FLAGS) build

release: bootstrap generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'platform=macOS' -derivedDataPath $(DERIVED) $(XCODEBUILD_FLAGS) build

install: release
	scripts/install.sh $(RELEASE_APP)

dist: release
	rm -f $(ZIP)
	ditto -c -k --keepParent $(RELEASE_APP) $(ZIP)
	@echo "Wrote $(ZIP)"
	@unzip -l $(ZIP) | tail -n 1

test: bootstrap generate
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=macOS' -derivedDataPath $(DERIVED) $(XCODEBUILD_FLAGS)

format:
	xcrun swift-format format --in-place --recursive $(SOURCES)

lint:
	xcrun swift-format lint --strict --recursive $(SOURCES)

open: bootstrap generate
	open $(PROJECT)

run: build
	open $(APP)

clean:
	rm -rf build
