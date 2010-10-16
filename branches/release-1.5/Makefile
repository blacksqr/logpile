PREFIX=/usr

BINPREFIX=""
BINS=index search email_alert index-compact
LIBS=lib/logpile.tcl lib/filetraverse_filters.tcl lib/timezoneutils.tcl lib/userFuncs.tcl
CONFS=etc/logpile.conf etc/templates/users.report etc/templates/graph.report
MANFILES=man/man1/search.1 man/man1/index.1
FILES=$(CONFS) $(MANFILES)
DIRS=etc bin etc/templates man/man1
TCLSH=tclsh8.5

all: _a $(LIBS) 
	@echo "To install use install"

install: _a install_start $(LIBS) install_libs $(DIRS) $(FILES) $(BINS)
	@echo "done."

$(DIRS): _a
	@-mkdir -p $(PREFIX)/$@

$(FILES): _a
	@-cp $@ $(PREFIX)/$@

$(BINS): _a
	@-cp bin/$@ $(PREFIX)/bin/$(BINPREFIX)$@
	@-chmod +x $(PREFIX)/bin/$(BINPREFIX)$@

install_libs:  _a
	./support/install.tcl $(LIBS) logpile

install_start: _a
	@echo "Installing logpile"

test: _a $(LIBS)
	@(echo package require tcltest ; echo ::tcltest::runAllTests ) | ( cd tests ; $(TCLSH) )

doc: _a
	@echo "Generating documentation"
	@(cd support ; $(TCLSH) ./tcldoc.tcl ../doc ../lib )
	@echo "done"

clean: _a
	@echo "Cleaning"
	@-rm -rf doc 
	@echo "done"

_a:
