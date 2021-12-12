/*
 * Intel MSR undervolt utility
 */

#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#include "compat.h"
#include "uvctl.h"

int              verbose;

__dead void
usage(void)
{
	extern char     *__progname;
	fprintf(stderr, "usage: %s [-wvn] [-p processor] [-f file]\n"
	    , __progname);
	exit(1);
}

int
undervolt(struct undervolt_conf *conf)
{
	struct processor_c	*processor = NULL;

	if (conf->opts & UVCTL_OPT_CHECK) {
		fprintf(stderr, "configuration OK\n");
		return (0);
	}

	TAILQ_FOREACH(processor, &conf->processor_list, entry) {
		if (intel_genuine_processor(0) == -1)
			errx(EXIT_FAILURE, "Unsupported processor\n");

		if (conf->opts & UVCTL_OPT_WRITE) {
			if (write_msr_values(processor) == -1)
				errx(EXIT_FAILURE, "Could not configure CPU%d\n",
				    processor->idx);
		}

		if (verbose || !(conf->opts & UVCTL_OPT_WRITE))
			print_msr_values(processor->idx);
	}

	return (0);
}

int
main(int argc, char *argv[])
{
	int			 c;
	int			 itmp;
	const char		*errstr;
	char			*conffile = CONF_FILE;
	int			 popts = 0;
	int			 p = -1;
	struct undervolt_conf	*conf = NULL;


	while ((c = getopt(argc, argv, "wvnp:f:")) != -1) {
		switch (c) {
		case 'f':
                        if ((conffile = strdup(optarg)) == NULL)
                                err(EXIT_FAILURE, "strdup");
                	break;
		case 'p':
			itmp = strtonum(optarg, 0, sysconf(_SC_NPROCESSORS_ONLN),
			   &errstr);
			if (errstr != NULL)
				errx(1, "Processor %s out of range", optarg);
			p = itmp;
			break;
                case 'v':
                        verbose = verbose ? 2 : 1;
                        popts |= UVCTL_OPT_VERBOSE;
                	break;
                case 'n':
			popts |= UVCTL_OPT_CHECK;
	                break;
                case 'w':
			popts |= UVCTL_OPT_WRITE;
        	        break;
		default:
			usage();
		}
	}
	if (p >=0 && popts & UVCTL_OPT_WRITE)
		errx(EXIT_FAILURE, "Write mode can only use configuration files\n");

	if (p >= 0) {
		if (intel_genuine_processor(0) == -1)
			errx(EXIT_FAILURE, "Unsupported processor\n");
		print_msr_values(p);
		goto done;
	}

	if ((conf = parse_config(conffile, popts)) == NULL)
		return (EXIT_FAILURE);

        if (undervolt(conf))
		return (EXIT_FAILURE);

done:
	return (0);
}
