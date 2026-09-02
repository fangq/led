# led build system
#
# Common targets:
#   make            - build the editor (optimized + stripped Release, ~7 MB)
#   make debug      - build with debug info and range checks (large, for development)
#   make tests      - build and run the headless core suite
#   make selftest   - build and run the scripted GUI self-test (needs a display)
#   make check      - both of the above, plus the grammar gate
#   make run        - build and launch the editor
#   make res        - regenerate app/led.res from packaging/windows/led.rc
#   make icon       - regenerate the icons from tools/make-icon.py
#   make grammars   - reconvert data/grammars from the .lang sources
#   make conpty     - type-check the Windows ConPTY backend on any platform
#   make deb        - build dist/*.deb and a portable dist/*.tar.gz (Linux)
#   make clean      - remove build artifacts
#   make distclean  - also remove the binaries
#   make install    - install the prebuilt binary, data, icons and .desktop
#                     user:   make && make install                 (~/.local, no sudo)
#                     system: make && sudo make install PREFIX=/usr/local
#   make uninstall  - remove the installed files
#
# Cross-compile targets (need a matching cross-FPC + LCL for the target):
#   make linux | win64 | win32 | macos
#
# led reads its grammars, themes and tools from data/ at run time, so those
# travel with the binary; `make install` puts them in $(PREFIX)/share/led and
# the binary finds them relative to itself.

LAZBUILD ?= lazbuild
FPC      ?= fpc
FPCRES   ?= fpcres
PREFIX   ?= $(HOME)/.local

# Optional: force the Lazarus install dir.  Useful when lazbuild's saved config
# points elsewhere (a different Lazarus, or a shared home whose ~/.lazarus was
# written by another machine).  Empty -> let lazbuild auto-detect.
#   make LAZARUSDIR=/usr/lib/lazarus/2.2.0
LAZARUSDIR ?=
LAZDIR := $(if $(LAZARUSDIR),--lazarusdir="$(LAZARUSDIR)")

# The widgetset for a native build.  gtk2 is the default on Unix because it is
# what upstream Lazarus ships prebuilt; qt5 also works.
WIDGETSET ?= gtk2

PROJECT  := app/led.lpi
TESTPROJ := test/ledcoretest.lpi
LANGPROJ := tools/langcheck/langcheck.lpi
BIN      := bin/led
RES      := app/led.res
ICON     := packaging/icons/led.ico

ICONSIZES := 16 22 24 32 48 64 128 256 512

PASSRC := $(shell find packages app -name '*.pas' -o -name '*.lpr')

.PHONY: all build release debug tests selftest check run res icon grammars \
        conpty \
        deb clean distclean install uninstall linux win64 win32 macos help

all: build

# ---- icons and resources ---------------------------------------------------
# The icon is generated, not committed as an opaque blob, so the design lives
# in a script that can be read and changed.
$(ICON): tools/make-icon.py
	python3 tools/make-icon.py
icon: $(ICON)

# Only Windows reads the resource, but app/led.lpr references it
# unconditionally, so it is committed and a fresh clone needs no fpcres.
$(RES): packaging/windows/led.rc packaging/windows/led.manifest $(ICON)
	cd packaging/windows && $(FPCRES) -of res -o ../../$(RES) led.rc
res: $(RES)

# ---- builds ----------------------------------------------------------------
build release: $(RES)
	$(LAZBUILD) $(LAZDIR) --widgetset=$(WIDGETSET) --build-mode=Release $(PROJECT)

debug: $(RES)
	$(LAZBUILD) $(LAZDIR) --widgetset=$(WIDGETSET) --build-mode=Debug $(PROJECT)

# ---- cross builds ----------------------------------------------------------
linux: $(RES)
	$(LAZBUILD) $(LAZDIR) --operating-system=linux  --widgetset=gtk2  --build-mode=Release $(PROJECT)
win64: $(RES)
	$(LAZBUILD) $(LAZDIR) --operating-system=win64  --cpu=x86_64 --widgetset=win32 --build-mode=Release $(PROJECT)
win32: $(RES)
	$(LAZBUILD) $(LAZDIR) --operating-system=win32  --cpu=i386   --widgetset=win32 --build-mode=Release $(PROJECT)
macos: $(RES)
	$(LAZBUILD) $(LAZDIR) --operating-system=darwin --widgetset=cocoa --build-mode=Release $(PROJECT)

# ---- tests -----------------------------------------------------------------
# The core suite is built with the nogui widgetset on purpose: ledcore must
# stay free of any visual dependency, and this is what enforces it.
tests:
	$(LAZBUILD) $(LAZDIR) --widgetset=nogui $(TESTPROJ)
	./bin/ledcoretest --all --format=plain

