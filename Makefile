.PHONY: build test app universal dmg run install clean

build:
	swift build

test:
	swift test

app:
	./scripts/bundle.sh

universal:
	UNIVERSAL=1 ./scripts/bundle.sh

dmg: universal
	./scripts/make-dmg.sh

run: app
	open build/Dokr.app

install: app
	rm -rf /Applications/Dokr.app
	cp -R build/Dokr.app /Applications/

clean:
	rm -rf .build build
