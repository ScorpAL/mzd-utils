#!/bin/sh
# A sub-menu of the test: sh submenu.sh KIND   (short | long | longnames | three | four | empty)
# Choosing an item shows a window with it and the menu comes back on the same item. The buttons: Back (or "Scenario 3" in the
# "three" menu) leaves the menu, Exit ends the whole test (exit code 20), the others only show a window.
. "$(dirname "$(readlink -f "$0")")/../mzd-lib/mzd.sh"
KIND=${1:-short}
mzd_start "submenu-${KIND}"

LIST="${MZD_TMP}/mzd-submenu-items.txt"
case ${KIND} in
  short)
    printf 'Apple\tapple\nBanana\tbanana\nCherry\tcherry\n' > "${LIST}"
    set -- Back Exit ;;
  long)
    _i=1
    : > "${LIST}"
    while [ ${_i} -le 40 ]
    do
      printf 'Item %02d of 40\tvalue-%02d\n' "${_i}" "${_i}" >> "${LIST}"
      _i=$((_i + 1))
    done
    set -- Back Exit ;;
  longnames)
    cat > "${LIST}" <<'ITEMS'
Short
A medium name of an item in the list
A rather long name of an item that will not fit into the width of the window
An extremely long name: it goes on and on and on and on and on and on and on and on and on
Another short one
ITEMS
    set -- Back Exit ;;
  three)
    _i=1
    : > "${LIST}"
    while [ ${_i} -le 8 ]
    do
      printf 'Entry %s\tentry-%s\n' "${_i}" "${_i}" >> "${LIST}"
      _i=$((_i + 1))
    done
    set -- "Scenario 1" "Scenario 2" "Scenario 3" ;;       # Scenario 3 (and Back / Home) leave this menu
  four)
    printf 'One\t1\nTwo\t2\nThree\t3\nFour\t4\nFive\t5\nSix\t6\n' > "${LIST}"
    set -- Back Skip Info Exit ;;
  empty)
    : > "${LIST}"
    set -- Back Exit ;;
  *) mzd_fail "Unknown menu: ${KIND}" ;;
esac

# the labels of the buttons by number
B1=$1; B2=$2; B3=$3; B4=$4
label_of() { case $1 in 1) echo "${B1}";; 2) echo "${B2}";; 3) echo "${B3}";; 4) echo "${B4}";; esac; }

MZD_MENU_FOCUS=0
while :
do
  mzd_menu "Menu: ${KIND}" "${LIST}" "$@"
  _rc=$?
  case ${_rc} in
    0) MZD_MENU_FOCUS=${MZD_MENU_INDEX}
       mzd_info "You chose" "Item number ${MZD_MENU_INDEX}\nvalue: ${MZD_MENU_VALUE}" 4 ;;
    253) mzd_fail "mzd-listmenu is missing on the USB drive." ;;
    254) mzd_end 0 ;;
    *) _label=$(label_of ${_rc})
       case ${_label} in
         Back|"Scenario 3") mzd_end 0 ;;
         Exit) mzd_end 20 ;;
         *) mzd_info "Button" "The button \"${_label}\" was pressed." 3 ;;
       esac ;;
  esac
done
