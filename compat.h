#ifndef COMPAT_H
#define COMPAT_H

#include <stdarg.h>

#ifndef __dead
#define __dead __attribute__ ((__noreturn__))
#endif

#ifndef HAVE_EXPLICIT_BZERO
/* explicit_bzero.c */
void		 explicit_bzero(void *, size_t);
#endif

#ifndef HAVE_REALLOCARRAY
/* reallocarray.c */
void		*reallocarray(void *, size_t, size_t);
#endif

#include "compat/queue.h"

#ifndef HAVE_STRTONUM
/* strtonum.c */
long long	 strtonum(const char *, long long, long long, const char **);
#endif

#ifndef HAVE_ASPRINTF
/* asprintf.c */
int		 asprintf(char **, const char *, ...);
int		 vasprintf(char **, const char *, va_list);
#endif

#endif /* COMPAT_H */
