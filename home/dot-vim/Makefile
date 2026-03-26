SHELL := /usr/bin/env bash

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPT := $(ROOT_DIR)/scripts/install_mozuku.sh
STAMP_DIR := $(HOME)/.cache/mozuku-install/stamps
KAKEHASHI_STAMP_DIR := $(HOME)/.cache/kakehashi-install/stamps
KAKEHASHI_INSTALL_ROOT ?= $(HOME)/.local
KAKEHASHI_INSTALL_CMD := cargo install --git https://github.com/atusy/kakehashi --root "$(KAKEHASHI_INSTALL_ROOT)" kakehashi
PATCH_FILES := $(sort $(wildcard $(ROOT_DIR)/patch/*.patch))

.PHONY: all install reinstall verify clean
.PHONY: kakehashi-install kakehashi-reinstall kakehashi-verify kakehashi-clean

all: install

install: $(STAMP_DIR)/mozuku-installed

reinstall:
	rm -f \
		"$(STAMP_DIR)/mozuku-patches-applied" \
		"$(STAMP_DIR)/mozuku-installed" \
		"$(STAMP_DIR)/verified"
	$(MAKE) install

verify: $(STAMP_DIR)/verified

clean:
	rm -rf $(STAMP_DIR)

kakehashi-install: $(KAKEHASHI_STAMP_DIR)/installed

kakehashi-reinstall:
	rm -f \
		"$(KAKEHASHI_STAMP_DIR)/installed" \
		"$(KAKEHASHI_STAMP_DIR)/verified"
	$(MAKE) kakehashi-install

kakehashi-verify: $(KAKEHASHI_STAMP_DIR)/verified

kakehashi-clean:
	rm -rf $(KAKEHASHI_STAMP_DIR)

$(STAMP_DIR):
	mkdir -p "$@"

$(KAKEHASHI_STAMP_DIR):
	mkdir -p "$@"

$(STAMP_DIR)/system-packages: $(SCRIPT) | $(STAMP_DIR)
	"$(SCRIPT)" system-packages
	touch "$@"

$(STAMP_DIR)/sources: $(SCRIPT) $(STAMP_DIR)/system-packages | $(STAMP_DIR)
	"$(SCRIPT)" fetch-sources
	touch "$@"

$(STAMP_DIR)/mecab-installed: $(SCRIPT) $(STAMP_DIR)/sources | $(STAMP_DIR)
	"$(SCRIPT)" install-mecab
	touch "$@"

$(STAMP_DIR)/mecab-ipadic-installed: $(SCRIPT) $(STAMP_DIR)/mecab-installed | $(STAMP_DIR)
	"$(SCRIPT)" install-mecab-ipadic
	touch "$@"

$(STAMP_DIR)/crfpp-installed: $(SCRIPT) $(STAMP_DIR)/sources | $(STAMP_DIR)
	"$(SCRIPT)" install-crfpp
	touch "$@"

$(STAMP_DIR)/cabocha-installed: $(SCRIPT) $(STAMP_DIR)/mecab-ipadic-installed $(STAMP_DIR)/crfpp-installed | $(STAMP_DIR)
	"$(SCRIPT)" install-cabocha
	touch "$@"

$(STAMP_DIR)/tree-sitter-prepared: $(SCRIPT) $(STAMP_DIR)/sources $(STAMP_DIR)/system-packages | $(STAMP_DIR)
	"$(SCRIPT)" prepare-tree-sitter
	touch "$@"

$(STAMP_DIR)/mozuku-patches-applied: $(SCRIPT) $(STAMP_DIR)/sources $(PATCH_FILES) | $(STAMP_DIR)
	"$(SCRIPT)" apply-mozuku-patches
	touch "$@"

$(STAMP_DIR)/mozuku-installed: $(SCRIPT) $(STAMP_DIR)/cabocha-installed $(STAMP_DIR)/tree-sitter-prepared $(STAMP_DIR)/mozuku-patches-applied | $(STAMP_DIR)
	"$(SCRIPT)" install-mozuku
	touch "$@"

$(STAMP_DIR)/verified: $(SCRIPT) $(STAMP_DIR)/mozuku-installed | $(STAMP_DIR)
	"$(SCRIPT)" verify
	touch "$@"

$(KAKEHASHI_STAMP_DIR)/installed: | $(KAKEHASHI_STAMP_DIR)
	$(KAKEHASHI_INSTALL_CMD)
	touch "$@"

$(KAKEHASHI_STAMP_DIR)/verified: $(KAKEHASHI_STAMP_DIR)/installed | $(KAKEHASHI_STAMP_DIR)
	"$(KAKEHASHI_INSTALL_ROOT)/bin/kakehashi" --version
	touch "$@"
