  1. install tcl:
```
port install tcl
```
  1. Add a variant to: /opt/local//var/macports/sources/rsync.macports.org/release/ports/devel/xapian-bindings/Portfile
```
variant     tcl description {builds tcl bindings} {
  configure.args-delete  --without-tcl
  configure.args-append  --with-tcl
  depends_lib-append port:tcl
} 
```
  1. install xapian-bindings:
```
port install xapian-bindings +tcl
```
  1. install tcllib:
```
port install tcllib
```
  1. fix the xapian library for tcl:
```
cp /opt/local/lib/xapian1.0.15/xapian.so /opt/local/lib/xapian1.0.15/xapian.dylib
```