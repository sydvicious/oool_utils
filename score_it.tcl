#!/usr/bin/tclsh

lappend auto_path [file dirname [info script]]
package require property_utils 1.0

set owners {}
set score_file [open "Scores.tab"]
set contents [read $score_file]
set roster_items [split $contents \n]
foreach item $roster_items {
  global owners
  set item_list [split $item \t]
  set owner [lindex $item_list 0]
  if {[string equal $owner ""]} {
    continue
  }
  if {[lsearch -exact $owners $owner] == -1} {
    lappend owners $owner
  }
  set player [lindex $item_list 1]
  set statsid [lindex $item_list 2]
  set_property $player StatsID $statsid
  set sydid [lindex $item_list 3]
  set_property $player SydID $sydid
  set position [lindex $item_list 4]
  set backups [lindex $item_list 5]
  if {[string equal $position "IR"]} {
    set ir_list [get_property $owner "IR"]
    lappend ir_list $player
    set_property $owner "IR" $ir_list
  } else {
    set_property $owner $position $player
  }

  set batting_scores {}
  foreach i {6 7 8 9 10 11 12 13 14 15 16 17 18 19} {
    set score [lindex $item_list $i]
    if {![string equal $score {}]} {
      lappend batting_scores $score
    }
  }
  
  set starting_scores {}
  foreach start {20 21 22 23 24 25 26} {
    set score [lindex $item_list $start]
    if {$score != ""} {
      lappend starting_scores $score
    }
  }

  # Check for Monday/Tuesday start with no Saturday/Sunday start
  set monday [lindex $item_list 20]
  set tuesday [lindex $item_list 21]
  set saturday [lindex $item_list 25]
  set sunday [lindex $item_list 26]
  if {$monday != ""} {
    if {$saturday == "" && $sunday == ""} {
      puts stderr "$owner: $player $statsid has a Monday starting score $monday, but no Saturday or Sunday score."
    }
  }
  if {$tuesday != ""} {
    if {$saturday == "" && $sunday == ""} {
      puts stderr "$owner: $player $statsid has a Tuesday starting score $tuesday, but no Saturday or Sunday score."
    }
  }

  set relief_scores {}
  foreach relief {27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43} {
    set score [lindex $item_list $relief]
    if {$score != ""} {
      lappend relief_scores $score
    }
  }
  
  set batting_scores [lsort -integer -decreasing $batting_scores]
  set_property $player "backups" $backups
  set_property $player "batting" $batting_scores
  set starting_scores [lsort -integer -decreasing $starting_scores]
  set relief_scores [lsort -integer -decreasing $relief_scores]
  set_property $player "starting" $starting_scores
  set_property $player "relief" $relief_scores
}

proc process_normal_position {owner position} {
  set player [get_property $owner $position]
  set backups [split [get_property $player "backups"] {,}]
  set scores [get_property $player "batting"]
  set scores_needed [expr 7 - [llength $scores]]
  if {$scores_needed > 0} {
    foreach backup $backups {
      set backup_player [get_property $owner "B$backup"]
      set backup_scores [get_property $backup_player "batting"]
      set backup_score_count [llength $backup_scores]
      if {$backup_score_count < $scores_needed} {
	set size $backup_score_count
      } else {
	set size $scores_needed
      }
      set used_scores [lrange $backup_scores 0 [expr $size - 1]]
      set scores [lsort -integer -decreasing [concat $scores $used_scores]]
      set backup_scores [lrange $backup_scores $size end]
      set_property $backup_player "batting" $backup_scores
      set scores_needed [expr $scores_needed - $size]
      if {$scores_needed <= 0} {
	break
      }
    }
  }
  set scores [lrange $scores 0 4]
  set total 0
  foreach score $scores {
    incr total $score
  }
  set outstring [format "%3s %-30s %3s" $position $scores $total]
  puts $outstring

  return $total
}

proc comp_outfield_score {a b} {
  set score1 [lindex $a 0]
  set score2 [lindex $b 0]
  if {$score1 < $score2} {
    return -1
  } elseif {$score1 > $score2} {
    return 1
  }
  return 0
}

