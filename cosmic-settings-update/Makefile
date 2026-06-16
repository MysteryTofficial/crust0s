# Crust OS — COSMIC Settings update panel build
#
TARGET   := /usr/bin/cosmic-settings-update
CARGO   ?= cargo
PROFILE  := release

all: build

build:
	$(CARGO) build --$(PROFILE)

install: build
	install -Dm755 target/$(PROFILE)/cosmic-settings-update $(DESTDIR)$(TARGET)

clean:
	$(CARGO) clean

.PHONY: all build install clean
