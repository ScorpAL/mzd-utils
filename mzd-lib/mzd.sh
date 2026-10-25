# mzd-lib/mzd.sh - the core of the mzd shell library for the Mazda CMU (fw 74.00.324). Source it, do not run it.
#
#   #!/bin/sh
#   . "$(dirname "$(readlink -f "$0")")/mzd-lib/mzd.sh"        (a script in scenarios/: .../../mzd-lib/mzd.sh)
#   mzd_start my-scenario            # first line of every scenario: from here on it runs in the worker (see below)
#   mzd_ask "Title" "Text" "Next" "Skip" || exit 0
#   mzd_terminal --hint "Run: ls -la"
#   mzd_bye
#
# The USB drive root (MZD_ROOT) has the entry script, mzd-debug.flag and the folders:
#   mzd-lib/   this library (mzd.sh sources dialog.sh and terminal.sh)
#   mzd-bin/   the programs: mzd-dlg (windows), mzd-listmenu (lists), mzd-kbd-bridge (Terminal keyboard)
#   scenarios/ the other scripts (menus, scenarios) started by the entry script with sh
#   logs/      launches.log (every start / exit of every scenario, never deleted) and <name>-<date-time>/ for every run
#
# mzd_start NAME [--limit SECONDS]
#   Called from the USB drive by the updater of the CMU, the script is only a "launcher": mzd_start starts the SAME script
#   again as the "worker" in a session of its own (setsid) and waits for it; the code before mzd_start runs twice, so keep
#   it empty. The worker has stdout / stderr in logs/<NAME>-<time>/stdio.log, a watchdog (default 3600 s) that kills it, the
#   dialog program in /tmp, and cleans /tmp when it ends. (Why a worker: in round 7 the script died a few seconds after the
#   Terminal closed; the worker in its own session survived. Also nothing left in the car can keep the updater's pipe open.)
#   Called again in a scenario started by another one (sh scenario-1.sh from the worker): does nothing.
# mzd_log TEXT       one line with the time into progress.log (and sync)
# mzd_end [CODE]     log and leave the script (the cleanup runs by itself on every exit)
#
# Debug mode (heartbeat every 2 s, every caught signal, verbose bridge log, screenshots around the Terminal, process
# lists): create an empty file  mzd-debug.flag  in the USB drive root, or put MZD_DEBUG=1 before the "." line.
#
# Settings that can be overridden by the environment before the "." line (the tests do): MZD_ROOT, MZD_TMP (/tmp),
# MZD_STOCK (/jci/scripts/run-terminal.sh), MZD_IVI (/usr/bin/ivi-shell), MZD_SURFACE (JCI_OPERA_PRIMARY: the CMU user
# interface, it must get the keyboard focus back after the Terminal), MZD_JCI_DIALOG (/jci/tools/jci-dialog).

MZD_SELF=$(readlink -f "$0")
if [ -z "${MZD_ROOT}" ]
then
  MZD_ROOT=$(dirname "${MZD_SELF}")
  [ -d "${MZD_ROOT}/mzd-lib" ] || MZD_ROOT=$(dirname "${MZD_ROOT}")          # a script in scenarios/: the root is one level up
fi
: "${MZD_TMP:=/tmp}"
: "${MZD_STOCK:=/jci/scripts/run-terminal.sh}"
: "${MZD_IVI:=/usr/bin/ivi-shell}"
: "${MZD_SURFACE:=JCI_OPERA_PRIMARY}"
: "${MZD_JCI_DIALOG:=/jci/tools/jci-dialog}"
MZD_LIB="${MZD_ROOT}/mzd-lib"
MZD_BIN="${MZD_ROOT}/mzd-bin"
MZD_LAUNCH_LOG="${MZD_ROOT}/logs/launches.log"
[ -f "${MZD_ROOT}/mzd-debug.flag" ] && MZD_DEBUG=1
export MZD_ROOT MZD_TMP MZD_STOCK MZD_IVI MZD_SURFACE MZD_JCI_DIALOG MZD_DEBUG

# what looks like a leftover of a run, for the lists in the logs
MZD_PS_RE='mzd-|terminal|jci-dialog|ivi-shell|sleep'

mzd_log()
{
  [ -n "${MZD_PROGRESS}" ] || return 0
  echo "[$(date +%T)] $1" >> "${MZD_PROGRESS}"
  sync
}

mzd_end()
{
  mzd_log "end ${MZD_NAME}"
  exit "${1:-0}"
}

# --- launch log (outside the run folders; never deleted)
_mzd_launch_log()
{
  echo "[$(date '+%F %T')] $1" >> "${MZD_LAUNCH_LOG}" 2>/dev/null
}

_mzd_ps_list()
{
  ps | grep -E "${MZD_PS_RE}" | grep -v grep
}

