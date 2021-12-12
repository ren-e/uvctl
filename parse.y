/*
 * Copyright (c) 2016 Kristaps Dzonsons <kristaps@bsd.lv>
 * Copyright (c) 2016 Sebastian Benoit <benno@openbsd.org>
 * Copyright (c) 2004, 2005 Esben Norby <norby@openbsd.org>
 * Copyright (c) 2004 Ryan McBride <mcbride@openbsd.org>
 * Copyright (c) 2002, 2003, 2004 Henning Brauer <henning@openbsd.org>
 * Copyright (c) 2001 Markus Friedl.  All rights reserved.
 * Copyright (c) 2001 Daniel Hartmeier.  All rights reserved.
 * Copyright (c) 2001 Theo de Raadt.  All rights reserved.
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

%{
#include <sys/types.h>
#include <sys/stat.h>
#include <ctype.h>
#include <err.h>
#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "uvctl.h"

TAILQ_HEAD(files, file)		 files = TAILQ_HEAD_INITIALIZER(files);
static struct file {
	TAILQ_ENTRY(file)	 entry;
	FILE			*stream;
	char			*name;
	size_t			 ungetpos;
	size_t			 ungetsize;
	u_char			*ungetbuf;
	int			 eof_reached;
	int			 lineno;
	int			 errors;
} *file, *topfile;
struct file	*pushfile(const char *);
int		 popfile(void);
int		 yyparse(void);
int		 yylex(void);
int		 yyerror(const char *, ...)
    __attribute__((__format__ (printf, 1, 2)))
    __attribute__((__nonnull__ (1)));
int		 kw_cmp(const void *, const void *);
int		 lookup(char *);
int		 igetc(void);
int		 lgetc(int);
void		 lungetc(int);
int		 findeol(void);

struct processor_c	*conf_new_processor(struct undervolt_conf *, int );
void			 clear_config(struct undervolt_conf *);
void			 print_config(struct undervolt_conf *);
int			 conf_check_file(char *);

TAILQ_HEAD(symhead, sym)	 symhead = TAILQ_HEAD_INITIALIZER(symhead);
struct sym {
	TAILQ_ENTRY(sym)	 entry;
	int			 used;
	int			 persist;
	char			*nam;
	char			*val;
};
int		 symset(const char *, const char *, int);
char		*symget(const char *);

static struct undervolt_conf	*conf;
static struct processor_c	*proc;

static int			 errors = 0;

typedef struct {
	union {
		int64_t		 number;
		char		*string;
	} v;
	int lineno;
} YYSTYPE;

%}

%token	PROCESSOR URL API ACCOUNT TJUNCTION VOLTAGE
%token	YES NO
%token	INCLUDE
%token	ERROR
%token	<v.string>	STRING
%token	<v.number>	NUMBER
%type	<v.string>	string
%type	<v.number>		voltagegroup

%%

grammar		: /* empty */
		| grammar include '\n'
		| grammar varset '\n'
		| grammar '\n'
		| grammar processor '\n'
		| grammar error '\n'		{ file->errors++; }
		;

include		: INCLUDE STRING		{
			struct file	*nfile;

			if ((nfile = pushfile($2)) == NULL) {
				yyerror("failed to include file %s", $2);
				free($2);
				YYERROR;
			}
			free($2);

			file = nfile;
			lungetc('\n');
		}
		;

string		: string STRING	{
			if (asprintf(&$$, "%s %s", $1, $2) == -1) {
				free($1);
				free($2);
				yyerror("string: asprintf");
				YYERROR;
			}
			free($1);
			free($2);
		}
		| STRING
		;

varset		: STRING '=' string		{
			char *s = $1;
			if (conf->opts & UVCTL_OPT_VERBOSE)
				printf("%s = \"%s\"\n", $1, $3);
			while (*s++) {
				if (isspace((unsigned char)*s)) {
					yyerror("macro name cannot contain "
					    "whitespace");
					free($1);
					free($3);
					YYERROR;
				}
			}
			if (symset($1, $3, 0) == -1)
				errx(EXIT_FAILURE, "cannot store variable");
			free($1);
			free($3);
		}
		;

