#!/usr/bin/tclsh

lappend auto_path [file dirname [info script]]
package require property_utils 1.0

set best_player_method 0
set draftbot_rev 0
set debug 0

set replacement_file [open "Replacement.tab"]
set line [gets $replacement_file]
set replacement_level(C) [lindex $line 0]
set replacement_level(1B) [lindex $line 1]
set replacement_level(2B) [lindex $line 2]
set replacement_level(3B) [lindex $line 3]
set replacement_level(SS) [lindex $line 4]
set replacement_level(OF) [lindex $line 5]
set replacement_level(DH) [lindex $line 6]
set replacement_level(SP) [lindex $line 7]
set replacement_level(RP) [lindex $line 8]

set replacement_positions "C 1B 2B 3B SS OF DH SP RP"
proc debug_pause {} {
  global debug
  
  if {$debug} {
    puts -nonewline "Hit Enter to continue... "
    flush stdout
    gets stdin
  }
}

proc debug_puts {arg1 {arg2 {}}} {
  global debug
  if {$debug} {
    if {$arg2 eq ""} {
      puts $arg1
    } else {
      puts $arg1 $arg2
    }
  }
}

proc find_best_player_in_list {pick_owner players} {
  global available
  
  while {[llength $available($players)] > 0} {
    set player [lindex $available($players) 0]
    debug_puts "player - $player - [get_property $player "name"]"
    set current_owner [get_property $player "owner"]
    debug_puts "current_owner - $current_owner"
    if {$current_owner ne ""} {
      remove_player_from_list $player $players
    } else {
      return $player
    }
  }
  return ""
}

proc remove_player_from_list {player players} {
  global available
  
  set index [lsearch -exact $available($players) $player]
  if {$index > -1} {
    set available($players) [lreplace $available($players) $index $index]
  }
}

proc compare_replacement_level {p1 p2} {
  global replacement_level
  set points1 $replacement_level($p1)
  set points2 $replacement_level($p2)
  if {$points1 < $points2} {
    return -1
  } elseif {$points1 > $points2} {
    return 1
  }
  return 0
}

set replacement_positions [lsort -command compare_replacement_level $replacement_positions]

set owner_file [open "Owner Info.txt"]
fconfigure $owner_file -encoding macRoman
set owner_contents [read $owner_file]
close $owner_file

set owner_items [split $owner_contents \n]
set owners {}
foreach owner_item $owner_items {
  set owner_fields [split $owner_item \t]
  set owner [lindex $owner_fields 1]
  if {[string equal $owner {}]} {
    continue
  }
  set_property $owner "draft_order" [lindex $owner_fields 5]
  set_property $owner "num_players" 0
  lappend owners $owner
}

# Process draft picks so that they can be output in the owner loop

if {[catch {open "Draft Picks.txt"} draft_picks_file]} {
  set draft_pick_items ""
} else {
  fconfigure $draft_picks_file -encoding macRoman
  set draft_pick_contents [read $draft_picks_file]
  close $draft_picks_file
  set draft_pick_items [split $draft_pick_contents \n]
}

proc strip_ordinal ordinal {
    regsub {st} $ordinal {} result
    regsub {nd} $result {} result
    regsub {rd} $result {} result
    regsub {th} $result {} result
    return $result
}

foreach pick $draft_pick_items {
  set pick_items [split $pick \t]
  set acquirer [lindex $pick_items 0]
  if {[string equal $acquirer {}]} {
    continue
  }
  set releaser [lindex $pick_items 1]
  set round [lindex $pick_items 2]

  puts "Setting $releaser's $round round draft pick to $acquirer."
  set_property $releaser "draft_[strip_ordinal $round]" $acquirer
}

set owners [lsort $owners]

proc strip_ordinal ordinal {
    regsub {st} $ordinal {} result
    regsub {nd} $result {} result
    regsub {rd} $result {} result
    regsub {th} $result {} result
    return $result
}

