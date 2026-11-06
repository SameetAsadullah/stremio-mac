PROJECT := Stremio.xcodeproj
SCHEME  := Stremio
DERIVED ?= build/DerivedData
APP     := $(DERIVED)/Build/Products/Debug/Stremio.app
SOURCES := Stremio Tests

.PHONY: bootstrap generate build test format lint open run clean

bootstrap:
	scripts/bootstrap.sh

generate:
	xcodegen generate --quiet

build: bootstrap generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' -derivedDataPath $(DERIVED) $(XCODEBUILD_FLAGS) build

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