# debug mode: every signal is written down and ignored (to learn what kills a script)
_mzd_sigmark()
{
  _mzd_launch_log "${MZD_WHO} pid=$$ CAUGHT SIG$1"
  sync
}
_mzd_trap_signals()
{
  for _s in HUP INT QUIT TERM USR1 USR2 PIPE ALRM
  do
    trap "_mzd_sigmark ${_s}" ${_s}
  done
}

# --- the launcher part: start the worker, wait for it, leave
_mzd_launch()
{
  MZD_WHO=launcher
  mount -o rw,remount "${MZD_ROOT}" 2>/dev/null
  hwclock --hctosys 2>/dev/null
  mkdir -p "${MZD_ROOT}/logs" 2>/dev/null
  MZD_WORKER=$(date +%m%d-%H%M%S)
  MZD_OUT="${MZD_ROOT}/logs/${MZD_NAME}-${MZD_WORKER}"
  mkdir -p "${MZD_OUT}" 2>/dev/null
  _mzd_launch_log "=== LAUNCH ${MZD_NAME} pid=$$ ppid=${PPID} script=${MZD_SELF} run=${MZD_WORKER}"
  [ -n "${MZD_DEBUG}" ] && { echo "--- processes that look like leftovers:"; _mzd_ps_list; } >> "${MZD_LAUNCH_LOG}" 2>&1
  sync
  [ -n "${MZD_DEBUG}" ] && _mzd_trap_signals
  trap '_mzd_launch_log "=== LAUNCHER EXIT pid=$$"; sync' EXIT

  export MZD_WORKER MZD_NAME MZD_LIMIT
  if command -v setsid > /dev/null 2>&1
  then
    setsid sh "${MZD_SELF}" > /dev/null 2>&1 < /dev/null &
    _mzd_launch_log "launcher: worker started with setsid"
  else
    sh "${MZD_SELF}" > /dev/null 2>&1 < /dev/null &
    _mzd_launch_log "launcher: NO setsid, worker started in the same session"
  fi

  # wait for the worker as if the script ran in place: until its pid is gone (it writes its pid file first thing)
  _w=0
  while [ ! -s "${MZD_OUT}/worker.pid" ] && [ ${_w} -lt 30 ]
  do
    sleep 1
    _w=$((_w + 1))
  done
  _wp=$(cat "${MZD_OUT}/worker.pid" 2>/dev/null)
  if [ -n "${_wp}" ]
  then
    while kill -0 "${_wp}" 2>/dev/null
    do
      sleep 1
    done
    _mzd_launch_log "launcher: worker ${_wp} is gone"
  else
    _mzd_launch_log "launcher: the worker wrote no pid file in 30 s"
  fi
  exit 0
}

# --- the worker part: everything the scenario needs
_mzd_cleanup()
{
  [ -n "${MZD_HB_PID}" ] && kill "${MZD_HB_PID}" 2>/dev/null
  [ -n "${MZD_WD_PID}" ] && kill "${MZD_WD_PID}" 2>/dev/null
  killall -q jci-dialog mzd-dlg mzd-listmenu 2>/dev/null
  rm -f "${MZD_TMP}/mzd-dlg" "${MZD_TMP}/mzd-listmenu" "${MZD_TMP}/mzd-menu.out" "${MZD_TMP}"/mzd-menu-items.txt
  # the Terminal files stay while a Terminal is open (lock): the hook of the bridge removes them
  if [ ! -d "${MZD_TMP}/mzd-terminal.lock" ]
  then
    rm -f "${MZD_TMP}/mzd-kbd-bridge" "${MZD_TMP}/mzd-terminal-rc" "${MZD_TMP}/mzd-terminal-hook.sh" "${MZD_TMP}/mzd-terminal.done" "${MZD_TMP}/mzd-terminal.result"
  fi
}

_mzd_on_exit()
{
  _mzd_launch_log "=== WORKER EXIT ${MZD_NAME} pid=$$"
  [ -n "${MZD_DEBUG}" ] && _mzd_ps_list >> "${MZD_LAUNCH_LOG}" 2>&1
  _mzd_cleanup
  sync
}

