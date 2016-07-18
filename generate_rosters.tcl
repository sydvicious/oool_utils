#!/usr/bin/tclsh

lappend auto_path [file dirname [info script]]
package require property_utils 1.0

set off_season 0
set show_keepers_for_players 0
set raw_draft_order 0
set debug 0
set populate_database 0

proc usage {} {
  puts stderr {Usage: generate_rosters.tcl [--offseason] [--raw-draft-order] [--hide-keepers]}
  exit 1
}

foreach arg $argv {
    if {[string equal $arg "--offseason"]} {
    	set off_season 1
    	set show_keepers_for_players 1
    } elseif {[string equal $arg "--raw-draft-order"]} {
    	set raw_draft_order 1
    } elseif {[string equal $arg "--hide-keepers"]} {
    	set show_keepers_for_players 0
    } elseif {[string equal $arg "--populate-database"]} {
	set populate_database 1
    } elseif {[string equal $arg "--debug"]} {
	set debug 1
    } elseif {$populate_database} {
	set week $arg
    } else {
    	usage
    }
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

proc compare_this_week {owner1 owner2} {
    
    set last_claim1 [get_property $owner1 "last_claim_week"]
    set last_claim2 [get_property $owner2 "last_claim_week"]
    
    if {$last_claim1 < $last_claim2} {
	return -1
    } elseif {$last_claim1 > $last_claim2} {
	return 1
    } else {
	set last_standings1 [get_property $owner1 "standings"]
	set last_standings2 [get_property $owner2 "standings"]
	
	if {$last_standings1 < $last_standings2} {
	    return 1
	} else {
	    return -1
	}
    }
}

set owners_this_week [lsort -command compare_this_week $owners]

proc compare_next_week {owner1 owner2} {
    
    set last_claim1 [get_property $owner1 "next_claim_week"]
    set last_claim2 [get_property $owner2 "next_claim_week"]
    
    if {$last_claim1 < $last_claim2} {
	return -1
    } elseif {$last_claim1 > $last_claim2} {
	return 1
    } else {
	set last_standings1 [get_property $owner1 "next_standings"]
	set last_standings2 [get_property $owner2 "next_standings"]
	
	if {$last_standings1 > $last_standings2} {
	    return -1
	} else {
	    return 1
	}
    }
}

set owners_next_week [lsort -command compare_next_week $owners]

# Two output formats: One for BB; one for Subrata

if {$off_season} {
    set oool_fd [open "Offseason Report.txt" w]
} else {
    set oool_fd [open "OOOL Report.txt" w]
}

# Output keeper summary in offseason and conflicts during the season

if {!$off_season} {
    if {![catch {set conflicts_file [open "Conflicts.txt"]}]} {
	set conflict_text [read $conflicts_file]
	close $conflicts_file
	set conflict_items [split $conflict_text \n]
    } else {
	set conflict_items {}
    }


    puts $oool_fd "CONFLICTS:"
    if {[string equal $conflict_items {}]} {
	puts $oool_fd "\t* None."
    } else {
	foreach conflict $conflict_items {
	    set item [split $conflict \t]
	    set player [lindex $item 0]
	    if {[string equal $player {}]} {
		continue
	    }
	    set conflict_winner [lindex $item 1]
	    set count [lindex $item 2]
	    puts $oool_fd "\t* $player \($count; won by $conflict_winner\)"
	}
    }
    puts $oool_fd ""

    # Output draft order
    
    puts $oool_fd "DRAFT ORDER:"
    puts $oool_fd ""
    
    puts $oool_fd "    This Week       Next Week"
    puts $oool_fd "    =========       ========="
    
    for {set i 0} {$i < [llength $owners]} {incr i} {
	set owner_this_week [lindex $owners_this_week $i]
	set owner_next_week [lindex $owners_next_week $i]
	set output_string [format "%1s   * %-10s %2d * %-10s %2d" [get_property $owner_this_week "roster_received"] $owner_this_week \
		[get_property $owner_this_week "last_claim_week"] $owner_next_week [get_property $owner_next_week "next_claim_week"]]
	puts $oool_fd $output_string
    }
    
    puts $oool_fd ""
    puts $oool_fd {"N" means I did not receive a roster}
    puts $oool_fd {"R" means I received a roster}
    puts $oool_fd ""
}
    
# Output transaction summary

set transactions_file [open "Transactions.txt"]
fconfigure $transactions_file -encoding macRoman
set transaction_contents [read $transactions_file]
close $transactions_file

puts $oool_fd "TRANSACTIONS:"
puts $oool_fd ""

set transaction_items [split $transaction_contents \n]
set saw_transaction "no"
foreach transaction $transaction_items {
    set owner [lindex $transaction 0]
    if {[string equal $owner {}]} {
	continue
    }
    set saw_transaction "yes"
    puts $oool_fd $transaction
    
    # Store away for output with printout of rosters.

    # Strip off owner and dash
    if {[regsub -line {^[^\s]* - } $transaction "" transaction]} {
	if {[catch {set owner_trans [get_property $owner "transactions"]}]} {
	    set owner_trans $transaction
	} else {
	    lappend owner_trans $transaction
	}
	set_property $owner "transactions" $owner_trans
    }
}
if {[string equal $saw_transaction "no"]} {
    puts $oool_fd "    * None"
}
puts $oool_fd ""

# Process draft picks so that they can be output in the owner loop

if {[catch {open "Draft Picks.txt"} draft_picks_file]} {
  set draft_pick_items ""
} else {
  fconfigure $draft_picks_file -encoding macRoman
  set draft_pick_contents [read $draft_picks_file]
  close $draft_picks_file
  set draft_pick_items [split $draft_pick_contents \n]
}

foreach pick $draft_pick_items {
    set pick_items [split $pick \t]
    set acquirer [lindex $pick_items 0]
    if {[string equal $acquirer {}]} {
	continue
    }
    set releaser [lindex $pick_items 1]
    set round [lindex $pick_items 2]
    
    set_property $releaser $round $acquirer
    set new_acquirer [get_property $releaser $round]
}

set draft_rounds {1st 2nd 3rd 4th 5th 6th 7th 8th 9th 10th 11th 12th 13th 14th 15th 16th 17th 18th 19th 20th 21st 22nd 23rd 24th 25th 26th 27th 28th 29th 30th 31st 32nd 33rd 34th 35th 36th 37th 38th 39th 40th 41st 42nd 43rd 44th 45th 46th 47th 48th 49th 50th}
    
foreach releaser $owners {
    foreach round $draft_rounds {
	set acquirer [get_property $releaser $round]
	if {![string equal $acquirer {}]} {
	    if {[catch {set acquirer_draft_list [get_property $acquirer "draft_picks"]}]} {
		set acquirer_draft_list {}
	    }
	    set item [list $round $releaser "from"]
	    lappend acquirer_draft_list $item
	    set_property $acquirer "draft_picks" $acquirer_draft_list
	       
	    if {[catch {set releaser_draft_list [get_property $releaser "draft_picks"]}]} {
		set releaser_draft_list {}
	    }
	    set item [list $round $acquirer "to"]
	    lappend releaser_draft_list $item
	    set_property $releaser "draft_picks" $releaser_draft_list
	}
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

set owners [lsort $owners]

proc strip_ordinal ordinal {
    regsub {st} $ordinal {} result
    regsub {nd} $result {} result
    regsub {rd} $result {} result
    regsub {th} $result {} result
    return $result
}

proc sort_draft_list {owner pick1 pick2} {
    set round_for1 [strip_ordinal [lindex $pick1 0]]
    set round_for2 [strip_ordinal [lindex $pick2 0]]
 
    return [expr $round_for1 > $round_for2]
}

# Output a keeper year summary during the offseason

if {$off_season} {
    puts $oool_fd "CURRENT KEEPER YEAR TOTAL:"
    puts $oool_fd ""
    
    foreach owner $owners {
	set years [get_property $owner "keeper_years"]
	puts $oool_fd "$owner - $years"
    }
    puts $oool_fd ""
}

# Calcuate backup positions for a given owners bench

proc validate_bench_backups {owner} {
    global off_season
    
    set bench [get_property $owner "bench"]
    set bench_size [llength $bench]

    set of1 [lindex [get_property $owner "OF1"] 2]
    set of2 [lindex [get_property $owner "OF2"] 2]
    if {![string equal $of1 $of2]} {
	puts stderr "For owner $owner: OF1 backups and OF2 backups need to match - $of1 vs. $of2"
    }
    set of3 [lindex [get_property $owner "OF3"] 2]
    if {![string equal $of1 $of3]} {
	puts stderr "For owner $owner: OF1 backups and OF3 backups need to match - $of1 vs. $of3"
    }
    if {![string equal $of2 $of3]} {
	puts stderr "For owner $owner: OF2 backups and OF3 backups need to match - $of2 vs. $of3"
    }
    
    foreach position "C 1B 2B 3B SS OF1 DH" {
	set backups [lindex [get_property $owner $position] 2]
	set backup_list [split $backups ","]
	foreach backup $backup_list {
	    if {$backup > $bench_size} {
		puts stderr "There is no backup $backup for owner $owner"
	    }
	    # Split list aprt
	    set player [lindex $bench [expr $backup - 1]]
	    set name [lindex $player 0]
	    set team [lindex $player 1]
	    set positions_text [lindex $player 2]
	    set keeper_years [lindex $player 3]
	    set lahmanID [lindex $player 4]
	    set statsID [lindex $player 5]
	    set sydID [lindex $player 6]
	    
	    # Now, adjust the backup positions
	    set pos $position
	    if {[string equal $pos "OF1"]} {
		set pos "OF"
	    }
	    if {!$off_season && ![string equal $pos "DH"]} {
		set eligible [get_property $sydID $pos]
		if {![string equal $eligible "Yes"]} {
		    puts stderr "$owner - $name/$team is not eligible at position $pos"
		}
	    }
	    if {![string equal $positions_text {}]} {
		set positions_text [append positions_text ","]
	    }
	    set positions_text [append positions_text "$pos"]
	    set player [list $name $team $positions_text $keeper_years $lahmanID $statsID $sydID]
	    set bench [lreplace $bench [expr $backup - 1] [expr $backup - 1] $player]
	}
    }
    set_property $owner "bench" $bench
}

# Now, set up rosters

set rosters_file [open "Rosters_raw.txt"]
set roster_contents [read $rosters_file]
close $rosters_file
set roster_items [split $roster_contents \n]

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

    if {$keeper_years == ""} {
      set keeper_years 1
    }

    if {[string equal $owner {}]} {
	continue
    }

    set player_count [get_property $owner "player_count"]
    incr player_count
    set_property $owner "player_count" $player_count

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
    
    if {[string equal $position "IR"]} {
	set reserves [get_property $owner "IR"]
	lappend reserves [list $player $team $keeper_years $lahmanID $statsID $sydID]
	set_property $owner "IR" $reserves
    } elseif {[regexp {B\d} $position match]} {
	set bench [get_property $owner "bench"]
	lappend bench [list $player $team "" $keeper_years $lahmanID $statsID $sydID]
	set_property $owner "bench" $bench
    } elseif {[regexp {SW\d} $position match]} {
	set swing [get_property $owner "swing"]
	lappend swing [list $player $team $backups $keeper_years $lahmanID $statsID $sydID]
	set_property $owner "swing" $swing
    } else {
	set old_position [get_property $owner $position]
	if {![string equal $old_position {}]} {
	      puts stderr "Owner $owner already has a $position - $old_position vs. [list $player $team $backups]"
	}
	if {[string equal $position "OF1"] || [string equal $position "OF2"] || [string equal $position "OF3"]} {
	    set pos_elig "OF"
	} else {
	    set pos_elig $position
	}
	if {[string equal $pos_elig "C"] || [string equal $pos_elig "1B"] || [string equal $pos_elig "2B"] 
		|| [string equal $pos_elig "3B"] || [string equal $pos_elig "SS"] 
		|| [string equal $pos_elig "OF"]} {
	    set eligible [get_property $sydID $pos_elig]
	    if {!$off_season && ![string equal $eligible "Yes"]} {
		puts stderr "$owner - Player $player is not eligible at position $pos_elig"
	    }
	}
	set_property $owner $position [list $player $team $backups $keeper_years $lahmanID $statsID $sydID]
    }
}

proc format_roster_item {position player team backup keeper_years} {
    global off_season
    global show_keepers_for_players
    
    set player_string [format "%.26s/%s" $player $team]
    if {$off_season} {
	if {$keeper_years == {} || $keeper_years == 0} {
	    puts stderr "No keeper years for player $player_string"
	}
	if {$show_keepers_for_players} {
	  return [string trim [format "%-3s %-30s %2d" $position $player_string $keeper_years]]
	} else {
	  return [string trim [format "%-3s %-30s" $position $player_string]]
	}
    } else {
	return [string trim [format "%-3s %-30s %s" $position $player_string $backup]]
    }
}

proc format_for_scoring {owner position player team backup} {
    return [format "%-8s%-3s     %-23s%-3s%-37s" $owner $position $player $team $backup]
}

foreach owner $owners {
    global off_season
    global show_keepers_for_players
    
    if {!$off_season} {
	validate_bench_backups $owner
    }

    set player_count [get_property $owner "player_count"]
    if {!$off_season && $player_count > 35} {
      puts stderr "Owner $owner has $player_count players, which is greater than 35"
    }

    puts $oool_fd [get_property $owner "team_name"]
    set short_name [get_property $owner "short_name"]

    if {!$off_season} {
	puts $oool_fd "\nTRANSACTIONS:"
    
	# Put out transactions
	set owner_trans [get_property $owner "transactions"]
	if {![string equal $owner_trans {}]} {
	    foreach tran $owner_trans {
		puts $oool_fd "        * $tran"
	    }
	} else {
	    puts $oool_fd "        * None"
	}
    }

    puts $oool_fd ""
    
    # Output draft list for the owner
    set draft_list [get_property $owner "draft_picks"]
    if {![string equal $draft_list {}]} {
	puts $oool_fd "NOTES:"
	    
	set sorted_draft_list [lsort -command "sort_draft_list $owner" $draft_list]
	foreach item $sorted_draft_list {
	    set round [lindex $item 0]
	    set other_owner [lindex $item 1]
	    if {[string equal $owner $other_owner]} {
	      continue
	    }
	    set to_from [lindex $item 2]
	    if {[string equal $to_from "to"]} {
		set sign_string "-"
	    } elseif {[string equal $to_from "from"]} {
		set sign_string "+"
	    } else {
		error "Something screwy here"
	    }
	    puts $oool_fd "        $sign_string$round round draft pick \($to_from $other_owner)"
	}
	puts $oool_fd ""
    }

    # Output keeper list for owner
    set keeper_list [get_property $owner "keeper_trades"]
    if {![string equal $keeper_list {}]} {
        if {[string equal $draft_list {}]} {
            puts $oool_fd "\nNOTES:"
        }
	    
	foreach item $keeper_list {
            set years [lindex $item 0]
            set other_owner [lindex $item 1]
	    set to_from [lindex $item 2]
	    if {[string equal $to_from "to"]} {
		set sign_string "-"
	    } elseif {[string equal $to_from "from"]} {
		set sign_string "+"
	    } else {
		error "Something screwy here"
	    }
	    puts $oool_fd "        $sign_string$years keeper years \($to_from $other_owner)"
	}
	puts $oool_fd ""
    }
    
    if {$off_season} {
	puts $oool_fd "Keeper years available - [get_property $owner keeper_years]"
	if {$show_keepers_for_players} {
	  puts $oool_fd "Keeper years total - [get_property $owner keeper_total]"
	}
	puts $oool_fd ""
    }
    
    # Now output roster items
    
    # Normal positions
    foreach position "C 1B 2B 3B SS OF1 OF2 OF3 DH" {
	set roster_item [get_property $owner $position]
	if {[string equal $roster_item ""]} {
	    if {$off_season} {
		continue
	    } else {
		puts stderr "Owner $owner has no $position"
	    }
	}
	set player [lindex $roster_item 0]
	set team [lindex $roster_item 1]
	set backups [lindex $roster_item 2]
	set keeper_years [lindex $roster_item 3]
	set formatted_roster_item [format_roster_item $position $player $team $backups $keeper_years]
	puts $oool_fd $formatted_roster_item
	set statsID [lindex $roster_item 5]
	if {[string equal $statsID ""]} {
	  puts "No statsID for $formatted_roster_item"
	}
    }
    if {!$off_season} {
	puts $oool_fd ""
    }
    
    # Backup position players
    
    set reserves [get_property $owner "bench"]
    set num_reserves [llength $reserves]
    set current_reserve 0
    foreach reserve $reserves {
	incr current_reserve
	set position "B$current_reserve"
	set player [lindex $reserve 0]
	set team [lindex $reserve 1]
	set backups [lindex $reserve 2]
	set keeper_years [lindex $reserve 3]
	set formatted_roster_item [format_roster_item $position $player $team $backups $keeper_years]
	puts $oool_fd $formatted_roster_item
	set statsID [lindex $reserve 5]
	if {[string equal $statsID ""]} {
	  puts "No statsID for $formatted_roster_item"
	}
    }
    if {!$off_season} {
	puts $oool_fd ""
    }

    # Starting picthing
    foreach position "SP1 SP2 SP3 SP4 SP5" {
	set roster_item [get_property $owner $position]
	if {[string equal $roster_item ""]} {
	    if {$off_season} {
		continue
	    } else {
		puts stderr "Owner $owner has no $position"
	    }
	}
	set player [lindex $roster_item 0]
	set team [lindex $roster_item 1]
	set keeper_years [lindex $roster_item 3]
	set formatted_roster_item [format_roster_item $position $player $team "" $keeper_years]
	puts $oool_fd $formatted_roster_item
	set statsID [lindex $roster_item 5]
	if {[string equal $statsID ""]} {
	  puts "No statsID for $formatted_roster_item"
	}
    }
    if {!$off_season} {
	puts $oool_fd ""
    }
    
    # Swing pitchers - but first make sure that roster is sane
    set swing [get_property $owner "swing"]
    set num_swing [llength $swing]
    if {$num_swing + $num_reserves > 8} {
	if {!$off_season} {
	    puts stderr "Wrong number of players - owner: $owner; bench: $num_reserves; swing: $num_swing"
	}
    }
    set current_swing 0
    foreach pitcher $swing {
	incr current_swing
	set position "SW$current_swing"
	set player [lindex $pitcher 0]
	set team [lindex $pitcher 1]
	set keeper_years [lindex $pitcher 3]
	set formatted_roster_item [format_roster_item $position $player $team "" $keeper_years]
	puts $oool_fd $formatted_roster_item
	set statsID [lindex $pitcher 5]
	if {[string equal $statsID ""]} {
	  puts "No statsID for $formatted_roster_item"
	}
    }
    if {!$off_season} {
	puts $oool_fd ""
    }
    
    # Relief pitching
    foreach position "RP1 RP2 RP3" {
	set roster_item [get_property $owner $position]
	if {[string equal $roster_item ""]} {
	    if {$off_season} {
		continue
	    } else {
		puts stderr "Owner $owner has no $position"
	    }
	}
	set player [lindex $roster_item 0]
	set team [lindex $roster_item 1]
	set keeper_years [lindex $roster_item 3]
	set formatted_roster_item [format_roster_item $position $player $team "" $keeper_years]
	puts $oool_fd $formatted_roster_item
	set statsID [lindex $roster_item 5]
	if {[string equal $statsID ""]} {
	  puts "No statsID for $formatted_roster_item"
	}
    }
    if {!$off_season} {
	puts $oool_fd ""
    }
    
    # Injured reserve
    set reserves [get_property $owner "IR"]
    set num_reserves [llength $reserves]
    if {$num_reserves > 0} {
	foreach reserve $reserves {
	    set player [lindex $reserve 0]
	    set team [lindex $reserve 1]
	    set keeper_years [lindex $reserve 2]
	    set formatted_roster_item [format_roster_item "IR" $player $team "" $keeper_years]
	    puts $oool_fd $formatted_roster_item
	}
	if {!$off_season} {
	    puts $oool_fd ""
	}
    }
    if {$off_season} {
	puts $oool_fd ""
    }
}


# If offseason, output draft order

if {$off_season} {
    set draft_order_fd [open "Draft Order.txt" w]
    set pick_counter 1
    set count_players 1
    set round_threshold 100
    
    # We no longer do S-shaped draft, but if we ever go back, change this to 1
    set snake_order 0
    
    if {$raw_draft_order} {
	set count_players 0
	set round_threshold 35
    }
    
    for {set round 0} {$round < $round_threshold} {incr round} {
	set owner_count [llength $owners_this_week]
	if {$snake_order && ($round %2) != 0} {
	    set owner_position [expr $owner_count - 1]
	    set direction decreasing
	} else {
	    set owner_position 0
	    set direction increasing
	}
	set done 0
	while {!$done} {
	    set owner [lindex $owners_this_week $owner_position]
	    set round_text [lindex $draft_rounds $round]
	    set pick_owner [get_property $owner $round_text]
	    if {[string equal $pick_owner {}]} {
		set pick_owner $owner
		set supplemental_text ""
	    } else {
		set supplemental_text "\t\(from $owner\)"
	    }

	    set output_string [format "%2d %3d %-10s %s" [expr $round + 1] $pick_counter $pick_owner $supplemental_text]
	    if {$count_players} {
		set player_count [get_property $pick_owner "player_count"]
		if {$player_count < 35} {
		    puts $draft_order_fd $output_string
		    incr pick_counter
		    incr player_count
		    set_property $pick_owner "player_count" $player_count
		}
	    } else {
		puts $draft_order_fd $output_string
		incr pick_counter
	    }

	    if {[string equal $direction "increasing"]} {
		incr owner_position
		if {$owner_position == $owner_count} {
		    break
		}
	    } elseif {[string equal $direction "decreasing"]} {
		if {$owner_position == 0} {
		    break
		}
		incr owner_position -1
	    } else {
		error "Invalid direction $direction"
	    }
	}
    }    
    close $draft_order_fd
}

close $oool_fd

if {$populate_database} {
  package require populate_database
  populate_database $week $debug
}
