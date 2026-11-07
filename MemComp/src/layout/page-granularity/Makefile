COMP_SOURCE=lz4_huffman lz4

COMPDIR=

IFLAGS=
TARGET=
INCLUDE=
DFLAGS=

LDLIBS=-pthread -ldl
CFLAGS=-ggdb3 -O2
SFLAGS=-shared -fPIC
IFLAGS2=$(IFLAGS) -include ./page-granularity.h
DFLAGS2=$(DFLAGS) -DSLICE=2

COMPRESSIONTARGET=$(TARGET)/page-granularity
COMPRESSION_C=$(patsubst %,$(COMPDIR)/%.c,$(COMP_SOURCE))
COMPRESSION_SO=$(patsubst %,$(COMPRESSIONTARGET)/%.so,$(COMP_SOURCE))
COMPRESSION_SDIR=$(patsubst %,$(COMPDIR)/%/Makefile,$(COMP_SOURCE))

default: this $(COMPRESSION_SO) $(COMPRESSION_SDIR_SO)

$(COMPRESSION_SO): $(COMPRESSIONTARGET)/%.so : $(COMPDIR)/%.c
	$(CC) $(DFLAGS2) $(CFLAGS) $(SFLAGS) $(IFLAGS2) -o $@ $< -lrt -lm

$(COMPRESSION_SDIR_SO): $(COMPRESSIONTARGET)/%.so: $(COMPRESSIONDIR)/%/
	$(MAKE) -C $< DFLAGS="$(DFLAGS2)" IFLAGS=$(IFLAGS2) TARGET=$(COMPRESSIONTARGET) INCLUDE=$(INCLUDE)

this:
	mkdir $(TARGET)/page-granularity
	$(CC) $(DFLAGS2) $(CFLAGS) $(SFLAGS) $(IFLAGS) -o $(TARGET)/page-granularity.so ./page-granularity.c