optnl		: '\n' optnl
		|
		;

nl		: '\n' optnl		/* one newline or more */
		;

processor	: PROCESSOR NUMBER {
			if ((proc = conf_new_processor(conf, $2)) == NULL) {
				yyerror("processor already defined");
				YYERROR;
			}
		} '{' optnl processoropts_l '}' {
			proc = NULL;
		}
		;

processoropts_l	: processoropts_l processoroptsl nl
		| processoroptsl optnl
		;

processoroptsl	: VOLTAGE voltagegroup NUMBER {
			if (proc->voltage[$2].write) {
				yyerror("voltage %s already specified",
				    vg2txt($2));
				YYERROR;
			}
			if ($3 < VOLTAGE_OFFSET_MIN ||
			    $3 > VOLTAGE_OFFSET_MAX) {
				yyerror("voltage out of range");
				YYERROR;
			}
			proc->voltage[$2].offset = $3;
			proc->voltage[$2].write = 1;
		}
		| TJUNCTION NUMBER {
			if (proc->tjunction.write) {
				yyerror("tjunction offset already specified");
				YYERROR;
			}
			if ($2 < TJUNCTION_OFFSET_MIN ||
			     $2 > TJUNCTION_OFFSET_MAX) {
				yyerror("tjunction offset out of range");
				YYERROR;
			}
			proc->tjunction.offset = $2;
			proc->tjunction.write = 1;
		}
		;

voltagegroup	: STRING        {
                        if (!strcmp($1, "cpu"))
                                $$ = VOLTAGE_CPU;
                        else if (!strcmp($1, "gpu"))
                                $$ = VOLTAGE_GPU;
                        else if (!strcmp($1, "cache"))
                                $$ = VOLTAGE_CACHE;
                        else if (!strcmp($1, "sys"))
                                $$ = VOLTAGE_SYS;
                        else if (!strcmp($1, "io"))
                                $$ = VOLTAGE_IO;
                        else {
                                yyerror("illegal voltage `%s` specified", $1);
                                YYERROR;
                        }
                }
                ;

%%

struct keywords {
	const char	*k_name;
	int		 k_val;
};

int
yyerror(const char *fmt, ...)
{
	va_list		 ap;
	char		*msg;

	file->errors++;
	va_start(ap, fmt);
	if (vasprintf(&msg, fmt, ap) == -1)
		err(EXIT_FAILURE, "yyerror vasprintf");
	va_end(ap);
	fprintf(stderr, "%s:%d: %s\n", file->name, yylval.lineno, msg);
	free(msg);
	return (0);
}

int
kw_cmp(const void *k, const void *e)
{
	return strcmp(k, ((const struct keywords *)e)->k_name);
}

int
lookup(char *s)
{
	/* this has to be sorted always */
	static const struct keywords keywords[] = {
		{"include",		INCLUDE},
		{"processor",		PROCESSOR},
		{"tjunction",		TJUNCTION},
		{"voltage",		VOLTAGE},
	};
	const struct keywords	*p;

	p = bsearch(s, keywords, sizeof(keywords)/sizeof(keywords[0]),
	    sizeof(keywords[0]), kw_cmp);

	if (p != NULL)
		return p->k_val;
	else
		return STRING;
}

#define	START_EXPAND	1
#define	DONE_EXPAND	2

static int	expanding;

int
igetc(void)
{
	int	c;

	while (1) {
		if (file->ungetpos > 0)
			c = file->ungetbuf[--file->ungetpos];
		else
			c = getc(file->stream);

		if (c == START_EXPAND)
			expanding = 1;
		else if (c == DONE_EXPAND)
			expanding = 0;
		else
			break;
	}
	return c;
}

