# Run through scripts/run_gemm_ppa.py, from an isolated per-core build directory.
# Non-topographical DC: mapped cell area and pre-layout timing/power estimates.
proc require_success {label script} {
    set result [uplevel 1 $script]
    if {$result ne "1"} {error "$label returned $result"}
}

proc run_ppa {} {
    source run_config.tcl
    set_host_options -max_cores 1
    set_app_var target_library [list $target_db]
    set_app_var link_library [list * $target_db]
    define_design_lib WORK -path ./work
    saif_map -start
    require_success analyze {analyze -format sverilog $rtl_sources}
    require_success elaborate {elaborate $top -parameters "MatrixDim=$matrix_dim"}
    # elaborate selects the top, whose name may include parameter suffixes.
    # Keep that selection instead of looking up the unspecialized module name.
    require_success link {link}
    require_success check_design {check_design}
    if {[sizeof_collection [get_libs -quiet $library_name]] != 1} {
        error "Configured internal library name did not load: $library_name"
    }
    redirect library.rpt {require_success report_lib {report_lib $library_name}}
    redirect units.rpt {report_units}
    set_operating_conditions -library $library_name $operating_condition

    # Config uses ns; DC uses the time units of the loaded library.
    set unit $library_time_unit_ns
    create_clock -name core_clk -period [expr {$clock_period_ns / $unit}] [get_ports clk]
    set_clock_uncertainty [expr {$clock_uncertainty_ns / $unit}] [get_clocks core_clk]
    # Model a finite clock slew at sequential cells, without a physical clock tree.
    set_clock_transition [expr {$clock_transition_ns / $unit}] [get_clocks core_clk]
    set data_inputs [remove_from_collection [all_inputs] [get_ports clk]]
    set_input_delay [expr {$input_delay_ns / $unit}] -clock core_clk $data_inputs
    set_output_delay [expr {$output_delay_ns / $unit}] -clock core_clk [all_outputs]
    set_input_transition [expr {$input_transition_ns / $unit}] $data_inputs
    set_load $output_load_library_units [all_outputs]
    # rst is synchronous: constrain it as data, with no false paths/case analysis.
    # No inferred SRAM macros: behavioral memories are part of mapped cell area.
    set_app_var auto_wire_load_selection false
    set_wire_load_mode top
    if {$wire_load_model ne ""} {
        set_wire_load_model -name $wire_load_model -library $library_name [current_design]
    }
    # Equal effort, no retiming or automatic clock gating; keep report hierarchy.
    require_success compile {compile -map_effort high}
    require_success mapped_check {check_design}
    if {[sizeof_collection [get_cells -hierarchical -filter "is_unmapped == true"]] != 0} {
        error "Unmapped cells remain; area/timing/power are not comparable"
    }
    redirect area.rpt {report_area -hierarchy}
    redirect timing.rpt {report_timing -delay_type max -max_paths 10}
    redirect constraints.rpt {report_constraint -all_violators}
    redirect timing_checks.rpt {check_timing}
    redirect qor.rpt {report_qor}
    redirect references.rpt {report_reference -hierarchy}
    redirect design.rpt {report_design}
    write -format ddc -hierarchy -output mapped.ddc
    write_sdc mapped.sdc

    # Import after mapping so workload does not change the synthesis objective.
    # saif_map tracks RTL names across compile; inspect BOTH annotation reports.
    require_success read_saif {
        read_saif -auto_map_names -input ../sim/activity.saif -instance_name tb_gemm_ppa/dut
    }
    redirect activity.rpt {report_saif -hierarchy -rtl_saif}
    redirect activity_missing.rpt {report_saif -hierarchy -rtl_saif -missing}
    redirect power.rpt {require_success report_power {report_power -analysis_effort high -verbose}}
    redirect power_hierarchy.rpt {report_power -hierarchy}
    change_names -rules verilog -hierarchy
    write -format verilog -hierarchy -output mapped.v
    saif_map -type primepower -write_map saifmap.primepower.tcl
    set marker [open reports.complete w]
    puts $marker "Reports generated; review units, timing, annotation and power-model coverage before use."
    close $marker
}

if {[catch {run_ppa} failure]} {
    puts stderr "FAIL PPA: $failure"
    exit 1
}
exit 0
