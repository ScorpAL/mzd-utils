# mzd-lib/terminal.sh - the Terminal of the CMU with a working USB keyboard, as ONE step of a scenario (sourced by mzd.sh).
#
#   mzd_terminal [--hint TEXT] [--timeout SECONDS] [--no-wait] [--rc FILE]
#
#   --hint TEXT      printed inside the Terminal before the prompt; lines are separated by newlines or by "|"
#   --timeout N      the Terminal is closed by the script after N seconds at the latest (default 1800)
#   --rc FILE        a file with shell commands that the shell in the Terminal runs first (it is "sourced" through $ENV)
#   --no-wait        do not wait: return as soon as the Terminal is open. For a Terminal that is the last thing of the
#                    script (or a script that just opens it); the hook cleans up and gives the focus back when it closes
#
# Without --no-wait it returns when the Terminal is closed AND the keyboard focus is back in the CMU user interface (the
# next window can be shown at once). Return codes: 0 = closed (HOME on the commander, "exit" or Ctrl+D, ...),
# 1 = closed by the time limit, 2 = could not start (the reason is in the log), 3 = another Terminal is open, 4 = the hook
# did not run. MZD_TERMINAL_REASON has what the bridge reported: home, "shell-exit N", time-limit, terminal-closed, unknown.
#
# What it does: copies the stock /jci/scripts/run-terminal.sh in memory with three lines changed (font size, the shell = the
# bridge mzd-kbd-bridge, semi-transparent window so the CMU shows through), runs it, and hands the bridge a HOOK
# (MZD_KBD_ON_EXIT): a small script that the bridge's "janitor" runs when the Terminal is gone, whatever way it ended and even if
# this script is dead by then. The hook gives the keyboard focus back to the CMU user interface (the stock script gives the
# focus to the Terminal and never takes it back: without this the knob stays dead until a reboot) and creates a flag file.
# During the session everything is as in the stock: without a USB keyboard the knob types m / n into the Terminal and the
# CMU is quiet; with a USB keyboard the bridge grabs the CMU keyboard (the CMU stays quiet) and the Terminal types what you type.
# If mzd-bin/mzd-kbd-bridge is missing, the plain Terminal is opened (no USB keyboard fix) and a small watcher does the hook's job.

: "${MZD_TERMINAL_BIN:=/usr/bin/terminal}"
MZD_TERM_LOCK="${MZD_TMP}/mzd-terminal.lock"
MZD_TERM_FLAG="${MZD_TMP}/mzd-terminal.done"
MZD_TERM_RESULT="${MZD_TMP}/mzd-terminal.result"
MZD_TERM_RC="${MZD_TMP}/mzd-terminal-rc"
MZD_TERM_HOOK="${MZD_TMP}/mzd-terminal-hook.sh"
MZD_TERM_BRIDGE="${MZD_TMP}/mzd-kbd-bridge"
MZD_TERM_FONT=${MZD_TERM_FONT:-20}
MZD_TERM_ALPHA=${MZD_TERM_ALPHA:-120}
MZD_TERMINAL_REASON=""

_mzd_term_files_remove()
{
  rm -f "${MZD_TERM_RC}" "${MZD_TERM_HOOK}" "${MZD_TERM_FLAG}" "${MZD_TERM_RESULT}" "${MZD_TERM_BRIDGE}" "${MZD_TERM_LOCK}/pid"
  rmdir "${MZD_TERM_LOCK}" 2>/dev/null
}

# the hook (written to a file; it runs without any variable of this script)
_mzd_term_write_hook()
{
  _nowait=$1
  {
    echo '#!/bin/sh'
    echo "LOGF='${MZD_PROGRESS}'"
    echo 'log() { [ -n "${LOGF}" ] && echo "[$(date +%T)] terminal hook: $1" >> "${LOGF}"; echo "[$(date +%T)] terminal hook: $1" >> "'"${MZD_TMP}"'/mzd-hook.log"; }'
    echo 'export XDG_RUNTIME_DIR=/tmp'
    echo 'log "start"'
    echo "'${MZD_IVI}' -f '${MZD_SURFACE}' > /dev/null 2>&1"
    echo 'log "focus -> '"${MZD_SURFACE}"' rc=$?"'
    echo 'sleep 1'
    echo "'${MZD_IVI}' -f '${MZD_SURFACE}' > /dev/null 2>&1"
    echo 'log "focus again rc=$?"'
    echo "cat '${MZD_TERM_RESULT}' > '${MZD_TERM_FLAG}' 2>/dev/null || echo unknown > '${MZD_TERM_FLAG}'"
    if [ "${_nowait}" = 1 ]
    then
      # nobody waits: the hook removes everything, itself last
      echo "sleep 1"
      echo "rm -f '${MZD_TERM_RC}' '${MZD_TERM_FLAG}' '${MZD_TERM_RESULT}' '${MZD_TERM_BRIDGE}' '${MZD_TERM_LOCK}/pid'"
      echo "rmdir '${MZD_TERM_LOCK}' 2>/dev/null"
      echo 'log "done, files removed"'
      echo "rm -f '${MZD_TERM_HOOK}'"
    else
      echo 'log "done"'
    fi
  } > "${MZD_TERM_HOOK}"
  chmod +x "${MZD_TERM_HOOK}"
}

