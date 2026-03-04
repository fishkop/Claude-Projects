# Makefile - Belegerfassungsprogramm
#
# Voraussetzungen: postgresql-devel (Linux) oder postgresql (macOS via brew)
# Installieren (Debian/Ubuntu): sudo apt install libpq-dev
# Installieren (macOS):         brew install libpq

TARGET  = belegerfassung
SRC     = belegerfassung.c

CC      = gcc
CFLAGS  = -Wall -Wextra -O2 $(shell pg_config --cflags)
INCDIR  = $(shell pg_config --includedir)
LIBDIR  = $(shell pg_config --libdir)
LDFLAGS = -L$(LIBDIR) -lpq

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -I$(INCDIR) -o $@ $< $(LDFLAGS)

install: $(TARGET)
	install -m 0755 $(TARGET) /usr/local/bin/$(TARGET)

clean:
	rm -f $(TARGET)

.PHONY: install clean
