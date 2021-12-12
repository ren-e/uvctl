#include <stdint.h>
#include "compat.h"

#ifndef UV_H
#define UV_H

#define CONF_FILE		"/etc/undervolt.conf"

#define UVCTL_OPT_VERBOSE	0x00000001
#define UVCTL_OPT_CHECK		0x00000004
#define UVCTL_OPT_WRITE		0x000000f0

#define TJUNCTION_OFFSET_MIN	-40
#define TJUNCTION_OFFSET_MAX	0
#define VOLTAGE_OFFSET_MIN	-400
#define VOLTAGE_OFFSET_MAX	0

/* Reference to voltage settings index number */
enum voltagegroup {
	VOLTAGE_CPU,
	VOLTAGE_GPU,
	VOLTAGE_CACHE,
	VOLTAGE_SYS,
	VOLTAGE_IO,
	VOLTAGE_GROUP_EXCEED,
};


/* Reference to power limit settings index number */
enum powerlimitlevel {
	PKG_POWER_LIMIT_1,
	PKG_POWER_LIMIT_2,
	PKG_POWER_LIMIT_3,
	PKG_POWER_LIMIT_4,
};


struct pl_setting {
	int		level;
	uint8_t		enabled;
	uint8_t		locked;
	uint16_t	value;
	float		time;
};

struct setting {
	int		offset;
	int		write;
};

struct processor_c {
	TAILQ_ENTRY(processor_c)	entry;
	char				*name;
	int				idx;
	struct setting			tjunction;
	struct setting			voltage[5];
	struct pl_setting		power[4];
};

struct undervolt_conf {
	int				opts;
	int				write;
	int				processor;
	TAILQ_HEAD(, processor_c)	processor_list;
};

/* main.c */
extern int		 verbose;
__dead void		 usage(void);
int			 undervolt(struct undervolt_conf *);

/* msr.c */
void			 print_msr_values(int);
int			 write_msr_values(struct processor_c *);
int			 open_msr_interface(int);
int			 read_msr(int, off_t, uint64_t *);
int			 write_msr(int, off_t, uint64_t *);

/* tjunction.c */
int			 get_tjunction_offset(int);
int			 write_tjunction_offset(int, const struct setting *);

/* voltage.c */
float			 get_voltage_offset(int, int);
int			 write_voltage_offset(int, int, const struct setting *);

/* parse.y */
const char		*vg2txt(enum voltagegroup);
struct undervolt_conf	*parse_config(const char *, int);
int			 cmdline_symset(char *);
struct processor_c	*processor_find(struct undervolt_conf *, int);

/* power.c */
int			 get_power_limit(int, struct processor_c *);

/* util.c */
int			 intel_genuine_processor();

#endif /* UV_H */