proc sort_by_points {player1 player2} {
  set points1 [get_property $player1 "points"]
  set points2 [get_property $player2 "points"]
  if {$points1 > $points2} {
    return -1
  } elseif {$points1 < $points2} {
    return 1
  }
  return 0
}

# Read last years players

puts "Loading eligible players..."

set fd [open "2008Players.tab"]

set players {}
set catchers {}
set first_basemen {}
set second_basemen {}
set third_basemen {}
set shortstops {}
set outfielders {}
set designated_hitters {}
set starting_pitchers {}
set relief_pitchers {}

while {[gets $fd line] >= 0} {
  set line [split $line \t]

  set sydID [lindex $line 0]
  set name [lindex $line 1]
  set points [lindex $line 2]
#unused for now
  set owner [lindex $line 3]
  set eligible_C [lindex $line 4]
  set eligible_1B [lindex $line 5]
  set eligible_2B [lindex $line 6]
  set eligible_3B [lindex $line 7]
  set eligible_SS [lindex $line 8]
  set eligible_OF [lindex $line 9]
  set eligible_SP [lindex $line 10]
  if {$eligible_SP eq ""} {
    set eligible_SP 0
  }
  set eligible_RP [lindex $line 11]
  if {$eligible_RP eq ""} {
    set eligible_RP 0
  }
  
  set_property $sydID "name" $name
  set_property $sydID "points" $points
# set_property $sydID "owner" $owner

  lappend players $sydID

  if {$eligible_C == 1} {
    set_property $sydID "C" 1
    lappend catchers $sydID
  }
  
  if {$eligible_1B == 1} {
    set_property $sydID "1B" 1
    lappend first_basemen $sydID
  }
  
  if {$eligible_2B == 1} {
    set_property $sydID "2B" 1
    lappend second_basemen $sydID
  }

  if {$eligible_3B == 1} {
    set_property $sydID "3B" 1
    lappend third_basemen $sydID
  }

  if {$eligible_SS == 1} {
    set_property $sydID "SS" 1
    lappend shortstops $sydID
  }

  if {$eligible_OF == 1} {
    set_property $sydID "OF" 1
    lappend outfielders $sydID
  }

  if {$eligible_SP == 1} {
    set_property $sydID "SP" 1
    lappend starting_pitchers $sydID
  }

  if {$eligible_RP == 1} {
    set_property $sydID "RP" 1
    lappend relief_pitchers $sydID
  }

  if {!$eligible_SP && !$eligible_RP} {
    lappend designated_hitters $sydID
  }
}

set available(players) [lsort -command sort_by_points $players]
set available(catchers) [lsort -command sort_by_points $catchers]
set available(first_basemen) [lsort -command sort_by_points $first_basemen]
set available(second_basemen) [lsort -command sort_by_points $second_basemen]
set available(third_basemen) [lsort -command sort_by_points $third_basemen]
set available(shortstops) [lsort -command sort_by_points $shortstops]
set available(outfielders) [lsort -command sort_by_points $outfielders]
set available(starting_pitchers) [lsort -command sort_by_points $starting_pitchers]
set available(relief_pitchers) [lsort -command sort_by_points $relief_pitchers]
set available(designated_hitters) [lsort -command sort_by_points $designated_hitters]

unset players
unset catchers
unset first_basemen
unset second_basemen
unset third_basemen
unset shortstops
unset outfielders
unset starting_pitchers
unset relief_pitchers
unset designated_hitters


proc incr_num_players {owner} {
  set num_players [get_property $owner "num_players"]
  incr num_players
  set_property $owner "num_players" $num_players
  debug_puts "$owner now has $num_players players"
}

proc decr_num_players {owner} {
  set num_players [get_property $owner "num_players"]
  incr num_players -1
  set_property $owner "num_players" $num_players
  debug_puts "$owner now has $num_players players"
}

