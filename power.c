/*
 * Intel MSR undervolt utility
 */

#include <stdio.h>
#include <stdint.h>

#include "msr.h"
#include "uvctl.h"

static float pltime2sec(uint64_t buf, double time_units)
{
	float	result = 1.0;
	result += (((buf >> 22) & 0x3) / 4.0);
	result *= (1 << ((buf >> 17) & 0x1F));
	return (result * time_units);
}

int
get_power_limit(int fd, struct processor_c *p)
{
	double			 power_units, time_units;
	int			 i;
	uint64_t		 buf, units;

	int addr[4] = {
		MSR_PKG_POWER_LIMIT,
		MSR_PKG_POWER_LIMIT,
		MSR_PL3_CONTROL,
		MSR_PL4_CONTROL,
	};

	if (read_msr(fd, MSR_POWER_UNIT, &units))
		return (-1);

	power_units = 1.0 / (1 << (units & 0xf));
	time_units  = 1.0 / (1 << ((units >>16) & 0xf));


	for (i=PKG_POWER_LIMIT_1; i <= PKG_POWER_LIMIT_4; i++) {
		if (read_msr(fd, addr[i], &buf))
			return (-1);

		if (i == PKG_POWER_LIMIT_2)
			buf = buf >> 32;

		p->power[i].locked  = (buf >> 31) & 0x1;
		p->power[i].enabled = (buf >> 15 ) & 0x1;
		p->power[i].value   = (buf & 0x1fff)  * power_units;
		p->power[i].time    = pltime2sec(buf, time_units);
	}

	return (0);
}
