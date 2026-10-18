# swift-minidisc. Needs Xcode, xcodegen and node.
#
#   make js        bundle netmd-js + netmd-exploits for NetMDKit (JS/)
#   make generate  generate MiniDisc.xcodeproj from project.yml
#   make app       build the app (Debug)       make run   ...and open it
#   make test      swift test, plus upstream's byte-exact encoder tests
#   make cli ARGS='--list-usb'   hardware test tool (see docs/NETMD-JSC.md)

DERIVED := .build/xcode
APP     := $(DERIVED)/Build/Products/Debug/MiniDisc.app
CLI     := .build/release/netmd-cli

.PHONY: js generate app run test cli clean

js: Sources/NetMDKit/Resources/netmd-bundle.js
Sources/NetMDKit/Resources/netmd-bundle.js: JS/package.json JS/build.mjs JS/entry.js $(wildcard JS/shims/*.js)
	cd JS && npm ci --no-audit --no-fund && npm run build --silent

generate: js
	xcodegen generate --quiet

app: generate
	xcodebuild -project MiniDisc.xcodeproj -scheme MiniDisc -derivedDataPath $(DERIVED) -quiet build

run: app
	open $(APP)

test:
	swift test
	swift build -c release --product atrac3-swift
	python3 ThirdParty/atrac-encoder/tests/run_tests.py --bin .build/release/atrac3-swift

cli: js
	swift build -c release --product netmd-cli
	codesign --force -s - -o runtime --entitlements netmd-cli.entitlements $(CLI)
	$(CLI) $(ARGS)

clean:
	rm -rf MiniDisc.xcodeproj App/Info.plist .build
