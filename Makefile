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

secret-env:
	@if [[ -z "$(strip $(SECRET_ENV_KEYS))" ]]; then \
		echo "SECRET_ENV_KEYS is empty. Example: make secret-env SECRET_ENV_KEYS='CONTEXT7_API_KEY GH_TOKEN'"; \
		exit 1; \
	fi
	@command -v pass >/dev/null 2>&1 || { echo "pass command not found"; exit 1; }
	@install -d -m 700 "$(ENV_SNIPPET_DIR)"
	@for key in $(SECRET_ENV_KEYS); do \
		pass_path="$(PASS_ENV_PREFIX)/$$key"; \
		value="$$(pass show "$$pass_path" 2>/dev/null | sed -n '1p')"; \
		if [[ -z "$$value" ]]; then \
			echo "missing pass entry: $$pass_path"; \
			exit 1; \
		fi; \
		printf 'export %s=%q\n' "$$key" "$$value" > "$(ENV_SNIPPET_DIR)/$$key"; \
		chmod 600 "$(ENV_SNIPPET_DIR)/$$key"; \
		echo "wrote $(ENV_SNIPPET_DIR)/$$key"; \
	done

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
