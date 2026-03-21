SHELL := /bin/bash

STOW ?= stow
TARGET ?= $(HOME)

STOWFLAGS ?= --dotfiles
ENVFILE_DIR ?= ../envfile
ENV_SNIPPET_DIR ?= $(ENVFILE_DIR)/env
SECRET_FILE_DIR ?= $(ENVFILE_DIR)/files

bootstrap:
	@install -d -m 700 $(TARGET)/.ssh
	@install -d -m 700 $(TARGET)/.gnupg

stow-arch:
	$(STOW) $(STOWFLAGS) -vt $(TARGET) arch home
	$(MAKE) -C $(HOME)/.config/lf
	$(MAKE) -C $(HOME)/.local/src/river-inputctl

stow-gentoo:
	$(STOW) $(STOWFLAGS) -vt $(TARGET) gentoo home
	$(MAKE) -C $(HOME)/.config/lf
	$(MAKE) -C $(HOME)/.local/src/river-inputctl
	
restow-arch:
	$(STOW) $(STOWFLAGS) -Rvt $(TARGET) arch home
	$(MAKE) -C $(HOME)/.config/lf clean
	$(MAKE) -C $(HOME)/.config/lf
	$(MAKE) -C $(HOME)/.local/src/river-inputctl clean
	$(MAKE) -C $(HOME)/.local/src/river-inputctl

restow-gentoo:
	$(STOW) $(STOWFLAGS) -Rvt $(TARGET) gentoo home
	$(MAKE) -C $(HOME)/.config/lf clean
	$(MAKE) -C $(HOME)/.config/lf
	$(MAKE) -C $(HOME)/.local/src/river-inputctl clean
	$(MAKE) -C $(HOME)/.local/src/river-inputctl

secret-files:
	@command -v pass >/dev/null 2>&1 || { echo "pass command not found"; exit 1; }
	@if [[ ! -d "$(SECRET_FILE_DIR)" ]]; then \
		echo "missing directory: $(SECRET_FILE_DIR)"; \
		exit 1; \
	fi
	@find "$(SECRET_FILE_DIR)" -mindepth 1 -type f -name '*.gpg' | sort | while read -r src; do \
		rel_path="$${src#$(SECRET_FILE_DIR)/}"; \
		pass_path="files/$${rel_path%.gpg}"; \
		dest="$(TARGET)/$${rel_path%.gpg}"; \
		mode="$$(stat -c '%a' "$$src")"; \
		install -d -m 700 "$$(dirname "$$dest")"; \
		pass show "$$pass_path" > "$$dest"; \
		chmod "$$mode" "$$dest"; \
		echo "decrypted $$pass_path -> $$dest"; \
	done
	@if [[ -d "$(ENV_SNIPPET_DIR)" ]]; then \
		dest="$(TARGET)/.config/secrets/env"; \
		install -d -m 700 "$$(dirname "$$dest")"; \
		: > "$$dest"; \
		chmod 600 "$$dest"; \
		find "$(ENV_SNIPPET_DIR)" -mindepth 1 -type f -name '*.gpg' | sort | while read -r src; do \
			pass_path="env/$${src#$(ENV_SNIPPET_DIR)/}"; \
			pass_path="$${pass_path%.gpg}"; \
			pass show "$$pass_path" >> "$$dest"; \
			printf '\n' >> "$$dest"; \
			echo "merged $$pass_path -> $$dest"; \
		done; \
	fi