int
lgetc(int quotec)
{
	int		c, next;

	if (quotec) {
		if ((c = igetc()) == EOF) {
			yyerror("reached end of file while parsing "
			    "quoted string");
			if (file == topfile || popfile() == EOF)
				return (EOF);
			return quotec;
		}
		return c;
	}

	while ((c = igetc()) == '\\') {
		next = igetc();
		if (next != '\n') {
			c = next;
			break;
		}
		yylval.lineno = file->lineno;
		file->lineno++;
	}

	if (c == EOF) {
		/*
		 * Fake EOL when hit EOF for the first time. This gets line
		 * count right if last line in included file is syntactically
		 * invalid and has no newline.
		 */
		if (file->eof_reached == 0) {
			file->eof_reached = 1;
			return '\n';
		}
		while (c == EOF) {
			if (file == topfile || popfile() == EOF)
				return (EOF);
			c = igetc();
		}
	}
	return c;
}

void
lungetc(int c)
{
	if (c == EOF)
		return;

	if (file->ungetpos >= file->ungetsize) {
		void *p = reallocarray(file->ungetbuf, file->ungetsize, 2);
		if (p == NULL)
			err(1, "%s", __func__);
		file->ungetbuf = p;
		file->ungetsize *= 2;
	}
	file->ungetbuf[file->ungetpos++] = c;
}

int
findeol(void)
{
	int	c;

	/* skip to either EOF or the first real EOL */
	while (1) {
		c = lgetc(0);
		if (c == '\n') {
			file->lineno++;
			break;
		}
		if (c == EOF)
			break;
	}
	return ERROR;
}

int
yylex(void)
{
	u_char	 buf[8096];
	u_char	*p, *val;
	int	 quotec, next, c;
	int	 token;

top:
	p = buf;
	while ((c = lgetc(0)) == ' ' || c == '\t')
		; /* nothing */

	yylval.lineno = file->lineno;
	if (c == '#')
		while ((c = lgetc(0)) != '\n' && c != EOF)
			; /* nothing */
	if (c == '$' && !expanding) {
		while (1) {
			if ((c = lgetc(0)) == EOF)
				return 0;

			if (p + 1 >= buf + sizeof(buf) - 1) {
				yyerror("string too long");
				return findeol();
			}
			if (isalnum(c) || c == '_') {
				*p++ = c;
				continue;
			}
			*p = '\0';
			lungetc(c);
			break;
		}
		val = (u_char *)symget((char *)buf);
		if (val == NULL) {
			yyerror("macro '%s' not defined", buf);
			return findeol();
		}
		p = val + strlen((char *)val) - 1;
		lungetc(DONE_EXPAND);
		while (p >= val) {
			lungetc(*p);
			p--;
		}
		lungetc(START_EXPAND);
		goto top;
	}

	switch (c) {
	case '\'':
	case '"':
		quotec = c;
		while (1) {
			if ((c = lgetc(quotec)) == EOF)
				return 0;
			if (c == '\n') {
				file->lineno++;
				continue;
			} else if (c == '\\') {
				if ((next = lgetc(quotec)) == EOF)
					return 0;
				if (next == quotec || next == ' ' ||
				    next == '\t')
					c = next;
				else if (next == '\n') {
					file->lineno++;
					continue;
				} else
					lungetc(next);
			} else if (c == quotec) {
				*p = '\0';
				break;
			} else if (c == '\0') {
				yyerror("syntax error");
				return findeol();
			}
			if (p + 1 >= buf + sizeof(buf) - 1) {
				yyerror("string too long");
				return findeol();
			}
			*p++ = c;
		}
		yylval.v.string = strdup((char *)buf);
		if (yylval.v.string == NULL)
			err(EXIT_FAILURE, "%s", __func__);
		return STRING;
	}

#define allowed_to_end_number(x) \
	(isspace(x) || x == ')' || x ==',' || x == '/' || x == '}' || x == '=')

	if (c == '-' || isdigit(c)) {
		do {
			*p++ = c;
			if ((size_t)(p-buf) >= sizeof(buf)) {
				yyerror("string too long");
				return findeol();
			}
		} while ((c = lgetc(0)) != EOF && (isdigit(c)));
		lungetc(c);
		if (p == buf + 1 && buf[0] == '-')
			goto nodigits;
		if (c == EOF || allowed_to_end_number(c)) {
			const char *errstr = NULL;

			*p = '\0';
			yylval.v.number = strtonum((char *)buf, LLONG_MIN,
			    LLONG_MAX, &errstr);
			if (errstr != NULL) {
				yyerror("\"%s\" invalid number: %s",
				    buf, errstr);
				return (findeol());
			}
			return NUMBER;
		} else {
nodigits:
			while (p > buf + 1)
				lungetc(*--p);
			c = *--p;
			if (c == '-')
				return c;
		}
	}

#define allowed_in_string(x) \
	(isalnum(x) || (ispunct(x) && x != '(' && x != ')' && \
	x != '{' && x != '}' && \
	x != '!' && x != '=' && x != '#' && \
	x != ','))

	if (isalnum(c) || c == ':' || c == '_') {
		do {
			*p++ = c;
			if ((size_t)(p-buf) >= sizeof(buf)) {
				yyerror("string too long");
				return (findeol());
			}
		} while ((c = lgetc(0)) != EOF && (allowed_in_string(c)));
		lungetc(c);
		*p = '\0';
		if ((token = lookup((char *)buf)) == STRING) {
			if ((yylval.v.string = strdup((char *)buf)) == NULL)
				err(EXIT_FAILURE, "%s", __func__);
		}
		return token;
	}
	if (c == '\n') {
		yylval.lineno = file->lineno;
		file->lineno++;
	}
	if (c == EOF)
		return 0;
	return c;
}

