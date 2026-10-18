APP    = Clipcat.app
LABEL  = party.chee.clipcat
PREFIX ?= $(HOME)/Applications
AGENT  = $(HOME)/Library/LaunchAgents/$(LABEL).plist
BIN    = $(PREFIX)/$(APP)/Contents/MacOS/Clipcat

# signing identity: CLIPCAT_SIGN if set, else the keychain's first Apple Development
# one, then Developer ID Application, else ad hoc (-), whose accessibility grant
# macOS forgets at every build
IDENTITIES = security find-identity -v -p codesigning 2>/dev/null
find_id    = $(IDENTITIES) | sed -n 's/.*"\($(1):[^"]*\)".*/\1/p' | head -1
SIGN      ?= $(or $(CLIPCAT_SIGN),$(shell $(call find_id,Apple Development)),$(shell $(call find_id,Developer ID Application)),-)

.PHONY: build bundle install uninstall run

build:
	swift build -c release

bundle: build
	rm -rf build/$(APP)
	mkdir -p build/$(APP)/Contents/MacOS
	cp .build/release/Clipcat build/$(APP)/Contents/MacOS/Clipcat
	cp support/Info.plist build/$(APP)/Contents/Info.plist
	mkdir -p build/$(APP)/Contents/Resources
	cp -R support/fonts build/$(APP)/Contents/Resources/fonts
	cp support/Clipcat.icns build/$(APP)/Contents/Resources/Clipcat.icns
	@case "$(SIGN)" in \
	"Developer ID Application:"*) codesign --force --options runtime --timestamp --identifier $(LABEL) --sign "$(SIGN)" build/$(APP) ;; \
	*) codesign --force --identifier $(LABEL) --sign "$(SIGN)" build/$(APP) ;; \
	esac
	codesign --verify --strict build/$(APP)
	@echo "signed by: $(SIGN)"

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
