USING: accessors arrays assocs byte-arrays calendar combinators
  continuations formatting hashtables html.parser
  html.parser.analyzer http.client io io.directories
  io.encodings.binary io.files io.pathnames kernel locals make
  math math.parser multiline namespaces peg.javascript
  peg.javascript.ast regexp sequences splitting strings summary
  system threads ;
IN: monstercat

UNION: urldata
  string byte-array ;

TUPLE: monstercat-track
  { filename string }
  { metadata hashtable }
  { filedata urldata } ;

TUPLE: monstercat-album
  { art       urldata }
  { albartist string }
  { name      string }
  { tracks    array  } ;

SYMBOL: skipped-folder? inline

skipped-folder? f set

: skip-folder ( folder -- )
  skipped-folder? get
  [ drop skipped-folder? f set ]
  [
    "NOTE: '" "' exists, not overwriting it (delete the folder to redownload)"
    surround print skipped-folder? t set
  ]
  if ;

: (my-http-get) ( url -- data )
  [ "GET " prepend print ]
  [ http-get ]
  bi
  [
    [ code>>    ]
    [ message>> ]
    bi "\n%s %s\n\n" printf flush
  ] dip ;

: my-http-get ( url -- data )
  [ (my-http-get) ]
  [ summary ", retrying" append print (my-http-get) ]
  recover ;

: slug>page ( slug -- page )
  "music.monstercat.com" prepend my-http-get ;

! descriptor is one of "all", "track", "album"
:: music-urls ( descriptor -- pages )
  "music.monstercat.com" my-http-get parse-html
  "leftMiddleColumns" find-by-class-between
  [
    [ name>> "a" = ]
    [ attributes>> ]
    bi and
  ] filter
  [ attributes>> "href" swap at ] map sift
  [
    descriptor dup "all" =
      swap "(track|album)" swap
    ?
    "^/%s.*" sprintf <regexp> matches?
  ] filter ;


: title>data ( title -- assoc )
  dup R/ .*\s+-\s+.*/ matches?
  [
    "|" swap R/ \s+-\s+/ pick re-replace swap split
    first2
  ]
  [ "" swap ]
  if
  [ "title" ,, "artist" ,, ] 2curry H{ } make ;

: sanitize-filename ( string -- string' )
  "/" "+" replace
  os windows = [
    "\\" "+" replace
    ":"  ""  replace
    "?"  ""  replace
    "<"  ""  replace
    ">"  ""  replace
    ":"  ""  replace
    "\"" ""  replace
    "|"  ""  replace
    "?"  ""  replace
    "*"  ""  replace
  ] when
  R/ _{2,}/ "_" re-replace ;

: title>filename ( string -- string' )
  sanitize-filename ".mp3" append ;

: json>track ( json-info -- track )
  bindings>>
  [ name>> value>> { "track_num" "title" "file" } member? ] filter
  first3
  [
    [ value>> value>> ]
    bi@
    [ title>filename ]
    [ title>data     ]
    bi
    [ "title"  swap at ]
    [ "artist" swap at ]
    bi
  ] dip

  value>> bindings>> first value>> value>>
  "http:" prepend my-http-get

  [
    3dup swap "%s %s - %s\n\n" printf flush
  ] dip
  [ [ swap ] dip ] 2dip
  [ [ "artist" ,, "title" ,, "num" ,, ] H{ } make ] dip
  monstercat-track boa ;

: art-handler ( json -- jpeg )
  value>> value>> my-http-get ;

: current-handler ( json -- artist album )
  value>> bindings>>
  [ name>> value>> { "artist" "title" } member? ] filter
  first2
  [ value>> value>> ] bi@ ;

: trackinfo-handler ( trackinfo -- tracks )
  value>> values>> [ json>track ] map { } clone-like ;

:: page>tracks ( html -- album-data )
  html
  dup "var TralbumData" swap start tail
  dup "</script>" swap start head
  parse-javascript statements>>

  [ dup ast-begin?
    [ swap statements>> first name>> "TralbumData" = and ]
    [ drop f ]
    if*
  ] filter

  first statements>> first value>> bindings>>

  [ name>> { "artFullsizeUrl" "current" "trackinfo"  } member? ] filter
  first3
    :> trackinfo
    :> art
    :> current

  monstercat-album new

  current current-handler [ >>albartist ] dip
    dup exists?
    [ [ >>name ] [ skip-folder ] bi ]
    [
      >>name

      art art-handler
        >>art

      trackinfo trackinfo-handler
        >>tracks
    ]
    if ;


: write-track ( track -- )
  [ metadata>> ]
  [ filedata>> ]
  [ filename>> ] tri

  [ binary set-file-contents ]
  [ current-directory get swap "wrote %s/%s\n\n" printf flush ]
  bi drop ;

: write-album ( album-data -- )
  [ tracks>> ]
  [ art>>    ]
  [ name>>   ] tri

  dup exists?
  [ skip-folder 2drop ]
  [
    sanitize-filename
    [
      make-directories
    ]
    [
      [
        "AlbumArt.jpg" binary set-file-contents
        [ write-track ] each
      ] with-directory
    ]
    bi
  ]
  if ;

: (monstercat-main) ( descriptor -- )
  music-urls
  [
    [ print ]
    [ slug>page page>tracks write-album ]
    bi
    skipped-folder? get [
      "Sleeping for 10 seconds" print
      10 iota [ 1 + number>string "%s " printf flush 1 seconds sleep ] each
      "" print
      skipped-folder? f set
    ] when
  ] each ;

: monstercat-main ( -- )
  "all for all, track for tracks or album for albums" print
  readln (monstercat-main) ;

MAIN: monstercat-main
