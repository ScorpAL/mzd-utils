#!/bin/sh
# The window types of mzd-dlg: one, two and three buttons, each answer is shown in the next window.
. "$(dirname "$(readlink -f "$0")")/../mzd-lib/mzd.sh"
mzd_start dialogs

mzd_info "One button" "This window has one button.\nIt closes by itself in 8 seconds." 8
mzd_ask "Two buttons" "Which one will you press?\nUse the knob, touch or Back." "Yes" "No" 60
_a=$?
mzd_info "Result" "Two buttons: the answer is ${_a}\n(0 = the first button, 1 = the second, 254 = nobody)." 5
mzd_choice "Three buttons" "Scenario 1, Scenario 2 or Scenario 3?" "Scenario 1" "Scenario 2" "Scenario 3" 60
_b=$?
mzd_info "Result" "Three buttons: the answer is ${_b}\n(0, 1, 2 = the button, 254 = nobody)." 5
mzd_end 0
