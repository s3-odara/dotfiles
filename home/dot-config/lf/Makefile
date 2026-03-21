CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c11
LDFLAGS ?=
LDLIBS ?= -lseccomp

SRC_DIR := $(CURDIR)
TARGETS := $(SRC_DIR)/preview-guard $(SRC_DIR)/player-guard

.PHONY: all clean

all: $(TARGETS)

$(SRC_DIR)/preview-guard: $(SRC_DIR)/preview-guard.c
	$(CC) $(CFLAGS) $(LDFLAGS) $< $(LDLIBS) -o $@

$(SRC_DIR)/player-guard: $(SRC_DIR)/player-guard.c
	$(CC) $(CFLAGS) $(LDFLAGS) $< $(LDLIBS) -o $@

clean:
	rm -f $(TARGETS)
