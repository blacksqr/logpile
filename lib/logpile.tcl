package provide logpile 1.5

package require Tcl
package require logger
package require xapian
package require fileutil::traverse
package require fileutil
package require logpile::filetraverse
package require timezoneutils

#//#
# logpile is a library for indexing and searching log data
# using xapian.
#
# @author bill
# @version 1.3
# @see http://xapian.org/ Xapian
#//#


namespace eval ::logpile:: { 

	catch {
		###setup logger
		set log [logger::init index]
		logger::import -prefix log_ index
		${log}::setlevel $loglevel
	}

	set matchdaterange {[0-9]+-[0-9]+-[0-9]+(T[0-9]+:[0-9]+(:[0-9]+|)|)\.\.[0-9]+-[0-9]+-[0-9]+(T[0-9]+:[0-9]+(:[0-9]+|)|)}
	set matchmatches {(^| )RESULTS:[0-9]+($| )}
	set pastmatches {(^| )PAST:([0-9]+([a-zA-Z]|))($| )}
	set loglevel emergency
	set indexingline ""
}

set ::logpile::usage_string { <query> <minutes past> <destemailaddrs> <subject>

  query format:
    daterange: 2009-09-09T00:00..2009-09-10
    host: HOST:hostname
    tag: TAG:snmpd
    past timerange: PAST:1(h|m|s|Y|M|D)
    # of results: RESULTS:<number>
    example query:
    search "2009-09-09T00:00..2009-09-10 TAG:postfix HOST:hostname RESULTS:200 user@example.com"
    operators: AND OR NOT ()
    
  wildcards can be used for searches so foo* would match foo and foobar etc...
}

# index a file to a dated index in dbpath
#
#@param dbpath database directory
#@param indexfile file to index
#@param doProgress 1 to show progress dots 0 (default) to show no progress
#@param loglevel loglevel to log at (emergency default) 
#@param autocommit 1 to automatically commit transactions (default 0)
#@param detectgmt integer(seconds) if the time is wthin x seconds of localtime 
#and offset by local timeoffset, assume we are processing a gmt logline.
#this only works for realtime (fifo) processing (default 0)
#@see http://tcllib.sourceforge.net/doc/logger.html tcllib::logger
#
proc ::logpile::indexLogfile { dbpath indexfile {doProgress 0} {loglevel emergency} {autocommit 0} {detectgmt 0} } {


	set start [clock seconds]
	set count 0
	set db ""
	set dbdate ""
	${::logpile::log}::setlevel $loglevel

	#open the file or proc (if its a compressed file)
	set fp [detectFile $indexfile]

	set year [guessYear $indexfile] 

	log_debug "reading $indexfile"

	#register a flush every 60000ms
	if { $autocommit } {

		::logpile::commitEvery 60000
	}

	set lastdate 0
	while { -1 != [gets $fp line] } {

		set linelist [split $line]
		#"default" position in the logs we expect to find the host field
		set hostpos 3

		::logpile::showProgress $count $doProgress

		if { $detectgmt > 0 } {

			set date [guessDate $line $linelist $year hostpos -detectgmt $detectgmt]
		} else {

			set date [guessDate $line $linelist $year hostpos ]
		}

		set curdate [clock format $date -format "%Y/%m/%d"]

		#attempt to only open the database if we have to (if the date changed for some reason)
		if { $curdate != $dbdate } {
			
			set month [clock format $lastdate -format {%m}]
			set nmonth [clock format $date -format {%m}]
			#if time went backwards 
			if { $date < $lastdate } {

				#looks like a year change
				if { $month == 12 && $nmonth == 1 } {
					
					log_debug "time went backwards, and its january: advancing 1 year"
					incr year
					incr date 31536000
					set curdate [clock format $date -format "%Y/%m/%d"]
				} 
			#assume we have loglines that are bouncing back and forth from dec to jan (different years)
			} elseif { $month == 1 && $nmonth == 12 } {
				
				incr year -1
				incr date -31536000
				set curdate [clock format $date -format "%Y/%m/%d"]
				log_notice "guessing year went backwards $dbdate -> $curdate"
			}

			set lastdate $date
			::logpile::closeIndexDatabase $db 
			set db [::logpile::openIndexDatabase "$dbpath/$curdate"]
			set dbdate $curdate
			log_notice "opening $dbpath/$curdate"
			set lastdate $date
		}

		set hostname [guessHost $linelist $hostpos]

		set tag [guessTag $line $linelist $hostpos]

		indexRecord $db $indexfile $line $date $hostname $tag

		#allow the event loop to update for waiting tasks
		update

		incr count
	}

	::logpile::closeIndexDatabase $db

	close $fp

	#clear to a new line if we are showing progress
	if { $doProgress } { puts stderr "" }

	set stop [clock seconds]
	set diff [expr {$stop-$start}]
	set persec 0

	if { $diff > 0 } {
		set persec [expr {$count/$diff}]
	}

	log_notice "Indexed $count documents in $diff seconds ($persec doc/sec)"
}

