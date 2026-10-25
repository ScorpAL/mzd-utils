# mzd-lib - building blocks for USB scenarios on the Mazda CMU

A scenario is a small shell script on the USB drive. It sources this library and calls ready-made steps: windows
(`mzd-dlg`) and the Terminal with a working USB keyboard (`mzd-kbd-bridge`), without any plumbing of its own.

```sh
#!/bin/sh
. "$(dirname "$(readlink -f "$0")")/mzd-lib/mzd.sh"
mzd_start my-scenario                      # FIRST line after the "." : see "launcher and worker" below
mzd_ask "Step 1" "Open the Terminal and run:   ls -la" "Open Terminal" "Skip" || mzd_end 0
mzd_terminal --hint "Run: ls -la|Then press HOME or type exit"
mzd_info "Done" "The Terminal is closed, the knob works." 6
mzd_bye                                    # "You can remove the USB drive", closes by itself after 15 s
```

Layout of the USB drive: in the root only the entry script (and `mzd-debug.flag`), and the folders `mzd-lib/` (this), `mzd-bin/` (the ARM programs), `scenarios/` (the other scripts: menus, scenarios) and `logs/` (created). A script in `scenarios/` sources `../mzd-lib/mzd.sh`; the library finds the root by itself. See
`../make-usb.sh`. A **menu** and **scenarios** are plain scripts: `scenarios/recon-terminal-10.sh` (the entry script) shows a scrollable list
(`mzd_menu`) and starts the chosen scenario (`scenario-1.sh`, `scenario-2.sh`, `demo.sh N`) with `sh`; the menu comes back on
the same item when the scenario ends. The scenarios work alone, too. A list item is `NAME<TAB>script and arguments`; the menu
runs nothing itself - the script decides what to do with `MZD_MENU_VALUE` (here `sh ${MZD_MENU_VALUE}` in the folder of the scripts).

## Functions

| function | what it does | returns |
|---|---|---|
| `mzd_start NAME [--limit SEC]` | launcher / worker, logs, watchdog (3600 s), dialog program (see below) | - |
| `mzd_end [CODE]` | log and leave | - |
| `mzd_log TEXT` | a line with the time into `progress.log` | - |
| `mzd_ask TITLE TEXT OK CANCEL [SEC]` | two buttons, waits SEC (300) | 0, 1, 254 (nobody answered), 253 (no dialog program) |
| `mzd_choice TITLE TEXT B1 B2 B3 [SEC]` | three buttons (Back / Home = the last one) | 0, 1, 2, 254, 253 |
| `mzd_info TITLE TEXT [SEC]` | one button, closes by itself (8 s) | 0, 254 |
| `mzd_bye [SEC] [TEXT]` | "you can remove the USB drive", closes after SEC (15) | 0, 254 |
| `mzd_fail TEXT [SEC]` | error window, then the script ends with 1 | - |
| `mzd_dialog SEC ARGS...` | any options of `jci-dialog` / `mzd-dlg` | as above |
| `mzd_menu TITLE FILE [BUTTON...]` | a scrollable list (`mzd-listmenu`); FILE: `NAME<TAB>VALUE` or `NAME<TAB>VALUE<TAB>disabled` per line | 0 = an item (`MZD_MENU_INDEX`, `MZD_MENU_VALUE`), 1.. = the button, 254, 253 (no program) |
| `mzd_terminal [--hint T] [--timeout N] [--rc FILE] [--no-wait]` | the Terminal as a step | 0 closed, 1 time limit, 2 could not start, 3 another one is open, 4 hook did not run |

Texts: `\n` is a new line. `MZD_TERMINAL_REASON` after `mzd_terminal`: `home`, `shell-exit N`, `time-limit`, `terminal-closed`, `unknown`.

## The Terminal as a step (`terminal.sh`)

`mzd_terminal` opens the stock Terminal (the stock script is patched in memory: font size, the shell = the bridge, a
semi-transparent window) and, without `--no-wait`, **returns when it is closed and the keyboard focus is back in the CMU user
interface**, so the next window can follow at once. During the session it is as in the stock: without a USB keyboard the knob types m / n
into the Terminal and the CMU is quiet; with a keyboard the bridge grabs the CMU keyboard and the Terminal types what you type.
HOME on the commander, `exit` and Ctrl+D close it. `--no-wait` returns at once (for a Terminal that is the last thing of a script):
nothing is shown by the script afterwards; the hook gives the focus back and cleans up when the Terminal closes. Only one
Terminal at a time (return code 3). If `mzd-bin/mzd-kbd-bridge` is missing, the plain Terminal is opened (no USB keyboard fix).

The focus comes back by a **hook** that the bridge's janitor runs when the Terminal is gone (see `../mzd-kbd-bridge/README.md`):
it works even when the script is dead by then.

## Launcher and worker (`mzd.sh`)

The updater of the CMU starts the entry script and waits for it. `mzd_start` starts the same script again as a **worker** in
a session of its own (`setsid`) and waits for it; so **keep the lines before `mzd_start` empty** (they run twice). The worker has
its output in `logs/<name>-<date-time>/stdio.log`; nothing it starts can keep the updater's pipe open; a watchdog kills it
after the limit; `/tmp` is cleaned when it ends. A scenario started by another one (`sh scenario-1.sh` from the worker) skips all
of this. A new folder `logs/<name>-<date-time>/` for every run, plus `logs/launches.log` (every start and exit, never deleted).

## Debug mode

Off by default. Create an empty file `mzd-debug.flag` in the root of the USB drive (or put `MZD_DEBUG=1` before the `.` line).
It adds: a heartbeat every 2 s (`heartbeat.log`: free memory, load), every signal that arrives is written to `launches.log`
(and ignored), the bridge logs every key (`kbd-bridge.log`), process lists in `launches.log` and `mzd.log`, screenshots
around the Terminal in `screens/`.