proc process_outfield {owner} {
  set player1 [get_property $owner "OF1"]
  set player2 [get_property $owner "OF2"]
  set player3 [get_property $owner "OF3"]
  set backup_list [split [get_property $player1 "backups"] {,}]
  set outfield_list {}
  foreach backup_item $backup_list {
    set backup [get_property $owner "B$backup_item"]
    set backup_scores [get_property $backup "batting"]
    foreach score $backup_scores {
      lappend outfield_list [list $score $backup]
    }
  }
  set outfield_list [lsort -decreasing -command comp_outfield_score $outfield_list]
  
  set total 0
  
  foreach position [list OF1 OF2 OF3] {
    set current_score 0
    set player [get_property $owner $position]
    set scores [get_property $player "batting"]
    set scores_needed [expr 7 - [llength $scores]]
    while {($scores_needed > 0) && [llength $outfield_list] > 0} {
      set element [lindex $outfield_list 0]
      set outfield_list [lrange $outfield_list 1 end]
      incr scores_needed -1
      lappend scores [lindex $element 0]
      set backup [lindex $element 1]
      set backup_scores [lrange [get_property $backup "batting"] 1 end]
      set_property $backup "batting" $backup_scores
    }
    set scores [lrange [lsort -integer -decreasing $scores] 0 4]
    foreach score $scores {
      incr current_score $score
    }
    set outstring [format "%3s %-30s %3s" $position $scores $current_score]
    puts $outstring
    incr total $current_score
  }
  return $total
}

proc process_starting_pitching {owner} {
  set swing_starts {}
  foreach swing {SW1 SW2 SW3 SW4 SW5 SW6 SW7 SW8} {
    set pitcher [get_property $owner $swing]
    if {[string equal $pitcher {}]} {
      continue
    }
    set individual_starts [get_property $pitcher "starting"]
    if {[llength $individual_starts] > 0} {
      set outstring [format "%3s %-7s" $swing $individual_starts]
      puts $outstring

      lappend swing_starts [lindex $individual_starts 0]
    }
  }
  set swing_starts [lsort -integer -decreasing $swing_starts]

  set total 0
  set starts {}
  foreach pos {SP1 SP2 SP3 SP4 SP5} {
    set pitcher [get_property $owner $pos]
    set individual_starts [get_property $pitcher "starting"]
    set outstring [format "%3s %-7s" $pos $individual_starts]
    puts $outstring
    set num [llength $individual_starts]
    if {$num != 0} {
      set start [lindex $individual_starts 0]
      lappend starts $start
    }
  }
  set starts [lsort -integer -increasing $starts]
  
  set num_starts [llength $starts]
  set num_swing_starts [llength $swing_starts]
  if {$num_starts == 0 && $num_swing_starts == 0} {
    return 0
  }
  set new_starts {}
  set blank_starts [expr 5 - $num_starts]
  
  if {$blank_starts > 0} {
    set filler_starts [lrange $swing_starts 0 [expr $blank_starts - 1]]
    if {[llength $filler_starts] > 0} {
      eval lappend starts $filler_starts
    }
    set swing_starts [lrange $swing_starts $blank_starts end]
    set starts [lsort -integer -increasing $starts]
    set num_starts [llength $starts]
    set num_swing_starts [llength $swing_starts]
  }
  
  for {set i 0} {$i < $num_starts} {incr i} {
    set start [lindex $starts $i]
    if {$num_swing_starts == 0 || $start > 0} {
      lappend new_starts $start
    } else {
      set swing_start [lindex $swing_starts 0]
      if {$start > $swing_start} {
	lappend new_starts $start
      } else {
	lappend new_starts $swing_start
	set swing_starts [lrange $swing_starts 1 end]
	set num_swing_starts [llength $swing_starts]
      }
    }
  }

  set starts [lsort -integer -increasing $new_starts]
  if {[llength $starts] > 0} {
    foreach start $starts {
      incr total $start
    }
  }
  puts "Starts - $starts"
  return $total
}