proc place_player_in_roster {owner sydID pos} {
  puts "$owner - Placing [get_property $sydID "name"] at $pos"
  set_property $owner $pos $sydID
  set_property $sydID "owner" $owner
  incr_num_players $owner
  debug_pause
}

proc remove_player_from_roster {owner sydID pos} {
  puts "$owner - Removing [get_property $sydID "name"] at $pos"
  set_property $owner $pos ""
  set_property $sydID "owner" $owner
  decr_num_players $owner
  debug_pause
}

proc add_player_to_roster_replacement_version {owner sydID} {
  global replacement_level
  global debug

  debug_puts "owner - $owner"
  debug_puts "sydID - $sydID"
  debug_puts "name - [get_property $sydID "name"]"

  set num_players [get_property $owner "num_players"]
  if {$num_players >= 35} {
    debug_puts "Roster for $owner is full"
    debug_pause
    return ""
  }

  set points [get_property $sydID "points"]
  debug_puts "points - $points"

# For pitching, no need to calculate replacement points. This player is not going
# to be compared at other positions.

  set eligible_SP [get_property $sydID "SP"]
  if {$eligible_SP == 1} {
    foreach pos {"SP1" "SP2" "SP3" "SP4" "SP5"} {
      set pitcher [get_property $owner $pos]
      debug_puts "pitcher - [get_property $pitcher "name"] - $pitcher"
      if {$pitcher != ""} {
	set pitcher_points [get_property $pitcher "points"]
	debug_puts "pitcher_points - $pitcher_points"
	if {$points > $pitcher_points} {
	  puts "[get_property $sydID "name"] is bumping [get_property $pitcher "name"] at $pos"
	  remove_player_from_roster $owner $pitcher $pos
	  place_player_in_roster $owner $sydID $pos
	  if {[add_player_to_roster_replacement_version $owner $pitcher] eq ""} {
	    place_player_in_roster $owner $pitcher $pos
	    return ""
	  }
	  return $pos
	}
      } else {
	place_player_in_roster $owner $sydID $pos
	return $pos
      }
    }
  }
  
  set eligible_RP [get_property $sydID "RP"]
  if {$eligible_RP == 1} {
    foreach pos {"RP1" "RP2" "RP3"} {
      set pitcher [get_property $owner $pos]
      if {$pitcher != ""} {
	set pitcher_points [get_property $pitcher "points"]
	if {$points > $pitcher_points} {
	  puts "[get_property $sydID "name"] is bumping [get_property $pitcher "name"] at $pos"
	  remove_player_from_roster $owner $pitcher $pos
	  place_player_in_roster $owner $sydID $pos
	  if {[add_player_to_roster_replacement_version $owner $pitcher] eq ""} {
	    place_player_in_roster $owner $pitcher $pos 1
	    return ""
	  }
	  return $pos
	}
      } else {
	place_player_in_roster $owner $sydID $pos
	return $pos
      }
    }
  }
  
  if {$eligible_SP == 1 || $eligible_RP == 1} {
    foreach pos {"SW1" "SW2" "SW3"} {
      set pitcher [get_property $owner $pos]
      if {$pitcher != ""} {
	set pitcher_points [get_property $pitcher "points"]
	if {$points > $pitcher_points} {
	  puts "[get_property $sydID "name"] is bumping [get_property $pitcher "name"] at $pos"
	  remove_player_from_roster $owner $pitcher $pos
	  place_player_in_roster $owner $sydID $pos
	  if {[add_player_to_roster_replacement_version $owner $pitcher] eq ""} {
	    place_player_in_roster $owner $pitcher $pos
	    return ""
	  }
	  return $pos
	}
      } else {
	place_player_in_roster $owner $sydID $pos
	return $pos
      }
    }
  } else {
    set best_pos ""
    set best_replacement_points -999
  
    foreach pos "C 1B 2B 3B SS OF DH" {
      debug_puts "Trying $pos..."
      set eligible [get_property $sydID $pos]
      if {($pos ne "DH") && ($eligible eq "")} {
	continue
      }
      
      set replacement_points [expr $points - $replacement_level($pos)]
      debug_puts "Found $pos - $replacement_points"
      
      # Get existing players and points
      if {$pos eq "OF"} {
	set player [get_property $owner "OF1"]
      } else {
	set player [get_property $owner $pos]
      }
      
      if {$player ne ""} {
	debug_puts "Existing Player [get_property $player "name"]"
	set player_replacement_points [expr [get_property $player "points"] - $replacement_level($pos)]
	debug_puts "Existing player - $player_replacement_points"
      } else {
	debug_puts "Nobody at position $pos"
	set player_replacement_points -999
      }
      if {$replacement_points > $player_replacement_points && $replacement_points > $best_replacement_points} {
	set best_pos $pos
	debug_puts "best_pos now $pos"
	set best_replacement_points $replacement_points
	debug_puts "best_replacment_points now $best_replacement_points"
      }
    }

    if {$best_pos ne ""} {
      if {$best_pos eq "OF"} {
	debug_puts "Trying the outfield"
	foreach newpos "OF3 OF2 OF1" {
	  debug_puts "Trying $newpos"
	  set existing_player [get_property $owner $newpos]
	  debug_puts "existing_player - [get_property $existing_player "name"]"
	  if {$existing_player eq ""} {
	    place_player_in_roster $owner $sydID $newpos
	    return $newpos
	  } else {
	    debug_puts "points - $points"
	    set existing_points [get_property $existing_player "points"]
	    debug_puts "existing_points - $existing_points"
	    if {$points > $existing_points} {
	      puts "[get_property $sydID "name"] is bumping [get_property $existing_player "name"] at $newpos"
	      remove_player_from_roster $owner $existing_player $newpos
	      place_player_in_roster $owner $sydID $newpos
	      if {[add_player_to_roster_replacement_version $owner $existing_player] eq ""} {
		place_player_in_roster $owner $existing_player $newpos
	      } else {
		return $newpos
	      }
	    }
	  }
	}
      } else {
	debug_puts "Trying best_pos $best_pos"
	set existing_player [get_property $owner $best_pos]
	if {$existing_player eq ""} {
	  place_player_in_roster $owner $sydID $best_pos
	  return $best_pos
	} else {
	  puts "[get_property $sydID "name"] is bumping [get_property $existing_player "name"] at $best_pos"
	  remove_player_from_roster $owner $existing_player $best_pos
	  place_player_in_roster $owner $sydID $best_pos
	  if {[add_player_to_roster_replacement_version $owner $existing_player] eq ""} {
	    place_player_in_roster $owner $existing_player $best_pos
	  } else {
	    return $best_pos
	  }
	}
      }
    }
    
    # Try the bench.    
    foreach pos "B1 B2 B3 B4 B5" {
      debug_puts "$pos"
      set existing_player [get_property $owner $pos]
      if {$existing_player eq ""} {
	place_player_in_roster $owner $sydID $pos
	return $pos
      } else {
	debug_puts "existing_player - $existing_player [get_property $existing_player "name"]"
	set existing_points [get_property $existing_player "points"]
	debug_puts "existing_points - $existing_points"
	if {$points > $existing_points} {
	  puts "[get_property $sydID "name"] is bumping [get_property $existing_player "name"] at $pos"
	  remove_player_from_roster $owner $existing_player $pos
	  place_player_in_roster $owner $sydID $pos
	  if {[add_player_to_roster_replacement_version $owner $existing_player] eq ""} {
	    place_player_in_roster $owner $existing_player $pos
	    break
	  } else {
	    return $pos
	  }
	}
      }
    }
  }

  # No place for swing pitchers or bench. Try IR.
  
  debug_puts "No place in active roster for [get_property $sydID "name"]; reserving"
  debug_pause
  
  foreach pos "IR1 IR2 IR3 IR4 IR5 IR6 IR7 IR8 IR9 IR10" {
    set reserve_player [get_property $owner $pos]
    debug_puts "$pos - [get_property $reserve_player "name"]"
    if {$reserve_player eq ""} {
      place_player_in_roster $owner $sydID $pos
      return $pos
    }
  }
  
  debug_puts "No place for [get_property $sydID "name"]!"
  debug_puts "$owner has [get_property $owner "num_players"]"
  debug_pause
  return ""
}

