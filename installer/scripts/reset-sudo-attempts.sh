#!/bin/bash
# ── Reset Sudo Attempts ───────────────────────────────
# by Kori Tk (2026)
# ─────────────────────────────────────────────────────
echo ""
echo "Sudo Attempts that are Locked"
faillock --user $(whoami)  
echo ""
sleep 2
echo ""
echo "Removing Sudo Locks"
faillock --user $(whoami) --reset   
echo ""
sleep 2
echo ""
echo "Check Sudo Attempts have cleared"
faillock --user $(whoami)  

