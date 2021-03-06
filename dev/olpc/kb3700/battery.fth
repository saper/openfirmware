purpose: Sniff the battery state from EC internal variables
\ See license at end of file

[ifndef] ec@
: ec@ wbsplit h#  381 pc! h# 382 pc! h# 383 pc@ ;
: ec! wbsplit h#  381 pc! h# 382 pc! h# 383 pc! ;
[then]

\ Names try to match the variable names in EC code

h# F780  constant ec-bProcessOneWireIndex
h# F7CF  constant ec-bHDQ_ACCESS_FLAG2

h# FA00  constant ec-rambase
h# 01    constant ec-pwr_limit
h# 09    constant ec-va2
h# 20    constant ec-platformID
h# A5	 constant ec-mBAT_STATUS

h# FC00  constant ec-gpiobase
h# 00    constant ec-gpiofs00 
h# 12    constant ec-gpio-0A

h# FE00  constant ec-pwmbase
h# 08    constant ec-pwmhigh2
h# 09    constant ec-pwmhigh3 
h# 0A    constant ec-pwmhigh4

h# F900  constant ec-batrambase
h# 15    constant ec-debugflag4

: ec-ram@ ec-rambase + ec@ ;
: rr ec@ . ;
: ww ec! ;
: bat-b@ ec-batrambase + ec@  ;
: bat-b! ec-batrambase + ec!  ;
: bat-w@ dup 1+ bat-b@ swap bat-b@ bwjoin ;
: eram-w@  h# f400 + dup 1+ ec@ swap ec@ bwjoin ;
\ : uvolt@ 0 bat-w@ d# 9760 d# 32 */ ;
\ : cur@ 2 bat-w@ wextend  d# 15625 d# 120 */ ;
\ : pcb-temp 8 bat-w@ >degrees-c  ;
\ : bat-temp 6 bat-w@ >degrees-c  ;
\ : soc     h# 10 bat-b@  ;
: bat-state  h# 11 bat-b@  ;
: bat-cause@ h# 70 bat-b@  ;

\ A few commands for looking at what the EC is doing in
\ the battery state machine.
\ Unless you are on a serial console with stdout turned off
\ (stdout off) this will miss some state changes.
\

: next-bstate
        begin
         f780 ec@ tuck <>
        until
;

: see-bstate
        0 begin
         next-bstate dup . 
         dup 4 = if
            cr
         then key? 
        until
;

: next-e1-state
   begin 
      fae1 ec@ tuck <>
   until
;

: see-e1
        0 begin
            next-e1-state dup .
            key?
        until
;

\ Get platformID so we can decide if this is a gen 1 or gen 1.5
: bat-pid@ ( -- id ) ec-platformID ec-ram@ ;

\ Gen 1.5 Leds are PWM. In the interest of simplicity this just
\ adjusts the pwm value rather than fully turning the led off because
\ for off you have to disable the pwm and then set it to IO low.
\ pwm value of 0x00 is the same as full scale.
: bat-red-led-pwm-on ( -- ) h# ff ec-pwmbase ec-pwmhigh4 + ec! ;
: bat-green-led-pwm-on ( -- ) h# ff ec-pwmbase ec-pwmhigh2 + ec! ;
: bat-yellow-led-pwm-on ( -- ) bat-red-led-pwm-on bat-green-led-pwm-on ;
: bat-red-led-pwm-off ( -- ) h# 01 ec-pwmbase ec-pwmhigh4 + ec! ;
: bat-green-led-pwm-off ( -- ) h# 01 ec-pwmbase ec-pwmhigh2 + ec! ;
: bat-yellow-led-pwm-off ( -- ) bat-red-led-pwm-off bat-green-led-pwm-off ;

\ On XO 1 we just clear the IO on Gen 1.5 its bit more complex
: bat-chg-led-off 
   bat-pid@ h# cf > if bat-yellow-led-pwm-off else 
      fc24 ec@ 03 or fc24 ec!
   then  
;

\ Turn on the charging mosfet
: bat-enable-charge ( -- ) fc21 ec@ 40 or fc21 ec! ;

