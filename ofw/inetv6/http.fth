\ See license at end of file
purpose: HTTP package

hex

false instance value debug?

h# 100 instance buffer: url
0      instance value   /url
h# 80  instance buffer: proxy
0      instance value   /proxy

-1 value result-code
0  value image-size

\ proxy should have the value of
\   1.  environment variable, http-proxy, if not null$
\   2.  otherwise, devalias http-proxy, if not null$
\   3.  Location: URL$ for status code 305

: set-proxy  ( $ -- )
   \ strip "http://" or "http:\\"
   over " http:" comp 0=  if
      7 /string
   else
      over " HTTP:" comp 0=  if  7 /string  then
   then

   dup to /proxy  proxy swap move  
;
: init-proxy  ( -- )
   0 to /proxy
   " http-proxy" $getenv 0=  if
      ?dup  if
         set-proxy
         exit
      else
         drop
      then
   then
   " http-proxy" not-alias? 0=  if  set-proxy  then
;

d# 255 instance buffer: pathbuf
: fix-delims  ( $ -- $' )
   pathbuf pack count   ( $' )

   2dup bounds  ?do     ( $' )
      i c@  dup [char] | =  swap [char] \ =  or  if  [char] / i c!  then
   loop
;
: set-server  ( server$ -- )
   dup  if  " $set-host" $call-parent  else  2drop  then
;
char / constant delim
: url-parse  ( url$ -- filename$ server$ )
   \ If the string is shorter than 2 characters, the server portion is null
   dup 2 <  if  " " exit  then             ( url$ )

   \ If the string doesn't start with //, the server portion is null
   over  " //" comp  if  " " exit  then    ( url$ )

   2 /string                               ( server/filename$ )
   delim split-string                      ( server$ filename$ )
   2swap                                   ( filename$ server$ )
;

: close  ( -- )
;

\ false instance value reports?

2variable seek-ptr
: seek  ( d -- error? )  seek-ptr 2@  d<>  ;
: update-ptr  ( actual -- actual )
   dup 0  seek-ptr 2@  d+  seek-ptr 2!  ( actual )
;

: tcp-read  ( adr len -- actual )  " read" $call-parent  ;
: wait-read  ( adr len -- actual )
   begin
      2dup  tcp-read   dup -2 =         ( adr len actual flag )
   while                                ( adr len actual )
      drop                              ( adr len )
   repeat                               ( adr len actual )
   nip nip                              ( actual )
   update-ptr                           ( actual )
;

: read   ( adr len -- actual )
   over +  over                        ( start end next )
   begin                               ( start end next )
      \ Check for end of buffer
      2dup =  if                       ( start end next )
         nip swap -  update-ptr exit   ( actual )
      then                             ( start end next )

      2dup -                           ( start end next # )
      over swap wait-read              ( start end next actual )

      dup -1 =  if                     ( start end next -1 )
         drop                          ( start end next )
         nip  swap -  update-ptr       ( actual )
         \ Return -1 if this is the end and we didn't get any data this pass
         dup  0=  if  1-  then         ( actual | -1 )
         exit
      then                             ( start end next actual )

      +                                ( start end next' )
   again
;

: load  ( adr -- len )
   dup  begin                           ( adr next-adr )
      dup h# 800 read  dup -1 <>        ( adr next-adr )
   while                                ( adr next-adr actual )
      dup 0<=  if                       ( adr next-adr actual )
         drop                           ( adr next-adr )
      else                              ( adr next-adr actual )
         +                              ( adr next-adr' )
         show-progress                  ( adr next-adr' )
      then                              ( adr next-adr' )
   repeat                               ( adr next-adr actual )
   drop  swap -  update-ptr             ( len )
;

false instance value ipv6-host$?
: parse-ipv6-port  ( server$ -- server$' port$ )
   1 /string
   [char] ] left-parse-string		( port$ server$ )
   2swap  [char] : left-parse-string    ( server$ port$ junk$ )
   2drop                                ( server$ port$ )
;

: parse-port  ( server$ -- port# server$' )
   over c@ [char] [ =  dup to ipv6-host$?  if
      parse-ipv6-port			( server$ port$ )
   else

      [char] : left-parse-string        ( port$ server$ )
      2swap				( server$ port$ )
   then
   dup  if                              ( server$ port$ )
      push-decimal  $number  pop-base   ( server$ port# error? )
      abort" Bad port number"           ( server$ port# )
   else                                 ( server$ port$ )
      2drop d# 80                       ( server$ port# )
   then                                 ( server$ port# )
   -rot                                 ( port# server$ )
;

: tcp-write  ( adr len -- )  " write" $call-parent drop  ;

: decode-url  ( url$ -- send$ prefix$ port# server$ )
   fix-delims                           ( url$' )
   /proxy 0=  if
      url-parse null$                   ( filename$ server$ prefix$ )
      bootnet-debug  if  ." HTTP: Server is: " 2over type cr  then
   else                                 ( url$ )
      proxy /proxy                ( url$ proxy$ )
      bootnet-debug  if  ." HTTP: Proxy is: " 2dup type cr  then
      " http:"                          ( url$ proxy$ prefix$ )
   then                                 ( send$ server$ prefix$ )
   2swap  parse-port                    ( send$ prefix$ port# server$ )
;

vocabulary http-tags

: parse-line  ( adr len -- )
   save-input  2>r 2>r 2>r  -1 set-input
   parse-word  ['] http-tags  search-wordlist  if
      push-decimal  ['] execute catch  pop-base  throw
   then
   2r> 2r> 2r> restore-input
;

: read1  ( adr -- )  1 wait-read  -1 =  throw  ;

1 instance buffer: ch
: eat-line  ( -- )
   begin   ch read1   ch c@ carret =   until
   ch read1
;

: (get-line)  ( adr maxlen -- adr actual )
   over +  over                      ( start end next )
   begin                             ( start end next )
      \ Check for end of buffer
      2dup =  if                     ( start end next )
         eat-line                    ( start end next )
         nip over - exit             ( adr len )
      then                           ( start end next )

      \ Read the next character
      dup read1                      ( start end next )

      \ Check for end of line
      dup c@ carret =  if            ( start end next )
         dup read1                   ( start end next )   \ Eat the LF
         nip over - exit             ( adr len )
      then                           ( start end next )
   
      1+                             ( start end next' )
   again
;
h# 100 instance buffer: line-buffer

: get-line  ( -- adr len )  line-buffer h# 100 (get-line)  ;
: skipwhite  ( $ -- $' )
   begin                                  ( $ )
      dup                                 ( $ len )
   while                                  ( $ )
      over c@  dup bl =  swap 9 =  or      ( $ white? )
   while                                  ( $ )
      1 /string                           ( $' )
   repeat then                            ( $' )
;
: scanwhite  ( $ -- tail$ head$ )
   "  "t"  lex  if       ( tail$ head$ delim )
      drop               ( tail$ head$ )
   else                  ( $ )
      null$ 2swap        ( null-tail$ head$ )
   then                  ( tail$ head$ )
;

: get-number  ( adr len -- n )  push-decimal $number pop-base throw  ;
: version-bad?  ( $ -- flag )
   2dup " HTTP/1.0" $=  if  2drop false exit  then  ( $ )
   2dup " HTTP/1.1" $=  if
      2drop false 
   else
      bootnet-debug  if
         ." HTTP: Bad version: " type cr
      else  2drop  then
      true
   then
;
: result-code-supported?  ( # -- supported? )
   dup to result-code >r	( # )
   r@ d# 200 =    r@ d# 301 d# 303 between or
   r@ d# 305 = or r> d# 307 = or
;
: dump-response  ( -- )
   begin get-line dup  while  type  cr  repeat
;
: check-status-line  ( -- )
   get-line scanwhite                   ( rem$' head$ )
   version-bad?                         ( rem$' error? )
   abort" HTTP: Bad version line"	( rem$ )
   skipwhite  scanwhite                 ( rem$ head$ )
   get-number                           ( rem$ # )
   dup result-code-supported? not  if	( rem$ # )
      bootnet-debug  if			( rem$ # )
         ." HTTP: Bad response: " .d  type cr	( )
         dump-response
      then				( | rem$ # )
      abort				( )
   else	 3drop  then			( )
;
: parse-header-line  ( adr len -- )
   [char] : left-parse-string              ( tail$ head$ )
   ['] http-tags  search-wordlist  if      ( tail$ xt )
      execute                              ( )
   else                                    ( tail$ )
      2drop                                ( )
   then                                    ( )
;

also http-tags definitions
\ Sample header:
\ HTTP/1.0 200 OK
\ Date: Tue, 02 Mar 1999 22:46:34 GMT
\ Server: Apache/1.1.1
\ Content-type: text/html
\ Content-length: 10696
\ Last-modified: Thu, 11 Feb 1999 01:08:12 GMT
\ Location: http://www.w3.org/TheProject.html

: content-length  ( $ -- )  \ [<white>] length
   skipwhite scanwhite    ( tail$ head$ )
   2swap 2drop            ( head$ )
   get-number             ( size )
   to image-size
;
: location  ( $ -- )		\ [<white>] url$
   skipwhite scanwhite		( tail$ head$ )
   2swap 2drop			( head$ )
   ascii : left-parse-string 2drop	( head$' )
   result-code d# 305 =  if
      set-proxy
   else
      dup to /url		( head$ )
      url swap move		( )
      null$ set-proxy
      bootnet-debug  if  ." HTTP: Location: " url /url type cr  then
   then
;

previous definitions

: check-header  ( -- )
   0. seek-ptr 2!
   0 to image-size
   -1 to result-code
   check-status-line
   begin  get-line  dup  while  parse-header-line  repeat  2drop
;
: (mount)  ( $url -- error? )
   decode-url                           ( send$ prefix$ port# server$ )

   2dup set-server                      ( send$ prefix$ port# server$ )
   rot                                  ( send$ prefix$ server$ port# )

   bootnet-debug  if  ." Connecting to port " dup .d cr  then
   " connect" $call-parent  0=  if      ( send$ prefix$ server$ )
      4drop 2drop true exit
   then                                 ( send$ prefix$ server$ )

   bootnet-debug if  ." Connected" cr  then

   " GET " tcp-write                    ( send$ prefix$ server$ )
   2swap tcp-write  2swap tcp-write     ( server$ )
   "  HTTP/1.1"r"nUser-Agent: FirmWorks/1.1"r"nHost: "  tcp-write
   ipv6-host$?  if  " [" tcp-write  then
   ( server$ ) tcp-write
   ipv6-host$?  if  " ]" tcp-write  then
   " "r"n"r"n" tcp-write

   " flush-writes" $call-parent

   ['] check-header catch
;
: mount  ( url$ -- error? )
   dup to /url  2dup url swap move
   begin  (mount) 0=  if  result-code d# 200 <>  else  false  then  while
      " disconnect" $call-parent
      url /url
   repeat
   result-code d# 200 <>
;

: open  ( -- )
   my-args dup  if
      init-proxy
      bootnet-debug  if
         2dup ." HTTP: URL is: " type cr
      then
      mount 0=
      bootnet-debug  if
         ." HTTP: "
         dup  if   ." Succeeded"  else ." Failed!"  then  cr
      then
   else
      2drop true
   then
;
: size  ( -- d )  image-size 0  ;
\ LICENSE_BEGIN
\ Copyright (c) 2006 FirmWorks
\ 
\ Permission is hereby granted, free of charge, to any person obtaining
\ a copy of this software and associated documentation files (the
\ "Software"), to deal in the Software without restriction, including
\ without limitation the rights to use, copy, modify, merge, publish,
\ distribute, sublicense, and/or sell copies of the Software, and to
\ permit persons to whom the Software is furnished to do so, subject to
\ the following conditions:
\ 
\ The above copyright notice and this permission notice shall be
\ included in all copies or substantial portions of the Software.
\ 
\ THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
\ EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
\ MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
\ NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
\ LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
\ OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
\ WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
\
\ LICENSE_END
