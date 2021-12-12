#include <cpuid.h>

int
intel_genuine_processor(int leaf)
{
	unsigned int	maxlvl,ebx, ecx, edx;
	ebx = ecx = edx = 0;

	__cpuid(leaf, maxlvl, ebx, ecx, edx);

	if (ebx == 0x756e6547 && ecx == 0x6c65746e && edx == 0x49656e69)
		return (0);

	return (-1);
}
