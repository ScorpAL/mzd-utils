# mzd-lib/dialog.sh - windows for scenarios (sourced by mzd.sh). The window program is mzd-dlg (knob, USB keyboard and
# touch; a drop-in for the stock /jci/tools/jci-dialog, which is touch only and is the fallback).
#
# Return codes of every window: the index of the pressed button (0 = first, 1 = second, 2 = third), 254 = nobody answered
# within the time (the window is closed), 253 = there is no dialog program at all. Back / Home on the commander = the last
# button. Texts: "\n" is a new line. In scenarios the first button of a question is "go on", the last one is "skip / stop".
#
#   mzd_ask    TITLE TEXT OK-LABEL CANCEL-LABEL [SECONDS]        two buttons, waits SECONDS (default 300)
#   mzd_choice TITLE TEXT LABEL1 LABEL2 LABEL3 [SECONDS]         three buttons
#   mzd_info   TITLE TEXT [SECONDS]                              one button "OK"; closes by itself after SECONDS (default 8)
#   mzd_bye    [SECONDS] [TEXT]                                  "you can remove the USB drive", closes after SECONDS (15)
#   mzd_fail   TEXT [SECONDS]                                    error + "nothing was changed", then the script ends (code 1)
#   mzd_dialog SECONDS ARGS...                                   anything else: the options of jci-dialog / mzd-dlg
#   mzd_menu   TITLE ITEMS-FILE [BUTTON...]                      a scrollable list (mzd-listmenu), see below

MZD_DLG="${MZD_TMP}/mzd-dlg"
: "${MZD_USE_DLG:=0}"      # set by the worker (_mzd_dialog_setup) and exported: a scenario started by another one must not reset it

_mzd_dialog_setup()
{
  _src="${MZD_BIN}/mzd-dlg"
  if [ -f "${_src}" ] && { [ -f /jci/fonts/Tipperary.ttf ] || [ -n "${MZD_NO_FONT_CHECK}" ]; }
  then
    if cp "${_src}" "${MZD_DLG}" && chmod +x "${MZD_DLG}" && "${MZD_DLG}" --version > /dev/null 2>&1
    then
      MZD_USE_DLG=1
    fi
  fi
  export MZD_USE_DLG
  if [ ${MZD_USE_DLG} -eq 1 ]
  then
    mzd_log "dialog: mzd-dlg (knob, keyboard, touch)"
  else
    mzd_log "dialog: stock jci-dialog (touch only); mzd-dlg missing or cannot run"
  fi
}

# every window and its result go to progress.log
mzd_dialog()
{
  _mzd_dlg_title=""
  for _a in "$@"
  do
    case "${_a}" in --title=*) _mzd_dlg_title=${_a#--title=} ;; esac
  done
  _mzd_dialog_run "$@"
  _mzd_dlg_rc=$?
  mzd_log "window \"${_mzd_dlg_title}\" returned ${_mzd_dlg_rc}"
  return ${_mzd_dlg_rc}
}

_mzd_dialog_run()
{
  _limit=$1
  shift
  if [ ${MZD_USE_DLG} -eq 1 ]
  then
    killall -q jci-dialog mzd-dlg 2>/dev/null
    "${MZD_DLG}" --timeout=${_limit} --max-seconds=$((_limit + 20)) "$@" &
    _pid=$!
    _sec=0
    while kill -0 ${_pid} 2>/dev/null && [ ${_sec} -lt $((_limit + 10)) ]
    do
      sleep 1
      _sec=$((_sec + 1))
    done
    if kill -0 ${_pid} 2>/dev/null
    then
      kill ${_pid} 2>/dev/null
      killall -q mzd-dlg 2>/dev/null
      wait ${_pid} 2>/dev/null
      return 254
    fi
    wait ${_pid}
    _rc=$?
    # 255 = mzd-dlg could not start, 127 = the file is gone: use the stock dialog for this window
    [ ${_rc} -ne 255 ] && [ ${_rc} -ne 127 ] && return ${_rc}
    mzd_log "mzd-dlg returned ${_rc}, using jci-dialog for this window"
  fi
  [ -x "${MZD_JCI_DIALOG}" ] || return 253
  killall -q jci-dialog 2>/dev/null
  "${MZD_JCI_DIALOG}" "$@" &
  _pid=$!
  _sec=0
  while kill -0 ${_pid} 2>/dev/null && [ ${_sec} -lt ${_limit} ]
  do
    sleep 1
    _sec=$((_sec + 1))
  done
  if kill -0 ${_pid} 2>/dev/null
  then
    kill ${_pid} 2>/dev/null
    killall -q jci-dialog 2>/dev/null
    wait ${_pid} 2>/dev/null
    return 254
  fi
  wait ${_pid}
}

mzd_ask()
{
  mzd_dialog "${5:-300}" --question --title="$1" --text="$2" --ok-label="$3" --cancel-label="$4"
}

mzd_choice()
{
  mzd_dialog "${6:-300}" --3-button-dialog --title="$1" --text="$2" --ok-label="$3" --cancel-label="$4" --button3-label="$5"
}