# without the bridge nobody runs the hook: a detached watcher waits for the Terminal and runs it
_mzd_term_watcher()
{
  (
    trap '' HUP
    _i=0
    while [ ${_i} -lt 1000 ] && ! mzd_exe_running terminal
    do
      sleep 1
      _i=$((_i + 1))
    done
    while mzd_exe_running terminal
    do
      sleep 1
    done
    echo "unknown" > "${MZD_TERM_RESULT}"
    sh "${MZD_TERM_HOOK}"
  ) > /dev/null 2>&1 < /dev/null &
}

mzd_terminal()
{
  _hint=""
  _tmo=${MZD_TERM_TIMEOUT:-1800}
  _wait=1
  _rcfile=""
  while [ $# -gt 0 ]
  do
    case "$1" in
      --hint) _hint=$2; [ $# -gt 1 ] && shift ;;
      --timeout) _tmo=$2; [ $# -gt 1 ] && shift ;;
      --rc) _rcfile=$2; [ $# -gt 1 ] && shift ;;
      --no-wait) _wait=0 ;;
    esac
    shift
  done
  MZD_TERMINAL_REASON=""

  if [ ! -f "${MZD_STOCK}" ] || [ ! -x "${MZD_TERMINAL_BIN}" ] || [ ! -x "${MZD_IVI}" ]
  then
    mzd_log "terminal: not available here (stock script, terminal or ivi-shell missing)"
    return 2
  fi

  # one Terminal at a time (a stale lock, whose owner is gone, is removed)
  if ! mkdir "${MZD_TERM_LOCK}" 2>/dev/null
  then
    _lp=$(cat "${MZD_TERM_LOCK}/pid" 2>/dev/null)
    if [ -n "${_lp}" ] && kill -0 "${_lp}" 2>/dev/null
    then
      mzd_log "terminal: another one is open (owner ${_lp})"
      return 3
    fi
    _mzd_term_files_remove
    mkdir "${MZD_TERM_LOCK}" 2>/dev/null || { mzd_log "terminal: cannot take the lock"; return 2; }
  fi
  echo $$ > "${MZD_TERM_LOCK}/pid"
  rm -f "${MZD_TERM_FLAG}" "${MZD_TERM_RESULT}"

  # the bridge
  _bridge=0
  if [ -f "${MZD_BIN}/mzd-kbd-bridge" ] && cp "${MZD_BIN}/mzd-kbd-bridge" "${MZD_TERM_BRIDGE}" && chmod +x "${MZD_TERM_BRIDGE}" && "${MZD_TERM_BRIDGE}" --help > /dev/null 2>&1
  then
    _bridge=1
  else
    rm -f "${MZD_TERM_BRIDGE}"
    mzd_log "terminal: the keyboard bridge is missing or cannot run: the plain Terminal is opened (no USB keyboard fix)"
  fi

  # the text printed in the Terminal, and the commands it runs first
  {
    echo "PS1='mzd> '"
    echo "${_hint}" | tr '|' '\n' | while IFS= read -r _hl
    do
      [ -n "${_hl}" ] && printf "echo '%s'\n" "$(printf '%s' "${_hl}" | sed "s/'/'\\\\''/g")"
    done
    [ -n "${_rcfile}" ] && [ -f "${_rcfile}" ] && cat "${_rcfile}"
  } > "${MZD_TERM_RC}"

  _mzd_term_write_hook $((1 - _wait))

  # the stock script with the changed lines
  _o1='echo "" > /tmp/root/weston.ini'
  _n1="{ echo '[terminal]'; echo 'font-size=${MZD_TERM_FONT}'; } > /tmp/root/weston.ini"
  _o2="export SHELL='/bin/sh'"
  _n2="export SHELL='${MZD_TERM_BRIDGE}'"
  _o3='ivi-shell -a "Wayland Terminal":255 > /dev/null &'
  _n3="ivi-shell -a \"Wayland Terminal\":${MZD_TERM_ALPHA} > /dev/null \\&"     # \& : a plain & in a sed replacement means "the matched text"
  if [ ${_bridge} -eq 1 ]
  then
    _patched=$(sed -e "s|^${_o1}\$|${_n1}|" -e "s|^${_o2}\$|${_n2}|" -e "s|^${_o3}\$|${_n3}|" "${MZD_STOCK}")
    _need=3
  else
    # no bridge: the shell stays the stock one
    _patched=$(sed -e "s|^${_o1}\$|${_n1}|" -e "s|^${_o3}\$|${_n3}|" "${MZD_STOCK}")
    _need=2
  fi
  _count=$(echo "${_patched}" | grep -c -e "font-size=${MZD_TERM_FONT}" -e "${MZD_TERM_BRIDGE}" -e "Terminal\":${MZD_TERM_ALPHA} ")
  if [ -z "${_patched}" ] || [ "${_count}" -lt ${_need} ]
  then
    mzd_log "terminal: the stock script does not have the expected lines, nothing was started"
    _mzd_term_files_remove
    return 2
  fi
  [ ${_bridge} -eq 0 ] && _mzd_term_watcher

  mzd_log "terminal: start (bridge=${_bridge}, wait=${_wait}, timeout=${_tmo} s)"
  [ -n "${MZD_DEBUG}" ] && _mzd_ps_list >> "${MZD_LOG}" 2>&1
  (
    export ENV="${MZD_TERM_RC}" MZD_KBD_ON_EXIT="sh ${MZD_TERM_HOOK}" MZD_KBD_RESULT_FILE="${MZD_TERM_RESULT}" MZD_KBD_MAX_SECONDS="${_tmo}"
    [ -n "${MZD_DEBUG}" ] && export MZD_KBD_LOG="${MZD_OUT}/kbd-bridge.log" MZD_KBD_VERBOSE=1
    sh -c "${_patched}" >> "${MZD_LOG}" 2>&1
  )

  # did it open?
  _i=0
  while [ ${_i} -lt 15 ] && ! mzd_exe_running terminal
  do
    sleep 1
    _i=$((_i + 1))
  done
  if ! mzd_exe_running terminal
  then
    mzd_log "terminal: did not open in 15 s"
    _mzd_term_files_remove
    return 2
  fi
  mzd_log "terminal: open"

  if [ ${_wait} -eq 0 ]
  then
    mzd_log "terminal: not waiting (--no-wait); the hook cleans up when it closes"
    return 0
  fi

  _t0=$(date +%s)
  _timeout=0
  _shot=0
  while [ ! -f "${MZD_TERM_FLAG}" ]
  do
    if [ -n "${MZD_DEBUG}" ] && [ ${_shot} -eq 0 ] && [ $(( $(date +%s) - _t0 )) -ge 15 ]
    then
      _shot=1
      mzd_shoot terminal-during
    fi
    if [ ${_timeout} -eq 0 ] && [ $(( $(date +%s) - _t0 )) -ge $((_tmo + 5)) ]
    then
      mzd_log "terminal: time is up, closing it"
      _timeout=1
      killall -q terminal 2>/dev/null
      sleep 1
      mzd_exe_running terminal && killall -q -9 terminal 2>/dev/null
      _t1=$(date +%s)
    fi
    if [ ${_timeout} -eq 1 ] && [ $(( $(date +%s) - _t1 )) -ge 20 ]
    then
      mzd_log "terminal: the hook did not run in 20 s, running it here"
      sh "${MZD_TERM_HOOK}"
      _timeout=2
    fi
    [ ${_timeout} -eq 2 ] && [ ! -f "${MZD_TERM_FLAG}" ] && break
    sleep 1
  done
  MZD_TERMINAL_REASON=$(cat "${MZD_TERM_FLAG}" 2>/dev/null)
  mzd_log "terminal: closed (reason: ${MZD_TERMINAL_REASON:-none})"
  rm -f "${MZD_TMP}/mzd-hook.log"        # (its lines are in progress.log; in --no-wait mode it stays for the next run)
  [ -n "${MZD_DEBUG}" ] && { mzd_shoot terminal-after; _mzd_ps_list >> "${MZD_LOG}" 2>&1; }
  _mzd_term_files_remove
  case "${_timeout}" in
    0) [ "${MZD_TERMINAL_REASON}" = "time-limit" ] && return 1; return 0 ;;
    1) return 1 ;;
    *) return 4 ;;
  esac
}
