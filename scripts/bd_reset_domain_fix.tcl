# MINERVA P5 -- put the CPU-side BRAM controllers in the CPU's reset domain.
#
# Symptom this fixes: asserting the CPU hold while the CPU is fetching resets
# the crossbar but not imem_ctrl_cpu / dmem_ctrl_cpu. One side of a live AXI
# transaction goes away, the controller keeps RVALID asserted, the reset
# crossbar never asserts RREADY, and the slave is deadlocked until it is reset.
# From software this looks like an FI operation stuck with STATUS = BUSY that
# no retry can clear.
#
# Run in the Vivado Tcl console with the project open. Requires the updated
# p4_top.v (adds the fabric_aresetn output) already in the project.

open_bd_design [get_files p4_bd.bd]

# 1. Pick up the new port on the module reference.
update_module_reference p4_bd_p4_top_0_0

# 2. Move only the CPU-side controllers off the PS peripheral reset.
#    The _ps controllers stay on it: the PS loads memory while the CPU is held.
set psrst [get_bd_nets rst_ps7_100M_peripheral_aresetn]
disconnect_bd_net $psrst [get_bd_pins dmem_ctrl_cpu/s_axi_aresetn]
disconnect_bd_net $psrst [get_bd_pins imem_ctrl_cpu/s_axi_aresetn]

connect_bd_net [get_bd_pins p4_top_0/fabric_aresetn] \
               [get_bd_pins dmem_ctrl_cpu/s_axi_aresetn] \
               [get_bd_pins imem_ctrl_cpu/s_axi_aresetn]

# 3. Check it landed -- assign/connect steps fail quietly in this flow.
puts "fabric_aresetn now drives:"
foreach p [get_bd_pins -of_objects [get_bd_nets -of_objects \
           [get_bd_pins p4_top_0/fabric_aresetn]]] { puts "  $p" }
puts "PS peripheral reset still drives:"
foreach p [get_bd_pins -of_objects $psrst] { puts "  $p" }

validate_bd_design
save_bd_design

# 4. The address map must be unchanged by this edit -- print it and compare.
puts "---- address map ----"
foreach seg [get_bd_addr_segs -of_objects [get_bd_cells /]] {
    puts [format "%-40s %s %s" $seg [get_property OFFSET $seg] [get_property RANGE $seg]]
}
