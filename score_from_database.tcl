#!/usr/bin/tclsh

lappend auto_path [file dirname [info script]]
package require mysqltcl
package require property_utils

set strict_get_property 1

set debug 0
set output_all_weeks 0
set output_current_week 1
set weeks ""

foreach arg $argv {
  if {[string equal $arg "--debug"]} {
    set debug 1
  } elseif {[string equal $arg "--output-all-weeks"]} {
    set output_all_weeks 1
  } elseif {[string equal $arg "--standings-only"]} {
    set output_current_week 0
  } else {
    set weeks $arg
  }
}

if {$debug} {
  set mysql_host "localhost"
} else {
  set mysql_host "rotowatch.rotowatch.com"
}

set db [::mysql::connect -host $mysql_host -user oool -password scoring -db oool]

::mysql::exec $db {DROP TABLE ScoringWeeks;}
::mysql::exec $db {CREATE TABLE IF NOT EXISTS ScoringWeeks (weekid INT, owner VARCHAR(255), battingpoints INT, startingpoints INT, reliefpoints INT, total INT);}

if {[string equal $weeks ""]} {
  set weeks [::mysql::sel $db {SELECT DISTINCT weekID from RosterItems ORDER BY weekid} -list]
}

set current_week [lindex [lsort -decreasing -integer $weeks] 0]

set owners [::mysql::sel $db {SELECT DISTINCT Owner from RosterItems ORDER BY Owner} -list]