#flush write db every x seconds
#
#@param ms milliseconds commit interval
#@param db xapian::WriteableDatabase
#
proc ::logpile::commitEvery { ms }  {

	after $ms "::logpile::commitEvery $ms"
	catch {
		::logpile::xapiandb flush
		::logpile::log_debug "db flushed"
	}
}

#detect filetype based on extension
#
#@param file filename to guess type based on extension
#@return file handle
#
proc ::logpile::detectFile {file} {

	set ext [file extension $file] 
	switch $ext {

		.bz2 {

			log_debug "detected bzip2"
			set fh [open "|bzip2 -dc $file" r]
		}

		.gz {

			log_debug "detected gzip"
			set fh [open "|gzip -dc $file" r]
		}

		default {

			log_debug "detected text"
			set fh [open $file r]
		}
	}

	fconfigure $fh -buffering line -buffersize 1024000

return $fh
}

#guess a year based on a filename
#
#@param file filename
#@return best guess at what year that file represents
#
proc ::logpile::guessYear {file} {

	set returnvalue [clock format [clock seconds] -format {%Y}]
	catch {
		set start [ string first "-" $file ] 
		if { $start > -1 } {

			set end [ string first "-" $file [expr {$start+1}] ]
			if { $end > -1 } {

				set returnvalue [string range $file [expr {$start+1}] [expr {$end-1}] ]
			}
		} else {

			log_debug "filename $file doesn't appear to have a date"

		}
	}

	log_notice "Guessing year is $returnvalue"

return $returnvalue
}

#open a writable xapian index 
#
#@param file path to index to open (writable)
#@return xapian::WritableDatabase
#
proc ::logpile::openIndexDatabase {file} {

	if {![file isdirectory $file]} {

		if {[file exists $file]} {

			log_error "Cannot create index cache dir"
		} else  {

			file mkdir $file
		}
	}

	while { [ catch { set db [xapian::WritableDatabase ::logpile::xapiandb $file $::xapian::DB_CREATE_OR_OPEN] } ] } {

		log_notice "waiting for lock on $file"
		after 5000
	}

return $db
}

#close a xapian database
#
#@param db xapian::Database
#
proc ::logpile::closeIndexDatabase {db} {

	if { $db != "" } {

		catch {$db flush}
		catch {::logpile::xapiandb flush}
		$db -delete
		::logpile::xapiandb -delete
	}
}

#guess a hostname
#
#@param linelist a list version of the logline(split)
#@param hostpos position in the logs we expect to find the host field
#
proc ::logpile::guessHost {linelist hostpos} {

		return [lindex $linelist $hostpos]
}

#guess a tag based on a logline
#
#@param line logline
#@param linelist a list version of the line (split)
#@param hostpos position in the logs we expect to find the host field
#
proc ::logpile::guessTag {line linelist hostpos} {

	set tag [lindex $linelist [expr "$hostpos+1"]] 

	if { [regexp {^[0-9.]+(:|)$} $tag] || ! [regexp {[0-9a-zA-Z]+} $tag]  } {

		set tag "unknown"
	} else {

		set tag [regsub {\[[0-9]+\]} $tag ""]
	}

return $tag
}