proc process_relief_pitching {owner} {
  set total 0
  set scores {}
  foreach pos {RP1 RP2 RP3 SW1 SW2 SW3 SW4 SW5 SW6 SW7 SW8} {
    set pitcher [get_property $owner $pos]
    if {[string equal $pitcher {}]} {
      continue
    }
    set individual_scores [get_property $pitcher "relief"]
    set scores [concat $scores $individual_scores]
    if {[llength $individual_scores] > 0} {
      set outstring [format "%3s %-27s" $pos $individual_scores]
      puts $outstring
    }
  }
  set scores [lsort -integer -decreasing $scores]
  set num [llength $scores]
  if {$num > 5} {
    set new_scores [lrange $scores 0 4]
    set extra_scores [lrange $scores 5 end]
    set num_extras [llength $extra_scores]
    while {$num_extras > 0} {
      set new_score [lindex $extra_scores 0]
      if {$new_score < 0} {
	break
      }
      lappend new_scores $new_score
      set extra_scores [lrange $extra_scores 1 end]
      incr num_extras -1
    }
    set scores $new_scores
  }
  set scores [lrange $scores 0 9]
  puts "Relief - $scores"
  foreach score $scores {
    incr total $score
  }
  return $total
}

proc output_roster_with_scores owner {
  puts "$owner:"
  puts ""
  puts "Offense:"
  puts ""

  set outstring [format {%3s %5s %-30s %-14s %s} "POS" "ID" "LAST_FIRST/TEAM" "BACKUPS" "SCORES"]
  puts $outstring
  puts "=== ===== ============================== ============= ===================="
  foreach position {"C" "1B" "2B" "3B" "SS" "OF1" "OF2" "OF3" "DH"} {
    set player [get_property $owner $position]
    set statsid [get_property $player "StatsID"]
    if {[string equal $statsid ""]} {
      set statsid "****"
    }
    set backups [get_property $player "backups"]
    set scores [get_property $player "batting"]
    if {[string equal $scores ""]} {
      puts stderr "$owner: $position $statsid $player has no batting scores."
    }
    
    set outstring [format {%3s %5s %-30s %-14s %s} $position $statsid $player $backups $scores]
    puts $outstring
    
    # Set backup position strings
    if {[string equal $position "OF2"] || [string equal $position "OF3"]} {
      continue
    }
    set backup_list [split $backups ","]

    foreach backup $backup_list {
	# Split list apart
	set backup_player [get_property $owner B$backup]
	set backup_positions [get_property $backup_player backup_positions]
	if {![string equal $backup_positions ""]} {
	  append backup_positions ","
	}
	if {[string equal $position "OF1"]} {
	  append backup_positions "OF"
	} else {
	  append backup_positions $position
	}
	set_property $backup_player backup_positions $backup_positions
    }
  }
  puts ""
  
  foreach position {"B1" "B2" "B3" "B4" "B5" "B6" "B7" "B8"} {
    set player [get_property $owner $position]
    if {![string equal $player ""] } {
      set statsid [get_property $player "StatsID"]
      if {[string equal $statsid ""]} {
	set statsid "****"
      }
      set backup_positions [get_property $player "backup_positions"]
      set scores [get_property $player "batting"]

      if {[string equal $scores ""]} {
	puts stderr "$owner: $position $statsid $player has no batting scores."
      }
      
      set outstring [format {%3s %5s %-30s %-14s %s} $position $statsid $player $backup_positions $scores]
      puts $outstring
    }
  }
  
  set bench_scores 0
  set ir_list [get_property $owner "IR"]
  foreach player $ir_list {
    set scores [get_property $player "batting"]
    if {$scores == ""} {
      continue
    }
    if {!$bench_scores} {
      puts ""
      incr bench_scores
    }
    set statsid [get_property $player "StatsID"]
    if {[string equal $statsid ""]} {
      set statsid "****"
    }
    set outstring [format {%3s %5s %-30s %-14s %s} "IR" $statsid $player "" $scores]
    puts $outstring
  }
  
  puts ""

  puts "STARTING PITCHING:"
  puts ""
  set outstring [format {%3s %5s %-30s %s} "POS" "ID" "LAST_FIRST/TEAM" "SCORES"]
  puts $outstring
  puts "=== ===== ============================== ===================="
  
  foreach position {"SP1" "SP2" "SP3" "SP4" "SP5" "SW1" "SW2" "SW3" "SW4" "SW5" "SW6" "SW7" "SW8"} {
    set pitcher [get_property $owner $position]
    if {![string equal $pitcher ""]} {
      set statsid [get_property $pitcher "StatsID"]
      if {[string equal $statsid ""]} {
	set statsid "****"
      }
      set scores [get_property $pitcher "starting"]
      
      set second_char [string range $position 1 1]
      if {[string equal $second_char "P"] && [string equal $scores ""]} {
	puts stderr "$owner: $position $statsid $pitcher has no starting scores."
      }
      if {[string equal $second_char "W"] && [string equal $scores ""]} {
	set relief_scores [get_property $pitcher "relief"]
	if {[string equal $relief_scores ""]} {
	  puts stderr "$owner: $position $statsid $pitcher has no pitching scores."
	}
      }
      
      set outstring [format {%3s %5s %-30s %s} $position $statsid $pitcher $scores]
      puts $outstring
    }
  }
  
  set bench_scores 0  
  foreach player $ir_list {
    set scores [get_property $player "starting"]
    if {$scores == ""} {
      continue
    }
    if {!$bench_scores} {
      puts ""
      incr bench_scores
    }
    set statsid [get_property $player "StatsID"]
    if {[string equal $statsid ""]} {
      set statsid "****"
    }
    set outstring [format {%3s %5s %-30s %s} "IR" $statsid $player $scores]
    puts $outstring
  }
  
  puts ""
  
  puts "RELIEF PITCHING:"
  puts ""
  
  foreach position {"RP1" "RP2" "RP3" "SW1" "SW2" "SW3" "SW4" "SW5" "SW6" "SW7" "SW8"} {
    set pitcher [get_property $owner $position]
    if {![string equal $pitcher ""]} {
      set statsid [get_property $pitcher "StatsID"]
      if {[string equal $statsid ""]} {
	set statsid "****"
      }
      set scores [get_property $pitcher "relief"]
      set outstring [format {%3s %5s %-30s %s} $position $statsid $pitcher $scores]
      puts $outstring
    }
  }


  set bench_scores 0  
  foreach player $ir_list {
    set scores [get_property $player "relief"]
    if {$scores == ""} {
      continue
    }
    if {!$bench_scores} {
      puts ""
      incr bench_scores
    }
    set statsid [get_property $player "StatsID"]
    if {[string equal $statsid ""]} {
      set statsid "****"
    }
    set outstring [format {%3s %5s %-30s %s} "IR" $statsid $player $scores]
    puts $outstring
  }
  
  puts ""
  
}