struct file *
pushfile(const char *name)
{
	struct file	*nfile;

	if ((nfile = calloc(1, sizeof(struct file))) == NULL) {
		warn("%s", __func__);
		return NULL;
	}
	if ((nfile->name = strdup(name)) == NULL) {
		warn("%s", __func__);
		free(nfile);
		return NULL;
	}
	if ((nfile->stream = fopen(nfile->name, "r")) == NULL) {
		warn("%s: %s", __func__, nfile->name);
		free(nfile->name);
		free(nfile);
		return NULL;
	}
	nfile->lineno = TAILQ_EMPTY(&files) ? 1 : 0;
	nfile->ungetsize = 16;
	nfile->ungetbuf = malloc(nfile->ungetsize);
	if (nfile->ungetbuf == NULL) {
		warn("%s", __func__);
		fclose(nfile->stream);
		free(nfile->name);
		free(nfile);
		return NULL;
	}
	TAILQ_INSERT_TAIL(&files, nfile, entry);
	return nfile;
}

int
popfile(void)
{
	struct file	*prev;

	if ((prev = TAILQ_PREV(file, files, entry)) != NULL)
		prev->errors += file->errors;

	TAILQ_REMOVE(&files, file, entry);
	fclose(file->stream);
	free(file->name);
	free(file->ungetbuf);
	free(file);
	file = prev;
	return (file ? 0 : EOF);
}

struct undervolt_conf *
parse_config(const char *filename, int opts)
{
	struct sym	*sym, *next;

	if ((conf = calloc(1, sizeof(struct undervolt_conf))) == NULL)
		err(EXIT_FAILURE, "%s", __func__);
	conf->opts = opts;

	if ((file = pushfile(filename)) == NULL) {
		free(conf);
		return NULL;
	}
	topfile = file;

	TAILQ_INIT(&conf->processor_list);

	yyparse();
	errors = file->errors;
	popfile();

	/* Free macros and check which have not been used. */
	TAILQ_FOREACH_SAFE(sym, &symhead, entry, next) {
		if ((conf->opts & UVCTL_OPT_VERBOSE) && !sym->used)
			fprintf(stderr, "warning: macro '%s' not "
			    "used\n", sym->nam);
		if (!sym->persist) {
			free(sym->nam);
			free(sym->val);
			TAILQ_REMOVE(&symhead, sym, entry);
			free(sym);
		}
	}

	if (errors != 0) {
		clear_config(conf);
		return NULL;
	}

	if (opts & UVCTL_OPT_CHECK) {
		if (opts & UVCTL_OPT_VERBOSE)
			print_config(conf);
	}

	return conf;
}

