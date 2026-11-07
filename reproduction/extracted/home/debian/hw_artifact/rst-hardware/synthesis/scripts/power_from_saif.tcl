# Power signoff helper for mapped top artifacts.
#
# Required variables before sourcing:
#   TOP
#   DDC_FILE
#   SDC_FILE
#   OUTPUT_DIR
#
# Optional variables:
#   POWER_MODE         activity | clock_only | zero_toggle   (default: activity)
#   OUTPUT_TAG         output file suffix       (default: power)
#   SAIF_FILE          SAIF to annotate for activity mode
#   SAIF_INSTANCE_NAME preferred SAIF instance path or name
#   SAIF_STRIP_PATH    alternate SAIF instance path or name to try
#   SAIF_IGNORE_NAMES             SAIF object names to remove before reading (default: {clk})
#   FORCE_SDC_CLOCK_ACTIVITY      1 to override root clock activity from SDC after SAIF read (default: 0)
#   INCLUDE_REG_CLOCK_PIN_POWER   1 to keep register clock-pin internal power in clock_network (default: 0)
#   PYTHON_BIN                    Python executable for SAIF preprocessing (default: python3)

set power_script_dir [file dirname [file normalize [info script]]]
source [file join $power_script_dir common_setup.tcl]

if {![info exists TOP] || $TOP eq ""} {
    error "TOP must be set"
}
if {![info exists DDC_FILE] || $DDC_FILE eq ""} {
    error "DDC_FILE must be set"
}
if {![info exists SDC_FILE] || $SDC_FILE eq ""} {
    error "SDC_FILE must be set"
}
if {![info exists OUTPUT_DIR] || $OUTPUT_DIR eq ""} {
    error "OUTPUT_DIR must be set"
}
if {![info exists POWER_MODE]} {
    set POWER_MODE activity
}
if {![info exists OUTPUT_TAG]} {
    set OUTPUT_TAG power
}
if {![info exists SAIF_FILE]} {
    set SAIF_FILE ""
}
if {![info exists SAIF_INSTANCE_NAME]} {
    set SAIF_INSTANCE_NAME $TOP
}
if {![info exists SAIF_STRIP_PATH]} {
    set SAIF_STRIP_PATH ""
}
if {![info exists SAIF_IGNORE_NAMES]} {
    set SAIF_IGNORE_NAMES {clk}
}
if {![info exists FORCE_SDC_CLOCK_ACTIVITY]} {
    set FORCE_SDC_CLOCK_ACTIVITY 0
}
if {![info exists INCLUDE_REG_CLOCK_PIN_POWER]} {
    set INCLUDE_REG_CLOCK_PIN_POWER 0
}
if {![info exists PYTHON_BIN]} {
    set PYTHON_BIN python3
}

set DDC_FILE [file normalize $DDC_FILE]
set SDC_FILE [file normalize $SDC_FILE]
set OUTPUT_DIR [file normalize $OUTPUT_DIR]
if {$SAIF_FILE ne ""} {
    set SAIF_FILE [file normalize $SAIF_FILE]
}

file mkdir $OUTPUT_DIR

proc normalize_list_value {value} {
    if {$value eq ""} {
        return {}
    }
    return $value
}

proc unique_nonempty_append {items_var value} {
    upvar 1 $items_var items

    if {$value eq ""} {
        return
    }
    if {[lsearch -exact $items $value] < 0} {
        lappend items $value
    }
}

proc tail_instance_name {value} {
    if {$value eq ""} {
        return ""
    }
    if {[string first "/" $value] < 0} {
        return $value
    }
    return [lindex [split $value "/"] end]
}

proc build_saif_instance_candidates {instance_name strip_path top_name} {
    set candidates {}

    unique_nonempty_append candidates $instance_name
    unique_nonempty_append candidates [tail_instance_name $instance_name]
    unique_nonempty_append candidates $strip_path
    unique_nonempty_append candidates [tail_instance_name $strip_path]
    unique_nonempty_append candidates $top_name
    lappend candidates ""
    return $candidates
}

proc read_text_file {path} {
    if {![file exists $path]} {
        return ""
    }
    set fp [open $path r]
    set text [read $fp]
    close $fp
    return $text
}

