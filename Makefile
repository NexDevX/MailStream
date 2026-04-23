PROJECT := MailClient.xcodeproj
SCHEME := MailClient
DERIVED_DATA := build/DerivedData

.PHONY: icon generate build test package clean

icon:
	swift ./scripts/design/generate_app_icon.swift

generate: icon
	xcodegen generate

build: generate
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO \
		clean build

test: generate
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO \
		test

package:
	./scripts/build_dmg.sh

clean:
	rm -rf build
