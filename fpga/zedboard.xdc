# 100 MHz System Clock (Y9)
set_property PACKAGE_PIN Y9 [get_ports {clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk}]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports {clk}]

# Reset Button (Center Button - BTNC P16)
set_property PACKAGE_PIN P16 [get_ports {rst_n}]
set_property IOSTANDARD LVCMOS18 [get_ports {rst_n}]

# LEDs LD0-LD7  (NOTE: Vivado renamed to led_0 in the wrapper)
set_property PACKAGE_PIN T22 [get_ports {led_0[0]}]
set_property PACKAGE_PIN T21 [get_ports {led_0[1]}]
set_property PACKAGE_PIN U22 [get_ports {led_0[2]}]
set_property PACKAGE_PIN U21 [get_ports {led_0[3]}]
set_property PACKAGE_PIN V22 [get_ports {led_0[4]}]
set_property PACKAGE_PIN W22 [get_ports {led_0[5]}]
set_property PACKAGE_PIN U19 [get_ports {led_0[6]}]
set_property PACKAGE_PIN U14 [get_ports {led_0[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_0[*]}]