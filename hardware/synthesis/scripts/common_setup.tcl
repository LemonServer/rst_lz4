# Common synthesis setup for all modules
# Include this at the start of synthesis scripts

# ============================================================================
# Library Setup
# ============================================================================

# ASAP7nm library paths
# This is the trimmed in-repo DB bundle retained for synthesis script
# compatibility; older area_nums_for_ram collateral was removed.
set script_dir   [file dirname [info script]]
set proj_root    [file normalize "$script_dir/../.."]
set lib_dir      [file normalize "$proj_root/synthesis/libs/asap7_db"]

# Pick corner / Vt - Options: TT / SS / FF and LVT / RVT / SLVT
set corner TT
set vt     RVT

# All 20 ASAP7 library files (7nm1.db through 7nm20.db)
set target_library [lsort -unique [glob -nocomplain "$lib_dir/7nm*.db"]]

set link_library   "* $target_library"

# Set operating conditions (RVT/TT)
set_operating_conditions -library asap7sc7p5t_22b_AO_RVT_TT_170906 PVT_0P7V_25C

if {![info exists FAST_POC]} {
    set FAST_POC 0
}
if {![info exists IO_DELAY_FRAC]} {
    set IO_DELAY_FRAC -1.0
}
if {![info exists COMB_IO_DELAY]} {
    set COMB_IO_DELAY -1.0
}
if {![info exists INPUT_TRANSITION_NS]} {
    set INPUT_TRANSITION_NS -1.0
}
if {![info exists OUTPUT_LOAD_PF]} {
    set OUTPUT_LOAD_PF -1.0
}
if {![info exists TIME_UNITS_PER_NS]} {
    # ASAP7 report timing is in ps in our current DC environment, so convert
    # user-facing nanosecond inputs before passing them to constraints.
    set TIME_UNITS_PER_NS 1000.0
}

proc ns_to_time_units {value_ns} {
    global TIME_UNITS_PER_NS

    return [expr {$value_ns * $TIME_UNITS_PER_NS}]
}

proc report_clock_constraint_sanity {clock_name clk_period_ns} {
    set clocks [get_clocks -quiet $clock_name]
    if {[sizeof_collection $clocks] == 0} {
        return
    }

    set actual_period [get_attribute $clocks period]
    set expected_period [ns_to_time_units $clk_period_ns]

    puts [format "  CLOCK_SANITY(%s) requested_ns=%.3f expected_tu=%.2f actual_tu=%.2f" \
        $clock_name $clk_period_ns $expected_period $actual_period]

    # Guard against the exact failure mode we hit in the sorter sweeps: someone
    # requests a sub-ns clock, but the created period stays in raw ns-scale
    # values instead of the ps-scale units used by this DC environment.
    if {$clk_period_ns >= 0.1 && $actual_period < 10.0} {
        error [format \
            "Clock '%s' period sanity check failed: requested %.3f ns but created %.2f internal time units. This usually means nanoseconds were passed to create_clock without conversion." \
            $clock_name $clk_period_ns $actual_period]
    }
}

proc constraint_profile_name {} {
    global FAST_POC

    if {$FAST_POC} {
        return "fast_poc"
    }
    return "nominal"
}

proc effective_seq_io_delay_frac {} {
    global FAST_POC IO_DELAY_FRAC

    if {$IO_DELAY_FRAC >= 0.0} {
        return $IO_DELAY_FRAC
    }
    if {$FAST_POC} {
        return 0.0
    }
    return 0.1
}

proc effective_comb_io_delay {} {
    global FAST_POC COMB_IO_DELAY

    if {$COMB_IO_DELAY >= 0.0} {
        return $COMB_IO_DELAY
    }
    if {$FAST_POC} {
        return 0.0
    }
    return 0.2
}

proc effective_input_transition {} {
    global FAST_POC INPUT_TRANSITION_NS

    if {$INPUT_TRANSITION_NS >= 0.0} {
        return $INPUT_TRANSITION_NS
    }
    if {$FAST_POC} {
        return 0.01
    }
    return 0.03
}

proc effective_output_load {} {
    global FAST_POC OUTPUT_LOAD_PF

    if {$OUTPUT_LOAD_PF >= 0.0} {
        return $OUTPUT_LOAD_PF
    }
    if {$FAST_POC} {
        return 0.0
    }
    return 0.02
}

proc get_tier_package_file {tier} {
    global proj_root

    switch -- $tier {
        tiny   { return [file normalize "$proj_root/synthesis/configs/rst_pkg_tiny.sv"] }
        small  { return [file normalize "$proj_root/synthesis/configs/rst_pkg_small.sv"] }
        medium { return [file normalize "$proj_root/synthesis/configs/rst_pkg_medium.sv"] }
        large  { return [file normalize "$proj_root/synthesis/configs/rst_pkg_large.sv"] }
        default {
            error "Unknown RST tier '$tier' (expected tiny/small/medium/large)"
        }
    }
}

