#!/bin/sh
# A demo scenario for the menu: only shows a window. Usage: sh demo.sh NUMBER
. "$(dirname "$(readlink -f "$0")")/../mzd-lib/mzd.sh"
mzd_start demo
mzd_info "Demo scenario $1" "This is demo scenario number $1.\nIt only shows this window." 5
mzd_end 0
