/*
 * Intel MSR undervolt utility
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <fcntl.h>
#include <linux/limits.h>
#include <unistd.h>
#include <err.h>

#include "msr.h"
#include "uvctl.h"

int
open_msr_interface(int cpu)
{
	char	path[PATH_MAX +1];
	int	fd = -1;

	snprintf(path, sizeof(path), "/dev/cpu/%d/msr", cpu);
	fd = open(path, O_RDWR | O_SYNC);

	if (fd < 0)
		err(-1, "Unable to open MSR interface for CPU %d", cpu);

	return (fd);
}

int
write_msr(int fd, off_t address, uint64_t *buf)
{
	if (pwrite(fd, buf, sizeof(*buf), address) != sizeof(*buf))
		err(-1, "write to address 0x%lx = 0x%lx failed", address, *buf);

	if (verbose == 2)
		fprintf(stderr, "%s: write to address 0x%lx = 0x%lx success\n",
		    __func__, address, *buf);

	return (0);
}

int
read_msr(int fd, off_t address, uint64_t *buf)
{
	if (pread(fd, buf, sizeof(*buf), address) != sizeof(*buf))
		err(-1, "read from address 0x%lx failed", address);

	if (verbose == 2)
		fprintf(stderr, "%s: read from address 0x%lx = 0x%lx success\n",
		    __func__, address, *buf);

	return (0);
}

int
write_msr_values(struct processor_c *p)
{
	int	r = -1;
	int	i;
	int	fd = open_msr_interface(p->idx);

	if (write_tjunction_offset(fd, &p->tjunction) == -1)
		goto err;

	for (i=0; i < VOLTAGE_GROUP_EXCEED; i++) {
		if (write_voltage_offset(fd, i, &p->voltage[i]) == -1)
			goto err;
	}

	r = 0;
err:
	if (fd)
		close(fd);
	return (r);
}

void
print_msr_values(int cpu)
{
	float	mv;
	int 	c, i;
	int	fd = open_msr_interface(cpu);

	struct processor_c *p = NULL;
        if ((p = calloc(1, sizeof(struct processor_c))) == NULL)
                err(EXIT_FAILURE, "%s", __func__);

	printf("Settings for processor %d\n", cpu);

	if ((c = get_tjunction_offset(fd)) != -1)
		printf(" Tjunction offset: %d °C\n", 0 - c);

	if (get_power_limit(fd, p) != -1) {
		printf(" Power limit:\n");
		for (i=0;i < 4; i++) {
			printf("\tPL%d: %'3d W @ %'12.4f ms (%sabled, "
			    "%slocked)\n",
			    i + 1,
			    p->power[i].value,
			    p->power[i].time * 1000,
			    p->power[i].enabled == 1 ? "en" : "dis",
			    p->power[i].locked == 1 ? "" : "un" );
		}
	}


	printf(" Voltage offset:\n");
	for (i=0; i < VOLTAGE_GROUP_EXCEED; i++) {
		if ((mv = get_voltage_offset(fd, i)) != -1)
			printf("\t%5s: %'7.2f mV\n", vg2txt(i), 0 - mv);
	}

	if (p)
		free(p);

	if (fd)
		close(fd);
}