proc prepare_saif_file {saif_file ignore_names output_dir output_tag python_bin script_dir} {
    set ignore_names [normalize_list_value $ignore_names]
    if {[llength $ignore_names] == 0} {
        return $saif_file
    }

    set sanitizer_script [file join $script_dir filter_saif.py]
    set sanitized_file "${output_dir}/${output_tag}_sanitized.saif"
    set cmd [list exec $python_bin $sanitizer_script --input $saif_file --output $sanitized_file]
    foreach ignore_name $ignore_names {
        lappend cmd --strip-name $ignore_name
    }

    puts "Preparing sanitized SAIF with: $cmd"
    if {[catch {eval $cmd} err]} {
        error "Failed to sanitize SAIF '$saif_file': $err"
    }
    return $sanitized_file
}

proc try_read_saif {saif_file instance_candidates ignore_names output_dir output_tag} {
    set last_err ""
    set attempt_index 0

    foreach instance_name $instance_candidates {
        incr attempt_index
        catch {reset_switching_activity}

        if {$instance_name eq ""} {
            set cmd [list read_saif -input $saif_file]
            set label "<root>"
        } else {
            set cmd [list read_saif -input $saif_file -instance_name $instance_name]
            set label $instance_name
        }
        lappend cmd -verbose

        set saif_log_file "${output_dir}/${output_tag}_saif_attempt${attempt_index}.log"
        file delete -force $saif_log_file

        puts "Trying SAIF annotation command: $cmd"
        set rc [catch {redirect $saif_log_file { eval $cmd }} err]
        set saif_log [read_text_file $saif_log_file]
        if {$saif_log ne ""} {
            puts $saif_log
        }

        if {$rc} {
            puts "SAIF annotation attempt failed: $err"
            set last_err $err
            continue
        }
        if {[string match "*PWR-362*" $saif_log] || [string match "*No switching activity has been annotated*" $saif_log]} {
            puts "SAIF annotation attempt produced no annotated activity for instance '$label'"
            set last_err "No switching activity annotated for '$label'"
            continue
        }

        set final_log_file "${output_dir}/${output_tag}_saif_annotation.log"
        file copy -force $saif_log_file $final_log_file

        if {[llength [info commands report_saif]] > 0} {
            set saif_report_file "${output_dir}/${output_tag}_saif_summary.rpt"
            catch {redirect $saif_report_file { report_saif }}
        }

        puts "SAIF annotation succeeded with instance '$label'"
        return
    }

    error "Failed to annotate SAIF '$saif_file': $last_err"
}

proc apply_zero_toggle_activity {} {
    catch {reset_switching_activity}

    set clk_ports [get_ports -quiet clk]
    if {[sizeof_collection $clk_ports] > 0} {
        catch {set_switching_activity -static_probability 0.0 -toggle_rate 0.0 $clk_ports}
    }

    set data_inputs [all_inputs]
    if {[sizeof_collection $clk_ports] > 0} {
        set data_inputs [remove_from_collection $data_inputs $clk_ports]
    }
    if {[sizeof_collection $data_inputs] > 0} {
        catch {set_switching_activity -static_probability 0.0 -toggle_rate 0.0 $data_inputs}
    }
}

proc apply_zero_data_activity {} {
    catch {reset_switching_activity}

    set clk_ports [get_ports -quiet clk]
    set data_inputs [all_inputs]
    if {[sizeof_collection $clk_ports] > 0} {
        set data_inputs [remove_from_collection $data_inputs $clk_ports]
    }
    if {[sizeof_collection $data_inputs] > 0} {
        catch {set_switching_activity -static_probability 0.0 -toggle_rate 0.0 $data_inputs}
    }
}

proc configure_clock_power_accounting {include_reg_clock_pin_power} {
    if {[catch {
        set_app_var power_clock_network_include_register_clock_pin_power $include_reg_clock_pin_power
    } err]} {
        puts "Warning: could not set power_clock_network_include_register_clock_pin_power: $err"
    } else {
        puts "Configured power_clock_network_include_register_clock_pin_power = $include_reg_clock_pin_power"
    }
}