proc read_tiered_filelist {filelist tier} {
    global proj_root

    set filelist_path [file normalize "$proj_root/$filelist"]
    set tier_pkg_file [get_tier_package_file $tier]
    set sources {}

    set fp [open $filelist_path r]
    while {[gets $fp line] >= 0} {
        set trimmed [string trim $line]
        if {$trimmed eq "" || [string match "#*" $trimmed]} {
            continue
        }

        if {$trimmed eq "rst_pkg.sv"} {
            lappend sources $tier_pkg_file
        } else {
            lappend sources [file normalize "$proj_root/$trimmed"]
        }
    }
    close $fp

    return $sources
}

proc default_filelist_for_top {top_name} {
    switch -- $top_name {
        PageCompressorTop -
        PageDecompressorTop {
            return "m4_filelist.f"
        }
        default {
            return "m0_filelist.f"
        }
    }
}

proc top_is_sequential {top_name} {
    switch -- $top_name {
        DictSerializer -
        DictDeserializer -
        Matcher -
        Filter -
        Replacer -
        PriorityEncoder -
        SeqHasher -
        SeqSorter -
        SeqAggregator -
        BankGrouper {
            return 0
        }
        default {
            return 1
        }
    }
}

proc reuse_safe_top {top_name} {
    switch -- $top_name {
        BankGrouper -
        FIFO -
        HashTableBank -
        HashTableSubTable -
        LifoExpander -
        PriorityEncoder -
        ProgrammablePE -
        SeqAggregator -
        SeqHasher -
        SeqSorter -
        UpdatePipelineN {
            return 0
        }
        default {
            return 1
        }
    }
}

proc parse_reuse_manifest {manifest_path tier current_top} {
    set entries {}
    if {$manifest_path eq ""} {
        return $entries
    }

    set manifest_norm [file normalize $manifest_path]
    if {![file exists $manifest_norm]} {
        error "Reuse manifest '$manifest_norm' does not exist"
    }

    set fp [open $manifest_norm r]
    while {[gets $fp line] >= 0} {
        set trimmed [string trim $line]
        if {$trimmed eq "" || [string match "#*" $trimmed]} {
            continue
        }

        set fields [split $trimmed "\t"]
        if {[llength $fields] < 3} {
            continue
        }

        set top_name [string trim [lindex $fields 0]]
        set tier_name [string trim [lindex $fields 1]]
        set ddc_path [string trim [lindex $fields 2]]

        if {$top_name eq "top" && $tier_name eq "tier"} {
            continue
        }

        if {$top_name eq "" || $ddc_path eq ""} {
            continue
        }
        if {$top_name eq $current_top} {
            continue
        }
        if {![reuse_safe_top $top_name]} {
            puts "Warning: skipping reuse target $top_name because parameterized-module reuse is not parameter-aware yet"
            continue
        }
        if {$tier_name ne "" && $tier_name ne $tier} {
            continue
        }

        set ddc_norm [file normalize $ddc_path]
        if {![file exists $ddc_norm]} {
            puts "Warning: skipping reuse target $top_name because DDC is missing: $ddc_norm"
            continue
        }
        lappend entries [list $top_name $ddc_norm]
    }
    close $fp

    return $entries
}

proc preload_reuse_designs {reuse_entries} {
    foreach entry $reuse_entries {
        lassign $entry top_name ddc_path

        if {[sizeof_collection [get_designs -quiet $top_name]] > 0} {
            catch { remove_design $top_name }
        }
        puts "Reusing mapped design $top_name from $ddc_path"
        read_ddc $ddc_path
    }
}

proc protect_reuse_designs {reuse_entries} {
    foreach entry $reuse_entries {
        lassign $entry top_name ddc_path

        if {[sizeof_collection [get_designs -quiet $top_name]] > 0} {
            set design_obj [get_designs $top_name]
            catch { set_dont_touch $design_obj }
            catch { set_ungroup $design_obj false }
        }

        set insts [get_cells -hierarchical -quiet -filter "ref_name == $top_name"]
        if {[sizeof_collection $insts] > 0} {
            catch { set_dont_touch $insts }
            catch { set_ungroup $insts false }
        }
    }
}

# ============================================================================
# Design Compiler Settings for Combinational Circuits
# ============================================================================

# Prevent optimization of combinational logic
# This is critical for purely combinational circuits that might otherwise
# be optimized away entirely

# Set compile strategy
set compile_seqmap_propagate_constants false
set compile_seqmap_propagate_high_effort false

# Prevent constant propagation through the design (global setting)
set_optimize_registers false

# Additional settings to preserve logic
set compile_delete_unloaded_sequential_cells false
set compile_seqmap_identify_shift_registers false

# ============================================================================
# Constraints for Combinational Circuits
# ============================================================================

# For purely combinational modules, we need to set proper constraints
# to prevent the tool from optimizing everything away

