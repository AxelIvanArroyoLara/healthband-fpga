# Lee la memoria "PPG" (ppg_logger) de la DE10-Lite por JTAG.
#   quartus_stp -t read_ppg.tcl salida.hex
set out [lindex $argv 0]
set hw [lindex [get_hardware_names] 0]
set dev [lindex [get_device_names -hardware_name $hw] 0]
begin_memory_edit -hardware_name $hw -device_name $dev
set inst [lindex [get_editable_mem_instances -hardware_name $hw -device_name $dev] 0]
puts "instancia: $inst"
set data [read_content_from_memory -instance_index 0 -start_address 0 -word_count 4096 -content_in_hex]
end_memory_edit
set f [open $out w]
puts $f $data
close $f
puts "OK $out"
