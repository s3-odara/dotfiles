CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c11
LDFLAGS ?=
LDLIBS ?= -lseccomp

PREFIX := $(HOME)/.config/lf
TARGET := $(PREFIX)/preview-guard
SOURCE := $(PREFIX)/preview-guard.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SOURCE)
	$(CC) $(CFLAGS) $(LDFLAGS) $(SOURCE) $(LDLIBS) -o $(TARGET)

clean:
	rm -f $(TARGET)
