package provide property_utils 1.0

proc set_property {dictionary property value} {
  global debug_properties
  global $dictionary
  array set $dictionary [list $property $value]
  if {[info exists debug_properties] && $debug_properties} {
    puts stderr "set_property $dictionary $property $value"
  }
}

proc must_get_property {dictionary property} {
    global $dictionary
    global strict_get_property
    global debug_properties
    set result [lindex [array get $dictionary $property] 1]
    if {[info exists debug_properties] && $debug_properties} {
      puts stderr "must_get_property $dictionary $property => $result"
    }
    if {![info exists strict_get_property] || ($strict_get_property == 0)} {
      return $result
    } elseif {[string equal $result ""]} {
      error "must_get_property $dictionary $property returned NULL."
    } else {
      return $result
    }
}

proc get_property {dictionary property} {
    global $dictionary
    global debug_properties
    set result [lindex [array get $dictionary $property] 1]
    if {[info exists debug_properties] && $debug_properties} {
      puts stderr "get_property_null_ok $dictionary $property => $result"
    }
    return $result
}
