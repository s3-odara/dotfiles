STOW ?= stow
TARGET ?= ~

STOWFLAGS ?= --no-folding

bootstrap:
	@install -d -m 700 $(TARGET)/.ssh
	@install -d -m 700 $(TARGET)/.gnupg

stow-arch:
	$(STOW) $(STOWFLAGS) -vt $(TARGET) arch common

stow-gentoo:
	$(STOW) $(STOWFLAGS) -vt $(TARGET) gentoo common

	
stow-arch:
	$(STOW) $(STOWFLAGS) -Rvt $(TARGET) arch common

stow-gentoo:
	$(STOW) $(STOWFLAGS) -Rvt $(TARGET) gentoo common


