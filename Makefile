STOW ?= stow
TARGET ?= ~

STOWFLAGS ?= --no-folding

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


