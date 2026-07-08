CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c11
LDFLAGS ?=
LDLIBS ?= -lseccomp

SRC_DIR := $(CURDIR)
COMMON_SRC := $(SRC_DIR)/sandbox-guard-common.c
COMMON_HDR := $(SRC_DIR)/sandbox-guard-common.h
TARGETS := $(SRC_DIR)/preview-guard $(SRC_DIR)/player-guard

.PHONY: all clean

all: $(TARGETS)

$(SRC_DIR)/preview-guard: $(SRC_DIR)/preview-guard.c $(COMMON_SRC) $(COMMON_HDR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRC_DIR)/preview-guard.c $(COMMON_SRC) $(LDLIBS) -o $@

$(SRC_DIR)/player-guard: $(SRC_DIR)/player-guard.c $(COMMON_SRC) $(COMMON_HDR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRC_DIR)/player-guard.c $(COMMON_SRC) $(LDLIBS) -o $@

clean:
	rm -f $(TARGETS)