# Now, read keepers and assign them to rosters

puts "Reading keepers..."
set fd [open keeper.tab]
while {[gets $fd line] >= 0} {
  set owner [lindex $line 0]
  set sydID [lindex $line 1]
  set_property $sydID "owner" $owner

  add_player_to_roster_replacement_version $owner $sydID
  remove_player_from_list $sydID "players"
}
puts "Finished keepers"

puts "Simulating draft..."

debug_pause

proc do_pick {pick_owner owner round} {
  global position_order
  global debug
  global best_player_method
  global replacement_level
  global available

  puts ""
  puts -nonewline "Round #$round: $pick_owner"
  if {[string equal $owner $pick_owner]} {
    puts ""
  } else {
    puts " from $owner"
  }
  debug_pause

  set player ""
  
  if {!$best_player_method} {
    set best_pos ""
    set best_points 0
    set best_player ""
    foreach list "catchers first_basemen second_basemen third_basemen shortstops outfielders designated_hitters starting_pitchers relief_pitchers" pos "C 1B 2B 3B SS OF1 DH SP5 RP3" {
      set player [find_best_player_in_list $pick_owner $list]
      
      debug_puts "Found $player [get_property $player "name"] for position $pos"
      
      if {$player ne ""} {
	set player_points [get_property $player "points"]
	if {$pos eq "OF1"} {
	  set replacement_position "OF"
	} elseif {$pos eq "SP5"} {
	  set replacement_position "SP"
	} elseif {$pos eq "RP3"} {
	  set replacement_position "RP"
	} else {
	  set replacement_position $pos
	}
	
	set existing_player [get_property $pick_owner $pos]
	set replacement_points [expr $player_points - $replacement_level($replacement_position)]
	if {$existing_player eq ""} {
	  debug_puts "No existing player - $replacement_points"
	} else {
	  set existing_points [get_property $existing_player "points"]
	  if {$player_points <= $existing_points} {
	    set replacement_points 0
	  }  else {
	    set replacement_points [expr $existing_points - $replacement_level($replacement_position)]
	  }
	  debug_puts "[get_property $existing_player "name"] - raw $existing_points - replacement $replacement_points"
	}
	if {$replacement_points > $best_points} {
	  set best_pos $pos
	  set best_points $replacement_points
	  set best_player $player
	  debug_puts "Best so far - [get_property $player "name"] - $pos - $replacement_points"
	}
      }
    }
    set player ""
    debug_puts "Best player - [get_property $best_player "name"] $best_pos $best_points"
    debug_pause
    if {$best_player ne ""} {
      set player $best_player
      if {[add_player_to_roster_replacement_version $pick_owner $best_player ] eq ""} {
	set player ""
	puts "No more placing by positions."
      }
    }
  }
  
  if {$player eq ""} {
    set remaining_players $available(players)
    set length [llength $remaining_players]
    for {set i 0} {$i < $length} {incr i} {
      set candidate [lindex $remaining_players $i]
      debug_puts "Trying [get_property $candidate "name"]"
      debug_pause
      if {[add_player_to_roster_replacement_version $pick_owner $candidate] ne ""} {
	debug_puts "Found [get_property $candidate "name"]"
	set player $candidate
	debug_pause
	break
      } else {
	global debug
	puts "Could not place [get_property $candidate "name"]"
	debug_pause
      }
    }
  }
  
  debug_puts "Final player - [get_property $player "name"]"
  
  if {[string equal $player ""]} {
    puts "Ran out of players for owner $pick_owner"
    debug_pause
    return ""
  } else {
    remove_player_from_list $player "players"
  }
}

