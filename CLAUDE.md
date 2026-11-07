# Account Queue — Claude Code Context

This file is for Claude (or any future contributor) picking this project back up.
Read this before making changes — several bugs listed below were subtle and cost
real debugging time; the patterns that fixed them should be preserved, not
accidentally reintroduced.

## What this is

A single-file AutoHotkey v2 desktop utility (`AccountQueue.ahk`) that speeds up
logging into many game accounts across multiple client windows. It reads
credentials from local `.txt` files, shows them in a GUI, and provides hotkeys
to paste an account's email/password into whatever window currently has focus,
then advance to the next account. It grew from a rough ~150-line personal
script into a full utility with editing, window-linking automation, notes,
theming, and persisted settings.

**Platform: Windows only. AutoHotkey v2.0 required.** Now ~9,000 lines,
single file, current version 0.43.0 (see `CHANGELOG.md` for the full arc
0.1.0 → today — read it; each entry records a decision or a hard-won bug).

## Handoff quick-start (read this first)

- **Ship convention (the author's own machine).** The live script that
  gets run day to day lives outside the repo, versioned by an
  incrementing filename number (`AccountQueue<N>.ahk`, currently
  **60 = v0.42.0**). Each release: bump `Config.Version`, add a
  `CHANGELOG.md` entry, run the test suite, then copy
  `AccountQueue.ahk` to the next `AccountQueue<N+1>.ahk` (leaving the
  previous file as a fallback) and refresh the repo copy. No zips — that
  step was dropped at 0.27.0.
- **The repo working copy is this folder** (this is
  where you edit + run tests). The live `Logins\*.txt` holds REAL
  credentials — never read or commit them.
- **Testing, without burning the owner's time (READ THIS):**
  - While iterating: `tests\run-tests.ps1 -Fast -Quiet` - **3.7s, one
    line of output, and it does NOT touch the mouse.** Covers 287 of the
    314 checks (everything pure: data, routines, search, session math,
    layout).
  - Before shipping a version, ONCE: `tests\run-tests.ps1` (~12s, all
    314; macro-test drives the real mouse and resize-stress flashes a
    window, so don't run it while the owner is working).
  - `-Only <substring>` runs matching files only (e.g. `-Only macro`).
  - **Do not re-run the suite after documentation-only edits** (CHANGELOG,
    README, this file) - they cannot affect it.
  - One fast run per batch of code edits, not one per edit. The suite is
    cheap; invoking it four times a turn is not.
  - **NEVER broad-kill AutoHotkey processes** (`Get-Process AutoHotkey64 |
    Stop-Process`). The owner runs the REAL Account Queue on this machine
    while you work — that command closes their app mid-session. Kill only
    PIDs you started yourself.
  - **Tests must not disturb the desktop they run on.** Three rules,
    learned the hard way (0.35.1): (1) never point `Config.GameProcess`
    at the real game — any scan path (auto-next, jump-to-client, the
    login funnel) will ACTIVATE or CLICK a real client; use the
    `NO_SUCH_GAME` name. (2) Every fixture sets `AQ_TEST_QUIET` before
    the `#Include` so the app window comes up with `NoActivate`, and
    writes a Settings.ini with `AlwaysOnTop=0`. (3) Every fixture
    captures the foreground window at start and calls
    `AQRestoreForeground()` before exiting — otherwise Windows promotes
    whatever is underneath when the test window dies, which on this
    machine is a game client.
- **AutoHotkey v2**: `tests\run-tests.ps1` finds it on its own (Program
  Files, the registry, or `PATH`). Set `AHK_PATH` to override.

## State of play — what is PROVEN vs. what has never met the real game

Read this before you trust any green test run. The suite is large (314
checks) but it exercises **fake windows and pure logic**. Whole
subsystems have never run against a live ToW client, because doing so
launches real game clients and needs the owner at the keyboard.

**Proven by tests / measured probes:**
- Data round-trips, file preservation, search (incl. cross-file), views,
  session/game-day math, money parsing, layout + resize.
- The routine engine: parser, block/jump resolution, loops, `break`/
  `continue`/`goto`, `repeat` retry semantics, conditions, dry-run,
  tracing. Programs really execute (against the app's own window).
- Macro click scaling and playback (real clicks on throwaway windows).
- Idle-job selection, scope/pending/done bookkeeping, away detection,
  block reasons, history recording.
- Measured with dedicated probes: playback z-order (gotcha #17),
  pointer-restore timing (#18), mouse-jitter idle (#20), test-desktop
  hygiene (0.35.1), X-to-tray.

**NEVER verified end-to-end against a real client — assume nothing:**
- The login funnel against real pixels (`LoginFunnel`, retries, the
  freeze-sensitive email→F4 gap).
- `RunChore` (idle chore: login → macro → close → next) — the loop is
  code-reviewed and reuses vetted helpers, but has never driven a real
  client.
- `RoutineRestartClient` (close → relaunch → re-login → carry on).
- The idle countdown appearing during a genuine 2-hour absence.
- Activity mode across a full multi-hour session.

**When something here misbehaves, get the artifacts before theorising:**
`Logins\idle-history.txt` (what idle runs did, per account),
`Logins\Routines\routine-log.txt` (routine failures + last ~60 steps),
the Idle Actions status line (why nothing is running), and a routine's
**🔍 Dry run** + trace. Several bugs this session were found by writing
a throwaway probe in the scratchpad and *measuring*, not by reading code
— do that.

## Critical constraint for AI assistants working on this repo

**There is no AHK interpreter available in typical sandboxed dev environments**
(Windows-only language). Every change must be reasoned through manually
against AHK v2 semantics and then verified by the human on an actual Windows
machine, test with `tests\run-tests.ps1 -Fast -Quiet` after each batch of
code edits, and the full `tests\run-tests.ps1` once before you ship (see
the testing policy above — 314 checks: data round-trips, views, session
timers, linking, macros, queue, routines, layout audit, resize stress).
The AHK exe is GUI-subsystem, so anything invoking it directly must
explicitly wait for the exit code. The tests `#Include` the real app
against a sandbox `tests\Logins`, and the two "slow" ones briefly show
windows / move the mouse. This still doesn't cover live game clients — hotkey
flows and window linking against real ToW windows need a human. Static
review is necessary but not sufficient — several
real bugs in this project's history (see "Hard-won gotchas" below) looked
correct on read-through and only surfaced when actually run. After any
non-trivial change, explicitly ask the person to test the specific affected
flow rather than assuming correctness.

Specifically worth testing after changes:
- Any new hotkey binding (check for `#HotIf` context leaks between blocks)
- Any GUI resize behavior (add/remove a control below the list, then resize
  the window taller/shorter — see the layout system below)
- Any new `DllCall` usage (theming, DWM, uxtheme — these are Windows-version-
  and-build sensitive and always wrapped in `try`)
- Any new confirmation/`MsgBox` dialog (must go through `ShowConfirm()`, see below)
- Any local variable name — check it doesn't collide case-insensitively with a
  built-in (see gotcha #2)

## File layout

```
AccountQueue.ahk       The entire application (single file)
Logins/                 User's data folder (gitignored — contains real credentials)
  *.txt                 One file per account "batch" — see file format below
  Backups/               Timestamped backups, auto-created before credential writes
  Macros/                Recorded click macros, one .txt per macro (ref|w|h + click|x|y|delayMs lines)
  Routines/              Built programs: macros + loops/pixel tests/branching (0.32.0)
  Settings.ini            Persisted preferences (theme, window size, quota/idle state, etc.)
  IdleJobs.txt            Idle Actions jobs (reserved — skipped by the account loader)
  idle-history.txt        Idle run history (reserved — skipped by the account loader)
tests/                  Self-contained test scripts + run-tests.ps1 (314 checks; sandbox
                          Logins is generated next to the tests, gitignored)
docs/sample-login-format.txt   Example file showing the format, with fake data
CHANGELOG.md            Version history
README.md               End-user documentation
```

## Data formats

**Login files** (`Logins/*.txt`), one account per line:
```
Name|Email|Password
Name|Email|Password|Note                                (fields 4+ optional)
Name|Email|Password|Note|Class|Level|Money|LastLogin    (full form, 0.5.0+)
```
- Fields 5-8 are the Game Info view's data. `WriteAccountsFile()` trims
  trailing *empty* fields (never below the first 3), so lines only grow
  when the user actually fills something in.
- **Invariant: every account object in memory carries ALL eight props**
  (defaulted to "") — loader, `CloneAccount()`, and the add-dialog all
  enforce this, and display/filter/save code does direct property reads
  with no `HasOwnProp` guards. Only `ClientSession`/`ClientHwnd` remain
  optional props. Keep the invariant when adding fields.
- Lines starting with `;` or blank lines are skipped for display but
  **preserved verbatim on save**: every non-account line (comment, blank,
  unparseable) is attached to the account that follows it (`RawBefore`) or
  to the file object's `TrailingRaw`, and `WriteAccountsFile()` re-emits
  them. Before 0.4.0, any save — including note autosaves — silently
  destroyed these lines on disk. Don't regress this: `CloneAccount()` must
  keep carrying `RawBefore`, and any new save path must pass the file's
  `TrailingRaw` to `WriteAccountsFile()`.
- Lines with fewer than 3 `|`-delimited parts are treated as raw lines too
  (kept in the file, not parsed) and counted per-file in `UnparsedCount`,
  surfaced in the count label as "N unreadable lines kept in file".
- **Account identity for internal matching (position memory, window-link
  ownership) uses Email, not Name.** Name is just a display label and is not
  guaranteed unique — a real user's file had every single account named `x`.
  Don't reintroduce Name-based matching for anything that needs to reliably
  find "the same account" later.

**Settings.ini** (`Logins/Settings.ini`), written via `IniWrite`/`IniRead`:
```ini
[Preferences]
Theme=light|dark
ShowPasswords=0|1
AlwaysOnTop=0|1
WindowWidth=<int>
WindowHeight=<int>
WindowX=<int>          (outer coords; validated against live monitors on load)
WindowY=<int>
LastFile=<filename without .txt>

[Positions]
<filename>=<email of last-selected account in that file>
```
The `[Positions]` section has one dynamically-named key per login file —
read/written manually via `IniRead(path, "Positions")` (whole-section read)
and parsed as `key=value` lines, since AHK's `IniRead` doesn't return a
structured map.

## Architecture

- **`class Config`** — static "constants" (paths, sizes, delays, the game's
  process name). Since 0.16.0 a subset is user-tunable at runtime via the
  ⚙ Preferences dialog, persisted in `Settings.ini [Tuning]`: the
  `TuningSchema()` table is the single source for which values, their
  ranges, labels and tooltips — to expose a new tunable, add one entry
  there (defaults are captured by `CaptureTuningDefaults()` BEFORE
  `LoadSettings`, so keep that ordering). Changing `DayResetHour` must
  keep adopting the new boundary (`App.CurrentGameDay := GameDayStamp()`
  in `PrefsSave`) or the next housekeeping tick fakes a day rollover.
  Safe to bump `Version` as a convention when
  making notable changes. `WindowWidth/WindowHeight` are the **design size**
  the layout is built at — never overwrite them with the user's saved size
  (that's `App.WinW/WinH`, applied at `Show()` time); `Gui_Size` uses
  `Config.WindowHeight` as its resize baseline and breaks if it drifts.
- **`class Colors`** — *mutable at runtime*, despite being a class. `ApplyTheme()`
  reassigns `Colors.Bg/Text/TextDim/Accent` to switch light/dark. Anything that
  reads `Colors.X` at draw time (not cached) picks up theme changes for free —
  this is how the Add/Edit dialog gets correct theming with zero extra code.
- **`global App`** — single object holding all mutable runtime state: loaded
  files/accounts, current selection, filter text, edit-mode/dialog-open flags,
  window-linking state (`UsedWindowHwnds`, `WindowSessionNumbers`,
  `AutoNextClient`), theme name, notes-autosave state, position-memory
  state, `AlwaysOnTop`, the saved window size (`WinW`/`WinH` — see the
  resize system below), the shared pending-clipboard-restore slot
  (`SavedClip`), the captured resize layout, and GUI control references.

### The dynamic resize system (important — don't bypass it)

`CaptureLayout()` runs once at the end of `BuildGUI()`. It measures the real
on-screen Y position of every control below the ListView via `GetPos()` and
records them via `RecordBelowList(ctrl, isFullWidth)`. `Gui_Size()` then:
1. Grows/shrinks the ListView by exactly the same delta as the window's height change.
2. Shifts *every* registered below-list control by that identical delta.
3. Resizes full-width controls' widths to match the new window width.

**This exists because an earlier version used a hardcoded pixel budget**
(`listH := Height - 370`, a guessed number) that silently went stale every
time a new row of controls was added below the list — causing the ListView to
grow over the top of checkboxes/buttons and make them unclickable. That bug
was hard to diagnose because it only manifested on resize/at certain window
heights.

**Rule: any new control added below the ListView must be registered via
`RecordBelowList()` inside `CaptureLayout()`, or it will not get its position
updated on resize and may end up covered.**

The baseline for the height delta is `Config.WindowHeight` — the fixed
design height the layout is built at. The user's *saved* size is kept
separately in `App.WinW/WinH` and applied at `Show()` time, followed by an
explicit `Gui_Size` pass. (0.3.0 overwrote the Config values with the saved
size, which zeroed the delta at startup and left restored windows with
cut-off or floating bottom controls.)

## Design philosophy: friction is proportional to risk

This was a deliberate, repeated theme across the project — preserve it when
extending:

- **Credential edits** (Name/Email/Password): high friction on purpose. Requires
  toggling "Edit Mode" first, shows a confirmation dialog naming exactly what
  will change, and takes a mandatory timestamped backup before writing —
  aborting the whole save if the backup itself fails.
- **Notes and Game Info fields (Class/Level/Money/LastLogin)**: low friction
  on purpose. No toggle, no dialog, autosaves ~800ms
  after typing stops (debounced), no confirmation, and *skips* the backup step
  (backing up on every keystroke-adjacent save would flood the Backups folder
  for something explicitly called "not critical"). Still writes atomically
  (temp file + rename) regardless — atomicity is cheap, backups are not.
- **Client window links**: session-only, *never* written to the `.txt` files.
  Resets on every restart. This is intentional — it's positional bookkeeping
  about which window a paste went to, not credential data.

When adding new fields/features, decide deliberately which bucket they belong
in rather than defaulting to "just add a confirmation dialog."

## Hard-won AHK v2 gotchas (do not reintroduce these)

1. **`<` `>` `<=` `>=` are numeric-only in v2**, unlike v1 which fell back to
   string comparison. Comparing strings with these operators throws
   `TypeError: expected a number but got a string`. Use the built-in
   `StrCompare(a, b)` (returns negative/0/positive) for string ordering — see
   `SortArray()`.

2. **Local variable names that collide case-insensitively with a built-in
   class/function break in confusing ways.** A local variable named `menu`
   in a function that also calls the built-in `Menu()` constructor resolves
   `Menu()` to the *local variable* (not-yet-assigned), throwing "this local
   variable has not been assigned a value." AHK identifier resolution is
   case-insensitive throughout a function's scope, not just after the point of
   first assignment. Avoid local names that shadow `Menu`, `Gui`, `Map`,
   `Array`, etc. (Fixed instance: renamed to `ctxMenu` in `OnListContextMenu`.)

3. **String escaping uses a backtick**, not doubled quotes: `` `" `` for a
   literal double-quote inside a double-quoted string, `` `n ``/`` `r `` for
   newline/carriage-return, `` `' `` for a literal apostrophe inside a
   single-quoted string.

4. **`GuiControl.GetPos()`/`.Move()` accept blank/omitted positional args** to
   skip fields, e.g. `ctrl.GetPos(, &y)` (skip X, W, H) or
   `ctrl.Move(, newY, newWidth)` (skip X). Used throughout the resize system.

5. **An Always-on-Top main window can visually bury a `MsgBox`**, since
   `MsgBox` isn't itself topmost. Fixed via `ShowConfirm()`, which suspends
   `+AlwaysOnTop` on `App.Gui` right before calling `MsgBox` and restores it
   right after. **Any new blocking dialog must go through `ShowConfirm()`
   (MsgBox) or `ShowInput()` (InputBox), never the raw functions**, or it
   can reintroduce this bug. Relatedly: an owned
   dialog (`+Owner <hwnd>`) already stacks above its owner automatically —
   giving it its own independent `+AlwaysOnTop` is redundant and was actively
   making the z-order fight worse, not better.

10. **`Gui.GetPos()` returns the OUTER window size, but `Gui.Show("w h")`
   and `+MinSize` take CLIENT-area sizes.** Persisting a size measured with
   `GetPos()` and re-applying it via `Show()` makes the window grow by the
   title-bar/border size on every single run — a slow creep that's easy to
   miss in testing. Use `Gui.GetClientPos()` when the number will ever be
   fed back to `Show()`/`MinSize`. Also skip saving size while the window
   is maximized or minimized (`WinGetMinMax() != 0`).

11. **`Menu.Add(name, cb)` with an existing item name UPDATES that item**
   instead of adding a duplicate. Any menu built from dynamic data must
   guarantee unique labels (the window-link context menu prefixes a running
   index) or entries silently merge and fire the wrong callback.

12. **ListView `Click` fires only for mouse; keyboard navigation inside the
   control (Home/End/PageUp/PageDown) doesn't go through it.** Track the
   selection with the `ItemSelect` event (fires for both), or hotkey-driven
   state (like "which account do F1/F2 paste") silently desyncs from what's
   highlighted on screen.

13. **Programmatic `.Text`/`.Value` assignment does NOT raise the Change
   event in v2 — only real user input does.** Two consequences: (a) don't
   rely on setting a box's text to trigger its autosave handler; (b) in the
   include-based test harness, simulate typing with
   `ControlSend("text", , "ahk_id " ctrl.Hwnd)`, not `.Text := "text"` —
   a test doing the latter silently tests nothing (this exact mistake made
   four tests fail-then-pass during 0.5.0 development).

14. **ListView header-click sorting reorders rows visually WITHOUT touching
   your own arrays.** With hotkey-driven state ("which account do F1/F2
   paste"), a single header click silently desyncs highlight from paste
   target. The list is created with `NoSort` — don't re-enable sorting
   without also remapping `App.Displayed`.

15. **Windows virtual desktops CLOAK windows, and AHK's default
   detection treats cloaked as nonexistent.** Measured on the owner's
   machine: switching desktops leaves game windows with `IsWindow=1`,
   `IsWindowVisible=1`, `DWMWA_CLOAKED=2` — but `WinExist`/`WinGetList`
   with `DetectHiddenWindows` off report them GONE (this silently
   detached every link whenever the owner switched to their work
   desktop). Any *state-keeping* check on a client hwnd must run with
   `DetectHiddenWindows(true)` (save/restore `A_DetectHiddenWindows` —
   it's thread-local). **But hidden-aware `WinGetList` by process is a
   trap of its own**: ToW.exe showed 60 matches of which only 20 were
   real clients — the rest are genuinely hidden helper windows. So
   *scanning* for clients must use `GetGameClientWindows()`
   (hidden-aware + `IsWindowVisible` filter). Deliberate exception:
   `MaybeAdvanceToNextClient` and "queue on all clients" stay
   default-detection on purpose — they should only act on clients the
   user can currently see, not yank the user across desktops.

16. **Moving many controls in a Size handler leaves stale paint ("ghost"
   copies of controls at their old spots) during rapid resizes** — fixed in
   `Gui_Size` by wrapping the batch of `.Move()` calls in `WM_SETREDRAW`
   off/on plus one `RedrawWindow` at the end. Two traps inside that fix:
   (a) it must be `DllCall` by raw hwnd — `SendMessage(.., "ahk_id " hwnd)`
   and `WinRedraw()` do a window *search* that throws "Target window not
   found" because Size fires during `Show()` while the window isn't visible
   yet (and an uncaught throw in a GUI event thread is a blocking error
   dialog); (b) the re-enable must sit in a `finally`, or any error between
   off/on leaves the window permanently unpainted ("frozen").

20. **Never gate automation on unbroken `A_TimeIdlePhysical` (0.42.0).**
   Idle jobs required 2 h of *continuous* physical silence. MEASURED on
   the owner's machine: the mouse emits stray events while untouched -
   over a 20 s sample the keyboard idled the whole time while the mouse
   reset the timer on nearly every 1 s sample. One twitch zeroes the
   counter, so the threshold was unreachable and NOTHING ever fired for
   8+ h. Away-ness is now judged by POINTER POSITION sampled per
   housekeeping tick (`UserWasActive` - pure, unit-tested;
   `Config.AwayMouseSlackPx` = 12 px of tolerated drift), accumulated
   into `App.AwayMs` by `UpdateAwayTracking`. That tracker FREEZES
   while our own automation runs (it moves the mouse; a position check
   can't distinguish it) so the next job in the list can still start.
   Corollary rule: **any gate that can silently decline must be able to
   say why** - `IdleBlockReason()` returns the first failing gate and
   the Idle Actions window shows it live. Cancelling the countdown resets
   `AwayMs` or it re-pops on the next tick.

19. **Only the OUTERMOST playback restores the pointer / topmost / flags
   (0.37.0).** Playback nests: a routine's `run` step plays a macro or
   sub-routine via `RunAutomationOnWindow(.., nested:=true)`. Everything
   that brackets a run - `RestorePointerAfterPlayback`, `App.MacroPlaying`,
   `PlaybackWindowsAside`/topmost - must be guarded by `if !nested` so it
   fires ONCE at the top. A nested restore added 250ms per sub-call AND
   re-fired gotcha #18 (the sub-macro's last click landing at the moved
   pointer). `RunMacroOnWindow` and `RunRoutineOnWindow` both take
   `nested` now; regression-tested in macro-test (nested leaves the
   pointer on its last click, outer returns it home).

18. **Never move the pointer immediately after playback ends (0.35.2).**
   Every playback path used to finish with `MouseMove(origX, origY, 0)`
   to park the cursor where the user left it. BlueStacks-style clients
   read a tap from the pointer's position when they PROCESS the event,
   so that instant move made the run's LAST click register at the
   cursor's destination - reproducibly on the "Test on client" button
   that started the run, following it when the window moved. All three
   paths (RunMacroOnWindow, RunRoutineOnWindow, RoutineMakerTest) must
   go through `RestorePointerAfterPlayback()`, which settles for
   `Config.MouseRestoreDelayMs` (default 250, 0 = never move it back)
   first. This also explains older "sometimes a macro clicks somewhere
   weird at the end" reports.

17. **Our own Always-on-Top windows swallow playback clicks (0.35.0).**
   Macro/routine playback sends clicks at SCREEN coordinates. The main
   window is topmost by user preference and every owned dialog (Macro
   Manager, Routine Maker) floats with it, so any click aimed at a spot
   they cover landed on US - most confusingly on the "Test on client"
   button that started the run. MEASURED with a repro harness: the target
   window received 0 of the clicks aimed at it while the app was topmost,
   1 of 1 after. **Every playback entry point must bracket the run with
   `PlaybackWindowsAside()` / `PlaybackWindowsRestore(wasTop)`** -
   currently `RunAutomationOnWindow` (covers queue, playlists, row menu,
   console) and `RoutineMakerTest` (calls the interpreter directly). Any
   NEW path that sends input must do the same. Related: never pass "Focus"
   when highlighting a row mid-playback - it pulls focus off the game
   between clicks (the maker's live cursor uses "Select Vis").

6. **Windows 11's taskbar doesn't reliably expose button order** via classic
   Win32 APIs (it's a different UI framework internally). Don't attempt to
   read taskbar order for the window-linking batch ordering. Instead,
   `SortByScreenPosition()` sorts candidate windows by actual on-screen X/Y
   (`WinGetPos`) as the closest reliable, cross-version equivalent.

7. **Dark mode is best-effort and control-type-dependent.** Text/Checkbox/
   Progress controls take custom colors live via `.SetFont("cCOLOR")` /
   `.Opt("cCOLOR")`. ListView and Edit controls need
   `DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "str", "DarkMode_Explorer"
   /"", "ptr", 0)` for native-ish dark rendering (Win10/11 only, wrapped in
   `try`) — **but that only themes the chrome (scrollbars, list header);
   the client area needs explicit `.Opt("+Background<hex> c<hex>")` /
   `"+BackgroundDefault cDefault"` or it stays white in dark mode.** **Native Button controls do not take dark theming** without much
   heavier custom-draw work — left alone intentionally in both themes; don't
   "fix" this without discussing the cost/benefit, it was a conscious
   trade-off. Title bar dark mode via
   `DllCall("dwmapi\DwmSetWindowAttribute", hwnd, 20 (or 19 on older builds), &1, 4)`.

8. **Clone-then-mutate, don't rebuild-from-scratch, when saving an edited
   object.** An earlier version of the credential-save path replaced the
   whole account object with a fresh `{Name, Email, Password}` literal on
   edit — which silently dropped `Note`, `ClientSession`, and `ClientHwnd`
   any time someone fixed a typo in a name. Fixed by cloning the existing
   object (`CloneAccount()`) and mutating only the fields actually being
   edited. Apply this pattern to any future "edit an existing record" code.

9. **Debounced autosave via `SetTimer` requires a stable function reference.**
   `SetTimer(CommitNoteAutosave, -800)` called repeatedly *with the same named
   function* resets the pending one-shot timer (standard debounce). If you
   instead pass a fresh closure/bound-func each call, AHK treats each as a
   distinct timer and they stack up instead of debouncing. Keep autosave
   handlers as plain top-level function references for this reason.

## Feature summary (as of the current version)

- **Hotkeys (global unless noted):** F1 paste email · F2 password+advance
  · F4 combo login+advance · F10 pause/resume the paste keys (0.43.0 —
  session-only flag `App.PastePaused`; all three go through
  `PasteKeysReady()`, which toasts WHY when it refuses) · F3/Shift+F3
  switch file · F5 toggle auto-next
  client · F6 cycle view · F7 record macro / abort · F8 pick mode · F9
  online view · F12 (armed only) capture a login point · Up/Down navigate
  (main window focused). Everything auto-login lives in the **🚀 Mass
  Login** console (button), not a hotkey.
- **Bottom-of-window control rows** (below the list, all registered in
  `CaptureLayout`/`RecordBelowList`): selected-account edit boxes +
  progress/status; login-flow row (Auto-next, 🚀 Mass Login, Forget Used,
  Macros, Pick); manage row (Edit Mode, Add, Reload); prefs row
  (Show pw, Dark, On-Top, ⚙, ❔ Hotkeys). ⚙ = `OpenPreferences`
  (data-driven from `TuningSchema`). **There is no `Status` control
  since 0.30.0** — the bold status line became the four-segment STAT
  STRIP (`StatDone/StatOnline/StatToGo/StatMoney`, s11 bold,
  Success/Warning/TextDim/Accent, updated only via `SetStatText` in
  `RefreshSummary`); selection/count info lives in `CountLabel`
  (dim italic, right-anchored by `LayoutDynamicRows`). `FormatMoney`
  keeps THREE decimals of the unit (1.036B) — the owner explicitly
  wants the precision; don't round it back down.
- **Three list views** (button next to Search cycles, or F6; persisted):
  Credentials (#/Name/Email/Password/Client/Note), Game Info
  (#/Name/Class/Level/Money/Note) and Session
  (#/Name/Client/Online/Left/Last login/Note). Same accounts, same order —
  `SetViewMode()` rebuilds columns via `SetListColumns()` (ModifyCol
  retitles col 1, InsertCol/DeleteCol handle the rest; `App.ListColCount`
  tracks the live count) and `BuildRowCells()` picks the cell set. In game
  view the quick-edit row shows Class/Level/Money + Note boxes
  (`LayoutDynamicRows()` handles their x/width per view, plus the
  status-left/count-right line — none of those are registered full-width
  in `CaptureLayout()`). "Last login" is auto-stamped by F2/F4 via
  `StampLastLogin()`.
- **Layout zones (0.7.0)**: below the list, controls are grouped into
  four zones split by etched separator lines (`0x10` Text controls,
  registered full-width): selected-account panel, login flow, account
  management (Edit Mode beside Add/Reload), preferences row.
- **Macros (0.9.0)**: record-by-doing click sequences. Recording is a
  pass-through `~LButton` hotkey enabled only while `App.IsRecording`;
  only clicks whose window-under-mouse matches `Config.GameProcess`
  become steps (window-relative coords + real inter-click pauses as
  delays, ref window size stored for proportional scaling in
  `MacroStepScreenPos()` — pure, unit-tested). Playback
  (`RunMacroOnWindow`) sleeps in 50ms slices checking Esc/F7 and window
  existence, restores the mouse, guards via `App.MacroPlaying` (F7 is
  both record-toggle and abort — the flag decides). **Left-clicks only,
  deliberately: recording keystrokes would write passwords into
  plain-text macro files.** Manager window (`OpenMacroManager`) mirrors
  the account editor's owner/theming pattern; "edit" = open the file in
  Notepad, not an in-app editor. Macro files: `Logins/Macros/<name>.txt`,
  never rewritten except record/rename/delete, so hand-edits are safe.
- **Session view + online-time bookkeeping (0.11.0)**: third view mode
  ("session") for the 30-accounts×30-minutes workflow. Session-only
  props `LinkTime` (current link start) and `OnlineMs` (banked earlier
  periods); total = `AccountOnlineMs()`. **Since 0.13.0 the stats are
  game-DAY-scoped, not app-session-scoped**: the day flips at
  `Config.DayResetHour` (02:00, `GameDayStamp()` = date of now-2h);
  `PeriodicHousekeeping` resets all stats on rollover
  (`ResetSessionStats` — live links keep counting from the boundary),
  and minutes persist across restarts within a day via
  `Settings.ini [SessionTimes]` (email=ms + `__gameday` stamp; saved
  ~1/min + on close by `SaveSessionTimes`, restored by
  `LoadSessionTimes` only when the stamp matches). `ReloadFiles` must
  keep snapshotting/re-applying times across the account rebuild. **Invariant: `DetachClient()`
  is the ONLY correct way to clear `ClientHwnd`/`ClientSession`** — it
  banks elapsed time first; deleting the props directly silently drops
  earned minutes. `PeriodicHousekeeping` (5s SetTimer) detaches
  dead-window links (the "stale Client number" fix) and ticks the
  Session view via `UpdateAllRowsInPlace()` + `RefreshSummary()` —
  NEVER `RefreshDetails()` from the timer: it rewrites the edit boxes
  and would steal the caret mid-typing. **Two hard-won rules inside the
  housekeeping check (0.12.0, after a real all-links-lost incident): it
  must run with `DetectHiddenWindows(true)` (BlueStacks windows go
  briefly hidden without closing — default detection calls that
  "gone"), and it must keep the two-strike `MissingTicks` debounce (a
  window missing once is a flicker; twice is closed). Relatedly,
  `MaybeAdvanceToNextClient` must never jump to a window that
  `FindAccountNameForWindow` says is occupied, independent of the
  used-set.** Session row colors: amber = linked/counting, green = done,
  red = partial time but no client (`OnListCustomDraw`). Done rows (≥
  `Config.SessionGoalMinutes`) get green text via NM_CUSTOMDRAW
  (`OnListCustomDraw`, x64 NMLVCUSTOMDRAW offsets: stage@24, item@56,
  clrText@80 — COLORREF is BGR; `Colors.DoneRowBGR` per theme). Note:
  the SELECTED row shows the system highlight instead of the green —
  that's native ListView behavior, not a bug. In session view the
  progress bar shows done/total and the bold status slot the batch
  summary (`RefreshSummary` — **global across all files, deduplicated
  by email since 0.14.0**), and `CloneAccount` must keep carrying
  `LinkTime`/`OnlineMs` or editing an account resets its clock. UI text
  policy since 0.14.0: status lines are terse fragments ("Clients: 20
  open · 2 fresh") with explanations in hover tooltips — don't
  reintroduce explainer sentences into on-screen labels. There is no
  Subtitle and no NoteLabel control anymore; the quick-edit boxes are
  labeled by EM_SETCUEBANNER hints only.
- **Pick queue (0.15.0, F8)**: session-only `App.LoginQueue` of account
  object references in click order. **Paste actions resolve their target
  via `GetPasteTarget()` (queue head, else current selection) — never
  `GetCurrentAccount()` directly**, and row updates after stamp/link go
  through `UpdateRowForAccount(acc)` because the target may not be the
  selected row (or even the current file). `OnListClick` (the "Click"
  event, re-added — fires on every click unlike ItemSelect) toggles
  membership only while `App.PickMode`. Queue members show "»n" in the
  # cell (BuildRowCells) and accent-blue rows via the shared custom-draw
  (non-session views only; session colors win there). `AdvanceLoginQueue`
  pops + `FocusAccountInUI` (cross-file, via PendingRestoreAccountEmail
  + SwitchFile). `ReloadFiles` re-points the queue at rebuilt objects by
  email. `StampLastLogin` schedules the autosave for
  `FindFileOfAccount(acc)`, not the current file.
- **Online view (0.15.0, F9 / 👁)**: owned dialog listing all linked
  accounts across files, sorted by ClientSession; refreshed by the
  housekeeping tick (`RefreshOnlineView` — tolerant of the window being
  closed); double-click jumps via `ActivateAnyDesktop`.
- **Macro queue (0.10.0)**: session-only `App.Queue` of
  `{Macro, Hwnd, Label, Status}` jobs, processed by `QueueWorker` (runs
  in a one-shot SetTimer thread so button handlers return; guarded by
  `App.QueueRunning`). `RunMacroOnWindow` returns
  `"done"/"aborted"/"failed"/"busy"` — *aborted* (Esc/F7, window still
  exists) pauses the queue, *failed* (window gone) marks the job ✖ and
  continues. `RefreshLinkStatus` is queue-aware: while running/paused it
  shows progress instead of client counts. UI lives in the Macro
  Manager's Queue section (`UpdateQueueUI` re-renders `dlg.QueueList`,
  tolerant of the manager being closed). Enqueue helpers:
  all-clients (screen order) / linked-accounts-in-current-file (list
  order) / selected / per-row context menu.
- **Auto-login system (🚀 Mass Login) — CURRENT (0.23.0).** The single
  biggest subsystem; the earlier "Launch + Login" popup/menu is retired.
  Entry point is `OpenLoginConsole` (the 🚀 button). Attended feature:
  pixel reads need the target window on the current desktop.
  - **Console** = a Gui in `App.LoginConsoleDlg`. Top: color stat header
    (✔ done / ● online / ⏳ queued / ETA via `ConsoleEta`). Table
    (`dlg.ConsoleList`): # / Account / File / Macros / **Left**
    (`MinsLeft`) / Status. Then macro dropdown + ➕ Selected/All +
    ▶ Run now; Play/Activity radios + inline Launch/Cap/Goal edits
    (`ConsoleApplyNumbers` → same `TuningSchema`/persist path as ⚙);
    Start / Stop / ⋯. Bold `dlg.StatusLine` = the live loop phase.
  - **`RefreshLoginConsole`** runs on a 1500ms timer AND after edits.
    **CRITICAL: it updates cells IN PLACE when the row-set is unchanged**
    (identity compare vs `dlg.ConsoleAccts`); full rebuild only on
    composition change, reselecting by identity. Rebuild-every-tick
    resets scroll/selection and breaks right-click menus. It's paused by
    `App.ConsoleHold` while a table context menu is open, and that menu
    captures the selection at open-time and binds it into the actions.
  - **Data model**: `App.LoginQueue` (pick queue = accounts to log in,
    also driven by ⊕ Pick / PickAll / PickNotDone). `App.LoginMacros`:
    email → **array** of macro names (a playlist). `App.LoginMode`
    ("play"/"activity"). Soft stop: `App.LoginStopReq` (read by
    `AbortPressed`/`StopPressed`).
  - **Run**: `ConsoleStart` → `PrepareLoginBatch` (guards) →
    `LaunchWithMode` (clears per-run `_macroRan`/`_macroIdx`/`_loginFails`
    on batch) → `LoginWorker` (SetTimer thread; `App.LoginRunning` stands
    F1/F2/F4/pick/macros down) → `RunPlay` or `RunActivity`.
  - **`RunActivity`** is a continuous loop (NOT waves — OnlineCap is a
    concurrency limit): `ReapActive` (close at-goal → `finished`,
    requeue dead) → refill free slots (at-goal skip / adopt-online /
    launch group ≤LaunchMax; failed logins requeue, dropped after 3
    strikes via `_loginFails`) → idle macro phase → `MonitorSleep`.
  - **`LoginGroup`** launches a group in parallel then `LoginWithRetry`
    (close+relaunch ≤`LoginMaxRetries`) → **`LoginFunnel`**: all-pixel
    probes via `LoginProbe(hwnd,key)` (each of the 5 points carries a
    `.Color`, matched by `ColorsClose` within `LoginColorTol`). Stages:
    TryAgain-until-logout/email → logout-until-email (double-click safe,
    `LoginLogoutRetryMs`) → email + F4 within `LoginEmailToF4Ms` (TINY —
    game freezes if login page lingers >~2s; `TypeCredentialsInto`,
    passwords never touch a macro file) → wait Start → click-until-char →
    `LinkActiveWindowToAccount2`. Each stage sets `SetLoginStatus`.
    Points captured window-relative + scaled (`LoginPointScreen` reuses
    `MacroStepScreenPos`); profile in `[LoginProfile]` (5 points, each
    `x,y,refW,refH,color`), captured via `OpenLoginSetup` + armed-F12
    (`DoLoginCapture`, `#HotIf App.CaptureKey != ""`).
  - **Post-login macros are PLAYLISTS run in ROUNDS** (macro 1 across
    everyone, then macro 2, …): `_macroIdx` = next position;
    `FirstPendingMacro` picks the lowest-idx account so rounds emerge;
    `RunAccountMacro` advances it. Play: after all logins, unlimited.
    Activity: during the idle wait, `MacroFitsBudget` gates each run
    (est. `MacroDurationMs` + `MacroReserveMinutes` reserve ≤ time-left,
    so total macro time stays within "idle − reserve"), reaping between
    each. `RunMacrosNow` (▶ Run now) sweeps online accounts standalone.
  - `RefreshLinkStatus` yields the main-window status line to
    `App.LoginStatusText` while running. **Testing: never auto-run the
    orchestrator (it calls Run + a blocking ShowConfirm); test the pure
    helpers (`ColorsClose`, `LoginProfileReady`, `LoginPointScreen`,
    `MacroFitsBudget`, `ReapActive`, `ConsoleMacroLabel`, `MinsLeft`,
    playlist idx logic) and the incomplete-profile guard only.**
- **Money system (0.17.0)**: `ParseMoney()` (human formats → number or
  "" — "" means "text, leave it alone") / `FormatMoney()` (compact
  display) / money operator search in `ApplyFilter` (`>6.6m` etc.) /
  global Σ in `RefreshSummary`'s game branch (email-deduplicated).
  **Raw user text is never rewritten** — parsing is read-only
  understanding. Grey unparseable cells use per-SUBITEM custom draw:
  since 0.31.0 EVERY view returns CDRF_NOTIFYSUBITEMDRAW (0x20) at item
  stage and colors per cell at stage 0x30001 (iSubItem @ offset 88) —
  required by the online dot: subitem 0 goes Colors.Success for any
  linked account, overriding session/queued row colors in that cell
  only. BuildRowCells prefixes "● " to the # cell for linked accounts;
  keep the # column ≥38px or it clips. `HexToBGR()` converts Colors.* hex to
  COLORREF.
- **Day board (0.25.0)**: the cell strip above the list — one cell per
  account across all files, email-deduped, states merged with the same
  rules as the session scoreboard (`BoardBuild()`, pure + unit-tested).
  Cells are a **fixed pool of 120 hidden Text controls** created once
  in `BuildGUI` (AHK v2 cannot destroy individual controls — reposition
  with `PositionBoard`, never create controls at refresh time).
  `RefreshBoard()` is state-diffed so it's safe to call from every
  summary refresh and housekeeping tick; `RefreshBoard(true)` forces a
  full recolor (theme switches). Cell colors are `Colors.Board*` hex
  values (RGB — unlike the `*RowBGR` COLORREFs). The board lives ABOVE
  the list, so it is deliberately NOT in `CaptureLayout`'s below-list
  registry; `Gui_Size` calls `PositionBoard(innerW)` directly. Board →
  `UpdateTaskbarProgress` (ITaskbarList3 via ComCall, fully
  try-wrapped) paints done/total on the taskbar button.
- **Command palette: built in 0.25.0, REMOVED in 0.26.0 by owner's
  explicit choice — do not reintroduce.** The pieces that survived it:
  `JumpToAccount` (board cells + search-jump share it; it clears any
  active filter first, because a filtered-out target row can't be
  selected) and the Search Enter/Esc keys.
- **Visual language (0.26.0)**: the rules live in the comment block on
  `class Colors` — H1 (file label) / Body / Strong (bold = only the
  live status line) / Meta (dim + italic = ignorable). Semantic hues
  `Colors.Success/Info/Warning/Danger` are theme-tuned in `ApplyTheme`
  — **never hardcode a status color in a dialog** (the console's stats
  did exactly that and were unreadable in dark mode). Zebra striping is
  `Colors.ZebraBGR` via clrTextBk (offset 84) in `OnListCustomDraw`.
  Title-bar caption/text colors are painted in `ApplyDarkTitleBar`
  (DWMWA 35/36, Win11-only, try-wrapped) for the main window and every
  dialog via `ApplyDialogDarkMode` — which now runs in BOTH themes (it
  early-returns after the caption in light). One font family:
  `Config.FontMain`.
- **List hover cards (0.25.0)**: `TrackTips` special-cases the main
  ListView — `ListRowFromPoint()` (LVM_HITTEST) + `AccountCardText()`
  (pure, unit-tested, never includes passwords) give per-row cards, so
  the control-level `TipText` pattern below doesn't apply to the list.
- **Hover tooltips (0.8.0)**: no static hint text on screen — every
  control carries a `TipText` property shown by a WM_MOUSEMOVE handler
  (`RegisterTooltips`/`TrackTips`). Uses **ToolTip slot 2** so hover tips
  and toasts (slot 1, `ShowToast` — duration scales with message length
  since 0.43.0, 1.2–4 s) can never clear each other. The full hotkey
  reference is `HotkeyReferenceText()` — ONE source of truth feeding
  both the ❔ Hotkeys label's tooltip and its click-to-open window
  (`OpenHotkeyReference`, 0.43.0). New hotkeys must be added there (and
  to README); there's no other on-screen legend. The view switcher is a
  Button showing the TARGET view, not a
  dropdown; `SetViewMode` keeps its caption in sync.
  An automated layout audit (`layout-audit.ahk` pattern: measure every
  registered control, assert none sits above the list bottom and content
  ends just above the client bottom) catches drift when rows change.
- **Search box** (0.29.0) filters across ALL files at once, grouped
  under 📁 separator rows (accent-colored, inert to clicks/nav/pick);
  matches by name/email/note/class/level/money + money operators. The
  `RowAccount` contract above is the load-bearing piece.
- **Show Passwords** toggle (masked by default)
- **Edit Mode** gates Add/Edit/Delete of credentials; double-click behavior
  depends on this: off → jump to the linked client, or **launch + login
  the account if unlinked** (`LaunchLoginSingle`, 0.27.0 — toast-only
  failures, never opens dialogs); on → open the edit dialog
- **Window linking (0.6.0 — no arming step)**: every F2/F4 links the account
  to the game window the paste actually landed in (`LinkActiveWindowToAccount`
  — reads the active window, ignores non-`Config.GameProcess` windows,
  transfers ownership if another account had that window) and marks it used.
  If the persisted **Auto-next client** checkbox is on (F5),
  `MaybeAdvanceToNextClient` then activates the leftmost open client not in
  `UsedWindowHwnds`. Every window gets a permanent session number on first
  touch, shown in the **Client** column. "Forget Used" clears the used set.
  The old snapshot-batch system (`LinkedWindows`/`LinkedPos`/"Link Windows"
  button) is gone — don't reintroduce an arming step.
- **Manual link/unlink**: right-click any row → **🔗 Link to a window**
  submenu (0.43.0 — the window list used to sit inline and didn't scale
  past a few clients) to link it to any currently-open game window, or
  unlink it. Shows the current owner (if any) before you reassign.
  The row menu is the per-account command center now: pick/unpick this
  account, launch+login (unlinked), jump-to / close-client (linked —
  close goes through `CloseAccountClient`, which banks time via
  `DetachClient` first), and run/queue submenus that list routines AND
  macros (`AutomationNames()`, not `ScanMacros()` — macros-only was a
  0.32.0 oversight).
- **Notes column**: quick low-friction free-text field per account, persisted
  to the `.txt` file, autosaved, no confirmation (see friction philosophy above).
- **Dark/Light theme** toggle, persisted.
- **Always-on-Top** toggle, persisted (added specifically to let `ShowConfirm`
  suspend/restore a *user-chosen* preference rather than a hardcoded one).
- **Settings persistence**: theme, show-passwords, always-on-top, window size,
  last file, and per-file last-selected-account (both across restarts and
  within a session when switching files with F3) — all in `Settings.ini`.
- **Reload** button re-reads all `.txt` files from disk without restarting,
  preserving current file + position. Loading is atomic: a failed reload
  keeps the previous in-memory file list. Files with zero parseable
  accounts still get listed (so an emptied file doesn't vanish).
- **List selection** is synced via the ListView's `ItemSelect` event, so
  mouse and keyboard navigation both keep `App.CurrentDisplayPos` (what
  F1/F2/F4 paste) in lockstep with the visible highlight.

## Known backlog (discussed, not yet built)

These were proposed during development; the person chose to build only a
subset. Legitimate candidates for future work, not accidental gaps:

- Pause/resume hotkey to temporarily disable F1/F2/F4
- Session "done" markers on accounts (visual progress tracking)
- Minimize to system tray instead of closing
- Sound cue when reaching the last account in a file
- Jump-to-account via typing in Search + pressing Enter
- Extra per-account fields beyond email/password (partially superseded by Notes)

(Previously listed here and since built in 0.4.0: warning about malformed
lines — they're now preserved on save and counted in the UI.)

## Required helpers (don't re-inline these patterns)

- `AtomicWriteText(path, content)` — every file write.
- `RowAccount(pos)` / `RowNum(pos)` / `FirstAccountRow(from)` —
  **every read of a visible list row (0.29.0).** `App.Displayed` holds
  integers (current-file indices) in normal mode but OBJECTS
  `{Acc, File, Num}` plus `{Sep: fileName}` separators while a
  search is active (search spans ALL files). Never index
  `Accounts[App.Displayed[pos]]` directly — that's normal-mode-only
  and breaks silently on search rows. Separators return "" from
  RowAccount; navigation must skip them; note/game-field autosaves must
  target `FindFileOfAccount(acc)`, never the current file. The
  credential-editor pipeline stays current-file+index based — reaching
  it from a search row goes through `JumpToAccount` first (clears the
  filter, switches file).
- `AccountIsOnline(acc)` — every "linked and window alive" check
  (0.28.0; nine sites used to inline the HasOwnProp+WinExistAnyDesktop
  pair). `BoardBuild()` is the single aggregation feeding scoreboard,
  progress bar, day board AND taskbar — never re-derive day totals.
- `WinExistAnyDesktop(hwnd)` / `ActivateAnyDesktop(hwnd)` — every client
  hwnd liveness check / activation (cloak-aware; see gotcha #15).
- `ApplyDialogDarkMode(dlg, editCtrls, listViews)` — every owned dialog,
  before `Show()`.
- `ShowConfirm()` / `ShowInput()` — every blocking dialog (gotcha #5).
- `RecordBelowList()` — every control below the ListView (layout system).

## Testing checklist for any change

1. Does it compile conceptually — any AHK v2 gotcha above reintroduced?
2. If it touches the GUI: is every new control registered in `CaptureLayout()`?
3. If it shows a blocking dialog: does it go through `ShowConfirm()`?
4. If it touches account identity: does it match by Email, not Name?
5. If it writes credentials: does it go through `WriteAccountsFile()` with a
   backup (default), or explicitly opt out with `takeBackup := false` for a
   deliberate, documented reason (like Notes)?
6. Ask the person to actually run it on Windows before considering it done.
