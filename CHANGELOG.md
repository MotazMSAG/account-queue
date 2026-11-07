# Changelog

## 0.43.0 — UX pass: a pause key and a grown-up right-click menu

- **F10 pauses the paste keys.** F1/F2/F4 are global — during normal
  desktop work, a stray press pasted credentials into whatever had
  focus (a browser, a chat box). F10 toggles them off and on; the title
  bar shows "⏸ paused", the tray menu has a checkable entry, and a
  blocked press *says* it's paused instead of doing nothing.
  Deliberately session-only: every start is live — pausing is a
  moment's choice, not a setting to forget about.
- **The row right-click menu now covers the whole account lifecycle,
  and scales.** New: ⊕ pick / ✖ unpick THIS account (no pick mode
  needed — the queue drives F1/F2/F4 as soon as it has entries) ·
  🚀 launch + log in an offline account (the double-click gesture, made
  discoverable) · 🗔 jump to its client · 🚪 close its client with the
  time banked. Manual linking moved into a **🔗 Link to a window**
  submenu — 20 open clients used to dump 20 window entries into the
  middle of the menu.
- **Fixed: routines were missing from the row menu.** "Run/queue on its
  client" listed only macros, contradicting 0.32.0's "routines run
  anywhere macros run". Both submenus now list both kinds.
- **Click ❔ Hotkeys for a reference window that stays open** (and can
  be copied from). The full list previously lived only in a tooltip
  that hid itself after 6 seconds — 30 lines of documentation on a
  timer. Hovering still works.
- **Toasts stay up long enough to read**: duration now scales with
  message length (1.2–4 s) instead of a flat 1.2 s that cut the
  instructional ones ("Pick mode — click accounts…") off mid-read.
- **A paste key pressed while Mass Login runs now explains** that it's
  standing down (F7 stops the run) instead of silently ignoring you.
- **The quota banner's quiet day is useful now**: "No activity quota
  today · next: Sunday · 30 accounts" instead of restating the fixed
  schedule (which stays in the hover tooltip).
- Removed dead code: the pre-console 🚀 Launch + Login popup menu
  (`StartLaunchAndLogin`), unreachable from the UI since 0.23.0. Its
  guard test now exercises `PrepareLoginBatch` directly.

## 0.42.0 — Fixed: idle jobs could never fire (and now they say why)

**The bug.** Idle jobs required `A_TimeIdlePhysical >= 2 h` — two hours
of *completely unbroken* silence. Measured on this machine: the mouse
emits stray events while nobody is touching it. Over a 20-second sample
the keyboard sat idle the whole time while the mouse reset the idle
timer on nearly every 1-second sample. A single twitch resets the
counter to zero, so the threshold was effectively unreachable and the
fishing chore never ran — after 8+ hours of uptime, nothing had ever
fired.

**The fix.** "Away" is now judged by sampling the **pointer position**
once per housekeeping tick instead of trusting the event stream. Drift
under ~12 px (⚙ → "Away mouse slack") isn't a person, so jitter no
longer resets anything; a real move or a keypress does. The counter is
frozen while the app's own automation runs (it moves the mouse itself,
and a position check can't tell that from a person) — so after one job
finishes, the next in the priority list can still start.

**And it explains itself now.** The Idle Actions window has a live
status line with the actual reason, e.g.:

- `Waiting — away 34 of 120 min  ·  next up: Fishing`
- `Nothing pending — every enabled job is done for today`
- `Login Setup is incomplete — ⚙ → Login Setup`
- `Auto-run is OFF — tray → "Run idle actions when idle"`
- `✓ Ready — starting the next job now…`

Cancelling the countdown also resets the away clock, so it can't
immediately pop straight back up.

## 0.41.0 — Idle: grace countdown + history

- **A cancel countdown before any idle job auto-starts.** When the PC's
  been idle and a job is about to fire, a small window counts down
  (5 s, tunable in ⚙ → "Idle cancel countdown", 0 disables) with
  **Run now** and **Cancel**. Touching the mouse/keyboard cancels it
  automatically — so a false idle trigger (you were there, just not
  typing) never launches anything behind your back. Manual "Run now"
  skips the countdown.
