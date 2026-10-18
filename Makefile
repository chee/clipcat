APP    = ClipCat.app
LABEL  = party.chee.clipcat
PREFIX ?= $(HOME)/Applications
AGENT  = $(HOME)/Library/LaunchAgents/$(LABEL).plist
BIN    = $(PREFIX)/$(APP)/Contents/MacOS/ClipCat

.PHONY: build bundle install uninstall run

build:
	swift build -c release

bundle: build
	rm -rf build/$(APP)
	mkdir -p build/$(APP)/Contents/MacOS
	cp .build/release/ClipCat build/$(APP)/Contents/MacOS/ClipCat
	cp support/Info.plist build/$(APP)/Contents/Info.plist
	mkdir -p build/$(APP)/Contents/Resources
	cp -R support/fonts build/$(APP)/Contents/Resources/fonts
	codesign --force --sign - --identifier $(LABEL) build/$(APP)

install: bundle
	-launchctl bootout gui/$$(id -u)/$(LABEL) 2>/dev/null
	mkdir -p $(PREFIX) $(HOME)/Library/LaunchAgents
	rm -rf $(PREFIX)/$(APP)
	cp -R build/$(APP) $(PREFIX)/$(APP)
	sed "s|@BIN@|$(BIN)|" support/$(LABEL).plist > $(AGENT)
	launchctl bootstrap gui/$$(id -u) $(AGENT)

uninstall:
	-launchctl bootout gui/$$(id -u)/$(LABEL) 2>/dev/null
	rm -f $(AGENT)
	rm -rf $(PREFIX)/$(APP)

run:
	swift run