#show a . for every 100 count
#
#@param count current progress count
#@param doProgress 1 to show progress, 0 to disable
#
proc ::logpile::showProgress {count doProgress} {

	if { $doProgress && [expr { $count %100 } ] == 0 } {

		puts -nonewline stderr "."
	}
}

#guess date in logline 
#
#@param line logline
#@param linelist a list version of the line (split)
#@param year year that we think this logline is in
#@param hostpos (upvar) position in the logs we expect to find the host field
#@param args (-detectgmt <timevariance in seconds> detect gmt passed in realtime proccessing within <timevariance> )
#
proc ::logpile::guessDate {line linelist year hostpos args} {

	upvar 1 $hostpos hp

	array set ar {}

	::logpile::parseargs ar $args

	#test for stupid windows 5 instead of 05
	if { [lindex $linelist 1] == "" } {

		#non-padded number
		set date "[lindex $linelist 0] [lrange $linelist 2 3]" 
		incr hp
	} else {

		#0 padded number
		set date "[lrange $linelist 0 2]"  
	}

	#remove trailing : from apple syslog lines:
	#Oct  2 00:32:52: --- last message repeated 1 time ---
	set date [string trimright $date ":"]

	#parse the date into a timestamp
	set date [clock scan "$date $year"]

	foreach a [array names ar] {

		switch -- $a {
			
			-detectgmt {

				set now [clock seconds]
				set offset [::timezoneutils::tzOffsetSeconds $now]
				###if the difference between current time and timestamp + offset is less than or 
				###equal to the acceptable delta, offset this timestamp as if it was gmt and we
				###are expecting localtime
				if { ( abs($now - ($date + $offset)) ) <= [lindex [array get ar -detectgmt] 1]} {

					log_debug "detected gmt timestamp: $line"
					set date [expr {$date + $offset}]
				}
			}
		}
	}

return $date
}

#index a line
#
#@param db xapian::WritableDatabase
#@param indexfile the file that the logline came from
#@param line index logline
#@param date unix timestamp date
#@param hostname hostname this line came from
#@param tag tag from this line
#
proc ::logpile::indexRecord {db indexfile line date hostname tag} {

	set doc [xapian::Document]
	set tgen [xapian::TermGenerator tgen]

	#log_debug "date: $date hostname: $hostname tag: $tag"
	$doc set_data [list $indexfile $line]
	$tgen set_document $doc
	$tgen index_text $hostname 1 "HOST"
	$tgen index_text $tag 1 "TAG"
	#"default" text used for untagged searches
	$tgen index_text $line 0
	$doc add_value 1 [xapian::sortable_serialise $date]
	$doc add_value 3 $hostname
	$doc add_value 4 $tag
	$db add_document $doc

	$doc -delete
	$tgen -delete
	rename tgen ""

	set ::logpile::indexingline $line
}

#search and remove results from the index
#
#@param dbpath path to index databases
#@param query query
#@param loglevel loglevel (default emergency)
#@see http://tcllib.sourceforge.net/doc/logger.html tcllib::logger
#
proc ::logpile::searchRemove {dbpath query {loglevel emergency} } {

	${::logpile::log}::setlevel $loglevel

	array set results {}
	set startrange 0
	set endrange 0
	set dbcount 0
	set x 0
	set start [clock seconds]
	set matches 0
	set totaldoccount 0
	set matchto 1000
	if { [info exists ::logpile::conf::defaultresults ] } { set matchto $::logpile::conf::defaultresults }
	set totalindexes 0

	::logpile::setupDaterange startrange endrange matchto query

	log_debug "using query: $query"

	set startrange [clock scan [clock format $startrange -format {%Y/%m/%d}] -format {%Y/%m/%d}]
        set endrange [clock scan [clock format $endrange -format {%Y/%m/%d}] -format {%Y/%m/%d}]

	for { set x $startrange } { $x <= $endrange && $matches < $matchto } { incr x 86400 } {

		if { [::logpile::testDbPath dbpath x] } {

			incr totalindexes 
			set databases [::xapian::WritableDatabase ::logpile::xapiandb $dbpath $::xapian::DB_OPEN]
			incr matches [doRemove $databases $query results $matchto $matches]
			incr totaldoccount [$databases get_doccount]
			$databases -delete
			::logpile::xapiandb -delete
			::logpile::cleanup
		}
	}

	log_info "$matches results found"
	set stop [clock seconds]


	log_info "took [expr {$stop-$start}] seconds"
	log_info "total docs searched: $totaldoccount across $totalindexes indexes"
}

