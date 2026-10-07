#!/bin/bash
# ----------------------------------------------------- 
#
# by hyprtk (Kori Tk) (2026)
# ----------------------------------------------------- 

pkill xautolock

xautolock -time 10 -locker "hyprlock" -notify 30 -notifier "notify-send 'Screen will be locked soon.' 'Locking screen in 30 seconds'"