\ Turn off the charging mosfet
: bat-disable-charge ( -- ) fc21 ec@ 40 invert and fc21 ec! bat-chg-led-off ;

\ Turn on the trickle charge with max system voltage
: bat-enable-trickle ( -- ) fc23 ec@ 1 or fc23 ec! 01 fc24 ec! ;

\ Turn off the trickle charger
: bat-disable-trickle ( -- ) fc23 ec@ 1 invert and fc23 ec! ;

\ Turn on the EC lifepo4 dump
: bat-enable-ec-life-dump ( -- ) f915 ec@ 8 or f915 ec! ;

\ Turn on the EC lifepo4 dump
: bat-disable-ec-life-dump ( -- ) f915 ec@ 8 invert and f915 ec! ;


\ Access the 1-wire data line via the EC GPIO ports

h# 383 constant dataport
h# 382 constant lowadr
4 constant dq-bit
0 value high
0 value low
false value 1w-initialized
0 value bat-fileih

: disable-ec-charging
   1 h# fa07 ec!
;

: disable-ec-1w
   1 h# fa08 ec!
;

: enable-ec-charging
   0 h# fa07 ec!
;

: enable-ec-1w
   0 h# fa08 ec!
;

: 1w-init  ( -- )
   disable-interrupts
   h# fc24 ec@  dq-bit invert and  fc24 ec!
   h# fc14 ec@ dup dq-bit or to low    dq-bit invert and to high
   high fc14 ec!
   true to 1w-initialized
   1 ms
;


\ New ec revs can turn off the battery subsystem without
\ putting the ec into reset allowing the user to
\ use the XO keyboard.
: init-ec-live
   disable-ec-charging
   disable-ec-1w
   1w-init
;

: init-ec-dead
   kbc-off
   1w-init
;

\ EC code at the time these commands were added can stop
\ the battery subsystem with out putting the EC into reset.
\ so we always do a live init
: batman-init init-ec-live 500 ms bat-disable-charge bat-disable-trickle ;
: batman-init? 1w-initialized if else batman-init then ;


: batman-start batman-init? ;

: batman-stop
   enable-ec-1w
   enable-ec-charging
   enable-interrupts
   false to 1w-initialized
;

: bit?  ( us -- flag )  \ Test the data after a delay
   us  h# 34 lowadr pc!  dataport pc@  dq-bit and  0<>
;

: 1w-pulse  ( us -- )  \ Pulse the wire low for some duration
   h# 14 lowadr pc!  low dataport pc!  us  high dataport pc!
;

\ Generic 1-wire primitives

: 1w-reset  ( -- )
   d# 480 1w-pulse
   d# 67 bit?  abort" No response from battery"
   begin  1 bit?  until
;