# Put owners in draft order

proc sort_by_draft_order {o1 o2} {
  set order1 [get_property $o1 "draft_order"]
  set order2 [get_property $o2 "draft_order"]
  if {$order1 < $order2} {
    return -1
  } elseif {$order1 > $order2} {
    return 1
  }
  error "should not be equal"
}

set owners_by_draft_order [lsort -command sort_by_draft_order $owners]
puts "owners_by_draft_order - $owners_by_draft_order"

for {set round 1} {[llength $owners_by_draft_order] > 0} {incr round} {
  
  foreach owner $owners_by_draft_order {
    set pick_owner [get_property $owner "draft_$round"]
    if {[string equal $pick_owner {}]} {
      set pick_owner $owner
    }
    set player [do_pick $pick_owner $owner $round]
    set num_players [get_property $pick_owner "num_players"]
    if {$num_players >= 35 || [string equal $player ""]} {
      puts "$pick_owner is done"
      set index [lsearch -exact $owners_by_draft_order $pick_owner]
      set owners_by_draft_order [lreplace $owners_by_draft_order $index $index]
    }
  }
}

# output final draft results with projected oool points and totals

proc output_item {owner pos} {
  set player [get_property $owner $pos]
  set name [get_property $player "name"]
  set points [get_property $player "points"]
  if {[string equal $points ""]} {
    set points 0
  }
  puts [format "%-4s %-40s %6.2f" $pos $name $points]
  return $points
}