#parse flag args and set an array of flags
#
#@param aaray (upvar) array that will contain the parsed results
#@param args list of flag arguments
#
proc ::logpile::parseargs { aaray args } {

	upvar 1 $aaray ar

	foreach a [lindex $args 0] {

		if { 0 == [string first "-" $a] } {
			set last $a
			array set ar [list $a 1]
		} elseif { [info exists last] } {

			array set ar [list $last $a]
		}
	}

}

#run a search query against the index defined by ::logpile::conf::indexpath or -indexpath
#
#@param query query
#@param aresults (upvar) array results can be (optionally) returned in
#@param args -command -loglevel and -indexpath
#
proc ::logpile::search { query aresults args } {
	
	upvar 1 $aresults results

	array set ar {}

	::logpile::parseargs ar $args

	set indexpath $::logpile::conf::indexpath
	set loglevel $::logpile::loglevel
	set command returnResults

	foreach a [array names ar] {

		switch -- $a {

			-command { set command [lindex [array get ar -command] 1] }
			-loglevel { set loglevel [lindex [array get ar -loglevel] 1] }
			-indexpath { set indexpath [lindex [array get ar -indexpath] 1] }
		}
	}

	array set results {}

	searchPath $indexpath $query results $command $loglevel
}

#run a query against a directory of indexes
#
#@param dbpath path to indexes
#@param query query
#@param aresults (upvar) arrray for results to be returned in
#@param command search command to run (defaults to returnResults
#@param loglevel defaults to emergency
#@see http://tcllib.sourceforge.net/doc/logger.html tcllib::logger
#
proc ::logpile::searchPath {dbpath query aresults {command returnResults} {loglevel emergency} } {

	upvar 1 $aresults results

	${::logpile::log}::setlevel $loglevel

	set startrange 0
	set endrange 0
	set dbcount 0
	set x 0
	set databases [::xapian::Database]
	set start [clock seconds]
	set matches 0
	set totaldoccount 0
	set matchto 1000
	if { [info exists ::logpile::conf::defaultresults ] } { set matchto $::logpile::conf::defaultresults }
	set totalindexes 0

	::logpile::setupDaterange startrange endrange matchto query

	log_debug "using query: $query"

	set startrange [clock scan [clock format $startrange -format {%Y-%m-%d}] ]
        set endrange [clock scan [clock format $endrange -format {%Y-%m-%d}] ]

	for { set x $startrange } { $x <= $endrange && $matches < $matchto } { incr x 86400 } {

		set values [::logpile::addDb $databases $dbpath $dbcount $x]

		set dbcount [lindex $values 0]
		set x [lindex $values 1]
		incr totaldoccount [lindex $values 2]

		if { ( $dbcount > 5 ||  ($x+86400) >= $endrange ) && $dbcount > 0 } {
			
			incr totalindexes $dbcount
			incr matches [doSearch $databases $query results $matchto $matches $command]

			$databases -delete
			#::logpile::cleanup

			set databases [::xapian::Database]
			set dbcount 0
		}
	}

	$databases -delete

	log_info "$matches results found"
	set stop [clock seconds]


	log_info "took [expr {$stop-$start}] seconds"
	log_info "total docs searched: $totaldoccount across $totalindexes indexes"
}

#delete xapian objects
#
proc ::logpile::cleanup {} {

	##shitty gc hack
	foreach f [info commands "*Xapian*"] {

		rename $f ""
	}
}