: 1w-write-byte  ( byte -- )
   8 0  do                     ( byte )
      dup  1 and  if           ( byte )
         1 1w-pulse  d# 60 us  ( byte )
      else                     ( byte )
         d# 60 1w-pulse        ( byte )
      then                     ( byte )
      2/                       ( byte' )
   loop                        ( byte )
   drop                        ( )
;

: 1w-read-byte  ( -- )
   0   8 0  do
      1 1w-pulse
      \ Shift bits in from the left, little endian
      d# 10 bit?  h# 100 and  or  2/  d# 50 us
   loop
;

: 1w-skip-address  ( -- )  h# cc 1w-write-byte  ;

: 1w-cmd   ( arg cmd -- )  1w-reset  1w-skip-address  1w-write-byte  1w-write-byte  ;

\ Basic commands for the DS2756 chip

: 1w-read   ( adr len start -- )
   h# 69 1w-cmd                            ( adr len )
   bounds  ?do  1w-read-byte i c!  loop    ( )
   1w-reset
;

: 1w-write   ( adr len start -- )
   h# 6c 1w-cmd                            ( adr len )
   bounds  ?do  i c@ 1w-write-byte  loop   ( )
   1w-reset
;

: 1w-write-start ( start -- )
   h# 6c 1w-cmd
;

: 1w-copy    ( start -- )  h# 48 1w-cmd  d# 10 ms  ;

: 1w-recall  ( start -- )  h# b8 1w-cmd  ;

\ : 1w-lock    ( start -- )  h# 6a 1w-cmd  ;

: 1w-sync  ( -- )  0  h# d2 1w-cmd  ;

\ Some higher-level commands for accessing battery data

\ buffer for reading bank data
h# 20 constant /ds-bank     \ Bytes per bank in the battery sensor chip
h# 60 constant /ds-eeprom   \ Bytes in the eeprom

h# 01 constant ni-mh
h# 02 constant li-fe
h# 00 constant ds-regs
h# 10 constant ds-acr

h# 20 constant ds-bank0
h# 25 constant ds-bat-misc-flag
h# 2d constant ds-last-dis-soc
h# 2e constant ds-last-dis-acr-msb
h# 2f constant ds-last-dis-acr-lsb
h# 31 constant ds-default-status

h# 40 constant ds-bank1
h# 5f constant ds-batid

h# 60 constant ds-bank2
h# 60 constant ds_bat_serial_num_1 
h# 61 constant ds_bat_serial_num_2
h# 62 constant ds_bat_serial_num_3
h# 63 constant ds_bat_serial_num_4
h# 64 constant ds_bat_serial_num_5
h# 68 constant ds-remain-acr-msb
h# 69 constant ds-remain-acr-lsb 
h# 6a constant ds_bat_charge_msb
h# 6b constant ds_bat_charge_lsb
h# 6c constant ds_bat_charge_soc  
h# 6d constant ds_bat_discharge_msb 
h# 6e constant ds_bat_discharge_lsb 
h# 6f constant ds_bat_discharge_soc

h# 01 constant ds-bat-low-volt
h# 20 constant ds-bat-full

h# 20 buffer: ds-bank-buf

: ds-bank$  ( -- adr len )  ds-bank-buf /ds-bank  ;

: bat-id  ( -- id )  ds-bank-buf 1 ds-batid 1w-read  ds-bank-buf c@ h# 0f and  ;

: read-bank  ( offset -- )  ds-bank$ rot 1w-read  ;

: bat-read-eeprom ( -- ) ds-bank-buf /ds-eeprom ds-bank0 1w-read ;

: bat-ds-regs@ ( -- )  ds-regs  read-bank  ;
: bat-bank0@   ( -- )  ds-bank0 read-bank  ;
: bat-bank1@   ( -- )  ds-bank1 read-bank  ;
: bat-bank2@   ( -- )  ds-bank2 read-bank  ;

: bat-dump-bank  ( -- )  ds-bank$ dump  ;

: bat-dump-banks ( -- )
   batman-init? 
   cr ." Regs"
   bat-ds-regs@ bat-dump-bank
   cr cr ." Bank 0"
   bat-bank0@ bat-dump-bank
   cr cr ." Bank 1"
   bat-bank1@ bat-dump-bank
   cr cr ." Bank 2"
   bat-bank2@ bat-dump-bank
;

: bat-dump-regs ( -- ) batman-init? bat-ds-regs@ bat-dump-bank ;

: s16>s32 ( signed16bit -- 32bit_sign-extended )
   d# 16 << d# 16 >>a
;

: >sd
   base @ >r decimal
   dup abs <# u#s swap sign u#>
   r> base !
;

: >sdx
   <# "  " hold$ u#s " 0x" hold$ u#>
;

: >sd.ddd  ( n -- formatted )
   base @ >r  decimal
   dup abs <# u# u# u# [char] . hold u# u#s swap sign u#>
   r> base !
;

: >sd.dd  ( n -- formatted )
   base @ >r  decimal
   dup abs <# u# u# [char] . hold u# u#s swap sign u#>
   r> base !
;

: bat-save  ( -- )
   " disk:\battery.dmp"
   2dup ['] $delete  catch  if  2drop  then  ( name$ )
   $create-file to bat-fileih

   1w-init
   h# 80 0  do
      ds-bank$ i 1w-read
      ds-bank$ " write" bat-fileih $call-method
   /ds-bank +loop

   bat-fileih close-dev
;

\ bg-* words access the gauge directly via 1w rather than
\ read the value from the ec cache
: bg-recall
   ds-bank0 1w-recall
   ds-bank1 1w-recall
   ds-bank2 1w-recall
;

: bg-acr@     ( -- acr )
   batman-init?
   ds-bank-buf 2 ds-acr 1w-read                  ( )
   ds-bank-buf c@ 8 <<                          ( msb )
   ds-bank-buf 1 + c@ or s16>s32                ( acr )
;

: bg-acr! ( acr -- )
   batman-init?
   wbsplit
   ds-acr 1w-write-start
   1w-write-byte
   1w-write-byte
   1w-reset
;

: bg-last-dis-soc@ ( -- last-dis-soc )
   batman-init?
   ds-bank-buf 1 ds-last-dis-soc 1w-read
   ds-bank-buf c@ 
;

: bg-last-dis-soc! ( soc -- )
   batman-init?
   ds-bank0 1w-recall
   ds-last-dis-soc 1w-write-start
   1w-write-byte
   ds-last-dis-soc 1w-copy
   1w-reset
;

: bg-last-dis-acr@ ( -- last-dis-acr )
   batman-init?
   ds-bank-buf 2 ds-last-dis-acr-msb 1w-read ( )
   ds-bank-buf c@ 8 <<                          ( last-dis-acr-msb )
   ds-bank-buf 1 + c@ or s16>s32                ( last-dis-acr )
;

: bg-last-dis-acr! ( last-dis-acr --)
   batman-init?
   wbsplit
   ds-bank0 1w-recall
   ds-last-dis-acr-msb 1w-write-start
   1w-write-byte
   1w-write-byte
   ds-last-dis-acr-msb 1w-copy
   1w-reset
;

: bg-misc@ ( -- misc-flag )
   batman-init?
   ds-bank-buf 1 ds-bat-misc-flag 1w-read
   ds-bank-buf c@
;

: bg-set-full-flag ( -- )
   bg-misc@
   ds-bat-full or
   ds-bank0 1w-recall
   ds-bat-misc-flag 1w-write-start
   1w-write-byte
   ds-bat-misc-flag  1w-copy
   1w-reset
;

: bg-clear-full-flag ( -- )
   bg-misc@
   ds-bat-full not and
   ds-bank0 1w-recall
   ds-bat-misc-flag 1w-write-start
   1w-write-byte
   ds-bat-misc-flag  1w-copy
   1w-reset
;

\ Retrieve the key battery stats in bulk and put it on the stack
\ sign extending the values that are 2's complement.
: bg-charge-info@
   ds-bank-buf 6 h# 0c 1w-read         ( )
   ds-bank-buf c@ 8 <<              ( voltage_msb )
   ds-bank-buf 1 + c@ or s16>s32    ( voltage )
   ds-bank-buf 2 + c@ 8 <<          ( voltage current_msb )
   ds-bank-buf 3 + c@ or s16>s32    ( voltage current )
   ds-bank-buf 4 + c@ 8 <<          ( voltage current ACR_msb )
   ds-bank-buf 5 + c@ or s16>s32    ( voltage current ACR )
;

: bg-net-addr@
   1w-reset
   h# 33 1w-write-byte
   1w-read-byte
   0 7 bounds ?do 1w-read-byte loop
;

: bg-acr>mAh ( raw-value -- acr_in_mAh )
   d# 625 ( mV ) * d# 15 ( mOhm ) /
;

: bg-V>V ( raw-value - V_in_mV )
   d# 488 ( mV ) * 2* d# 100 / 5 >>
;

: bg-I>mA ( raw-value -- I_in_mA )
   3 >>a
   d# 15625 ( nV ) * d# 15 ( mOhm ) / d# 10 /
;

: bg-temp>degc ( raw-value -- temp_in_degc )
   d# 125 * d# 10 / 5 >>
;

: .bg-eeprom
   base @ >r
   decimal
   ."          acr: " bg-acr@ . cr
   ." Last dis soc: " bg-last-dis-soc@ . cr
   ." Last dis acr: " bg-last-dis-acr@ . cr
   hex
   ."   Misc flags: " bg-misc@ dup . ."  : "
   dup ds-bat-full and if ." fully charged " then
   dup ds-bat-low-volt and if ." low voltage " then
   drop
   cr
   r> base !
;

: .bg-acr ( raw_acr_in_s32 -- )
   bg-acr>mAh >sd.dd type
;

: .bg-current ( raw_I_in_s32 -- )
   bg-I>mA >sd.dd type
;

: .bg-volt ( raw_V_in_s32 -- )
   bg-V>V >sd.ddd type
;

: .bg-net-addr ( -- )
   bg-net-addr@
   0 8 bounds ?do . loop cr
;

0 value bg-last-acr
0 value bg-v_avg

: bg-watch ( -- )
   bg-acr@
   begin
      bg-charge-info@
      dup to bg-last-acr
      ." ACR:" .bg-acr ."  I:" .bg-current ."  V:"  .bg-volt
      dup bg-last-acr swap - ."  Chg:" .bg-acr
      cr
      500 ms
      key?
   until
   drop
;

\ Instruct the EC to completely reset the battery
\ subsystem. (XO-1 F series EC code)

: (bat-reset) ( -- )
   1 ec-bHDQ_ACCESS_FLAG2    ec!
   4 ec-bProcessOneWireIndex ec!
;

: bat-set-default-status ( val -- )
   ds-bank0 1w-recall
   ds-default-status 1w-write-start
   1w-write-byte
   ds-bank0 1w-copy
   1w-reset
;

: bat-get-default-status ( -- val )
   ds-bank0 1w-recall
   ds-bank-buf 1 ds-default-status 1w-read    
   ds-bank-buf c@                               ( pack info ) 
;

: bat-fix-error-2
   batman-init?
   bat-get-default-status
   dup h# 6a = 
   if ." Pack info is already correct" drop
   else 
      ." Fixing bad pack info: " . 
      h# 6a bat-set-default-status
   then 
;

: bat-get-id  ( -- id )  ds-bank-buf 1 ds-batid 1w-read  ds-bank-buf c@  ;

: bat-set-life-byd ( -- )
   ds-batid 1w-recall
   ds-batid h# 6c 1w-cmd
   h# 22 1w-write-byte
   ds-batid 1w-copy
;

: bat-fix-byd-id
  batman-init?
  bat-get-id h# 22 = if
     ." Id is already correct"
  else
     ." Fixing BYD bat ID"
     bat-set-life-byd
  then
;

h# 90 buffer: logstr

\ Read values directly rather than using the ec-cmd

: bat-I@ ( -- rawI ) h# 02 bat-b@ 8 << h# 03 bat-b@ or s16>s32 ;
: bat-V@ ( -- rawV ) h# 00 bat-b@ 8 << h# 01 bat-b@ or s16>s32 ;

: bat-lfp-dataf@
      base @ >r 
      0 logstr c!

      decimal
      now drop <# " :" hold$ u#s u#> logstr $cat  <# "  " hold$ u#s u#> logstr $cat   \ Running time
      h# 10 bat-b@        \ SOC
      >sd logstr $cat

      hex
      h# e0 ec-ram@       \ C state
      >sdx logstr $cat
      h# e1 ec-ram@       \ w1 state index
      >sdx logstr $cat  
      h# F780 ec@         \ w1 state
      >sdx logstr $cat
      h# 40 ec-ram@       \ sPOWER_FLAG 
      >sdx logstr $cat
      h# a4 ec-ram@       \ sMBAT_STATUS 
      >sdx logstr $cat
      h# a5 ec-ram@       \ sMCHARGE_STATUS
      >sdx logstr $cat
      h# a6 ec-ram@       \ sMBAT_MISC 
      >sdx logstr $cat
      h# a7 ec-ram@       \ sMBAT_MISC2
      >sdx logstr $cat
      h# 70 bat-b@        \ AbnormalCauseCode
      >sdx logstr $cat
      h# fc21 ec@         \ GPIO_08-0F 0E is chg mosfet
      >sdx logstr $cat

      decimal
      bat-V@ bg-V>V >sd.ddd logstr $cat "  " logstr $cat \ V
      bat-I@ bg-I>mA >sd.dd logstr $cat "  " logstr $cat \ I

      h# 54 bat-b@ 8 << h# 55 bat-b@ or s16>s32    \ ACR
      bg-acr>mAh >sd.dd logstr $cat "  " logstr $cat

      h# 06 bat-b@ 8 << h# 07 bat-b@ or            \ Temp
      bg-temp>degc >sd.dd logstr $cat "  " logstr $cat

\      h# 17 bat-b@ 8 << h# 18 bat-b@ or            \ NiMh Chargetime
\      >sd logstr $cat

      \ Chemistry specific stuff below here
      h# 11 bat-b@        \ bat_state
      >sd logstr $cat

      hex
      h# FBD1 ec@          \ ProcessBatteryCharge
      >sdx logstr $cat
      h# FBD0 ec@          \ ChargeFlowControl
      >sdx logstr $cat

      r> base !
;

: bat-debug
   begin
      bat-lfp-dataf@
      logstr count type
      cr
      200 ms key?
   until key drop 
;

: bat-debug-log
   " disk:\batdbug.log" $new-file
   begin
      bat-lfp-dataf@
      logstr count ftype
      logstr count type
      fcr
      cr
      200 ms key?
   until key drop 
   ofd @ fclose
;


: bat-force-charge ( -- )
   batman-init?
   bat-enable-charge
   bg-acr@
   begin
      bg-charge-info@
      dup to bg-last-acr
      ." ACR:" .bg-acr ."  I:" .bg-current ."  V:"  .bg-volt
      dup bg-last-acr swap - ."  Chg:" .bg-acr
      cr
      500 ms
      key?
   until
   drop
   bat-disable-charge
;

: bat-enable-ecdbg
   ec-debugflag4 bat-b@ 
   h# 8 dup rot and or ec-debugflag4 bat-b!
;

: bat-enable-ecdbg-short
   ec-debugflag4 bat-b@ 
   h# 18 or ec-debugflag4 bat-b!
;

: bat-disable-ecdbg
   ec-debugflag4 bat-b@ 
   h# 18 invert and ec-debugflag4 bat-b!
;

: bat-disable-ecdbg-short
   ec-debugflag4 bat-b@ 
   h# 10 invert and ec-debugflag4 bat-b!
;

: bat-recover-info@ ( -- voltage ACR current temp )
   ds-bank-buf 6 h# 0c 1w-read                  ( )
   ds-bank-buf c@ 8 <<                          ( voltage_msb )
   ds-bank-buf 1 + c@ or d# 16 << d# 16 >>a     ( voltage )
   ds-bank-buf 4 + c@ 8 <<                      ( voltage ACR_msb )
   ds-bank-buf 5 + c@ or d# 16 << d# 16 >>a     ( voltage ACR )
   ds-bank-buf 4 h# 18 1w-read                  ( voltage ACR )
   ds-bank-buf 2 + c@ 8 <<                      ( voltage ACR current_msb )
   ds-bank-buf 3 + c@ or d# 16 << d# 16 >>a     ( voltage ACR current )
   swap                                         ( voltage current ACR )
   ds-bank-buf c@ 8 <<                          ( voltage ACR current temp_msb )
   ds-bank-buf 1 + c@ or d# 16 << d# 16 >>a     ( voltage ACR current temp )
;

4 value bon
2 value boff

: bat-recover ( -- )
   batman-init?
   bg-acr@
   begin
      bat-enable-charge
      bon ms
      bat-disable-charge
      bat-recover-info@
      bg-temp>degc >sd.dd type ."  C "
      to bg-last-acr
      bg-I>mA >sd.dd type ."  mA "
      bg-v_avg + 2 / dup to bg-v_avg
      bg-V>V >sd.ddd type ."  V "
      dup bg-last-acr swap - 
      bg-acr>mAh >sd.dd type ."  mAh "
      cr
      boff ms
      false
   until
   drop
   bat-disable-charge
;

: bat-reset
   batman-init?
   (bat-reset)
   batman-stop
;

fload ${BP}/dev/olpc/kb3700/batstat.fth

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
