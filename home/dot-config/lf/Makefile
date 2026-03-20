CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c11
LDFLAGS ?=
LDLIBS ?= -lseccomp

PREFIX := $(HOME)/.config/lf
TARGETS := $(PREFIX)/preview-guard $(PREFIX)/player-guard

.PHONY: all clean

all: $(TARGETS)

$(PREFIX)/preview-guard: $(PREFIX)/preview-guard.c
	$(CC) $(CFLAGS) $(LDFLAGS) $< $(LDLIBS) -o $@

$(PREFIX)/player-guard: $(PREFIX)/player-guard.c
	$(CC) $(CFLAGS) $(LDFLAGS) $< $(LDLIBS) -o $@

clean:
	rm -f $(TARGETS)
