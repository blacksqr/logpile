package provide logpile::filetraverse 1.1

namespace eval ::logpile::filetraverse {

	set dateExpr {/([0-9][0-9][0-9][0-9]+/[0-9][0-9]/[0-9][0-9])(|/)$}
}

#filter for a <a href="http://tcllib.sourceforge.net/doc/traverse.html">::fileutil::traverse</a>
#that only returns databases that haven't been compacted ( don't contain the file "flintlock" )
#
#@param filename path handed to the proc by <a href="http://tcllib.sourceforge.net/doc/traverse.html">::fileutil::traverse</a>
#@return 1 or 0; 1 for path matches 0 for path doesn't match
#@see http://tcllib.sourceforge.net/doc/traverse.html ::fileutil::traverse
#@see ::logpile::indexCompactRecurse ::logpile::indexCompactRecurse
#
proc ::logpile::filetraverse::flintlockfilter { filename } {

	set today [expr [clock scan yesterday] + 86400]

	if { "flintlock" == [file tail $filename] && [regexp $::logpile::filetraverse::dateExpr [file dirname $filename] -> bar] && [clock scan $bar -format {%Y/%M/%d}] < $today  } {

                return 1
        } else {

                return 0
        }
}

