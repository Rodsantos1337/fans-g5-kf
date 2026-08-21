CC ?= gcc
CFLAGS ?= -O2 -Wall
PREFIX ?= /usr/local
SYSTEMDUNITDIR ?= /etc/systemd/system

all: g5fan

g5fan: g5fan.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f g5fan

install: g5fan
	install -Dm755 g5fan $(DESTDIR)$(PREFIX)/bin/g5fan
	install -Dm755 fans $(DESTDIR)$(PREFIX)/bin/fans
	install -Dm755 fans-guard $(DESTDIR)$(PREFIX)/bin/fans-guard
	install -Dm644 fans-guard.service $(DESTDIR)$(SYSTEMDUNITDIR)/fans-guard.service

.PHONY: all clean install
