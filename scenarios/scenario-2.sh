#!/bin/sh
# Scenario 2: the Terminal is the LAST step; nothing is shown after it.
#   wait mode:   the script waits for the Terminal and ends after it closed (the menu appears again, if there is one)
#   finish mode: the script ends right after opening the Terminal (--no-wait); the bridge's hook gives the focus back later.
#                Exit code 10 tells the menu not to show anything over the open Terminal.
. "$(dirname "$(readlink -f "$0")")/../mzd-lib/mzd.sh"
mzd_start scenario-2

mzd_choice "Scenario 2" "The Terminal is the last step, nothing follows.\nOpen (wait): this script waits until it is closed.\nOpen (finish): this script ends at once." "Open (wait)" "Open (finish)" "Skip"
case $? in
  0) mzd_terminal --hint "Scenario 2 (wait). Last step. HOME or exit closes the Terminal." --timeout 600
     mzd_end 0 ;;
  1) mzd_terminal --no-wait --hint "Scenario 2 (finish). The script has ended. HOME or exit closes the Terminal." --timeout 600
     mzd_end 10 ;;
  *) mzd_log "skipped"
     mzd_end 0 ;;
esac
