SHELL := /bin/bash

STOW ?= stow
TARGET ?= $(HOME)

STOWFLAGS ?= --no-folding --dotfiles
ENVFILE_DIR ?= ../envfile
ENV_SNIPPET_DIR ?= $(ENVFILE_DIR)/env
SECRET_FILE_DIR ?= $(ENVFILE_DIR)/files
PASS_ENV_PREFIX ?= env
SECRET_ENV_KEYS ?=

bootstrap:
	@install -d -m 700 $(TARGET)/.ssh
	@install -d -m 700 $(TARGET)/.gnupg

stow-arch:
	$(STOW) $(STOWFLAGS) -vt $(TARGET) arch home

stow-gentoo:
	$(STOW) $(STOWFLAGS) -vt $(TARGET) gentoo home

	
restow-arch:
	$(STOW) $(STOWFLAGS) -Rvt $(TARGET) arch home

restow-gentoo:
	$(STOW) $(STOWFLAGS) -Rvt $(TARGET) gentoo home

secret-files:
	@if [[ ! -d "$(SECRET_FILE_DIR)" ]]; then \
		echo "missing directory: $(SECRET_FILE_DIR)"; \
		exit 1; \
	fi
	@find "$(SECRET_FILE_DIR)" -mindepth 1 -type f ! -name '.gitkeep' | sort | while read -r src; do \
		rel_path="$${src#$(SECRET_FILE_DIR)/}"; \
		dest="$(TARGET)/$$rel_path"; \
		mode="$$(stat -c '%a' "$$src")"; \
		install -d -m 700 "$$(dirname "$$dest")"; \
		install -m "$$mode" "$$src" "$$dest"; \
		echo "installed $$dest"; \
	done
	@if [[ -d "$(ENV_SNIPPET_DIR)" ]]; then \
		dest="$(TARGET)/.config/secrets/env"; \
		install -d -m 700 "$$(dirname "$$dest")"; \
		: > "$$dest"; \
		chmod 600 "$$dest"; \
		find "$(ENV_SNIPPET_DIR)" -mindepth 1 -type f ! -name '.gitkeep' | sort | while read -r src; do \
			[ -s "$$src" ] || continue; \
			cat "$$src" >> "$$dest"; \
			printf '\n' >> "$$dest"; \
			echo "merged $$src -> $$dest"; \
		done; \
	fi
