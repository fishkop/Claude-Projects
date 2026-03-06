# Makefile – conn_storm
#
# Requires: libpq-dev (PostgreSQL client library) and pg_config in PATH
#
#   macOS (Homebrew):  brew install libpq
#                      export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
#
#   Debian/Ubuntu:     apt install libpq-dev
#
#   RHEL/Fedora:       dnf install libpq-devel

CC      = gcc
CFLAGS  = -Wall -Wextra -O2 -g -I$(shell pg_config --includedir) $(shell pg_config --cflags)
LDFLAGS = -L$(shell pg_config --libdir) $(shell pg_config --libs) -lpq -lpthread
TARGET  = conn_storm
SRC     = conn_storm.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

clean:
	rm -f $(TARGET)
