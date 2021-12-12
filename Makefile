PROGRAMS=uvctl
OBJS=main.o parse.o msr.o util.o power.o voltage.o tjunction.o \
compat/recallocarray.o compat/strtonum.o
CC=cc
CFLAGS=-Wall -march=native -O2 -I.
LDFLAGS= -lm
LEX     = flex
YACC    = bison -y
YFLAGS  = -d


all: uvctl

$(PROGRAMS): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

.c.o :
	$(CC) -c $(CFLAGS) -o $@ $<

clean:
	rm -f uvctl *.o compat/*.o parse.tab.c parse.yy.c parse.tab.h y.tab.h
