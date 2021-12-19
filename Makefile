PROGRAMS=uvctl
OBJS=main.o parse.o msr.o util.o power.o voltage.o tjunction.o \
compat/reallocarray.o compat/strtonum.o compat/explicit_bzero.o
CFLAGS=-Wall -march=native -O2 -I. -DYYSTYPE_IS_DECLARED
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