proc override_root_clock_activity_from_sdc {} {
    set clk_ports [get_ports -quiet clk]
    if {[sizeof_collection $clk_ports] == 0} {
        puts "No top-level clk port found; skipping SDC clock activity override"
        return
    }

    set clk_objs [get_clocks -quiet clk]
    if {[sizeof_collection $clk_objs] == 0} {
        puts "No clock object named 'clk' found; skipping SDC clock activity override"
        return
    }

    set clk_period [get_attribute $clk_objs period]
    if {[llength $clk_period] > 1} {
        set clk_period [lindex $clk_period 0]
    }
    if {$clk_period eq "" || $clk_period <= 0} {
        puts "Clock 'clk' has invalid period '$clk_period'; skipping SDC clock activity override"
        return
    }

    set toggle_rate [expr {2.0 / double($clk_period)}]
    puts [format "Overriding root clock activity from SDC: clk period=%s time_units, toggle_rate=%0.6f" \
        $clk_period $toggle_rate]

    if {![catch {
        reset_switching_activity -switching_activity $clk_ports
    } err]} {
        puts "Cleared existing switching activity on [get_object_name $clk_ports]"
    } else {
        puts "Warning: failed to clear clock port switching activity: $err"
    }

    if {![catch {
        set_switching_activity -static_probability 0.5 -toggle_rate 2.0 -period $clk_period $clk_ports
    } err]} {
        puts "Applied SDC-derived activity to [get_object_name $clk_ports]"
    } else {
        puts "Warning: failed to override root clock activity from SDC: $err"
    }

    set clk_nets [get_nets -quiet clk]
    if {[sizeof_collection $clk_nets] > 0} {
        if {![catch {
            reset_switching_activity -switching_activity $clk_nets
        } err]} {
            puts "Cleared existing switching activity on [get_object_name $clk_nets]"
        } else {
            puts "Warning: failed to clear clock net switching activity: $err"
        }

        if {![catch {
            set_switching_activity -static_probability 0.5 -toggle_rate 2.0 -period $clk_period $clk_nets
        } err]} {
            puts "Applied SDC-derived activity to [get_object_name $clk_nets]"
        } else {
            puts "Warning: failed to override clock net activity from SDC: $err"
        }
    }
}

puts "Power signoff configuration:"
puts "  TOP                = $TOP"
puts "  DDC_FILE           = $DDC_FILE"
puts "  SDC_FILE           = $SDC_FILE"
puts "  OUTPUT_DIR         = $OUTPUT_DIR"
puts "  POWER_MODE         = $POWER_MODE"
puts "  OUTPUT_TAG         = $OUTPUT_TAG"
puts "  SAIF_FILE          = $SAIF_FILE"
puts "  SAIF_INSTANCE_NAME = $SAIF_INSTANCE_NAME"
puts "  SAIF_STRIP_PATH    = $SAIF_STRIP_PATH"
puts "  SAIF_IGNORE_NAMES  = $SAIF_IGNORE_NAMES"
puts "  FORCE_SDC_CLOCK_ACTIVITY    = $FORCE_SDC_CLOCK_ACTIVITY"
puts "  INCLUDE_REG_CLOCK_PIN_POWER = $INCLUDE_REG_CLOCK_PIN_POWER"
puts "  PYTHON_BIN         = $PYTHON_BIN"

read_ddc $DDC_FILE
current_design $TOP
link
read_sdc $SDC_FILE
current_design $TOP
configure_clock_power_accounting $INCLUDE_REG_CLOCK_PIN_POWER

switch -- $POWER_MODE {
    activity {
        if {$SAIF_FILE eq ""} {
            error "SAIF_FILE must be set when POWER_MODE=activity"
        }
        set prepared_saif [prepare_saif_file $SAIF_FILE $SAIF_IGNORE_NAMES $OUTPUT_DIR $OUTPUT_TAG $PYTHON_BIN $power_script_dir]
        set saif_candidates [build_saif_instance_candidates $SAIF_INSTANCE_NAME $SAIF_STRIP_PATH $TOP]
        puts "  SAIF_INSTANCE_CANDIDATES = $saif_candidates"
        try_read_saif $prepared_saif $saif_candidates {} $OUTPUT_DIR $OUTPUT_TAG
        if {$FORCE_SDC_CLOCK_ACTIVITY} {
            override_root_clock_activity_from_sdc
        }
    }
    clock_only {
        apply_zero_data_activity
        if {$FORCE_SDC_CLOCK_ACTIVITY} {
            override_root_clock_activity_from_sdc
        }
    }
    zero_toggle {
        apply_zero_toggle_activity
    }
    default {
        error "Unknown POWER_MODE '$POWER_MODE' (expected activity, clock_only, or zero_toggle)"
    }
}

set summary_file "${OUTPUT_DIR}/${OUTPUT_TAG}_summary.rpt"
set hierarchy_file "${OUTPUT_DIR}/${OUTPUT_TAG}_hierarchy.rpt"

redirect $summary_file { report_power }
redirect $hierarchy_file { report_power -hierarchy }

puts "Wrote:"
puts "  $summary_file"
puts "  $hierarchy_file"
quit
