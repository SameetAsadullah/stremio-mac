PROJECT := Stremio.xcodeproj
SCHEME  := Stremio
DERIVED ?= build/DerivedData
APP     := $(DERIVED)/Build/Products/Debug/Stremio.app
SOURCES := Stremio

.PHONY: generate build format lint open run clean

generate:
	xcodegen generate --quiet

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' -derivedDataPath $(DERIVED) build

format:
	xcrun swift-format format --in-place --recursive $(SOURCES)

lint:
	xcrun swift-format lint --strict --recursive $(SOURCES)

open: generate
	open $(PROJECT)

run: build
	open $(APP)

clean:
	rm -rf build
