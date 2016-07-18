#!/usr/bin/tclsh

lappend auto_path [file dirname [info script]]
package require property_utils 1.0

set off_season 0
set show_keepers_for_players 0
set raw_draft_order 0
set debug 0
set populate_database 0

proc usage {} {
  puts stderr {Usage: find_optimal_keepers.tcl}
  exit 1
}

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
    set_property $owner "roster_received" [lindex $owner_fields 0]
    set_property $owner "team_name" [lindex $owner_fields 2]
    set_property $owner "current_standings" [lindex $owner_fields 3]
    set_property $owner "last_claim_week" [lindex $owner_fields 4]
    set_property $owner "next_claim_week" [lindex $owner_fields 5]
    set_property $owner "next_standings" [lindex $owner_fields 6]
    set_property $owner "short_name" [lindex $owner_fields 7]
    set_property $owner "player_count" 0
    set_property $owner "keeper_years" 30
    set_property $owner "keeper_total" 0
    lappend owners $owner
}

set owners [lsort $owners]

# Now, set up rosters

set rosters_file [open "Projected_OOOL_Points.tab"]
set roster_contents [read $rosters_file]
close $rosters_file
set roster_items [split $roster_contents \n]

puts "Found [llength $roster_items] players..."

foreach item $roster_items {
    global off_season
    
    set item_list [split $item \t]
    set owner [lindex $item_list 0]
    set position [lindex $item_list 1]
    set player [lindex $item_list 2]
    set team [lindex $item_list 3]
    set backups [lindex $item_list 4]
    set keeper_years [lindex $item_list 5]
    set elig_C [lindex $item_list 6]
    set elig_1B [lindex $item_list 7]
    set elig_2B [lindex $item_list 8]
    set elig_3B [lindex $item_list 9]
    set elig_SS [lindex $item_list 10]
    set elig_OF [lindex $item_list 11]
    set lahmanID [lindex $item_list 12]
    set statsID [lindex $item_list 13]
    set sydID [lindex $item_list 14]
    set OOOL_points [lindex $item_list 15]
    set points_above_replacement [lindex $item_list 16]
    
    set_property $sydID "OOOL_points" $OOOL_points
    set_property $sydID "points_above_replacement" $points_above_replacement
    set_property $sydID "name" $player

    if {$keeper_years == ""} {
      set keeper_years 1
    }
    set_property $sydID "keeper_years" $keeper_years

    if {[string equal $owner {}]} {
	continue
    }

    set keeper_total [get_property $owner "keeper_total"]
    set keeper_total [expr $keeper_total + $keeper_years]
    set_property $owner "keeper_total" $keeper_total
    if {[string equal $elig_C "Yes"]} {
	set_property $sydID "C" "Yes"
    }
    if {[string equal $elig_1B "Yes"]} {
	set_property $sydID "1B" "Yes"
    }
    if {[string equal $elig_2B "Yes"]} {
	set_property $sydID "2B" "Yes"
    }
    if {[string equal $elig_3B "Yes"]} {
	set_property $sydID "3B" "Yes"
    }
    if {[string equal $elig_SS "Yes"]} {
	set_property $sydID "SS" "Yes"
    }
    if {[string equal $elig_OF "Yes"]} {
	set_property $sydID "OF" "Yes"
    }

    set players [get_property $owner "players"]
    lappend players $sydID
    set_property $owner "players" $players
}

