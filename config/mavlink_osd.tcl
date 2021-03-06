namespace eval osd {

set sysid 97
set compid 94
set restore_baud 0

proc timeout_set {t} {
 set e [clock milliseconds]
 incr e $t
 set w 50
 return [list $e $w]
}

proc timeout_check {ts} {
  upvar $ts x
  set left [expr {([lindex $x 0] - [clock milliseconds])}]
  set delay [expr {[lindex $x 1]<<1}]
  if {$left < $delay} {set delay $left}
  lset x 1 $delay
  return $delay
}

proc detect {fd {timeout 10000}} {
 set ts [timeout_set $timeout]
 while {1} {
  set w [timeout_check ts]
  if {$w <= 0} {return 0}
  mav::send_hb $fd
  set hb [mav::wait_for_msg $fd 0 $w]
  if {$hb eq {}} continue
  binary scan $hb "@6iucu" custom_mode type 
  if {$type == 24} break
 }
 binary scan $hb "@3cucu" osd::sysid osd::compid
 set b [expr {($custom_mode >> 16) & 0xff}]
 if {$b == 115} {
  set osd::restore_baud 115200
 } elseif {$b == 57} {set osd::restore_baud 57600}
 return 1
}

proc reboot {fd {target "bl"}} {
 if {$target eq "bl"} {
  set cmd_args [binary format f7 {0 0 0 0 0 0 0}]
 } elseif {$target eq "fl"} {
  set cmd_args [binary format f7 {0 0 1.0 0 0 0 0}]
 }
 mav::send_cmd $fd $osd::sysid $osd::compid 246 $cmd_args
}

set serial_speed 0

array set config {
 chan 0
 baud 0
 timeout_min 20
 timeout_max 600
}

proc serial_fwd_config {s} {
 array set osd::config $s
}

proc serial_fwd_data {fd data resp_len} {
 set p 0
 set l [string length $data]
 if {$osd::serial_speed == $osd::config(baud)} {
   set b 0
 } else {
   set b $osd::config(baud)
   set osd::serial_speed $b
 }
 while {$p < $l} {
  set opts {EXCLUSIVE BLOCKING} 
  if {$l-$p <= 70} {
   set w [expr {$l-$p}]
   if {$resp_len != 0} {
    lappend opts RESPOND
    if {$resp_len > 70} {lappend opts MULTI}
   }
  } else {
   set w 70
  }
  binary scan $data "@${p}a${w}" d
  incr p $w
  mav::send_serial $fd $b $osd::config(timeout_min) $osd::config(chan) $opts $d
  set b 0
 }
 if {$l == 0} {
  set opts {EXCLUSIVE BLOCKING RESPOND} 
  if {$resp_len > 70} {lappend opts MULTI}
  mav::send_serial $fd $b $osd::config(timeout_min) $osd::config(chan) $opts {}
 }
 set end [expr {[clock milliseconds]+$osd::config(timeout_max)}]
 set repl {}
 while {$resp_len > 0} {
  # typical timeout is quite large (measured 266 ms)
  set m [mav::wait_for_msg $fd 126 [expr {$osd::config(timeout_min)+500}]]
  if {$m eq {}} {
   if {[clock milliseconds] > $end} {return $repl}
   set opts {EXCLUSIVE BLOCKING RESPOND} 
   if {$resp_len > 70} {lappend opts MULTI}
   mav::send_serial $fd 0 $osd::config(timeout_min) $osd::config(chan) $opts {}
  } else {
   binary scan $m "@14cu" n
   binary scan $m "@15a$n" r
   append repl $r
   incr resp_len -$n
  }
#binary scan $repl H* xx
#puts "got $n ($xx), $resp_len remaining"
 }
 return $repl
}

proc serial_fwd_exit {fd} {
 # exit exclusive mode
 mav::send_serial $fd $osd::restore_baud 0 $osd::config(chan) {} {}
}

proc test {} {
set fd [mav::open_serial "/dev/ttyACM0"]
osd::detect $fd
puts "osd detected: ${osd::sysid}:${osd::compid}"
mav::close_serial $fd
}
  
}