# Drives the real forms through a scripted sequence.  Needs a display; under
# CI that means xvfb-run.  It uses a configuration directory of its own, so it
# reports led's behaviour rather than yours.
# On its own display when one can be had.  Sharing the desktop makes the
# focus-dependent checks depend on whatever else has a window open, which
# showed up as two failures that would not reproduce on the next run.
selftest: build
	@if command -v xvfb-run >/dev/null 2>&1; then \
	  xvfb-run -a ./$(BIN) --self-test; \
	else \
	  echo "(xvfb-run not found; running on the current display)"; \
	  ./$(BIN) --self-test; \
	fi

# Every converted grammar must load in the engine the editor actually uses.
grammars:
	python3 tools/lang2tm.py data/langs data/grammars
	$(LAZBUILD) $(LAZDIR) --widgetset=nogui $(LANGPROJ)
	./bin/langcheck data/grammars

# The Windows terminal backend, compiled on whatever platform you are on.
# There is no Windows cross-toolchain on the machine it was written on, so
# without this the first compiler to see led.term.pty.conpty.inc would be a
# CI runner three minutes into a push.  The harness mirrors the Win32 surface
# the include uses, signature for signature out of FPC's rtl/win/wininc, and
# compiles the real source against it.  It proves nothing about Windows
# behaviour -- only that the code is well-formed.
conpty:
	$(FPC) -Mobjfpc -Sh -Fipackages/ledterm/src -FUlib/conptycheck \
	       -otools/conptycheck/conptycheck tools/conptycheck/conptycheck.lpr
	./tools/conptycheck/conptycheck

check: tests grammars conpty selftest

run: build
	./$(BIN)

# ---- packages --------------------------------------------------------------
# The same script CI runs, so a broken package can be found and fixed here
# rather than three minutes into a workflow.
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo 0.0.0-dev)

deb: build
	packaging/linux/build-deb.sh "$(CURDIR)" "$(VERSION)"

# ---- desktop integration (Linux) -------------------------------------------
# Copies the already-built files; does NOT recompile, so it is safe under sudo.
# Build first as your normal user, then install.
install:
	@test -x "$(BIN)" || { \
	  echo "led isn't built yet.  Build first as your normal user (not root):"; \
	  echo "    make"; \
	  echo "then:"; \
	  echo "    make install                        # into ~/.local (no sudo)"; \
	  echo "    sudo make install PREFIX=/usr/local # system-wide"; \
	  exit 1; }
	install -Dm755 $(BIN) $(PREFIX)/bin/led
	@# Grammars, themes and the shipped tools are read at run time.
	@for sub in grammars themes tools langs dict; do \
	  if [ -d "data/$$sub" ]; then \
	    mkdir -p "$(PREFIX)/share/led/$$sub"; \
	    cp -r "data/$$sub/." "$(PREFIX)/share/led/$$sub/"; \
	  fi; \
	done
	install -Dm644 packaging/linux/led.desktop $(PREFIX)/share/applications/led.desktop
	install -Dm644 packaging/icons/led.svg \
	  $(PREFIX)/share/icons/hicolor/scalable/apps/led.svg
	@for s in $(ICONSIZES); do \
	  install -Dm644 packaging/icons/hicolor/$${s}x$${s}/apps/led.png \
	    $(PREFIX)/share/icons/hicolor/$${s}x$${s}/apps/led.png; \
	done
	-update-desktop-database $(PREFIX)/share/applications 2>/dev/null || true
	-gtk-update-icon-cache -f -t $(PREFIX)/share/icons/hicolor 2>/dev/null || true
	@echo
	@echo "installed: $(PREFIX)/bin/led"
	@echo "data:      $(PREFIX)/share/led"
	@echo "(ensure $(PREFIX)/bin is on PATH; set LED_DATA_DIR only if you moved the data)"

uninstall:
	rm -f $(PREFIX)/bin/led
	rm -rf $(PREFIX)/share/led
	rm -f $(PREFIX)/share/applications/led.desktop
	rm -f $(PREFIX)/share/icons/hicolor/scalable/apps/led.svg
	@for s in $(ICONSIZES); do \
	  rm -f $(PREFIX)/share/icons/hicolor/$${s}x$${s}/apps/led.png; \
	done
	-update-desktop-database $(PREFIX)/share/applications 2>/dev/null || true
	@echo "uninstalled from $(PREFIX)"

clean:
	rm -rf lib
	find . -name '*.o' -o -name '*.ppu' -o -name '*.or' | xargs -r rm -f

distclean: clean
	rm -f bin/led bin/led.exe bin/ledcoretest bin/ledcoretest.exe \
	      bin/langcheck bin/langcheck.exe
	rm -rf dist

help:
	@sed -n '1,27p' Makefile
