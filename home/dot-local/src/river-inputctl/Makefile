CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -pedantic -std=c11
LDFLAGS ?=
LDLIBS ?=

SRC_DIR := $(CURDIR)
PROTO_DIR := $(SRC_DIR)/protocol
GEN_DIR := $(SRC_DIR)/gen
BINARY := $(SRC_DIR)/river-inputctl.bin

WAYLAND_CFLAGS := $(shell pkg-config --cflags wayland-client)
WAYLAND_LIBS := $(shell pkg-config --libs wayland-client)

.PHONY: all clean

all: $(BINARY)

$(GEN_DIR):
	mkdir -p $@

$(GEN_DIR)/river-input-management-v1-client-protocol.h $(GEN_DIR)/river-input-management-v1-protocol.c &: $(PROTO_DIR)/river-input-management-v1.xml | $(GEN_DIR)
	wayland-scanner client-header $< $(GEN_DIR)/river-input-management-v1-client-protocol.h
	wayland-scanner private-code $< $(GEN_DIR)/river-input-management-v1-protocol.c

$(GEN_DIR)/river-libinput-config-v1-client-protocol.h $(GEN_DIR)/river-libinput-config-v1-protocol.c &: $(PROTO_DIR)/river-libinput-config-v1.xml | $(GEN_DIR)
	wayland-scanner client-header $< $(GEN_DIR)/river-libinput-config-v1-client-protocol.h
	wayland-scanner private-code $< $(GEN_DIR)/river-libinput-config-v1-protocol.c

$(BINARY): \
	$(SRC_DIR)/main.c \
	$(GEN_DIR)/river-input-management-v1-client-protocol.h \
	$(GEN_DIR)/river-input-management-v1-protocol.c \
	$(GEN_DIR)/river-libinput-config-v1-client-protocol.h \
	$(GEN_DIR)/river-libinput-config-v1-protocol.c
	$(CC) $(CFLAGS) $(LDFLAGS) \
		-I$(GEN_DIR) \
		$(SRC_DIR)/main.c \
		$(GEN_DIR)/river-input-management-v1-protocol.c \
		$(GEN_DIR)/river-libinput-config-v1-protocol.c \
		$(WAYLAND_CFLAGS) $(WAYLAND_LIBS) $(LDLIBS) \
		-o $@

clean:
	rm -rf $(GEN_DIR) $(BINARY)
