# The board oscillator drives the entire design; no generated/gated clocks.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_clock_uncertainty

# KEY0 only drives the reset synchronizer's asynchronous reset pins.
# KEY1 only drives start_meta, the first stage of the button synchronizer.
# Their arrival times are unrelated to CLOCK_50. Internal stage-to-stage paths
# and synchronous reset distribution remain timed at 50 MHz.
set_false_path -from [get_ports {KEY[0]}]
set_false_path -from [get_ports {KEY[1]}]

# LEDs are observed by a person, not sampled by an external clocked device.
set_false_path -to [get_ports {LED_READY LED_BUSY LED_PASS LED_FAIL}]
