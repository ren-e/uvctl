# Intel MSR undervolt utility
> :warning: **This tool may damage your hardware**: Use at your own risk!

The `uvctl` utility allows you to modify processor settings,
such as voltage and tjunction temperature offsets. This application
uses the MSR interface to read and apply the settings.


### Requirements
  - Linux

### Compile
```
make
```

### Usage
```
usage: uvctl [-wvn] [-p processor] [-f file]
```

### How
#### Read values
To read the processor values
```
./uvctl
```

output:
```
Settings for processor 0
 Tjunction offset: -10 °C
 Power limit:
	PL1:  35 W @   28000.0000 ms (enabled, unlocked)
	PL2:  92 W @       2.4414 ms (enabled, unlocked)
	PL3:   0 W @       0.9766 ms (disabled, locked)
	PL4: 120 W @       0.9766 ms (disabled, unlocked)
 Voltage offset:
	  cpu:   -9.77 mV
	  gpu:    0.00 mV
	cache:   -9.77 mV
	  sys:    0.00 mV
	   io:    0.00 mV
```

#### Apply processor settings from configuration
```
./uvctl -wv
```

### Example configuration file
The configuration file should be written to `/etc/undervolt.conf`:
```
# Example configuration
processor 0  {
	voltage cpu -10
	voltage cache -10
	voltage gpu 0
	voltage sys 0
	voltage io 0
	tjunction -10
}

```