#convert daterange from human readable dates to unix timestamps and alter the query
#and parse the results tag from the query and set matchto
#
#@param startrange (upvar) the startrange value
#@param endrange (upvar) the endrange value
#@param matchto (upvar) the 
#@param query (upvar) the query to parse 
#
proc ::logpile::setupDaterange {startrange endrange matchto query} {

	upvar 1 $startrange srange 
	upvar 1 $endrange erange 
	upvar 1 $query qry
	upvar 1 $matchto match

	log_debug "query starts as ($qry)"

	if { [regexp $::logpile::pastmatches $qry -> -> m] } {

		log_debug "past tag: $m"
		log_debug "past parses to: [parseInputToSeconds $m]"
		set ::logpile::past [expr {[clock seconds] - [parseInputToSeconds $m]}]
		set qry [regsub $::logpile::pastmatches $qry " "]
	}

	#setup daterange
	if { ! [ regexp $::logpile::matchdaterange $qry daterange ] } {

		log_debug "query doesn't have daterange"
		if { [info exists ::logpile::past] && [string is integer $::logpile::past] } {

			log_debug "using past: $::logpile::past"
			set erange [clock seconds]
			set srange $::logpile::past
			set qry [format {%s..%s %s} $srange $erange $qry]
		} else {
			log_debug "using daterange: 1 day"
			set erange [clock scan "today"]
			set srange [expr $erange - 86400]
			set qry [format {%u..%u %s} $srange $erange $qry]
		}
	} else {

		log_debug "query has daterange"
		set ranges [split $daterange ".."]
		set srange [regsub "T" [lindex $ranges 0] " "]
		set erange [regsub "T" [lindex $ranges 2] " "]
		set srange [clock scan $srange]
		set erange [clock scan $erange]
		set qry [regsub $::logpile::matchdaterange $qry "${srange}..${erange}"]
	}

	if { [ regexp $::logpile::matchmatches $qry m ] } {

		log_debug "query has matches: $m"
		set m [split $m ":"]
		set match [lindex $m 1]
		set qry [regsub $::logpile::matchmatches $qry " "]
	}
}

#test for a the existence of a index database and skip to next available
#
#@param idbpath (upvar) path to indexes
#@param ix (upvar) unix timestamp
#@returns 1 if database exists
#
proc ::logpile::testDbPath {idbpath ix} {

	upvar 1 $ix x 
	upvar 1 $idbpath dbpath

	set exists 0

	set year [clock format $x -format "%Y"]
		if { ! [file isdirectory "$dbpath/$year"]  } {

		log_debug "skipping year $year"
		set year [scan $year "%u"]
		incr year
		set x [clock scan "$year-01-01 00:00:00"]	
	} else {

		set month [clock format $x -format "%m"]
		if { ! [file isdirectory "$dbpath/$year/$month"] } {

			log_debug "skipping month $year/$month"
			set month [scan $month "%u"]
			incr month
			set x [clock scan "$year-$month-01 00:00:00"]
		} else {
			set day [clock format $x -format "%Y/%m/%d"]
			if { [file isdirectory "$dbpath/$day"] } {
			
				set dbpath "$dbpath/$day"
				set exists 1
			}
		}
	}

return $exists
}

#add a index database to a database object
#
#@param databases ::xapian::Database 
#@param dbpath path to database to add
#@param dbcount count of open databases
#@param x unix timestamp of index to open
#@return list of databasecount, current timestamp, total documents represented by the added database
#
proc ::logpile::addDb {databases dbpath dbcount x } {
 
	set totaldoccount 0
	if { [::logpile::testDbPath dbpath x] } {

		log_debug "adding index $dbpath"
		if { ! [catch {set d [::xapian::Database "${databases}_d" "$dbpath"]} ] } {

			#look here for problems
			incr totaldoccount [$d get_doccount]
			incr dbcount	
			$databases add_database $d
			$d -delete
			"${databases}_d" -delete
		}
	}

return [list $dbcount $x $totaldoccount]
}


#delete entries in a xapian::Database based on a query
#
#@param databases ::xapian::Database to delete from
#@param userquery query to delete results 
#@param aresults (upvar) array to return results 
#@param matchto maximum entries to delete to
#@param matchcount (upvar) count of matched entries
#@return entries matched/removed in this call
#
proc ::logpile::doRemove {databases userquery aresults matchto matchcount} {

	upvar 1 $aresults results

	set thismatchcount 0

	set enquire [::logpile::setupQuery ::logpile::xapiandb $userquery]

	set matches [$enquire get_mset 0 $matchto]

	for {set i [$matches begin]} { $matchcount < $matchto && ( ![$i equals [$matches end]] ) } {$i next} {

		xapian::Document document [$i get_document]
		log_debug [format {removing: ID %s %s%% %s [%s]} \
			[$i get_docid] [$i get_percent] [xapian::sortable_unserialise [document get_value 1]] [document get_data]]
		
		#$databases delete_document [format {UID:%s} [$i get_docid]]
		$databases delete_document [$i get_docid]
		incr thismatchcount
		incr matchcount
		document -delete
	}

	$matches -delete
	$enquire -delete

return $thismatchcount
}