proc get_database_data {week} {
  global db
  
  # First, get all of the normal roster players.
  
  set data [::mysql::sel $db "SELECT Owner, position, lastname, firstname, team, sydID, statsID, backups from RosterItems where weekID = '$week' and position <> 'IR'" -flatlist]
  foreach {owner position lastname firstname team sydID statsID backups} $data {
    set_property $owner-$week $position $sydID
    set player [generate_woolner_id $lastname $firstname $team]
    set_property $sydID-$week "player" $player
    set_property $sydID-$week "backups" $backups
    set_property $sydID "statsID" $statsID
  }


  # Then, get all of the reservers
  
  set data [::mysql::sel $db "SELECT Owner, lastname, firstname, team, sydID, statsID from RosterItems where weekID = '$week' and position = 'IR'" -flatlist]
  foreach {owner lastname firstname team sydID statsID} $data {
    set reserves [get_property $owner-$week "IR"]
    lappend reserves $sydID
    set_property $owner-$week "IR" $reserves
    set player [generate_woolner_id $lastname $firstname $team]
    set_property $sydID-$week "player" $player
    set_property $sydID "statsID" $statsID
  }

  # Get batting scores
  
  set db_scores [::mysql::sel $db "SELECT sydID, battingpoints from RosterItems, week, playerpoints where RosterItems.statsID = playerpoints.playerID and week.weekid = '$week' and week.weekid = RosterItems.weekid and playerdate >= start and playerdate <= end" -flatlist]
  foreach {sydID score} $db_scores {
    set scores [get_property $sydID-$week "batting"]
    lappend scores $score
    set scores [lsort -decreasing -integer $scores]
    set_property $sydID-$week "batting" $scores
  }
  
  # Get starting scores
  
  set db_scores [::mysql::sel $db "SELECT sydID, startingpoints from RosterItems, week, playerpoints where RosterItems.statsID = playerpoints.playerID and week.weekid = '$week' and week.weekid = RosterItems.weekid and playerdate >= start and playerdate <= end" -flatlist]
  foreach {sydID score} $db_scores {
    set scores [get_property $sydID-$week "starting"]
    lappend scores $score
    set scores [lsort -decreasing -integer $scores]
    set_property $sydID-$week "starting" $scores
  }

  # Get relief scores
  
  set db_scores [::mysql::sel $db "SELECT sydID, reliefpoints from RosterItems, week, playerpoints where RosterItems.statsID = playerpoints.playerID and week.weekid = '$week' and week.weekid = RosterItems.weekid and playerdate >= start and playerdate <= end" -flatlist]
  foreach {sydID score} $db_scores {
    set scores [get_property $sydID-$week "relief"]
    lappend scores $score
    set scores [lsort -decreasing -integer $scores]
    set_property $sydID-$week "relief" $scores
  }
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

proc process_normal_position {owner week position} {
  global current_week
  global output_all_weeks
  global output_current_week

  set player [must_get_property $owner-$week $position]
  set backups [split [get_property $player-$week "backups"] {,}]
  set scores [get_property $player-$week "batting"]
  set scores_needed [expr 7 - [llength $scores]]
  if {$scores_needed > 0} {
    foreach backup $backups {
      set backup_player [must_get_property $owner-$week "B$backup"]
      set backup_scores [get_property $backup_player-$week "batting"]
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
  
  if {$output_all_weeks || ($output_current_week && ($week == $current_week))} {
    set outstring [format "%3s %-30s %3s" $position $scores $total]
    puts $outstring
  }

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

proc process_outfield {owner week} {
  global current_week
  global output_all_weeks
  global output_current_week

  set player1 [must_get_property $owner-$week "OF1"]
  set player2 [must_get_property $owner-$week "OF2"]
  set player3 [must_get_property $owner-$week "OF3"]
  set backup_list [split [get_property $player1-$week "backups"] {,}]
  set outfield_list {}
  foreach backup_item $backup_list {
    set backup [must_get_property $owner-$week "B$backup_item"]
    set backup_scores [get_property $backup-$week "batting"]
    foreach score $backup_scores {
      lappend outfield_list [list $score $backup]
    }
  }
  set outfield_list [lsort -decreasing -command comp_outfield_score $outfield_list]
  
  set total 0
  
  foreach position [list OF1 OF2 OF3] {
    set current_score 0
    set player [must_get_property $owner-$week $position]
    set scores [get_property $player-$week "batting"]
    set scores_needed [expr 7 - [llength $scores]]
    while {($scores_needed > 0) && [llength $outfield_list] > 0} {
      set element [lindex $outfield_list 0]
      set outfield_list [lrange $outfield_list 1 end]
      incr scores_needed -1
      lappend scores [lindex $element 0]
      set backup [lindex $element 1]
      set backup_scores [lrange [get_property $backup-$week "batting"] 1 end]
      set_property $backup-$week "batting" $backup_scores
    }
    set scores [lrange [lsort -integer -decreasing $scores] 0 4]
    foreach score $scores {
      incr current_score $score
    }

    if {$output_all_weeks || ($output_current_week && ($week == $current_week))} {
      set outstring [format "%3s %-30s %3s" $position $scores $current_score]
      puts $outstring
    }
    incr total $current_score
  }
  return $total
}

proc process_starting_pitching {owner week} {
  global current_week
  global output_all_weeks
  global output_current_week

  set swing_starts {}
  foreach swing {SW1 SW2 SW3 SW4 SW5 SW6 SW7 SW8} {
    set pitcher [get_property $owner-$week $swing]
    if {[string equal $pitcher {}]} {
      break
    }
    set individual_starts [get_property $pitcher-$week "starting"]
    if {[llength $individual_starts] > 0} {
      if {$output_all_weeks || ($output_current_week && ($week == $current_week))} {
	set outstring [format "%3s %-7s" $swing $individual_starts]
	puts $outstring
      }

      lappend swing_starts [lindex $individual_starts 0]
    }
  }
  set swing_starts [lsort -integer -decreasing $swing_starts]

  set total 0
  set starts {}
  foreach pos {SP1 SP2 SP3 SP4 SP5} {
    set pitcher [must_get_property $owner-$week $pos]
    set individual_starts [get_property $pitcher-$week "starting"]
    if {$output_all_weeks || ($output_current_week && ($week == $current_week))} {
      set outstring [format "%3s %-7s" $pos $individual_starts]
      puts $outstring
    }
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
  if {$output_all_weeks || ($output_current_week && ($week == $current_week))} {
    puts "Starts - $starts"
  }
  return $total
}

proc process_relief_pitching {owner week} {
  global current_week
  global output_all_weeks
  global output_current_week

  set total 0
  set scores {}
  foreach pos {RP1 RP2 RP3} {
    set pitcher [must_get_property $owner-$week $pos]
    if {[string equal $pitcher {}]} {
      break
    }
    set individual_scores [get_property $pitcher-$week "relief"]
    set scores [concat $scores $individual_scores]
    if {([llength $individual_scores] > 0) && ($output_all_weeks || ($output_current_week && ($week == $current_week)))} {
      set outstring [format "%3s %-27s" $pos $individual_scores]
      puts $outstring
    }
  }
  foreach pos {SW1 SW2 SW3 SW4 SW5 SW6 SW7 SW8} {
    set pitcher [get_property $owner-$week $pos]
    if {[string equal $pitcher {}]} {
      break
    }
    set individual_scores [get_property $pitcher-$week "relief"]
    set scores [concat $scores $individual_scores]
    if {([llength $individual_scores] > 0) && ($output_all_weeks || ($output_current_week && ($week == $current_week)))} {
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
  if {$output_all_weeks || ($output_current_week && ($week == $current_week))} {
    puts "Relief - $scores"
  }
  foreach score $scores {
    incr total $score
  }
  return $total
}

proc generate_woolner_id {last first team} {
  set player $last
  append player "_"
  append player $first
  append player "/"
  append player $team
  return $player
}

# Returns a three item list
# 0 - Woolner-style id
# 1 - StatsID
# 2 - Backup positions


proc output_roster_with_scores {owner week} {
  global db

  puts "$owner:"
  puts ""
  puts "Offense:"
  puts ""

  set outstring [format {%3s %5s %-30s %-14s %s} "POS" "ID" "LAST_FIRST/TEAM" "BACKUPS" "SCORES"]
  puts $outstring
  puts "=== ===== ============================== ============= ===================="
  foreach position {"C" "1B" "2B" "3B" "SS" "OF1" "OF2" "OF3" "DH"} {
    set sydID [must_get_property $owner-$week $position]
    set statsID [get_property $sydID "statsID"]
    set backups [get_property $sydID-$week "backups"]

    if {[string equal $statsID ""] || ($statsID == 0)} {
      set statsID "****"
      set scores {}
    } else {
      set scores [get_property $sydID-$week "batting"]
    }
    set player [get_property $sydID-$week "player"]

    set outstring [format {%3s %5s %-30s %-14s %s} $position $statsID $player $backups $scores]
    puts $outstring

    # Set backup position strings
    if {[string equal $position "OF2"] || [string equal $position "OF3"]} {
      continue
    }
    set backup_list [split $backups ","]
  }
  puts ""

  foreach position {"B1" "B2" "B3" "B4" "B5" "B6" "B7" "B8"} {
    set sydID [get_property $owner-$week $position]
    if {[string equal $sydID ""]} {
      continue
    }
    set player [get_property $sydID-$week "player"]
    set statsID [get_property $sydID "statsID"]
    if {[string equal $statsID ""]} {
      set statsID "****"
    }
    set scores [get_property $sydID-$week "batting"]
    set backup_positions [get_property $sydID-$week "backups"]
    set outstring [format {%3s %5s %-30s %-14s %s} $position $statsID $player $backup_positions $scores]
    puts $outstring
  }


  set bench_scores 0
  set ir_list [get_property $owner-$week "IR"]

  foreach sydID $ir_list {
    set player [get_property $sydID-$week "player"]
    set statsID [get_property $sydID "statsID"]
    if {![string equal $statsID ""]} {
      set scores [get_property $sydID-$week "batting"]
      if {![string equal $scores ""]} {
	if {$bench_scores == 0} {
	  puts ""
	  incr bench_scores
	}

	set outstring [format {%3s %5s %-30s %-14s %s} "IR" $statsID $player "" $scores]
	puts $outstring
      }
    }
  }
  
  puts ""

  puts "STARTING PITCHING:"
  puts ""
  set outstring [format {%3s %5s %-30s %s} "POS" "ID" "LAST_FIRST/TEAM" "SCORES"]
  puts $outstring
  puts "=== ===== ============================== ===================="
  
  foreach position {"SP1" "SP2" "SP3" "SP4" "SP5" "SW1" "SW2" "SW3" "SW4" "SW5" "SW6" "SW7" "SW8"} {
    set sydID [get_property $owner-$week $position]
    if {[string equal $sydID ""]} {
      continue
    }

    set pitcher [get_property $sydID-$week "player"]
    set statsID [get_property $sydID "statsID"]

    if {[string equal $statsID ""]} {
      set statsID "****"
    }
    set scores [get_property $sydID-$week "starting"]
    set outstring [format {%3s %5s %-30s %s} $position $statsID $pitcher $scores]
    puts $outstring
  }

  set bench_scores 0  

  # ir_list set when getting batting scores
  
  foreach sydID $ir_list {
    set player [get_property $sydID-$week "player"]
    set statsID [get_property $sydID "statsID"]
    if {![string equal $statsID ""]} {
      set scores [get_property $sydID-$week "starting"]
      if {![string equal $scores ""]} {
	if {$bench_scores == 0} {
	  puts ""
	  incr bench_scores
	}

	set outstring [format {%3s %5s %-30s %s} "IR" $statsID $player $scores]
	puts $outstring
      }
    }
  }

  puts ""
  
  puts "RELIEF PITCHING:"
  puts ""
  
  foreach position {"RP1" "RP2" "RP3" "SW1" "SW2" "SW3" "SW4" "SW5" "SW6" "SW7" "SW8"} {
    set sydID [get_property $owner-$week $position]
    if {[string equal $sydID ""]} {
      continue
    }
    set pitcher [get_property $sydID-$week "player"]
    set statsID [get_property $sydID "statsID"]
    if {[string equal $statsID ""]} {
      set statsID "****"
    }
    set scores [get_property $sydID-$week "relief"]
    set outstring [format {%3s %5s %-30s %s} $position $statsID $pitcher $scores]
    puts $outstring
  }

  set bench_scores 0  
  # ir_list set in batting scores
  
  foreach sydID $ir_list {
    set player [get_property $sydID-$week "player"]
    set statsID [get_property $sydID "statsID"]
    if {![string equal $statsID ""]} {
      set scores [get_property $sydID-$week "relief"]
      if {![string equal $scores ""]} {
	if {$bench_scores == 0} {
	  puts ""
	  incr bench_scores
	}

	set outstring [format {%3s %5s %-30s %s} "IR" $statsID $player $scores]
	puts $outstring
      }
    }
  }
  
  puts ""
}

foreach week $weeks {
  global output_all_weeks
  global current_week
  global output_current_week
  
  set week_standings_list {}
  
  get_database_data $week

  foreach owner $owners {


  # First, output the roster with scores
    
    if {$output_all_weeks || ($output_current_week && ($week == $current_week))} {
      puts "SCORES FOR WEEK $week:"
      puts ""
      output_roster_with_scores $owner $week

      set outstring [format "%3s %-30s %3s" "POS" "SCORES" "SUBTOTAL"]
      puts $outstring
      puts "=== ============================== ==="
      puts ""
    }


    set offense 0
    
  # Infield
    foreach position {"C" "1B" "2B" "3B" "SS"} {
      incr offense [process_normal_position $owner $week $position]
    }
    
  # outfield
    incr offense [process_outfield $owner $week]

  # dh
    incr offense [process_normal_position $owner $week "DH"]
    
  # starters
    set starting_pitching [process_starting_pitching $owner $week]

  # relievers
    set relief_pitching [process_relief_pitching $owner $week]

  # total
    set total [expr $offense + $starting_pitching + $relief_pitching]

    if {$output_all_weeks || ($output_current_week && ($week == $current_week))} {
      puts ""
      puts "TOTAL OFFENSE - $offense"
      puts ""

      set outstring [format "%3s %3s" "POS" "SCORES"]
      puts $outstring

      puts ""
      puts "STARTING PITCHING - $starting_pitching"
      puts ""

      set outstring [format "%3s %3s" "POS" "SCORES"]
      puts $outstring
      puts ""

      puts ""
      puts "RELIEF PITCHING - $relief_pitching"
      puts ""
    
      puts "** TOTAL FOR $owner - $offense + $starting_pitching + $relief_pitching = $total"
      puts ""
    }
    
    lappend week_standings_list [list $owner $total]
    set insert_cmd {INSERT INTO ScoringWeeks (weekid, owner, battingpoints, startingpoints, reliefpoints, total) VALUES (}
    append insert_cmd "$week, '$owner', $offense, $starting_pitching, $relief_pitching, $total"
    append insert_cmd {);}
    ::mysql::exec $db $insert_cmd
  }

  set week_standings_list [lsort -command sort_standings $week_standings_list]

  if {$output_all_weeks || ($output_current_week && ($week == $current_week))} {
    puts "Standings for week $week:"
    foreach pair $week_standings_list {
      puts $pair
    }
  }
}

puts ""
puts "OVERALL STANDINGS THROUGH WEEK $current_week:"
puts ""
set outstring [format "%-10s %8s %8s %8s - %8s" "OWNER" "BATTING" "STARTING" "RELIEF" "TOTAL"]
puts $outstring
puts "========== ======== ======== ========   ========"

set owner_standing_items [::mysql::sel $db {SELECT owner, sum(battingpoints), sum(startingpoints), sum(reliefpoints), sum(total) as Total from ScoringWeeks group by Owner order by Total DESC;} -flatlist]

foreach {owner batting starting relief total} $owner_standing_items {
  set outstring [format "%-10s %8d %8d %8d - %8d" $owner $batting $starting $relief $total]
  puts $outstring
}

::mysql::close $db
