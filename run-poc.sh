#!/bin/sh
# recon-terminal-10: a test of the new windows and menus for the car. First an invitation (mzd-dlg: Start / Exit), then the main
# menu (mzd-listmenu): other menus with different lists and buttons, the dialog types, and the Terminal as a step.
# Everything can be left: the button Exit in every menu, Back / Home in the main menu. The test ends with the window
# "you can remove the USB drive". The USB drive root has only this script, mzd-debug.flag and the folders mzd-bin, mzd-lib and
# scenarios (the other scripts). A scenario or menu is a script of its own, started with sh; exit code 10 = it left the Terminal
# open on purpose (end quietly), 20 = "Exit" was pressed (end everything).
. "$(dirname "$(readlink -f "$0")")/mzd-lib/mzd.sh"
mzd_start recon-10

mzd_ask "MZD test" "A test of the new windows and menus.\nStart: the menu of tests.\nExit: leave now." "Start" "Exit" 180 \
  || { mzd_bye 15; mzd_end 0; }

# the main menu: NAME<TAB>what to run (a script of this folder and its arguments)
LIST="${MZD_TMP}/mzd-menu-items.txt"
cat > "${LIST}" <<'ITEMS'
Short list (3 items)	submenu.sh short
Long list (40 items, scrolling)	submenu.sh long
Long names (cut with dots)	submenu.sh longnames
Three buttons: Scenario 1 | 2 | 3	submenu.sh three
Four buttons	submenu.sh four
Empty list	submenu.sh empty
Window types (one, two, three buttons)	dialogs.sh
A scenario with an argument	demo.sh 7
Terminal: windows, Terminal, windows	scenario-1.sh
Terminal as the last step	scenario-2.sh
ITEMS

MZD_MENU_FOCUS=0
while :
do
  mzd_menu "MZD test: main menu" "${LIST}" "Exit"
  _rc=$?
  case ${_rc} in
    0) MZD_MENU_FOCUS=${MZD_MENU_INDEX}
       ( cd "${MZD_ROOT}/scenarios" && set -f && sh ${MZD_MENU_VALUE} )
       _src=$?
       [ ${_src} -eq 10 ] && mzd_end 0                       # the Terminal stays open: show nothing over it
       if [ ${_src} -eq 20 ]; then mzd_bye 15; mzd_end 0; fi ;;
    253) mzd_fail "mzd-listmenu is missing on the USB drive." ;;
    *) mzd_bye 15
       break ;;                # Exit, Back / Home on the commander, or nobody answered
  esac
done
mzd_end 0
