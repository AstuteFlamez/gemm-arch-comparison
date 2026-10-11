# Run with dc_shell from build/env/dc. This is a library inspection only.
# This candidate path was present in the user's CAE directory listing.
# No target_library setting or synthesis result is established by this probe.
# The user's first run confirmed that this file's internal name is lsi_10k.
set candidate_db /srv/auto/apps/synopsys-2026/syn/Y-2026.03/libraries/syn/lsi_10k.db

if {![file readable $candidate_db]} {
    puts stderr "FAIL library_probe: cannot read $candidate_db"
    exit 1
}

if {[catch {read_db $candidate_db} load_error]} {
    puts stderr "FAIL library_probe: $load_error"
    exit 1
}

set candidate_library [get_libs -quiet lsi_10k]
if {[sizeof_collection $candidate_library] != 1} {
    puts stderr "FAIL library_probe: the candidate library lsi_10k did not load"
    exit 1
}

list_libs
set library_name [get_object_name $candidate_library]
set cell_count [sizeof_collection [get_lib_cells -quiet ${library_name}/*]]
if {$cell_count == 0} {
    puts stderr "FAIL library_probe: candidate contains no cells"
    exit 1
}

puts "LOADED library_probe: $library_name contains $cell_count cells"
set report_text ""
set report_status 0
set report_exception [catch {
    redirect -variable report_text {set report_status [report_lib $library_name]}
} report_error]
set report_file [open library-inspection.rpt w]
puts $report_file "Library: $library_name; cell count: $cell_count"
puts $report_file $report_text
if {$report_exception} {puts $report_file "Error: $report_error"}
close $report_file

# DC can print Error and return 0 without raising a Tcl exception. Check both.
if {$report_exception || $report_status ne "1" ||
    [regexp {(^|\n)[[:space:]]*Error:} $report_text]} {
    puts stderr "FAIL library_probe: report_lib failed; inspect library-inspection.rpt"
    exit 1
}
puts "PASS library_probe: candidate loaded and report_lib completed"
puts "Review library-inspection.rpt before selecting a synthesis target."
quit
