purpose: Diagnostic console driver for IMX 6 UART

\ The following value is correct for UART2 of the IMX6ULL CPU
\ Override the value after loading this file for different ports
h# 21e8000 value uart-base

d# 115200 value diaguart-baud

: uart@  ( offset -- value )  uart-base + l@  ;
: uart!  ( value offset -- )  uart-base + l!  ;

: >uartclk ( cscdr1 -- clk )
   dup   h# 40 and
         if d# 80000000 else d# 24000000 then
   swap  h# 3f and 1+ 
   /
;

: uart-set-baud  ( baud -- )
   d# 16 *                   ( 16xbaud )

   h# 20c4024 l@ >uartclk
   over /mod         ( 16xbaud rem quot )
   1+ h# a4 uart!    ( rem  r: 16xbaud )
   1+ h# a8 uart!    ( quot r: 16xbaud )
;

: init-uart  ( -- )
   h#    0 h# 80 uart!  \ Disable while programming
   h#    0 h# 84 uart!
   begin   h# b4 uart@ h# 1 and 0= until \ reset complete
   h#  782 h# 88 uart!  \ DSR, DCD, RI, -autobaud, RXDMUXSEL
   h#  a01 h# 90 uart!  \ input clock 2/, DCE, TxFIFO=2, RxFIFO=1
   diaguart-baud uart-set-baud
   h# 4000 h# 8c uart!  \ CTS off if 16 chars in RxFIFO
   h#  227 h# 84 uart!  \ CTSC, 8 bits, rx, tx enable
   h#    1 h# 80 uart!  \ UARTEN (re-enable)
;

: ukey?  ( -- flag )    h# 98 uart@ 1 and ;
: ukey  ( -- char )
   begin  ukey?  until
   0 uart@  h# ff and
;
: uemit  ( char -- )
   begin  h# b4  uart@  h# 8  and  0= until
   h# 40 uart!
;


\ LICENSE_BEGIN
\ Copyright (c) 2009 FirmWorks
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
