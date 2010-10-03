package provide timezoneutils 1.0

package require Tcl

#//#
# zone utils for timezone manipulation 
#
# @author bill
# @version 1.0
#//#


namespace eval ::timezoneutils:: { 

}

# Find the local timezone offset in seconds
#
#@param timestamp the timestamp 
#
proc ::timezoneutils::tzOffsetSeconds {timestamp} {

	set tzoffset [clock format $timestamp -format {%z}]
	set multiplier "[string index $tzoffset 0]1"
	set hours [string range $tzoffset 1 2]
	set minutes [string range $tzoffset 3 4]
	
	return [expr { $multiplier * ( ( $hours * 3600 ) + ( $minutes * 60 ) ) }]
}
