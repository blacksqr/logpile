#!/usr/bin/env tclsh8.5

set installto [string trim [expr {[info exists tcl_pkgPath] ? $tcl_pkgPath : [lindex $auto_path 0]}]]

set installing [lrange $argv 0 [expr { $argc - 2 } ]]
set installpack [lrange $argv [expr {$argc-1}] [expr {$argc-1}] ]

if { "" == $installing || "" == $installpack } {
	
	puts {usage: [files ..] dest}
	exit 1
}

if { [file isdirectory $installto] } {

	if {  [file writable $installto]  } {

		set packagedir [file join $installto $installpack]
		if { ! [file isdirectory $packagedir] } {

			puts "creating package at $packagedir"
			file mkdir $packagedir
		} else {

			puts "overwriting/adding to package at $packagedir"
		}

		puts -nonewline "installing: " 
		foreach install $installing {

			set sourcefile $install
			set destfile [file join $packagedir [file tail $sourcefile] ]
			puts -nonewline "$sourcefile "
			if { [catch { file copy $sourcefile $destfile } error] } {

				puts $error
				exit 1
			}
		}
		puts "done."

		puts -nonewline "making index "
		pkg_mkIndex $packagedir *
		puts "done."
	} else { 

		puts "$installto isn't writable"
		exit 1
	}
} else {

	puts "$installto does not exist"
	exit 1
}