- **Idle History** (🕒 Idle → 📜 History, or tray → Idle History…):
  every idle run recorded — per account, **green ✔ for success, red ✖
  for failure** ("logged in, macro ran, client closed" vs "login
  failed" / "macro aborted"), plus start/finish summaries and cancels.
  Newest first, with Clear and Open-log-file. It's also written to
  `Logins\idle-history.txt` so it survives restarts and you can read it
  after an overnight run.

## 0.40.0 — Idle Actions system

The idle auto-run grew up into a proper system. Open **🕒 Idle** (main
window) or the tray's **Idle Actions…**:

- **A prioritized list of idle jobs.** When the PC has been idle long
  enough, the app works through them **top to bottom** — the highest job
  with work to do runs; when it's finished for the day, the next one
  goes. Reorder with ▲▼; enable/disable each with its checkbox.
- **Two kinds of job:**
  - **Activity** — the built-in daily quota (keep the day's accounts
    online for the goal, then close). Always present, on by default,
    can't be deleted (disable it with its checkbox).
  - **Chore** — pick a macro/routine and a set of accounts (all / one
    file / your current ⊕ Pick selection). For each account it **logs
    in, runs the macro once, then closes the client** and moves on.
- **No account repeats a job the same day.** Each (job, account) is
  tracked per game-day, so a chore never runs its macro twice on the
  same client — and an interrupted run resumes where it left off
  instead of redoing accounts. Resets at 02:00 with everything else.
- **▶ Run now** (manager or tray) runs the top pending job immediately,
  ignoring the idle timer. The master "run when idle" switch and the
  2-hour delay (⚙ Preferences) still gate the automatic firing, and all
  the 0.39.x guards apply — not while locked, not during another run,
  only with Login Setup ready, logged to `quota-log.txt`.

Fixed along the way: app files that live in the Logins folder
(`IdleJobs.txt`, `quota-log.txt`) are no longer mistakenly loaded as
account files.

## 0.39.1 — Quota/tray edge cases ironed out

- **Won't auto-launch into a locked screen.** Auto-run now checks
  whether the workstation is locked (the login funnel can't read pixels
  on the secure desktop) and holds off. Unlocking counts as input, so it
  waits for you to be idle again afterward.
- **The X button minimizes to tray** (when minimize-to-tray is on), so a
  stray click can't kill your 24/7 automation — a one-time notification
  points you to the tray's Exit. Turn minimize-to-tray off and X exits
  normally again.
- **No blocking startup popup when auto-run is on** — the red banner and
  the auto-run itself are enough; the popup only nags if you've turned
  auto-run off.
- **Honest banner wording.** It now says the quota was *started* (not
  "done") and points you to the Session view for live progress —
  starting a run isn't the same as every account finishing.
- **Click the banner again to re-run.** If the first run failed or you
  want more, clicking a started-quota banner re-queues only the accounts
  that still need it (and tells you if there are none left).
- **Auto-runs use a Windows notification** instead of an on-screen toast
  (the window's usually hidden in the tray), and an auto-run that finds
  nothing to do now says so in `quota-log.txt`.

## 0.39.0 — Run it 24/7: tray + idle auto-run

- **Minimize to the tray.** The minimize button now hides the window to
  the system tray so you can leave it running around the clock.
  Right-click the tray icon to **Show**, **Run today's quota now**,
  toggle **Auto-run quota when idle**, toggle **Minimize to tray**, or
  **Exit**. Double-click the icon to show. (Both toggles are remembered.)
- **Auto-run the quota when you're away.** If auto-run is on and you've
  had **no keyboard or mouse input for 2 hours** (tunable in ⚙ →
  "Auto-run idle"), the app fires that day's quota by itself — queues
  the right number of random accounts and starts Activity, no click
  needed. Idle is measured from *physical* input, so the app's own
  clicks during a run don't reset it, and actually using the PC does.
- Tight guards so it can't misfire: only on a quota day, **once per
  day**, only when nothing else is running, and only if Login Setup is
  ready and the launcher exists. Every unattended fire is written to
  **`Logins\quota-log.txt`** with the time and count, so you can see
  what happened while you were gone.

Note: auto-run defaults **on** — it's the whole point of this release —
but it's one click to turn off in the tray menu, and it will never do
anything on a non-quota day or a day you've already run.

## 0.38.0 — Daily activity quota

A standing weekly commitment, enforced and one-click:

- **The schedule:** Sunday 30 · Monday 10 · Tuesday 10 accounts in
  Activity mode; other days nothing. (Edit `DailyQuotaCount` to change
  it.) "Today" is the game day — it rolls at 02:00 like the rest of the
  session system.
- **Strict reminder:** on a quota day that isn't done yet, a popup at
  startup tells you what you owe, and a **red banner** sits under the
  stat strip until you've run it. When done it turns green; on non-quota
  days it's a quiet grey note.
- **One click:** the banner *is* the button. Click it → it picks that
  many accounts **at random** (deduped across all files, skipping any
  already done or online so no slot is wasted), shows a one-line confirm
  with the count, and **starts Activity** for them. If fewer than the
  quota are eligible, it queues what's left and says so.
- **Session goal is now 45 minutes** by default (was 30) — Activity
  keeps each account online for 45, and that's the "done" threshold on
  the day board and scoreboard too. Change it any time in ⚙ Preferences.
- Fulfilment is remembered per game-day (`Settings.ini [Quota]`), so the
  nag stops once you've started today's run and survives a restart.

## 0.37.0 — Audit pass: nested runs no longer disturb the pointer

**The bug (real, and it hit the common case):** a routine that uses a
`▶ Run` step to play a macro or another routine restored the mouse
pointer **after every one of those sub-calls** — a 250 ms pause plus a
jump back to a mid-routine position. Two consequences:

- It made routines that call macros noticeably slower (a quarter-second
  added per sub-call).
- It re-fired the exact bug from 0.35.2: the sub-macro's *last click*
  landed wherever the pointer was then dragged to, instead of where you
  aimed it.

**The fix:** only the **outermost** run parks the pointer, once, at the
very end. Nested runs leave it where they are. A new regression test
(with real windows) confirms a nested run leaves the pointer on its last
click while the outer run returns it home.

Also from the audit (verified, no change needed): the `ok`/`not ok` flag
is only ever set by `wait for a pixel` and `try until` — an ordinary
`if pixel` check can't corrupt it; the loop/branch engine handles nested
loops, `break`, `continue` and `goto` correctly; and `Sleep(-1)` (used
so dry runs don't crawl) is a valid instant yield in AHK v2.

## 0.36.1 — Dry runs can't crawl on "keep going while…" loops

A dry run performs no clicks, so a loop shaped *"while the icon is
there, click it"* never sees the screen change and runs until the step
limit. It now does that in a second instead of grinding (waits yield
instead of sleeping), and the trace explains what happened rather than
just reporting a step-limit failure:

> (dry run changes nothing on screen, so 'keep going while X is there'
> loops never finish here — test those with ▶ Test on client)

## 0.36.0 — "Wait for a pixel" now says what a timeout means

Previously a pixel wait that timed out just **carried on to the next
step**, silently, and you were expected to catch it yourself with
`if the last pixel wait timed out`. Forget that check and the routine
ploughs into a screen that never loaded — a footgun.

The step now carries its own answer to "what if it never appears?":

- **stop and report failure** — the new default. A screen that never
  showed up is nearly always a real problem, and this way the run stops
  and the trace says exactly which wait gave up.
- **stop the routine (done)** — end quietly, e.g. "nothing left to
  collect".
- **carry on** — the old behaviour, for when you *want* to branch
  yourself with `if the last pixel wait timed out` / `…succeeded`.

The step list spells it out (`…up to 8000 ms, else FAIL`) and the trace
says which path it took (`TIMED OUT after 8000 ms → not ok → stopping,
reported as FAILED`). **Routines you already saved keep carrying on** —
they have no stored choice, so nothing changes underneath them; open the
step and pick a behaviour when you want the stricter one.

## 0.35.2 — Fixed: the LAST click landing on the button that started it

**The symptom:** the final click of a routine landed wherever the
"Test on client" button was — and *followed the window* when you moved
it. Same cause behind "sometimes at the end of a macro it clicks
somewhere weird".

**Why:** every playback path ended by putting the mouse pointer back
where you left it — which is on the button you just pressed. That
`MouseMove` fired the instant the run finished, while the game was
still processing the final click. BlueStacks-style clients read a tap
from the pointer's position at the moment they handle the event, so the
click registered at the pointer's destination: the button.

**The fix:** the pointer now waits (default **250 ms**, tunable in
⚙ Preferences as "Pointer return delay") before going back, so the game
has finished with the click first. Applies to routines, macros and the
Test-on-client path alike. Set it to **0** to leave the pointer exactly
where the run ended and never move it back.

## 0.35.1 — The test suite no longer disturbs the desktop

Running the suite could yank a real game client to the front. Two
causes, both in the tests:

- One test set `Config.GameProcess` to the **real** `ToW.exe` and then
  called `MaybeAdvanceToNextClient()`, whose whole job is to *activate*
  a game client. Its comment assumed "no ToW.exe windows exist here" —
  false on a machine where the game is running. Tests now use a
  process name that cannot match anything real.
- Every test showed the app window Always-on-Top **and took focus**, so
  when the test process exited Windows promoted whatever was
  underneath — usually a game client. Tests now start the window with
  `NoActivate` (via an `AQ_TEST_QUIET` flag), keep it off the top of
  the z-order, and hand the foreground back to the window you were
  actually using when they finish.

Verified with a desktop simulation (background "clients" + a separate
working window): zero client activations across the full suite, focus
returned to the working window each time.

Not caused by the tests: BlueStacks raises itself to the foreground on
its own — measured with the suite not running at all.

## 0.35.0 — Fixed: playback clicked the app's own windows

**The bug:** clicks from a routine (and from macros) could land on
*Account Queue itself* instead of the game — most visibly on the
"Test on client" button that had just started the run, or on whatever
part of the game sat under the app's windows.

**The cause:** the main window is Always-on-Top by preference, and every
owned dialog — Macro Manager, Routine Maker — floats with it. Playback
sends clicks at *screen* coordinates, so any of our windows covering
that spot swallowed the click. Measured: with the app window over the
target, the game client received **zero** of the clicks aimed at it.
(Recording already hid the manager for exactly this reason; playback
never did.)

**The fix:** every playback path now drops the topmost flag for the
duration of the run and restores it afterwards, so the activated game
client sits above the app. Verified with a reproduction harness: 0
clicks delivered before, 1 of 1 after.

Also fixed and improved:

- The live step cursor no longer takes **focus** — highlighting a step
  mid-run could pull focus off the game client between clicks.
- The trace now opens with the geometry every click is computed from:
  `client window at 300,200 size 416x339 · points captured at
  1280x720 → SCALED`. If a routine's points were captured at a
  different window size than it's running against, that line says so —
  the first thing to check when clicks land near-but-not-quite right.

## 0.34.0 — See what a routine actually did

Testing a routine used to be guesswork: it either worked or it didn't,
and nothing said which branch it took or where it died. Three answers:

- **🔍 Dry run** — walks the whole program **without touching the
  game**: no clicks, no keys, no macros, no waiting. But the pixel
  checks are read *for real*, so every `if` and `try` resolves exactly
  as it would live. In about a second you see the path your routine
  takes. This is the one to reach for while building.
- **📋 Trace viewer** — opens automatically after any test or dry run
  and lists **every step that executed, in order, with the decision it
  made**: "If pixel 640,360 = 0xC81E1E ±24 → TRUE — taking this
  branch", "end try → GAVE UP after all attempts → not ok",
  "Set tries = 0 → tries = 0". The text is selectable and there's a
  📋 Copy button. **📋 Last trace** reopens it any time.
- **A live cursor**: during a real ▶ Test on client, the step list
  highlights each instruction as it runs, so you watch execution walk
  the program.
- **Failures in unattended runs leave a post-mortem**: the last ~60
  steps are written into `Logins\Routines\routine-log.txt` whenever a
  routine fails during a Mass Login / playlist run — including which
  branch it took before it broke.

**Quick-insert buttons** for the steps you place constantly, with their
parameter right there instead of behind a menu and a dialog:

- **⏲ Wait [5] s** — type the seconds, click, done. No dialog.
- **▶ Run [macro ▾]** — pick from the dropdown, click, done. No dialog.
- **🖱 Click**, **❔ If pixel**, **🔂 Try until**, **🔁 Loop** — one
  click each. The full instruction set moved to **➕ All steps…**.

## 0.33.0 — Routines can give up, retry, and rescue a client

- **🔂 Try up to N times, until <condition>** — the retry block. The
  body runs, the condition is tested **after** each pass, and it stops
  early the moment the condition comes true. Afterwards `ok` / `not ok`
  says whether it worked, so "try three times, and if it's still not
  right, do X" is two blocks instead of a hand-rolled counter.
- **🚪 Close this client** — give up on this account. Goes through
  `DetachClient`, so the minutes it earned today are **banked**, never
  lost.
- **♻ Restart client + log back in** — closes the client, relaunches
  it, runs the full login funnel, re-links the account, and **carries
  on in the new window**. The routine keeps running where it left off.
- **⏲ Wait N seconds** alongside the millisecond wait.
- **📝 Write a log line** — timestamped, with the account name, to
  `Logins\Routines\routine-log.txt`, and shown live on the status line.
  Unattended runs now leave a trail you can read afterwards.
- **Two session-aware conditions**, because routines run during
  Activity's idle time: **this account has reached today's goal** (or
  hasn't), and **minutes left to the goal** compared to a number — so a
  20-minute farm can decline to start with 5 minutes left.

Fixed in the test harness: a test file that crashed before asserting
anything was reported as "all passed". Zero checks is now a failure.

## 0.32.0 — Routines: your macros became a programming language

Recorded macros were straight lines: click, click, click. A **routine**
is a program built out of them — with loops, pixel tests, branching,
waits, counters and jumps. Build one in **🎬 Macros → 🧩 Routine
Maker**, or hand-edit the text file like everything else here.

- **Routines run anywhere macros run.** They share one name space, so a
  routine can be assigned as a post-login playlist entry, queued in the
  macro queue, run from a row's right-click menu, or called *from
  another routine* (up to 5 deep). One dispatcher decides which is
  which — nothing else in the app had to learn the difference.
- **The instruction set:**
  - *Macros* — `▶ Run 'name' × N` (a macro or another routine)
  - *Input* — click at a point (left/right/middle), send keys, refocus
    the client
  - *Waiting* — wait N ms, wait a random range, **wait for a pixel**
    (with timeout)
  - *Flow* — `loop N times` (0 = forever), `while <condition>`,
    `if / otherwise / end`, `break`, `next pass`, `stop`, `report
    failure`, `label` + `go to`
  - *Counters* — `set` / `add`, and compare them in conditions
  - *Conditions* — pixel matches / doesn't match a captured colour
    (with tolerance), the last pixel-wait succeeded or timed out, the
    client is open or closed, a counter comparison, or a random %
- **Points and colours are captured, not typed**: click ◉ Capture,
  hover the spot in the game, press F12 — the same proven picker Login
  Setup uses. Coordinates are window-relative and **scale to any client
  size**, exactly like macro clicks.
- **Safe by construction**: block instructions are inserted as balanced
  pairs (and deleted as pairs), the editor re-parses after every change,
  and saving refuses a program that wouldn't run. Two runaway guards —
  a total step budget and a nesting-depth limit — mean a mistaken
  `loop forever` stops instead of hanging. Esc/F7 abort mid-routine and
  a closed client ends it, same contract as macros.
- **▶ Test on client** runs the steps you're looking at — unsaved —
  against the selected account's client.
- The Macro Manager now lists routines and macros together (with a Kind
  column and an estimated runtime), and Rename / Delete / Open-in-editor
  work on both.

Note: `send keys` exists for game keys. Recording keystrokes is still
deliberately impossible — never put a password in a routine; F1/F2/F4
handle credentials without ever writing them to a file.

## 0.31.0 — The green dot

- **Every online account carries a green ● in its # cell** — in all
  three views, in cross-file search results, next to pick markers
  ("● »2"), everywhere the list renders. Green = linked to a client
  right now (the same signal that makes session rows amber; dead links
  are pruned by housekeeping within ~10s). One glance at any view now
  answers "which of these are up?".
- Under the hood: the list draws **per-cell in every view** now (only
  Game view did before), which is what lets the dot stay green on top
  of amber/red/queued row colors and zebra shading. The # column
  widened to fit the dot; Note gave up the pixels so no view scrolls
  horizontally.

## 0.30.0 — Headline numbers act like headlines

- **Money shows its real value**: three decimals of the unit, trailing
  zeros trimmed — 1,036,000,000 is **"1.036B"**, not "1B" (36M is real
  money). Clean values stay clean ("6.6M"). Applies to the Money
  column, the Σ totals, and money-search standardization alike.
- **A permanent stat strip** replaces the small status line under the
  progress bar — the day's headline numbers, big/bold/color-coded in
  EVERY view (same color language as the console): **✔ done** (green),
  **▶ online** (amber), **N to go**, **Σ total money** (accent).
  Hover any segment for its meaning. Selection info ("1 / 6 · Name"),
  the session Σ-hours, shown-Σ while filtering, and the unreadable-line
  count all live in the dim right-hand label now.

## 0.29.0 — Search everywhere + back-to-back double-click logins

- **Search now searches EVERY file, not just the current one.** A note
  you remember writing shouldn't hide because you're looking at the
  wrong file. Results are grouped under **📁 file separators** (accent
  colored, unselectable); the # column shows each match's number
  *within its own file*; money-operator queries (">6.6m") go global
  too. Arrow keys and F2's auto-advance skip the separators; the count
  reads "N accounts (M shown)" across all files.
- Everything works on cross-file results exactly as it should: notes
  and game-field edits **save to the account's own file** (this was
  the one dangerous path — it used to write the current file), pick
  mode queues across files, hover cards and colors are per-row, and
  opening the credential editor on a result from another file first
  jumps there (clearing the search) so the edit pipeline stays on its
  home file.
- **Double-click logins now chain.** Double-clicking an unlinked
  account while a launch+login run is already going queues it in a
  hidden mini queue — it starts automatically the moment the current
  run finishes, skipping anything that came online in the meantime.
  The status line shows "⌛ N next" while something is waiting;
  stopping a run (F7/Stop) also clears the waiting list; Reload
  re-points it safely.

## 0.28.0 — Streamline + a dozen small sharpenings

One consolidation pass and a batch of small features aimed at "convey
more, faster, with fewer clicks".

**Faster to read:**
- **The progress bar now always means THE DAY** (done/total accounts —
  same metric as the board and the taskbar). It used to show your
  position in the list outside Session view, which duplicated the
  "1 / 6" text and measured nothing.
- **Session scoreboard gained Σ total online time**: "✔ 9 done · ▶ 5
  online · 7 to go · Σ 3.4h".
- **Day-complete fanfare**: the moment the last account reaches the
  goal, a two-note chime + "🎉 All N accounts done for today" toast —
  once per game day (and not on startup into an already-done day).
- **Failed logins are no longer silent**: accounts dropped after 3
  failed attempts (or left behind by a Play run) are now counted in
  the console — "Idle — ✖ 2 failed last run" — and **➕ → Re-add
  failed** puts them back in the queue in one click.

**Faster to act:**
- **Board cells are pickers in pick mode** — click cells to queue
  accounts, same toggle as clicking rows. Outside pick mode they jump,
  as before.
- **Double-click a Mass Login console row** → shows that account in
  the main window.
- **Right-click a row → 📋 Copy email / Copy password** (explicit
  copies stay on the clipboard — no auto-restore).
- **Ctrl+F focuses the Search box.**
- **Window position is remembered** (not just size) — validated
  against live monitors, so an unplugged screen can't strand the
  window off-screen.

**Backend streamline (no behavior change):**
- The session scoreboard, progress bar, day board, and taskbar all
  read from ONE aggregation (`BoardBuild`) — the scoreboard had its
  own duplicate merge loop; summary refreshes also stop double-building
  the board.
- `AccountIsOnline()` replaces nine inlined copies of the
  linked-and-window-alive check.
- Pick-queue toggling is one shared function (`TogglePickMembership`)
  for list rows and board cells.

## 0.27.0 — Double-click does the right thing

- **Double-click an unlinked row → launch + login that one account**
  (Play mode). Double-click already jumped to the client when linked;
  now the same gesture gets an offline account online. Guards: needs a
  complete Login Setup profile and no automation already running —
  failures just toast (an accidental double-click never pops a dialog).
  A linked-but-flickering client still counts as linked (only
  housekeeping's two-strike check may decide a window is really gone),
  so this can't spawn duplicate clients during a desktop-switch blip.
- Edit Mode double-click (open the edit dialog) is unchanged.

## 0.26.0 — Visual identity: one type system, one color language

- **Command palette removed** (0.25.0 feature, by owner's choice — the
  day board, hover cards, and search keep their jump features).
- **A written visual language** (top of the `Colors` class) the whole
  app now follows:
  - **H1** — one per window: the file label, bold accent.
  - **Body** — everything interactive: 9pt regular.
  - **Strong (bold) is reserved for "what's happening right now"** —
    the status/scoreboard line, the console phase line. Nothing else.
  - **Meta is dim + italic** — counts, hints, the version, "no clients
    open": readable when you look for it, invisible when you don't.
  - **Color always means state, never decoration**: green done, amber
    counting, red lost, accent selected/queued.
- **Semantic status palette** (`Success/Info/Warning/Danger`) tuned per
  theme — the console's done/online stats were hardcoded light-theme
  colors that turned muddy in dark mode; now they adapt. Login Setup's
  "✔ captured" and "Profile complete" turn green.
- **Zebra striping** in the account list (all three views, both themes)
  — a faint alternate-row shade that makes wide rows trackable; session
  colors and the selection highlight still win.
- **The title bar is part of the app now**: caption painted in the
  app's own background/text colors (Win11), main window and every
  dialog, both themes — no more OS-colored strip on top.
- **One font family constant** (`Config.FontMain`, Segoe UI Variable
  Text — Win11's own UI face) used by every window and dialog.

## 0.25.0 — The day at a glance, everything within reach

Four new ways to see and drive the day's grind — no behavior changes to
logins, macros, or data.

- **Day board.** A strip of colored cells above the list — one cell per
  account across **all** files (duplicates count once): grey = not
  started, amber = online and counting, green = goal reached, red =
  lost its client early. Hover a cell for the account's status, click
  it to jump straight to that account (switching files if needed). Live
  — updates with the same 5s tick as the session clocks.
- **Command palette (Ctrl+K).** One box that reaches everything: type
  a few letters of any account in any file and Enter jumps there;
  or find files (switch), macros (run on the selected account's
  client), and every command the buttons offer — Mass Login, views,
  pick mode, reload, dark mode… ↑/↓ move the highlight while you type,
  Esc closes. Empty query lists the commands, so it's also the menu.
- **Hover cards on the list.** Hover any row for the full account card
  — class/level/money, note, client, today's online minutes, last
  login — no matter which view you're in. No more view-hopping to
  check one field. Passwords never appear in cards.
- **Taskbar day progress.** The taskbar button itself fills as accounts
  reach the goal (done / total across all files) — glanceable from
  inside the game, no window switching.
- **Search learned Enter and Esc**: Enter jumps to the first match and
  clears the filter (the long-standing backlog item), Esc just clears.

## 0.24.0 — Layout & consistency pass (every surface)

UX-only release: no behavior changes, every remaining on-screen
explanation moved into hover tooltips, uniform control language across
the main window and all dialogs.

- **Main window header decluttered**: the in-window "Account Queue"
  title and the "Search" label are gone (the title bar already carries
  name + version; the search box now has a 🔍 cue banner) — the account
  list gained **~60px / 3 more visible rows** at the same window size.
  The version now sits quietly at the end of the bottom row.
- **Login-flow zone reorganized**: one uniform button row in
  priority order (🚀 Mass Login · ⊕ Pick · 🎬 Macros · ↺ Forget Used),
  with the Auto-next toggle and the live client status sharing the line
  below (status right-aligned).
- **Mass Login console**: the grey "right-click a row…" hint is now the
  table's tooltip; Play/Activity radios are terse (▶ Play / ⏱ Activity)
  with the full explanations as tooltips; Launch group / Online cap /
  Goal carry tooltips; Clear got its standard 🗑 glyph; the three number
  boxes now theme correctly in dark mode.
- **Preferences reflowed into two grouped columns** — General ·
  Mass Login · Activity — instead of a 23-row wall. Fixed the
  "Launch && Login max" label (Win32 ate the ampersand as a mnemonic —
  now "Launch group size") and the clipped last row.
- **Macro Manager**: both explainer paragraphs moved into tooltips
  (list, Record New, Run, Open in Editor, Queue header); dialog is
  correspondingly shorter.
- **Login Setup**: one row per capture point (button · label · state)
  instead of two; probe explanations are tooltips on the labels.
- Consistency sweep: ➕ Add Account matches the other add buttons;
  file-nav arrows sized to the standard button height.

## 0.23.0 — Console tells you what's actually happening

- **Overview stat row** at the top, color-coded and grouped: ✔ done
  (green) · ● online (blue) · ⏳ queued · **ETA** (estimated finish).
- **Left column** in the table — per-account minutes remaining to the
  goal (or "done" / "→ next" / "—").
- **The phase line now says what the loop is literally doing**:
  "Launching client 2/4 for Mommo…", "waiting for 2 clients to load
  (16s)…", "Mommo: clicking Logout → login page…", "entering credentials
  (F4)…", "Start Game → selecting character…", "Running macro 'Dailies'
  on Luo (1/2)…", "2 online, waiting — next free slot in 6m (3 queued)".
- Cut the grey helper paragraphs — the long explanations live in
  tooltips now, freeing the space for the stats and Left column.

## 0.22.1 — Console stops fighting your mouse

- Fixed: the console's live refresh rebuilt the whole table every 1.5s,
  which reset the scroll to the top, dropped selections, and disrupted
  open right-click menus. Now, when the row set hasn't changed, cells
  update **in place** — selection, scroll and menus survive; a full
  rebuild happens only when accounts actually enter/leave the list, and
  it restores your selection.
- The right-click menu also captures the rows you clicked on at
  menu-open time and pauses the refresh while open — its actions always
  hit exactly the accounts you selected, even if the list shifts.

## 0.22.0 — Macro playlists + decluttered console

- **Multiple macros per account (playlists).** Each ➕ adds another macro
  to the target's list; "(none)" clears it. They run in **rounds** —
  macro 1 across every account, then macro 2, and so on — in Play's
  post-login sweep, Activity's idle phase, and ▶ Run now alike.
- **Activity budgets macro time automatically**: a macro only runs if
  its estimated duration fits the account's remaining time **minus a
  reserve** (default 15 min, ⚙-tunable) — 45 min of idle allows ~30 min
  of macros. When time doesn't allow the rest you get one plain toast;
  no math shown. Play mode runs playlists without limits.
- **Console decluttered**: queue ops (remove / move to top / clear
  macros) moved into right-click on the table; the three add-buttons
  became one **➕ Add** menu; Close-done lives under **⋯**. Visible
  controls: Add · Clear · macro row · mode+limits · Start · Stop · ⋯.

## 0.21.0 — Console covers every scenario + flowchart gap fixes

- **Gap fixes from the flowchart audit:**
  - Activity: an account that fails all its login retries now goes to
    the **back of the queue** (like a dead client) instead of silently
    dropping out of the run; after failing twice more it's dropped with
    a toast so one broken account can't loop forever.
  - Play: the post-login macro sweep no longer skips accounts that are
    already past the session goal (the goal is irrelevant in Play mode).
- **Mass Login console — every scenario on one page:**
  - **➕ Not done** — queue every account (all files) still under the
    goal; the daily "continue where I left off" in one click.
  - **▲ Top** — move selected queued accounts to the front.
  - **▶ Run now** — run every assigned macro on its already-online
    account immediately, no launching or login run required.
  - **🧹 Close done** — close every online client whose account reached
    the goal (confirmed; time is banked) — Play mode's teardown.
  - **Inline Launch group / Online cap / Goal fields** — the three
    numbers that matter, editable right there, validated and persisted
    like ⚙ Preferences, applied on Start.

## 0.20.1 — Smarter macro timing

- Post-login macros no longer run inline (interrupting each login).
  Instead:
  - **Play mode** — all accounts log in first (uninterrupted), then a
    single macro sweep runs everyone's assigned macro.
  - **Activity mode** — a batch fills up and starts idling toward the
    goal, and the macros run *during that idle wait* (free time that was
    previously wasted). Macros run one at a time, and the client-health
    check (close-on-goal, requeue-dead) runs **between each macro**, so a
    client that dies or hits its goal mid-sweep is handled immediately
    instead of overshooting.
- A died-and-requeued account re-runs its macro after it logs back in.

## 0.20.0 — Mass Login console

- **🚀 Mass Login now opens a dedicated console window** instead of a
  popup menu. In one place you can:
  - Add accounts to the login queue (all-in-file / all-files / remove
    selected / clear) and see the whole queue as a table.
  - Choose **Play** or **Activity** mode with a radio.
  - **Assign a macro to run right after each account logs in** — per
    account (Set selected) or to everyone (Set all); pick "(none)" to
    clear. This is new: macros can now auto-run post-login.
  - **Start / Stop** — Stop is a soft button (no key press needed), and
    F7 still works.
  - Watch a **live status table**: what's ● online, which one is
    ▶ running its macro, what's → next, and what's queued — refreshed
    while the window is open.

## 0.19.4 — Bulk pick

- Right-click any row: **➕ Pick all in this file**, **➕ Pick all (every
  file)**, and **✖ Clear pick queue** — build a big login/queue selection
  in one click instead of clicking accounts one by one. Skips duplicates.

## 0.19.3 — Activity keeps the pipe full (no more waiting)

- **Fixed a big time-waster: `OnlineCap` is now a concurrency limit, not
  a batch size.** Activity used to launch a full wave of N, wait for
  ALL N to finish, then launch the next N — so the moment one client
  closed, its slot sat idle until the whole wave completed. Now Activity
  runs one continuous loop: the instant a client reaches the goal and
  closes, the next queued account is launched to refill that slot. It
  keeps exactly `OnlineCap` accounts online at all times until the queue
  drains.
- Same continuous handling for the cases we'd bolted on: accounts
  already at the goal finish without taking a slot, already-online ones
  are adopted, and clients that die early are requeued and relaunched as
  slots free — all inside the one loop, no wave boundaries.

## 0.19.2 — Activity adopts what's already running

- Activity waves now recognize accounts that are **already online**:
  their running client is adopted into the wave as-is (no duplicate
  launch, no re-login) and simply monitored until its total reaches the
  goal — an account at 30 of 36 minutes gets closed 6 minutes later.
- Accounts already **at the goal with a client still open** now get that
  client closed when the wave is built (previously they were skipped but
  left running).

## 0.19.1 — The 22-minute mystery, solved

- **Fixed: Activity mode closed a whole wave early.** The monitoring
  phase treated Esc (polled globally, physical key) as its abort signal
  — one Esc press anywhere, including inside the game, aborted the
  monitor, and the wave-end sweep then closed every client. Now:
  **during monitoring only F7 stops the run**, and **stopping never
  closes clients** — abort leaves everything exactly as it is. Esc still
  aborts the short, attended launch/login phases.
- Accounts that already banked the goal are **skipped entirely** when a
  wave is built (straight to "finished" — no pointless launch), and the
  goal is read live each check, so changing it in ⚙ mid-run applies.
  (Partial banked time already counted: a 30-min account closes 6 min
  after relogin.)

## 0.19.0 — Fully-probed login + Activity mode

- **Every login stage is now pixel-probed** (all 5 points carry a
  captured colour): unstick with Try Again until the logout button shows
  → click logout until the login page shows → email + F4 → wait for the
  Start Game button → click Start until character selection shows → click
  character. **If any stage times out, the client is closed and
  relaunched** (up to `LoginMaxRetries`), so a broken client self-heals.
  Re-capture points in Login Setup (each F12 now also samples its colour).
- **🚀 Launch + Login now asks for a mode:**
  - **Play mode** — what it did before: log everyone in and leave them
    running (groups of `LaunchMax`).
  - **Activity mode** — keeps up to `OnlineCap` accounts online for the
    session goal, then closes them and continues. 20 picked, cap 4,
    online-cap 10, goal 30m → 4,4,2 in → wait/close as each hits 30m →
    next 10 → done. Each account is closed the instant it reaches its
    goal (not batched), and any client that dies early is requeued to
    finish its time in a later wave.
- New ⚙ tunables: close+retry count, Activity online cap.

## 0.18.1 — Auto-login tuning

- **Login page is now detected by a second pixel probe (the email
  field), not a fixed wait.** The orchestrator re-clicks Logout on an
  interval until that probe confirms the login page is open — so the
  logout button needing a double/triple click just works, and an
  already-open login page is used as-is. Capture the email point in
  Login Setup to sample its colour (done automatically).
- **F4 fires immediately once the page is detected** (tiny, tunable
  `email→F4` gap, default 120ms), so the login page never lingers long
  enough to trigger the game's ~2-second freeze.
- **Batches larger than the launch cap now run in groups.** Pick 10 with
  a cap of 4 → it logs in 4, then 4, then 2, automatically. (Only the
  accounts that actually logged in are removed from the pick queue.)
- New ⚙ tunables: email→F4 gap, login-page poll interval, logout
  re-click interval.

## 0.18.0 — Auto-login (🚀 Launch + Login)

- **New: launch clients and log them in automatically.** Pick accounts
  (⊕ Pick) — or select one — then **🚀 Launch + Login**. It opens one
  client per account (parallel), waits the boot time once, then walks
  each new window through: **unstick loading → force logout to the login
  page → click email → F4 credentials → Start Game → pick character →
  link the account (session clock starts)**. Passwords never enter a
  macro file — the credential step is the same F4 combo, aimed at that
  window.
- **No blind clicks.** A captured pixel probe on the "logout→login"
  button tells the app whether a client has finished loading; while it
  hasn't, the app clicks "Try Again" and re-polls (your stuck-load fix).
  The logout button is then always clicked, so an auto-logged-in client
  still lands on the login page.
- **Login Setup** (⚙ Preferences → 🎯 Login Setup): capture the 5 click
  points + the loaded-state colour once, by hovering each spot in a real
  client and pressing F12. Stored window-relative and scaled, so it keeps
  working if the client moves or resizes.
- **Esc/F7 aborts** the whole run; a window that stays stuck past the
  timeout is skipped and the batch continues; progress shows in the
  status line ("Window 2 / 4: logging in Mommo…").
- All timings + the launcher path are tunable in ⚙ Preferences
  (launcher path defaults to `D:\Games\ToW\ToWRR\ToW.exe`; boot wait 16s;
  start→character 3s; plus poll interval, colour tolerance, and cap).

## 0.17.0 — Money that understands numbers

- **The Money field now parses human formats**: `3.3m`, `123k`, `1.2b`,
  `6,000,000`, `60000` (case-insensitive; commas/spaces ignored). What
  you type is stored verbatim — the app just understands it.
- **The column displays standardized-compact** regardless of input form:
  `6600000` and `6.6m` both render as "6.6M".
- **Money-value search operators**: `>6.6m`, `<500k`, `>=1m`, `=123k`
  filter by parsed value. Accounts with empty or unparseable money never
  match an operator query.
- **Σ total money** in the Game Info view's corner — across ALL files,
  deduplicated by email. While filtering it also shows the Σ of just the
  shown rows ("2 shown · Σ 3.3M · all Σ 142.7M") — filter `>1m` and see
  what that group is worth.
- **Unparseable money is kept as-is and greyed out** in the column
  (per-cell custom draw) — visible at a glance that it's text, not a
  number, and it's excluded from every total and operator search. Empty
  cells stay empty.

## 0.16.0 — Preferences (⚙)

- **New ⚙ Preferences dialog** (bottom row): every tunable is now
  editable in the app and persisted to `Settings.ini [Tuning]` — no more
  editing the script. Exposed: game process, **session goal minutes**
  (the green threshold), day-reset hour, F4 step delay, auto-next delay,
  clipboard-restore delay, autosave debounce, macro queue gap, and
  backups kept per file. Values are validated and clamped to sane
  ranges; hover any field for what it does; **↺ Defaults** restores the
  shipped values.
- Changes apply live — a new goal recolors the Session view instantly,
  and changing the reset hour adopts the new boundary without falsely
  triggering a "new game day" reset.
- Internals: one schema table (`TuningSchema`) drives the dialog rows,
  validation, tooltips, and persistence — a new tunable is one entry.

## 0.15.1 — Search everything

- Search now also matches **Note**, Level, and Money (previously only
  Name, Email, and Class) — so tags you type into notes ("n3 n4",
  "weekend", …) work as instant filters in every view.

## 0.15.0 — Pick queue + Online view

- **Pick queue (⊕ Pick button / F8).** Toggle pick mode, click accounts
  — in any files, switching with F3 mid-pick — in the order you want
  them logged in (click again to remove). Queued rows show their order
  in the # column ("»1 »2 …") and tint accent blue. Toggle off, or just
  start pressing F4: while the queue has entries, **F1/F2/F4 target its
  head instead of the selected row**, and every completed login pops the
  head and auto-navigates the list to the next pick — across files. The
  queue survives ⟳ Reload; re-entering pick mode starts a fresh one; the
  status line shows "⊕ N queued".
- **Online view (👁 button / F9).** One live window listing every
  currently-linked account across ALL files — name, file, client #,
  online minutes, time left — sorted by client number, refreshed every
  few seconds while open. Double-click a row to jump to its client
  (cloak-aware, works across virtual desktops).
- Internals: paste actions now resolve their target through
  `GetPasteTarget()` (queue head, else selection), and row updates after
  stamping/linking follow the actual target account (`UpdateRowForAccount`)
  rather than assuming it's the selected row.

## 0.14.1 — Hygiene pass (no behavior changes) + tests shipped

- **The test suite now lives in the repo**: `tests/` holds the four
  self-contained test scripts (91 checks: data round-trips, views,
  session timers, linking, macros, queue, layout audit, resize stress)
  plus `run-tests.ps1`, which validates the app and runs everything with
  one command. Each test builds its own sandbox `Logins` next to itself.
- Deduplicated three copy-pasted patterns into named helpers, now the
  required conventions for future code:
  - `AtomicWriteText()` — the temp-file+rename write (was duplicated in
    credentials and macro saving).
  - `WinExistAnyDesktop()` / `ActivateAnyDesktop()` — cloak-aware window
    liveness/activation (the save/restore detection dance existed in
    five places).
  - `ApplyDialogDarkMode()` — shared dark styling for owned dialogs;
    as a side effect, the Add/Edit dialog's text fields now get proper
    dark backgrounds like the main window.

## 0.14.0 — Global scoreboard + decluttered layout

- **The Session scoreboard (done / online / to go) and its progress bar
  now count across ALL files**, not just the current one — deduplicated
  by email, so an account listed in two files counts once. The selection
  label stays per-file.
- **Layout decluttered — say it once, say it short:**
  - Subtitle line removed.
  - The "Note for selected account (saves automatically):" caption row
    is gone — the note box carries a grey in-box hint ("Note —
    autosaves") instead. Both reclaimed rows went to the list (+34px).
  - Status texts are now fragments, not sentences: "3 / 4 · Mommo",
    "4 accounts · 1 unreadable", "Clients: 20 open · 2 fresh",
    "Queue 3/8 · Dailies → Mommo". The explanations moved into the
    status line's hover tooltip.

## 0.13.0 — Game-day (02:00) reset + session persistence

- **Session stats now follow the game's day, which flips at 02:00.**
  When the boundary passes while the app is running, every account's
  online minutes, done/green status and ⚠ states reset on the next tick
  (with a toast). Accounts still online at 02:00 keep their links and
  start counting the new day from the boundary. "Last login" is factual
  history and does not reset.
- **Green now truly stays green until 02:00 — even across restarts.**
  Online minutes are persisted about once a minute (and on close) to
  `Settings.ini [SessionTimes]`, stamped with the game day they belong
  to. Reopening the app the same game day restores them; reopening after
  02:00 starts clean. The ⟳ Reload button also carries the day's minutes
  across (it used to silently zero them along with rebuilding accounts).
- The boundary hour is one constant: `Config.DayResetHour` (2).

## 0.12.1 — Virtual desktop immunity

- **Root cause of the mass link-loss found and measured**: Windows
  virtual desktops don't hide or close windows — they **cloak** them
  (DWM `Cloaked=2`), and AHK's default window detection reports cloaked
  windows as nonexistent. Switching to the work desktop made one
  housekeeping tick "see" every client vanish. (0.12.0's hidden-aware
  check + two-strike rule already survive this; confirmed by a live
  experiment on the actual machine.)
- Hardened every remaining state-keeping check to be cloak-aware:
  used-window pruning, double-click jump-to-client (now switches you to
  the client's desktop instead of claiming it closed), queue-on-linked-
  accounts, and the client counter in the status line (no more "no
  clients open" while you're on the other desktop).
- Discovered along the way: hidden-aware scans of the game process see
  ~40 invisible helper windows besides the real clients — client
  scanning now goes through `GetGameClientWindows()` (hidden-aware +
  visibility filter). Auto-next and "queue on all clients" deliberately
  keep acting only on clients visible on the *current* desktop, so F4
  never yanks you across desktops.

## 0.12.0 — Session colors + link-loss hardening

- **Fixed the mass link-loss bug** (all links dropped while clients were
  still running — which then also let Auto-next jump into occupied
  clients): the housekeeping check now detects hidden-but-alive windows
  (BlueStacks windows can be briefly hidden without being closed), and a
  **two-strike rule** requires a window to be missing on two consecutive
  ticks before its link is dropped. Auto-next additionally refuses to
  jump to any window hosting a linked account, regardless of what the
  used-set says.
- **Session view color language**: amber = online and counting,
  **green** = goal reached, **red** = lost its client before the goal
  (with "⚠ N min left" in the Left column). Time already stops counting
  the moment the client is gone — the red row makes it impossible to
  miss. Theme-aware shades for light and dark.
- **The batch scoreboard is now the bold headline**: in Session view,
  "✔ 9 done · ▶ 5 online · 21 to go" takes the prominent bold status
  slot; selection info moves to the dim right label.
- **View switching is one click, always**: three square buttons
  (🔑 / 🎮 / ⏱) replace the cycle button — the active view's button is
  disabled as the indicator. F6 still cycles.

## 0.11.0 — Session view (the 30×30 dashboard) + stale-client fix

- **Fixed: a closed client left its number in the Client column.** A
  housekeeping timer (every 5s) now clears links whose window is gone —
  and **banks the online time first** (see below), so closing a finished
  client never discards what it earned.
- **New third view: ⏱ Session** (F6 now cycles Credentials → Game Info →
  Session). Columns: #, Name, Client, **Online**, **Left**, Last login
  (moved here from Game Info), Note. Built for the "log 30 accounts in
  for 30 minutes each" workflow:
  - Every account accumulates **online time across link periods**:
    linked → counts up live; client closed / unlinked / re-logged →
    time is banked and survives; nothing resets by accident.
  - **Rows turn green at 30 minutes** (real per-row text coloring via
    ListView custom-draw, theme-aware shades), with "Left" counting down
    ("18 min left" → "✔ done").
  - In this view the **progress bar becomes batch progress** (done
    accounts ÷ all accounts in the file) and the count label shows
    "✔ 9 done · ▶ 5 online · 21 to go (goal 30 min)".
- The goal is one constant: `Config.SessionGoalMinutes` (30).
- Online time is session-only — it is never written to the .txt files,
  and (like everything session-scoped) resets when the app restarts.

## 0.10.0 — Macro queue

- **Queue macros across a list of clients.** The Macro Manager gained a
  Queue section: pick a macro, then one click adds jobs for **all open
  clients** (left-to-right), for **every linked account in the current
  file** (list order — the queue reads like your roster), or for the
  **selected account**. Mix freely: right-click any linked row →
  "➕ Queue macro on its client" composes job by job, different macros
  included.
- Jobs run one at a time (playback owns the mouse) with a 1.5s breather
  between them, each row showing live status: ⏳ waiting → ▶ running →
  ✔ done / ✖ failed / ⛔ aborted.
- **A dead client doesn't kill the batch** — its job is marked ✖ failed
  and the queue moves on. **Esc/F7 aborts the current macro and pauses
  the queue** — resume or clear from the manager, nothing is lost.
- **Progress without the manager open**: while the queue works, the main
  window's status line shows "Queue: 3/8 done — running ... on ...".
- The queue is session-only (like window links) — a queue is a plan for
  now, not data worth persisting.

## 0.9.0 — Click macros

- **Record-by-doing macro recorder.** Press F7 (or 🎬 Macros → ⏺ Record
  New), click through the game once, press F7 again, name it. Only
  left-clicks that land on a game client become steps; clicks anywhere
  else are ignored. Your real pauses between clicks are recorded as the
  playback delays, so waiting out a loading screen while recording "just
  works". Keystrokes are deliberately NOT recordable — recorded keys
  would write passwords into plain-text macro files.
- **Window-relative playback with scaling.** Steps are stored relative
  to the game window plus its size at record time; playback re-anchors
  to wherever the target window is now and scales proportionally if it
  was resized — one recording works on every client.
- **Two ways to run:** right-click a linked row → "▶ Run macro on its
  client" → pick from the list; or the Macro Manager's ▶ Run (targets
  the selected account's linked client). **Esc or F7 aborts playback
  instantly**; a closed target window stops the run; the mouse returns
  to where it was.
- **Macro Manager window** (🎬 Macros): record, run, rename, delete
  (with confirmation), open the file in Notepad for hand-editing, and
  refresh. Files are plain text in `Logins/Macros/<name>.txt`
  (`ref|w|h` + `click|x|y|delayMs` lines).
- New `ShowInput()` helper — InputBox with the same Always-on-Top
  suspension as `ShowConfirm()` (rule extended: all blocking prompts go
  through these two).

## 0.8.0 — Tooltips, one-click view switch, visible version

- **Static hint text is gone from the window; hints now live in hover
  tooltips.** Every button, toggle and box shows its explanation (and
  hotkey, where it has one) after hovering ~0.4s. The full hotkey
  reference lives under the "❔ Hotkeys" label in the bottom row. The
  dynamic client-status line stays on screen — it's live information,
  not a hint. The freed rows went to the list (+26px on top of 0.7.0's
  gain). Implementation: WM_MOUSEMOVE + per-control `TipText` property,
  using ToolTip slot 2 so hover tips never fight with toast messages.
- **View switching is one click**: the dropdown is now a button that
  always shows the view you'd switch TO ("🎮 Game Info" ↔
  "🔑 Credentials"). F6 unchanged.
- **The version is visible**: "v0.8.0" next to the app title and in the
  window title bar.

## 0.7.0 — Layout reorganization

- **Everything below the list is now four clear zones, separated by
  etched divider lines:**
  1. *Selected account* — note/game-field boxes, progress bar, then
     status (left) and account count (right) sharing one line.
  2. *Login flow* — Auto-next client checkbox, Forget Used, live client
     status.
  3. *Managing accounts* — Edit Mode now sits directly beside the
     + Add Account and ⟳ Reload buttons it gates, with the read-only
     hint inline on the same row.
  4. *App preferences* — Show passwords, Dark Mode, Always on Top —
     with the hotkey legend as the final footer line.
- "File 1 of 3" merged into the filename label ("Dailies.txt · 1 / 3");
  the removed rows went to the list, which is ~100px taller at the same
  window size.
- **Dark mode now actually darkens the list and edit boxes.**
  `SetWindowTheme` only themes chrome (scrollbars/header); the client
  areas needed explicit background/text colors and stayed glaring white.
- Fixed: the "Search" label was invisible in dark mode (created without
  a stored reference, so theme changes never recolored it).
- Layout verified by an automated audit: no control overlaps the list,
  content ends 14px above the window bottom at design size, and the
  count label stays right-anchored through resizes.

## 0.6.0 — Linking without the arming step

- **Removed the "Link Windows" button and the snapshot-batch system**
  (`LinkedWindows`/`LinkedPos`, `Config.WindowBatchSize`). Previously, F4
  only linked an account to a client if you had clicked Link Windows first
  — logging in without arming left the account unlinked even though the
  paste clearly landed in a specific window.
- **Every F2/F4 now links the account to the window the paste actually
  landed in** (the active window at paste time). Non-game windows are
  ignored; if another account owned that window, ownership transfers —
  same semantics as the manual right-click link. The window is marked
  *used* and gets its permanent session number on first touch.
- **New "➡ Auto-next client after login" checkbox** (F5 toggles it,
  persisted in Settings.ini, default ON): when checked, after each F2/F4
  focus jumps to the leftmost open client that hasn't been used yet; when
  unchecked, focus stays put — paste and link only.
- The status line under the row now reports live client counts
  ("3 client(s) open, 1 not yet used…"). "Forget Used" works as before.

## 0.5.0 — Game Info view

- **New: two list views over the same accounts, in the same order.**
  *Credentials* (#, Name, Email, Password, Client, Note) and *Game Info*
  (#, Name, Class, Level, Money, Last login, Note). Switch with the
  dropdown next to Search or **F6**; the choice is remembered.
- **Game fields are edited inline, Notes-style** (low friction by design):
  in Game Info view the row under the list becomes Class / Level / Money
  boxes plus the note box — everything autosaves ~800ms after you stop
  typing, atomically, no dialogs, no backups.
- **"Last login" stamps itself**: every F2/F4 password paste records the
  timestamp automatically.
- **File format extended (backward compatible)**:
  `Name|Email|Password|Note|Class|Level|Money|LastLogin` — all new fields
  optional; empty trailing fields aren't written, so untouched lines stay
  exactly as they were. Search also matches Class now.
- **Fixed (latent bug, same family as the ItemSelect desync): header-click
  sorting is now disabled (`NoSort`).** Clicking a column header used to
  re-sort rows visually without reordering internal state — after which
  F1/F2/F4 could paste a different account than the one highlighted.
- Note: one-column-set widths are reapplied when switching views, so
  manual column-width tweaks reset on switch (kept within a view).

## 0.4.1 — Resize ghosting fix

- Fixed: resizing the window quickly in multiple directions left stale
  "ghost" copies of the bottom checkboxes/buttons and smeared label text at
  their old positions (moved controls don't reliably erase their previous
  spot on the parent window). `Gui_Size` now suspends painting
  (`WM_SETREDRAW`) while it moves the whole batch of controls, then forces
  one full repaint at the end.
- The redraw uses raw `DllCall`s by hwnd rather than
  `SendMessage`/`WinRedraw` with `"ahk_id"` — those do a window *search*
  that throws "Target window not found" when the Size event fires during
  `Show()`, before the window is actually visible (new gotcha #13 in
  `CLAUDE.md`; caught by the automated resize stress test, which hung on
  the blocking error dialog until the DllCall form fixed it).

## 0.4.0 — Hardening pass (full static review + AHK v2 load-validation)

Every change below was verified with `AutoHotkey64.exe /validate` (load-time
syntax check), but runtime behavior still needs on-Windows testing — see the
testing notes in `CLAUDE.md`.

### Fixed

- **Window grew larger on every run.** The saved window size was measured
  with `GetPos()` (outer size, including title bar and borders) but re-applied
  via `Show()` (client-area size), so every save added the chrome size. Now
  measured with `GetClientPos()`, and not saved while maximized/minimized.
- **A saved window size broke the resize layout.** `LoadSettings` overwrote
  `Config.WindowWidth/Height`, which `Gui_Size` uses as its resize baseline —
  but the layout is always *built* at the 620×860 design size. Restoring a
  shorter window cut off the bottom controls; a taller one left dead space.
  The design size is now a true constant and the saved size lives in
  `App.WinW/WinH`, applied at `Show()` time with an explicit layout pass.
- **Keyboard navigation could desync the selection from the paste target.**
  Home/End/PageUp/PageDown inside the ListView moved the visible selection
  without updating `App.CurrentDisplayPos`, so F1/F2/F4 could paste a
  *different account* than the one highlighted. The list now syncs through
  the `ItemSelect` event (fires for both mouse and keyboard).
- **Every save silently deleted comments and unparseable lines from disk.**
  Comment lines, blank lines, and lines that don't parse were skipped at load
  and never written back — so a note autosave 800ms after a keystroke would
  permanently strip them from the `.txt`. All non-account lines are now
  preserved verbatim and re-emitted on save; unparseable lines are counted
  and surfaced next to the account count ("N unreadable lines kept in file").
- **Files could vanish or the app could break on Reload.** A file whose last
  account was deleted disappeared from the app on Reload (files with zero
  parseable accounts are now still listed), and a failed reload clobbered the
  in-memory file list before the error was caught (loading is now atomic —
  the old list is kept unless the new one loads fully).
- **A pending note autosave was silently dropped** if you typed a note in one
  file, switched files, and typed another note within the debounce window.
  The previous file's note is now flushed to disk first.
- **Rapid F1/F2 presses raced the clipboard restore.** Each paste stacked its
  own restore timer, so an earlier timer could restore a stale clipboard
  mid-paste — and a quick second paste "saved" the first paste's secret as
  your clipboard. There's now a single pending-restore slot: the first paste
  of a burst captures your real clipboard, and it's restored exactly once.
- **Identical windows collapsed into one right-click menu entry.** `Menu.Add`
  treats a same-name add as an update, so two windows that described
  identically could only link to the second one. Menu items are now numbered.
- **Back-to-back toasts cut each other short** — an earlier toast's hide
  timer could clear a newer toast. Toasts now share one debounced timer.
- **An account name starting with `;` round-tripped into a comment** and the
  account vanished on the next reload. The editor now rejects it.
- **F1 on an account with an empty field** sat through a 1-second clipboard
  timeout with a confusing error; it now toasts "nothing to paste" instantly.
- Pressing Up/Down in the sliver of time before the GUI exists could throw
  (the `#HotIf` expression read `.Hwnd` off an empty string); now guarded.

### Improved

- The file-navigation row (◀ filename ▶) now stretches with the window.
- Manual column-width adjustments survive list refreshes (widths are set
  once at startup instead of on every refresh).
- Tagging a window (F2/F4) updates just that row instead of rebuilding the
  whole list — less flicker during rapid batch logins.
- The save confirmation now warns when another account already uses the same
  email (email is the internal identity key, so duplicates confuse position
  memory and window links).
- After adding an account, the list jumps to it.
- Dark mode now also themes the Add/Edit dialog's text fields and title bar.

## 0.3.0 — Bugfixes from real-world testing

- Fixed: editing an account's Name/Email/Password was silently dropping its
  linked Client window (and would have dropped Note too) — the save path now
  clones and mutates the existing account object instead of replacing it.
- Added: manual link/unlink via right-click on any row — for game windows
  that were already logged in before the script was opened.
- Fixed: position memory (which account you were on) was matching by account
  Name, which isn't guaranteed unique — switched to matching by Email
  throughout. Also fixed a related bug where the final position was still
  being saved by Name at app-close time, overwriting the correct value.
- Fixed: a local variable named `menu` collided with the built-in `Menu`
  class, breaking the right-click context menu with a "variable not assigned"
  error. Renamed to `ctxMenu`.
- Fixed: confirmation dialogs (save/delete) could appear behind the
  Always-on-Top main window. Added `ShowConfirm()`, which suspends
  Always-on-Top for the duration of any blocking dialog.
- Added: Always-on-Top is now a toggleable, persisted setting instead of
  hardcoded on.

## 0.2.0 — Full rebuild

Starting point: a rough ~150-line personal script (paste email/password,
switch between files, ugly layout, several latent bugs).

- Complete visual redesign: modern layout, resizable window with a dynamic
  layout system that can't drift out of sync as controls are added (see
  `CLAUDE.md` for why this matters).
- Added F4 "combo login" hotkey (email → Tab → password → Enter in one press).
- Added Edit Mode: add/edit/delete accounts from within the app, gated behind
  a toggle, with confirmation dialogs and automatic timestamped backups before
  every credential write.
- Added window-linking automation for games with a concurrent-session cap:
  snapshot a batch of open game windows, walk through them in lockstep with
  F2/F4, track which windows have already been used across batches, and show
  which numbered window each account is linked to (Client column).
- Added a Notes column/field: low-friction, autosaving, no confirmation —
  deliberately different from the credential-edit flow.
- Added Dark/Light theme support, including best-effort native dark styling
  for the list/edit controls and the title bar.
- Added settings persistence: theme, show-passwords, window size, last file,
  and last-selected-account-per-file, saved to `Settings.ini`.

## 0.1.0 — Original script

The starting point this project was rebuilt from: a minimal AutoHotkey v2
script that read `Name|Email|Password` lines from text files and pasted them
via F1/F2/F3 hotkeys. Functional but visually rough, with several small bugs
(unwired selection-change handler, duplicate column-width call, no guard
against empty account lists, unsorted file load order).