mzd_info()
{
  mzd_dialog "${3:-8}" --info --title="$1" --text="$2" --ok-label="OK" --no-cancel
}

mzd_bye()
{
  _s=${1:-15}
  mzd_dialog "${_s}" --info --title="${MZD_NAME:-MZD}" --ok-label="Close" --no-cancel \
    --text="${2:-You can remove the USB drive now.}\nThis window closes by itself in ${_s} seconds."
}

mzd_fail()
{
  _s=${2:-8}
  mzd_log "FAIL: $1"
  mzd_dialog "${_s}" --info --title="${MZD_NAME:-MZD}" --ok-label="Close" --no-cancel \
    --text="$1\nNothing was changed.\nYou can remove the USB drive.\nThis window closes in ${_s} seconds."
  mzd_end 1
}

# mzd_menu TITLE ITEMS-FILE [BUTTON...]
#   A scrollable list of items. ITEMS-FILE: one item per line, NAME<TAB>VALUE<TAB>disabled (VALUE defaults to NAME; the third column
#   is optional: the word "disabled" makes the item grey, it never gets the focus), "#" starts a comment.
#   The buttons (up to 4) are shown under the list and are always visible; Back / Home on the commander press the last one.
#   Returns 0 when an item was chosen: MZD_MENU_INDEX and MZD_MENU_VALUE have its number (from 0) and its value;
#   1.. when the button 1.. was pressed (MZD_MENU_INDEX / VALUE are empty); 254 = nobody answered within MZD_MENU_SECONDS
#   (default 600); 253 = there is no mzd-listmenu. The menu runs nothing: the script decides what to do with the value.
#   MZD_MENU_FOCUS (before the call) is the item that gets the focus, e.g. the last chosen one: MZD_MENU_FOCUS=${MZD_MENU_INDEX}.
#   MZD_MENU_BACK (before the call) is the number (from 0) of the button that Back / Home press; default the last one.
MZD_LISTMENU="${MZD_TMP}/mzd-listmenu"
MZD_MENU_INDEX=""
MZD_MENU_VALUE=""

_mzd_menu_setup()
{
  [ -x "${MZD_LISTMENU}" ] && return 0
  _src="${MZD_BIN}/mzd-listmenu"
  [ -f "${_src}" ] || return 1
  if [ -f /jci/fonts/Tipperary.ttf ] || [ -n "${MZD_NO_FONT_CHECK}" ]
  then
    cp "${_src}" "${MZD_LISTMENU}" && chmod +x "${MZD_LISTMENU}" && "${MZD_LISTMENU}" --version > /dev/null 2>&1 && return 0
  fi
  rm -f "${MZD_LISTMENU}"
  return 1
}

mzd_menu()
{
  _mt=$1
  _mf=$2
  shift 2
  MZD_MENU_INDEX=""
  MZD_MENU_VALUE=""
  if ! _mzd_menu_setup
  then
    mzd_log "menu \"${_mt}\": mzd-listmenu is missing or cannot run"
    return 253
  fi
  _ml=${MZD_MENU_SECONDS:-600}
  _mn=$#
  _mi=0
  while [ ${_mi} -lt ${_mn} ]
  do
    set -- "$@" "--button=$1"
    shift
    _mi=$((_mi + 1))
  done
  killall -q jci-dialog mzd-dlg 2>/dev/null
  rm -f "${MZD_TMP}/mzd-menu.out"
  [ -n "${MZD_MENU_BACK}" ] && set -- "--back-button=${MZD_MENU_BACK}" "$@"
  "${MZD_LISTMENU}" "--title=${_mt}" "--items-file=${_mf}" --print=both "--focus=${MZD_MENU_FOCUS:-0}" \
    "--timeout=${_ml}" "--max-seconds=$((_ml + 20))" "$@" > "${MZD_TMP}/mzd-menu.out" 2>/dev/null &
  _pid=$!
  _sec=0
  while kill -0 ${_pid} 2>/dev/null && [ ${_sec} -lt $((_ml + 10)) ]
  do
    sleep 1
    _sec=$((_sec + 1))
  done
  if kill -0 ${_pid} 2>/dev/null
  then
    kill ${_pid} 2>/dev/null
    killall -q mzd-listmenu 2>/dev/null
    wait ${_pid} 2>/dev/null
    mzd_log "menu \"${_mt}\" returned 254 (killed)"
    return 254
  fi
  wait ${_pid}
  _mrc=$?
  if [ ${_mrc} -eq 0 ]
  then
    _mline=$(head -1 "${MZD_TMP}/mzd-menu.out")
    _mtab=$(printf '\t')
    MZD_MENU_INDEX=${_mline%%${_mtab}*}
    MZD_MENU_VALUE=${_mline#*${_mtab}}
  fi
  rm -f "${MZD_TMP}/mzd-menu.out"
  mzd_log "menu \"${_mt}\" returned ${_mrc} index=${MZD_MENU_INDEX} value=${MZD_MENU_VALUE}"
  return ${_mrc}
}
