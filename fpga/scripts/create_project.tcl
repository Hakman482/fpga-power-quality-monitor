# Recreate a clean Vivado project from repository sources.
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file normalize [file join $script_dir ".."]]
set build_dir  [file normalize [file join $fpga_dir "build"]]

create_project pq_monitor_fpga $build_dir -part xc7a100tcsg324-1 -force
set_property target_language VHDL [current_project]

set design_files [glob -nocomplain [file join $fpga_dir "src" "*.vhd"]]
add_files -norecurse $design_files

add_files -fileset constrs_1 -norecurse \
    [file join $fpga_dir "constraints" "pq_nexys_top.xdc"]

set sim_files [glob -nocomplain [file join $fpga_dir "sim" "*.vhd"]]
add_files -fileset sim_1 -norecurse $sim_files

set_property top pq_nexys_top [get_filesets sources_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Created clean pq_monitor_fpga project in: $build_dir"
puts "Target: xc7a100tcsg324-1 (Nexys A7-100T)"