_mzd_init_worker()
{
  MZD_WHO=worker
  MZD_OUT="${MZD_ROOT}/logs/${MZD_NAME}-${MZD_WORKER}"
  mkdir -p "${MZD_OUT}/screens" 2>/dev/null
  echo $$ > "${MZD_OUT}/worker.pid"
  MZD_PROGRESS="${MZD_OUT}/progress.log"
  MZD_LOG="${MZD_OUT}/mzd.log"
  exec >> "${MZD_OUT}/stdio.log" 2>&1 < /dev/null
  trap '_mzd_on_exit' EXIT
  [ -n "${MZD_DEBUG}" ] && _mzd_trap_signals

  if [ -n "${MZD_DEBUG}" ]
  then
    # heartbeat: its own process, every 2 s; reads /proc with shell built-ins only
    (
      trap 'exit 0' TERM
      while :
      do
        _mf=""
        while read -r _k _v _u
        do
          if [ "${_k}" = "MemFree:" ]; then _mf=${_v}; break; fi
        done < /proc/meminfo
        read -r _l1 _l2 _l3 _rest < /proc/loadavg
        echo "[$(date +%T)] hb memfree=${_mf}kB load=${_l1}" >> "${MZD_OUT}/heartbeat.log"
        sync
        sleep 2
      done
    ) > /dev/null 2>&1 < /dev/null &
    MZD_HB_PID=$!
  fi

  # watchdog: independent of the main flow, kills the worker after the limit
  _mzd_main=$$
  (
    trap 'kill ${_sp} 2>/dev/null; exit 0' TERM
    sleep "${MZD_LIMIT}" &
    _sp=$!
    wait ${_sp}
    echo "[$(date +%T)] WATCHDOG: hard limit reached, stopping" >> "${MZD_PROGRESS}"
    kill -9 ${_mzd_main} 2>/dev/null
    killall -q jci-dialog mzd-dlg mzd-listmenu terminal mzd-kbd-bridge 2>/dev/null
    rm -f "${MZD_TMP}/mzd-dlg" "${MZD_TMP}/mzd-listmenu" "${MZD_TMP}/mzd-kbd-bridge"
    sync
  ) > /dev/null 2>&1 < /dev/null &
  MZD_WD_PID=$!

  mzd_log "start ${MZD_NAME} (worker pid $$, pgrp/session $(cut -d' ' -f5,6 /proc/$$/stat 2>/dev/null)), debug=${MZD_DEBUG:-off}"
  for _p in mzd-dlg mzd-listmenu mzd-kbd-bridge
  do
    [ -x "${MZD_BIN}/${_p}" ] && mzd_log "program: $("${MZD_BIN}/${_p}" --version 2>&1 | head -1)"
  done
  # what the hook of a Terminal left in /tmp (its log on the USB drive is lost when the drive was pulled before it ran)
  if [ -f "${MZD_TMP}/mzd-hook.log" ]
  then
    while IFS= read -r _hl
    do
      mzd_log "(from /tmp/mzd-hook.log) ${_hl}"
    done < "${MZD_TMP}/mzd-hook.log"
    rm -f "${MZD_TMP}/mzd-hook.log"
  fi
  MZD_INIT=1
  export MZD_INIT MZD_PROGRESS MZD_LOG MZD_OUT
  _mzd_dialog_setup
}

mzd_start()
{
  MZD_NAME=${1:-mzd}
  [ $# -gt 0 ] && shift
  MZD_LIMIT=3600
  while [ $# -gt 0 ]
  do
    case "$1" in
      --limit) MZD_LIMIT=$2; [ $# -gt 1 ] && shift ;;
    esac
    shift
  done
  # a scenario started by another one: everything is already there
  if [ -n "${MZD_INIT}" ]
  then
    return 0
  fi
  # the worker: the same script again, started by the launcher
  if [ -n "${MZD_WORKER}" ]
  then
    _mzd_init_worker
    return 0
  fi
  _mzd_launch
}

# --- small helpers shared by dialog.sh and terminal.sh

# guard SECONDS CMD...: a command that might hang; output to mzd.log; killed after SECONDS
mzd_guard()
{
  _glimit=$1
  shift
  echo "\$ $*" >> "${MZD_LOG}"
  "$@" >> "${MZD_LOG}" 2>&1 &
  _gp=$!
  _gi=0
  while kill -0 ${_gp} 2>/dev/null && [ ${_gi} -lt ${_glimit} ]
  do
    sleep 1
    _gi=$((_gi + 1))
  done
  if kill -0 ${_gp} 2>/dev/null
  then
    kill -9 ${_gp} 2>/dev/null
    echo "(TIMEOUT after ${_glimit}s)" >> "${MZD_LOG}"
  fi
}

# exe_running NAME: is a process with this executable running? ONE ls instead of a readlink per process (the CMU forks slowly)
mzd_exe_running()
{
  ls -l /proc/[0-9]*/exe 2>/dev/null | grep -q " -> .*/$1\$"
}

# mzd_shoot NAME: screenshot with the stock tool into the run folder (debug mode only)
mzd_shoot()
{
  [ -n "${MZD_DEBUG}" ] || return 0
  [ -x /usr/bin/screenshot ] || return 0
  _w="${MZD_TMP}/mzd-shot-$1"
  rm -rf "${_w}"
  mkdir -p "${_w}"
  mzd_guard 15 sh -c "cd ${_w} && XDG_RUNTIME_DIR=/tmp /usr/bin/screenshot"
  if [ -s "${_w}/wayland-screenshot.png" ]
  then
    cp "${_w}/wayland-screenshot.png" "${MZD_OUT}/screens/$1.png"
    mzd_log "screenshot $1 saved"
  else
    mzd_log "screenshot $1: no file"
  fi
  rm -rf "${_w}"
}

. "${MZD_LIB}/dialog.sh"
. "${MZD_LIB}/terminal.sh"