proc setup_combinational_constraints {clk_period_ns} {
    set clk_period [ns_to_time_units $clk_period_ns]
    set io_delay [ns_to_time_units [effective_comb_io_delay]]
    set input_transition [ns_to_time_units [effective_input_transition]]
    set output_load [effective_output_load]

    # Preserve only the primary I/O networks so the cone can't be ripped out
    set_dont_touch_network [all_inputs]
    set_dont_touch_network [all_outputs]

    # Add a tiny timing context so DC maps real gates (not just 'assign')
    create_clock -name fake_clk -period $clk_period
    report_clock_constraint_sanity fake_clk $clk_period_ns
    set_input_delay  $io_delay -clock fake_clk [all_inputs]
    set_output_delay $io_delay -clock fake_clk [all_outputs]

    # Reasonable slews/loads for stability
    set_input_transition $input_transition [all_inputs]
    set_load             $output_load [all_outputs]
}

# ============================================================================
# Constraints for Sequential Circuits
# ============================================================================

proc setup_sequential_constraints {clk_period_ns} {
    set clk_period [ns_to_time_units $clk_period_ns]
    set io_delay_frac [effective_seq_io_delay_frac]
    set input_transition [ns_to_time_units [effective_input_transition]]
    set output_load [effective_output_load]

    # Create clock
    if {[sizeof_collection [get_ports clk]] > 0} {
        create_clock -name clk -period $clk_period [get_ports clk]
        report_clock_constraint_sanity clk $clk_period_ns

        set data_inputs [all_inputs]
        set clock_ports [get_ports clk]
        if {[sizeof_collection $clock_ports] > 0} {
            set data_inputs [remove_from_collection $data_inputs $clock_ports]
        }
        set reset_ports [get_ports -quiet {rst reset}]
        if {[sizeof_collection $reset_ports] > 0} {
            set data_inputs [remove_from_collection $data_inputs $reset_ports]
        }

        # Set input/output delays
        if {[sizeof_collection $data_inputs] > 0} {
            set_input_delay -clock clk [expr {$clk_period * $io_delay_frac}] $data_inputs
            set_input_transition $input_transition $data_inputs
        }
        set_output_delay -clock clk [expr {$clk_period * $io_delay_frac}] [all_outputs]

        # Don't optimize away reset
        if {[sizeof_collection $reset_ports] > 0} {
            set_dont_touch $reset_ports
        }

        # Reasonable slews/loads for stability
        set_load $output_load [all_outputs]
    }
}

# ============================================================================
# Report Generation
# ============================================================================

proc generate_reports {output_dir design_name} {
    file mkdir $output_dir

    # Area report
    set area_file "${output_dir}/${design_name}_area.rpt"
    redirect $area_file {
        report_area -hierarchy
        report_area -designware
    }
    puts "Area report written to $area_file"

    # Timing report
    set timing_file "${output_dir}/${design_name}_timing.rpt"
    redirect $timing_file {
        report_units
        report_timing -max_paths 10 -transition_time -nets -attributes
        report_timing -delay min -max_paths 5
    }
    puts "Timing report written to $timing_file"

    # QoR report
    set qor_file "${output_dir}/${design_name}_qor.rpt"
    redirect $qor_file { report_qor }
    puts "QoR report written to $qor_file"

    # Reference report
    set ref_file "${output_dir}/${design_name}_reference.rpt"
    redirect $ref_file { report_reference }
    puts "Reference report written to $ref_file"

    # Constraint report
    set constraint_file "${output_dir}/${design_name}_constraints.rpt"
    redirect $constraint_file {
        report_units
        report_constraint -all_violators
        report_design
    }
    puts "Constraint report written to $constraint_file"
}

# ============================================================================
# Compilation Settings
# ============================================================================

# Default compile command with appropriate settings
proc compile_design {sequential} {
    global COMPILE_MODE

    if {![info exists COMPILE_MODE]} {
        set COMPILE_MODE compile
    }

    switch -- $COMPILE_MODE {
        compile {
            puts "Running compile command: compile"
            compile
        }
        ultra {
            puts "Running compile command: compile_ultra"
            compile_ultra
        }
        ultra_no_autoungroup {
            puts "Running compile command: compile_ultra -no_autoungroup"
            compile_ultra -no_autoungroup
        }
        ultra_retime {
            puts "Running compile command: compile_ultra -retime"
            compile_ultra -retime
        }
        ultra_retime_no_autoungroup {
            puts "Running compile command: compile_ultra -retime -no_autoungroup"
            compile_ultra -retime -no_autoungroup
        }
        default {
            error "Unknown COMPILE_MODE '$COMPILE_MODE'"
        }
    }
}

puts "Common synthesis setup loaded"
puts "Available procedures:"
puts "  - setup_combinational_constraints"
puts "  - setup_sequential_constraints <clk_period>"
puts "  - get_tier_package_file <tier>"
puts "  - read_tiered_filelist <filelist> <tier>"
puts "  - default_filelist_for_top <top_name>"
puts "  - top_is_sequential <top_name>"
puts "  - generate_reports <output_dir> <design_name>"
puts "  - compile_design <sequential>"
