/*
 * Intel MSR undervolt utility
 */

#include <stdio.h>
#include <stdint.h>
#include <errno.h>

#include "msr.h"
#include "uvctl.h"

int
write_tjunction_offset(int fd, const struct setting *t)
{
	uint64_t buf = (0 - t->offset) << 24;

	if (t->write != 1)
		return (0);

	if (t->offset < TJUNCTION_OFFSET_MIN  ||
	    t->offset > TJUNCTION_OFFSET_MAX)
		return (ERANGE);

	if (write_msr(fd, MSR_TJUNCTION_OFFSET, &buf))
		return (-1);

	return (0);
}

int
get_tjunction_offset(int fd)
{
	int		value = -1;
	uint64_t	buf = 0;

	if (read_msr(fd, MSR_TJUNCTION_OFFSET, &buf) == 0)
		value = (buf & 0x3f000000) >> 24;

	return (value);
}
