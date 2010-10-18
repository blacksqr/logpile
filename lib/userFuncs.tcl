package provide logpile::userfuncs 1.0

package require logpile
package require struct::set
package require term::ansi::ctrl::unix

namespace eval ::logpile::userfuncs {

}

proc usersbyhost {query} {

	array set bar {}
	::logpile::search $query bar -command returnUsersByHost
	set message ""

	if { ! [info exists ::logpile::resultscount] } { set ::logpile::resultscount 0 }

	if { [array size bar] > 0 } {

		foreach key [array names bar] {

			incr ::logpile::resultscount
			set message [format "%s\n%s:   %s\n----" $message $key [lsort [lindex [array get bar $key] 1]]]
		}

	}

return $message
}

proc returnUsersByHost {iterator matchcount aresults} {

        upvar 1 $aresults results

        set doc [$iterator get_document]
	set data [lindex [$doc get_data] 1]
        #set results($matchcount) [list [$iterator get_docid] [$iterator get_percent] [xapian::sortable_unserialise [$doc get_value 1]] [$doc get_data]]
	set hostname [lindex $data 3]
	#if { [regexp -nocase { (user|by|for|for user)( invalid user | name: | illegal user | )([^ ]*)} $data {} {} {} username]  } { }
	if { [regexp -nocase {(?:user has not [a-zA-Z ]+?)?(?:Unknown user name [a-zA-Z ]+?)?(?:user account locked out: )?(user|by|for|for user|target account name:)( invalid user | name: | illegal user | )([^ ]*)} \
		 $data {} {} {} username]  } {

		set username [regsub -all {[\\'\}\{:]} $username ""]
		set list [lindex [array get results $hostname] 1]
		::struct::set add list $username
		array set results [list $hostname $list]
	}
        rename $doc ""
}


proc graphResultsOverTime {query} {

	array set results {}

	set q $query

	::logpile::setupDaterange begin end matchto q

	set diff [expr {$end-$begin}]
	set incr [expr {int(ceil($diff/([term::ansi::ctrl::unix::columns]-1.0)))}]
	logpile::userfuncs::setupBucketsResultsOverTime $begin $end $incr bucket_names results

	::logpile::search $query results -command returnResultsOverTime
	set rows [expr {int(ceil([term::ansi::ctrl::unix::rows]-13.0))}]

	set max 0

	foreach x $bucket_names {

		if { $results($x) > $max } { set max $results($x) }
	}


	puts "max: $max"
	#puts "rows: $rows"

	set max [expr {log($max)}]

	set row_factor [expr {$rows/$max}]
	set max [expr {int($max*$row_factor)}]

	#puts "logmax: $max factor $row_factor"

	for { set line $max } { $line >= 0 } { incr line -1 } {

		foreach x $bucket_names {
			if { $line <= [expr {$row_factor*log($results($x))}] } {
				puts -nonewline "#"
			} else {
				puts -nonewline "."
			}
		}
		puts ""
	}

	set mark 0
	for {set line 0} { $line < 9 } { incr line } { 

		foreach x $bucket_names {

			if { $mark == 0 } {
				puts -nonewline [string index [clock format $x -format {%m%d %H%M%S}] $line]
				set mark 1
			} else { 
				puts -nonewline " "
				set mark 0
			}
		}
		puts ""
		set mark 0
	}

}

proc returnResultsOverTime {iterator matchcount aresults} {

        upvar 1 $aresults results
	set doc [$iterator get_document]
	set date [expr {int( [xapian::sortable_unserialise [$doc get_value 1]] ) }]
	set dest -1
	set destdiff 9999999999999

	foreach b [array names results] {

		set diff [expr { $date - $b }]
		if { ( $diff >= 0 && $diff < $destdiff ) } {

			set destdiff $diff
			set dest $b
			#puts "here: $b for $date"
		}
	}
	#puts [$doc get_data]
	#puts "here: $dest for $date"
	#logpile::log_debug "here"
	if {  $dest != -1 } { 
		set x $results($dest)
		incr x
		array set results "$dest $x"
	} else {
		::logpile::log_debug "discarding $date not in range"
	}
	#puts "$dest : $results($dest)"
	rename $doc ""
}

proc getResultsOverTime {query bkt_nms res} {

	upvar 1 $res results
	upvar 1 $bkt_nms bucket_names
	set q $query

	::logpile::setupDaterange begin end matchto q

	set diff [expr {$end-$begin}]
	set incr [expr {int(ceil($diff/([term::ansi::ctrl::unix::columns]-1.0)))}]
	logpile::userfuncs::setupBucketsResultsOverTime $begin $end $incr bucket_names results

	::logpile::search $query results -command returnResultsOverTime
	set rows [expr {int(ceil([term::ansi::ctrl::unix::rows]-13.0))}]

	set max 0
}

proc printResultsOverTime {query} {

	getResultsOverTime $query bucket_names results

	foreach x $bucket_names {

		puts "[array get results $x]"
	}
}

proc ::logpile::userfuncs::setupBucketsResultsOverTime {begin end incr bucketnames reslts} {

	upvar 1 $reslts results
	upvar 1 $bucketnames bucket_names

	for {set x $begin} {$x <= $end} {incr x $incr} {

		lappend bucket_names $x
		array set results "$x 0"
	}
}