int
symset(const char *nam, const char *val, int persist)
{
	struct sym	*sym;

	TAILQ_FOREACH(sym, &symhead, entry) {
		if (strcmp(nam, sym->nam) == 0)
			break;
	}

	if (sym != NULL) {
		if (sym->persist == 1)
			return (0);
		else {
			free(sym->nam);
			free(sym->val);
			TAILQ_REMOVE(&symhead, sym, entry);
			free(sym);
		}
	}
	if ((sym = calloc(1, sizeof(*sym))) == NULL)
		return -1;

	sym->nam = strdup(nam);
	if (sym->nam == NULL) {
		free(sym);
		return -1;
	}
	sym->val = strdup(val);
	if (sym->val == NULL) {
		free(sym->nam);
		free(sym);
		return -1;
	}
	sym->used = 0;
	sym->persist = persist;
	TAILQ_INSERT_TAIL(&symhead, sym, entry);
	return 0;
}

int
cmdline_symset(char *s)
{
	char	*sym, *val;
	int	ret;

	if ((val = strrchr(s, '=')) == NULL)
		return -1;
	sym = strndup(s, val - s);
	if (sym == NULL)
		errx(EXIT_FAILURE, "%s: strndup", __func__);
	ret = symset(sym, val + 1, 1);
	free(sym);

	return ret;
}

char *
symget(const char *nam)
{
	struct sym	*sym;

	TAILQ_FOREACH(sym, &symhead, entry) {
		if (strcmp(nam, sym->nam) == 0) {
			sym->used = 1;
			return sym->val;
		}
	}
	return NULL;
}

struct processor_c *
conf_new_processor(struct undervolt_conf *c, int n)
{
	struct processor_c *p;
	p = processor_find(c, n);
	if (p != NULL)
		return NULL;
	if ((p = calloc(1, sizeof(struct processor_c))) == NULL)
		err(EXIT_FAILURE, "%s", __func__);
	TAILQ_INSERT_TAIL(&c->processor_list, p, entry);
	p->idx = n;
	return p;
}

struct processor_c *
processor_find(struct undervolt_conf *c, int n)
{
	struct processor_c *p;

	TAILQ_FOREACH(p, &c->processor_list, entry) {
		if (n == p->idx) {
			return p;
		}
	}
	return NULL;
}

void
clear_config(struct undervolt_conf *xconf)
{
	struct processor_c	*p;

	while ((p = TAILQ_FIRST(&xconf->processor_list)) != NULL) {
		TAILQ_REMOVE(&xconf->processor_list, p, entry);
		free(p);
	}
	free(xconf);
}


const char*
vg2txt(enum voltagegroup vg)
{
	switch (vg) {
	case VOLTAGE_CPU:
		return "cpu";
	case VOLTAGE_GPU:
		return "gpu";
	case VOLTAGE_CACHE:
		return "cache";
	case VOLTAGE_SYS:
		return "sys";
	case VOLTAGE_IO:
		return "io";
	default:
		return "<unknown>";
	}
}

void
print_config(struct undervolt_conf *xconf)
{
	struct processor_c	*p;
	int			 i;

	TAILQ_FOREACH(p, &xconf->processor_list, entry) {
		printf("processor %d {\n", p->idx);
		for (i=0;i<5;i++) {
			if (p->voltage[i].write == 1) {
			printf("\tvoltage ");
			printf("%s", vg2txt(i));
			printf(" %d\n", p->voltage[i].offset);
			}
		}
		printf("}\n\n");
	}
}

int
conf_check_file(char *s)
{
	struct stat st;

	if (s[0] != '/') {
		warnx("%s: not an absolute path", s);
		return 0;
	}
	if (stat(s, &st)) {
		if (errno == ENOENT)
			return 1;
		warn("cannot stat %s", s);
		return 0;
	}
	if (st.st_mode & (S_IRWXG | S_IRWXO)) {
		warnx("%s: group read/writable or world read/writable", s);
		return 0;
	}
	return 1;
}
