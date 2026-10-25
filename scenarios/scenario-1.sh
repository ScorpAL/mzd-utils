#!/bin/sh
# Scenario 1: windows - Terminal - windows. The Terminal is a step in the middle: the next window follows by itself when it closes.
. "$(dirname "$(readlink -f "$0")")/../mzd-lib/mzd.sh"
mzd_start scenario-1

mzd_ask "Scenario 1 - step 1 of 3" "A short demo of the Terminal as a step.\nNext: you will be asked to open the Terminal." "Next" "Skip" \
  || { mzd_log "skipped at step 1"; mzd_end 0; }

mzd_ask "Scenario 1 - step 2 of 3" "Open the Terminal and run:   ls -la\nThen press HOME on the commander,\ntype exit, or press Ctrl+D." "Open Terminal" "Skip"
if [ $? -eq 0 ]
then
  mzd_terminal --hint "Scenario 1. Run:  ls -la|Then press HOME on the commander, type exit, or press Ctrl+D." --timeout 600
  _rc=$?
  mzd_info "Scenario 1 - the Terminal is closed" "Result ${_rc}, reason: ${MZD_TERMINAL_REASON}.\nThe knob works in the CMU again.\nThe next step follows." 6
else
  mzd_log "Terminal skipped"
fi

mzd_ask "Scenario 1 - step 3 of 3" "This window comes after the Terminal.\nPress Next to finish the scenario." "Next" "Skip" 120
mzd_end 0
