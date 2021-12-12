/*
 * Intel MSR undervolt utility
 */

#include <stdio.h>
#include <stdint.h>
#include <errno.h>

#include "msr.h"
#include "uvctl.h"

static uint64_t
pack_voltage(uint64_t idx, const struct setting *v)
{
	uint64_t offset;
	uint64_t payload = 1UL << 63 | idx << 40 |  1UL << 36;

	if (v->write) {
		offset = (uint64_t)(v->offset * 1.024) & 0xfff;
		payload |= 0xffe00000 & (offset << 21);
		payload |= 1UL << 32;
	}

	return (payload);
}

static float
unpack_voltage(uint64_t buf)
{
	float voltage;
	uint64_t offset = 0x800 - (buf >> 21);

        offset &= 0x800 -1;
	voltage = (float)offset / 1.024;

	return (voltage);
}

float
get_voltage_offset(int fd, int idx)
{
	uint64_t		buf;
	float			value = -1;
	const struct setting	v = {
		.write  = 0,
		.offset = 0,
	};

	if (idx < 0 || idx >= VOLTAGE_GROUP_EXCEED)
		return (ERANGE);

	buf = pack_voltage(idx, &v);
	if (write_msr(fd, MSR_VOLTAGE_OFFSET, &buf) == 0 &&
	    read_msr(fd, MSR_VOLTAGE_OFFSET, &buf) == 0)
		value = unpack_voltage(buf);

	return (value);
}

int
write_voltage_offset(int fd, int idx, const struct setting *v)
{
	uint64_t	buf = pack_voltage(idx, v);

	if (v->offset < VOLTAGE_OFFSET_MIN ||
	    v->offset > VOLTAGE_OFFSET_MAX)
		return (ERANGE);

	if (idx < 0 || idx >= VOLTAGE_GROUP_EXCEED)
		return (ERANGE);

	if (write_msr(fd, MSR_VOLTAGE_OFFSET, &buf))
		return (-1);

	/* Verify input with applied voltage */
	if (buf != pack_voltage(idx, v))
		return (-1);

	return (0);
}
