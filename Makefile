# Common tasks. Everything also works with plain `swift` and the scripts in Scripts/.

.PHONY: build test lint format app run check icon screenshots clean

build:
	swift build

test:
	swift test

lint:
	swift format lint --strict --recursive Sources Tests

format:
	swift format format --in-place --recursive Sources Tests

app:
	Scripts/build-app.sh

run: app
	open "build/Pitwall.app"

check:
	swift run pitwall-check

icon:
	Scripts/make-icon.sh

screenshots:
	Scripts/build-app.sh debug
	Scripts/snapshots.sh docs/screenshots --demo --appearance dark --prefix dark --select 88
	Scripts/snapshots.sh docs/screenshots --demo --appearance light --prefix light --group tag

clean:
	rm -rf .build build