proc fit_into_keeper_years {owner players_so_far players_to_go years_so_far years_total points_so_far} {

  for {set i 0} {$i < [llength $players_to_go]} {incr i} {
    set sydID [lindex $players_to_go $i]
    set name [get_property $sydID "name"]
    set years [get_property $sydID "keeper_years"]
    set proposed_years [expr $years_so_far + $years]
    set points [get_property $sydID "points_above_replacement"]
    if {[string equal $points ""]} {
      set points 0
    }
    
    if {$points < 0} {
      continue
    }

    if {$years_so_far + $years > $years_total} {
      continue
    }
    
    set new_players_to_go [lrange $players_to_go [expr $i + 1] end]
    set new_players_so_far [concat $players_so_far $sydID]
    set new_years_so_far [expr $years_so_far + $years]
    set new_points_so_far [expr $points_so_far + $points]

    set best_solution_points [get_property $owner "best_solution_points"]
    if {$new_points_so_far > $best_solution_points} {
      puts "NEW BEST SOLUTION FOUND FOR $owner:"
      foreach id $new_players_so_far {
	puts -nonewline [get_property $id "name"]
	puts " - [get_property $id "keeper_years"] - [get_property $id "OOOL_points"] - [get_property $id "points_above_replacement"] above replacement"
      }
      puts "Total points - $new_points_so_far"
      puts "Total years - $new_years_so_far"
      puts ""
      set best_solution_players $new_players_so_far
      set best_solution_years $new_years_so_far
      set best_solution_point $new_points_so_far
      set_property $owner "best_solution_players" $new_players_so_far
      set_property $owner "best_solution_years" $new_years_so_far
      set_property $owner "best_solution_points" $new_points_so_far
    }
    
    fit_into_keeper_years $owner $new_players_so_far $new_players_to_go $new_years_so_far $years_total $new_points_so_far
  }
}

# Process keeper trades

if {[catch {open "Keeper Year Trades.txt"} keeper_trade_file]} {
  set keeper_trade_items {}
} else {
  fconfigure $keeper_trade_file -encoding macRoman
  set keeper_trade_contents [read $keeper_trade_file]
  close $keeper_trade_file
  set keeper_trade_items [split $keeper_trade_contents \n]
}

foreach trade $keeper_trade_items {
    set keeper_items [split $trade \t]
    set acquirer [lindex $keeper_items 1]
    if {[string equal $acquirer {}]} {
        continue
    }
    set years [lindex $keeper_items 0]
    set releaser [lindex $keeper_items 2]
    
    if {[catch {set acquirer_keeper_list [get_property $acquirer "keeper_trades"]}]} {
	set acquirer_keeper_list {}
    }
    set item [list $years $releaser "from"]
    lappend acquirer_keeper_list $item
    set_property $acquirer "keeper_trades" $acquirer_keeper_list
       
    if {[catch {set releaser_keeper_list [get_property $releaser "keeper_trades"]}]} {
	set releaser_keeper_list {}
    }
    set item [list $years $acquirer "to"]
    lappend releaser_keeper_list $item
    set_property $releaser "keeper_trades" $releaser_keeper_list
    
    set acquirer_years [expr [get_property $acquirer "keeper_years"] + $years]
    set_property $acquirer "keeper_years" $acquirer_years
    set releaser_years [expr [get_property $releaser "keeper_years"] - $years]
    set_property $releaser "keeper_years" $releaser_years
}

proc sort_by_keepers {a b} {
  set a_keepers [get_property $a "keeper_years"]
  set b_keepers [get_property $b "keeper_years"]
  if {$a_keepers > $b_keepers} {
    return -1
  } elseif {$a_keepers == $b_keepers} {
    set a_points [get_property $a "points_above_replacement"]
    set b_points [get_property $b "points_above_replacement"]
    if {$a_points > $b_points} {
      return -1
    } elseif {$a_points == $b_points} {
      return 0
    }
    return 1
  }
  return 1
}

set owner "Syd"
set players [lsort -command sort_by_keepers [get_property $owner "players"]]
set total_years [get_property $owner "keeper_years"]
fit_into_keeper_years $owner {} $players 0 $total_years 0

foreach owner $owners {
  if {[string equal $owner "Syd"]} {
    continue
  }
  set players [lsort -command sort_by_keepers [get_property $owner "players"]]
  set total_years [get_property $owner "keeper_years"]
  fit_into_keeper_years $owner {} $players 0 $total_years 0
}

# Now, output the text file. Format: owner<tab>sydID

set fd [open keeper.tab w]

foreach owner $owners {
  set best_solution_players [get_property $owner "best_solution_players"]
  foreach player $best_solution_players {
    puts $fd "$owner\t$player"
  }
}

close $fd