puts ""
puts "Note that in the following, starting batters get 5/7 or their score; bench players get 2/7."
puts "Starting pitching already has this factored in; swing starters get 7/25; swing relievers get 100%."
puts "IR gets nothing."
puts ""

puts "Final teams:"

foreach owner $owners {
  puts ""
  puts "$owner:"
  puts ""
  
  set total_points 0
  
  # Use 5/7 of starters points
  
  foreach pos {C 1B 2B 3B SS OF1 OF2 OF3 DH} {
    set points [expr [output_item $owner $pos] * 5 / 7]
    set total_points [expr $total_points + $points]
  }
  
  puts ""
  
  
  foreach pos {B1 B2 B3 B4 B5} {
    set points [expr [output_item $owner $pos] * 2 / 7]
    set total_points [expr $total_points + $points]
  }
  
  puts ""
  
  foreach pos {SP1 SP2 SP3 SP4 SP5} {
    set total_points [expr $total_points + [output_item $owner $pos]]
  }
  
  puts ""
  
  foreach pos {SW1 SW2 SW3} {
    set points [output_item $owner $pos]
    set player [get_property $owner $pos]
    set starter [get_property $player "SP"]
    if {$starter == 1} {
      set points [expr $points * 7 / 25]
    }
    set total_points [expr $total_points + $points]

  }

  puts ""
  
  foreach pos {RP1 RP2 RP3} {
    set total_points [expr $total_points + [output_item $owner $pos]]
  }
  
  puts ""
  
  # Don't count points from IR
  foreach pos {IR1 IR2 IR3 IR4 IR5 IR6 IR7 IR8 IR9 IR10} {
    output_item $owner $pos
  }
  
  puts ""
  
  puts "Total projected points: [format {%8.2f} $total_points]"
  
  set_property $owner "total_points" $total_points
}

proc sort_by_total_points {o1 o2} {
  set total1 [get_property $o1 "total_points"]
  set total2 [get_property $o2 "total_points"]
  if {$total1 > $total2} {
    return -1
  } elseif {$total1 < $total2} {
    return 1
  }
  return 0
}

puts ""
set standing_order [lsort -command sort_by_total_points $owners]
foreach owner $standing_order {
  puts [format "%9s %-8.2f" $owner [get_property $owner "total_points"]]
}
