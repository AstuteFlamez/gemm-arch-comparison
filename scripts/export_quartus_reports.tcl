# Run after a full compile, from fpga/de2_115:
# quartus_sh -t ../../scripts/export_quartus_reports.tcl PROJECT REVISION OUT_DIR
# Export raw report tables, retaining vendor labels and units. No missing value
# is converted to zero, and exporting reports does not establish timing closure.
# API reference: https://cdrdv2-public.intel.com/654662/tclscriptrefmnl.pdf

proc csv_row {values} {
    set fields {}
    foreach value $values {
        lappend fields "\"[string map [list \" \"\"] $value]\""
    }
    return [join $fields ,]
}

proc export_reports {project revision output_dir} {
    global quartus
    load_package project
    load_package report
    project_open -revision $revision $project
    load_report

    file mkdir $output_dir
    set manifest [open [file join $output_dir panels.txt] w]
    fconfigure $manifest -encoding utf-8 -translation lf
    puts $manifest "Project: $project"
    puts $manifest "Revision: $revision"
    puts $manifest "Exported UTC: [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]"
    if {[info exists quartus(version)]} {
        puts $manifest "Quartus: $quartus(version)"
    }
    foreach name {FAMILY DEVICE TOP_LEVEL_ENTITY SEED PROJECT_OUTPUT_DIRECTORY} {
        if {[catch {get_global_assignment -name $name} value]} {
            set value "UNAVAILABLE: $value"
        }
        puts $manifest "$name: $value"
    }
    puts $manifest "Scope: full board design; use the u_gemm entity subtree for core resources."
    puts $manifest "Timing and resource values remain in their original report tables."
    puts $manifest "No automatic timing pass/fail or power estimate is inferred here.\n"

    set count 0
    set have_fitter 0
    set have_entity 0
    set have_timing 0
    foreach name [lsort [get_report_panel_names]] {
        set lower [string tolower $name]
        if {![string match "*flow summary*" $lower] &&
            ![string match "*flow settings*" $lower] &&
            ![string match "*fitter*summary*" $lower] &&
            ![string match "*fitter*resource*" $lower] &&
            ![string match "*fitter*ram*" $lower] &&
            ![string match "*fitter*dsp*" $lower] &&
            ![string match "*fitter*settings*" $lower] &&
            ![string match "*synthesis*settings*" $lower] &&
            ![string match "*timing analyzer*" $lower]} {
            continue
        }
        set id [get_report_panel_id $name]
        # Some report nodes are folders rather than tables.
        if {[catch {get_number_of_rows -id $id} rows] || $rows == 0} {
            puts $manifest "NO TABLE: $name"
            continue
        }
        regsub -all {[^A-Za-z0-9_-]} $name _ stem
        set filename [format "%03d_%s.csv" $count [string range $stem 0 119]]
        set handle [open [file join $output_dir $filename] w]
        fconfigure $handle -encoding utf-8 -translation lf
        for {set row 0} {$row < $rows} {incr row} {
            puts $handle [csv_row [get_report_panel_row -id $id -row $row]]
        }
        close $handle
        puts $manifest "$filename\t$name"
        incr count
        if {[string match "*fitter*summary*" $lower]} {set have_fitter 1}
        if {[string match "*fitter*resource*by entity*" $lower]} {set have_entity 1}
        if {[string match "*timing analyzer*summary*" $lower]} {set have_timing 1}
    }

    set missing {}
    if {!$have_fitter} {lappend missing "Fitter summary"}
    if {!$have_entity} {lappend missing "Fitter resource utilization by entity"}
    if {!$have_timing} {lappend missing "Timing Analyzer summary"}
    puts $manifest "\nExported tables: $count"
    puts $manifest "Missing required report groups: $missing"
    close $manifest
    unload_report
    project_close
    if {[llength $missing]} {
        error "Incomplete reports: [join $missing {; }]. Check panels.txt and the Quartus GUI."
    }
    puts "Exported $count tables for $revision to $output_dir"
    puts "Review timing constraints/slack and entity resource counts before drawing conclusions."
}

if {[llength $quartus(args)] != 3} {
    error "Usage: quartus_sh -t export_quartus_reports.tcl PROJECT REVISION OUT_DIR"
}
export_reports {*}$quartus(args)