#setup a ::xapian::Enquire object based on a query and ::xapian::Database
#
#@param databases xapian::Database
#@param userquery query string
#@return ::xapian::Enquire
#
proc ::logpile::setupQuery {databases userquery} {

	log_debug "Building query"
	set numberrange [xapian::NumberValueRangeProcessor "${databases}_nvrp" 1]
	set qp [xapian::QueryParser]
	$qp add_prefix "HOST" "HOST"
	$qp add_prefix "TAG" "TAG"
	$qp set_default_op $::xapian::Query_OP_AND
	set enq [xapian::Enquire "${databases}_enquire" $databases]
	$enq set_sort_by_value 1 0
	set bw [xapian::BoolWeight]
	$enq set_weighting_scheme $bw
	$bw -delete
	$qp add_valuerangeprocessor $numberrange
	$numberrange -delete
	$qp set_database $databases
	set query [$qp parse_query $userquery [expr $::xapian::QueryParser_FLAG_WILDCARD | $::xapian::QueryParser_FLAG_DEFAULT ] ]

	log_debug "Performing query [$query get_description]"

	$enq set_query $query

	rename $query ""
	rename $enq ""
	rename $qp ""
	rename "${databases}_nvrp" ""

return "${databases}_enquire"
}

#function to generate an array of search results
#
#@param iterator ::xapian::Mset iterator
#@param matchcount number of documents in this iterator
#@param aresults (upvar) array that is used to pass back results
#
#@see ::logpile::search  ::logpile::search
#@see ::logpile::searchPath ::logpile::searchPath
#
proc ::logpile::returnResults {iterator matchcount aresults} {

	upvar 1 $aresults results

	set doc [$iterator get_document]
	set results($matchcount) [list [$iterator get_docid] [$iterator get_percent] [xapian::sortable_unserialise [$doc get_value 1]] [$doc get_data]]
	rename $doc ""
}

#function to print search results
#
#@param iterator ::xapian::Mset iterator
#@param matchcount number of documents in this iterator
#@param aresults (upvar) array that is used to pass back results
#
#@see ::logpile::search  ::logpile::search
#@see ::logpile::searchPath ::logpile::searchPath
#
proc ::logpile::printResults {iterator matchcount aresults} {

	set doc [$iterator get_document]
	puts [format {%s|%s%%|%s|%s} \
		[$iterator get_docid] [$iterator get_percent] [xapian::sortable_unserialise [$doc get_value 1]] [lindex [$doc get_data] 1]]
	rename $doc ""
}

#executes a search against a database 
#
#@param databases ::xapian::Database
#@param userquery query 
#@param aresults (upvar) array that results are stored in
#@param matchto number of results to match to
#@param matchcount number of results currently matched
#@param command command to run against results
#
#@see ::logpile::returnResults ::logpile::returnResults
#@see ::logpile::printResults ::logpile::printResults
#
proc ::logpile::doSearch {databases userquery aresults matchto matchcount command} {

	upvar 1 $aresults results
	set thismatchcount 0

	#run the query
	retryReopen { set enquire [::logpile::setupQuery $databases $userquery] } $databases 100

	#handle results
	for { set x 0 } { $x <= $matchto } { incr x 100000 } {

		retryReopen { set matches [$enquire get_mset $x 100000] } $databases 100

		#got no results exit
		if { [$matches size] > 0 } { 

			#fetch results
			for {set i [$matches begin]} { $matchcount < $matchto && ( ![$i equals [set ms [$matches end]]] ) } { retryReopen {$i next} $databases 100 } {

				retryReopen { $command $i $matchcount results } $databases 100
				incr thismatchcount
				incr matchcount
				rename $ms ""
			}
			catch { rename $ms "" }
			rename $i ""
		} else {

			set x [expr $matchto + 1]
			log_debug "mset size <= 0, done"
		}
		rename $matches ""
	}
	rename $enquire ""

return $thismatchcount
}

