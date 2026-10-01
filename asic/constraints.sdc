# MINERVA P5 -- Sky130 constraints.
#
# Deliberately loose to start: the first run should route cleanly with no
# violations, not set a frequency record. Tighten CLOCK_PERIOD in config.json
# once the flow closes end to end.
#
# Note: OpenSTA does not implement remove_from_collection or other
# Synopsys-only collection commands, so the port groups below are listed
# explicitly rather than derived from all_inputs/all_outputs.

set clk_period 30.0
create_clock -name clk -period $clk_period [get_ports clk]
# Design rule limits. LibreLane normally applies these from its own base SDC,
# which this file replaces, so they have to be stated here.
set_max_transition 0.75 [current_design]
set_max_fanout 10 [current_design]
set_max_capacitance 0.2 [current_design]

# Jitter plus an allowance for CTS skew before the tree exists.
set_clock_uncertainty 0.25 [get_clocks clk]
set_clock_transition  0.15 [get_clocks clk]

# The reset pad is asynchronous and is synchronised inside the design, so the
# synchroniser's first flop has no meaningful setup relationship to the clock.
set_false_path -from [get_ports rst_n_pad]

# ---- port groups -----------------------------------------------------------
# Host port: an external tester drives the inputs and samples the outputs.
set host_inputs [get_ports {
    host_awaddr[*] host_awvalid
    host_wdata[*]  host_wstrb[*] host_wvalid
    host_bready
    host_araddr[*] host_arvalid
    host_rready
    cpu_hold
}]

set host_outputs [get_ports {
    host_awready host_wready
    host_bresp[*] host_bvalid
    host_arready
    host_rdata[*] host_rresp[*] host_rvalid
}]

# Debug pins: observability only. Never let them constrain the design.
set debug_outputs [get_ports {
    debug_out[*] if_pc_out[*] if_stall_out mem_stall_out dma_irq fi_irq
}]

# ---- I/O timing ------------------------------------------------------------
set_input_delay  -clock clk 2.0 $host_inputs
set_output_delay -clock clk 2.0 $host_outputs
set_false_path -to $debug_outputs

set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin Y $host_inputs
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin Y [get_ports rst_n_pad]
set_load 0.02 $host_outputs
set_load 0.02 $debug_outputs