set week_standings_list {}

foreach owner $owners {

# First, output the roster with scores
  output_roster_with_scores $owner

  set offense 0

  set outstring [format "%3s %-30s %3s" "POS" "SCORES" "SUBTOTAL"]
  puts $outstring
  puts "=== ============================== ==="
  puts ""
  
# Infield
  foreach position {"C" "1B" "2B" "3B" "SS"} {
    incr offense [process_normal_position $owner $position]
  }
  
# outfield
  incr offense [process_outfield $owner]

# dh
  incr offense [process_normal_position $owner "DH"]
  puts ""
  puts "TOTAL OFFENSE - $offense"
  puts ""

# starters

  set outstring [format "%3s %3s" "POS" "SCORES"]
  puts $outstring
  puts ""
  
  set starting_pitching [process_starting_pitching $owner]
  puts ""
  puts "STARTING PITCHING - $starting_pitching"
  puts ""

# relievers
  set outstring [format "%3s %3s" "POS" "SCORES"]
  puts $outstring
  puts ""

  set relief_pitching [process_relief_pitching $owner]
  puts ""
  puts "RELIEF PITCHING - $relief_pitching"
  puts ""
  
# total
  set total [expr $offense + $starting_pitching + $relief_pitching]
  puts "** TOTAL FOR $owner - $offense + $starting_pitching + $relief_pitching = $total"
  puts ""
  
  lappend week_standings_list [list $owner $total]
}

proc sort_standings {owner1 owner2} {
  set score1 [lindex $owner1 1]
  set score2 [lindex $owner2 1]
  if {$score1 < $score2} {
    return 1
  } elseif {$score1 > $score2} {
    return 0
  } else {
    return [expr -[string compare [lindex $owner1 0] [lindex $owner2 0]]]
  }
}

set week_standings_list [lsort -command sort_standings $week_standings_list]

puts "Standings:"
foreach pair $week_standings_list {
  puts $pair
}