#run query and format results from {@link ::logpile::returnResults}
#
#@param query query to execute
#@return formatted message string
#
#@see ::logpile::returnResults ::logpile::returnResults
#
proc ::logpile::simple_format {query} {

	array set foo {}
	::logpile::search $query foo -command returnResults
	set message ""
	if { [array size foo] > 0 } {

		for { set x 0 } { [expr $x < [array size foo]] } { incr x } {

			incr ::logpile::resultscount
			set message [format "%s\n%s" $message [lindex [lindex $foo($x) 3] 1]]
		}
	}
return $message
}

#recurses through a directory of indexes compacting them calling {@link ::logpile::indexCompact}
#
#@param dbpath path to directory of indexes
#
proc ::logpile::indexCompactRecurse { dbpath } {

	log_debug "starting at $dbpath"

	::fileutil::traverse findDbs $dbpath -filter ::logpile::filetraverse::flintlockfilter

	set count 0
	findDbs foreach db {
		
		eval {
			::logpile::indexCompact [file dirname $db]
			incr count
		}
	}
	findDbs destroy
	log_info "compacted $count indexes"
}

#compacts an index pointed to by dbDir
#
#@param dbDir path to an index to compact
#@see ::logpile::indexCompactRecurse ::logpile::indexCompactRecurse
#
proc ::logpile::indexCompact { dbDir } { 

	set tmpDbDir [format {%s_tmp} $dbDir]

	log_info "compacting $dbDir -> $tmpDbDir"

	if { [eval {set fh [open "| xapian-compact $dbDir $tmpDbDir"]}] != "" } {

		fconfigure $fh -buffering line
		gets $fh line
		while { [gets $fh line] >= 0 } {

			log_debug $line
		}
		close $fh
		if { [file isdirectory $tmpDbDir] } {

			log_info "renaming $tmpDbDir -> $dbDir"
			file delete -force $dbDir
			file rename $tmpDbDir $dbDir
		} else {

			log_warn "$tmpDbDir doesn't exit for some reason"
		}
	} else {
		fconfigure $fh -buffering line
		gets $fh line
		while { [gets $fh line] >= 0 } {

			log_debug $line
		}
		close $fh
	}
}

#parse a string with a label identifying a unit of time 
#measurement and a value and return the value in seconds 
#of the value
#
#@param input - value and label eg. 1d valid labels are (d|M|y|h|m|s)
#
proc ::logpile::parseInputToSeconds { input } {

	if { [regexp {([0-9]+)([a-zA-Z]|)} $input -> value label] } {
	
		switch -exact $label {

			{d} { set value [expr 86400 * $value] }
			{M} { set value [expr 2678400 * $value] }
			{s} { }
			{h} { set value [expr 3600 * $value] }
			{y} { set value [expr 31536000 * $value] }
			{m} { set value [expr 60 * $value] }
			{}  { set value [expr 60 * $value] }
			default { return -errorinfo "unknown label $label" -errorcode -1 -1 }
		}
	} else {

		return -errorinfo {input must follow format [0-9]+[a-zA-Z]} -errorcode -2 -2
	}

return $value
}
	
#run a command block until success or count exceeded, reopening
#database on failure
#
#@param command command to execute
#@param database database to reopen on error
#@param count number of attempts to retry (defaults to 0 infinite)
#
proc ::logpile::retryReopen {command database {count 0}} {

	set c 0
	while { [catch { uplevel 1 $command } error] } {

		if { $c != 0 && $c >= $count } {

			error $error 1
		}
		log_debug "reopening database ${c}: $error"
		incr c
		$database reopen
	}
}

#return a default value if variable doesn't exist
#
#@param variable name
#@param default value
#
proc ::logpile::val {var def} {

	if { ! [info exists $var] } {

		return $def
	} else { 

		return [set [set var]]
	}
} 
