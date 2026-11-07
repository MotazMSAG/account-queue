# Account Queue

A Windows desktop utility for quickly logging into many game accounts across
multiple client windows. Built with AutoHotkey v2.

Paste credentials into whichever client window has focus, advance to the next
account, keep track of which window belongs to whom, record click macros,
build them into routines, and let the whole thing run unattended. One file,
no installer, no network access.

## Read this first

**Your passwords are stored in plain text.** Account Queue reads accounts from
`Logins\*.txt` files on your own disk, in the form `Name|Email|Password`.
There is no encryption and no master password — anyone who can read that
folder (or a backup of it, or your screen while "Show passwords" is on) can
read every password in it. That design is deliberate: the files stay
hand-editable and nothing is hidden from you. Decide if that suits you before
putting real credentials in, keep the folder off any shared drive, and never
commit it (`.gitignore` already excludes it).

**Automating a game client may breach that game's terms of service.** This
tool sends clicks and keystrokes to other windows. Whether that is allowed is
between you and whoever runs the game; some operators ban for it. Use it on
accounts and games where you are comfortable with that risk. No warranty — see
[LICENSE](LICENSE).

## Requirements

- Windows 10 or 11
- [AutoHotkey v2.0](https://www.autohotkey.com/) installed

## Setup

1. Download or clone this repository.
2. Double-click `AccountQueue.ahk`.

On first run it creates a `Logins` folder next to the script with a starter
`Accounts.txt` in it, so the app opens with a working (fake) example you can
edit in place. Replace those lines with your own, or add accounts from the app
with **Edit Mode → Add**.

Group accounts by putting them in separate `.txt` files inside `Logins`
(e.g. `MainAccounts.txt`, `Alts.txt`) — each file is one "batch" you can
switch between with F3. See `docs/sample-login-format.txt` for the format.

The `Logins` folder also collects `Backups/` (automatic timestamped backups
made before any credential edit) and `Settings.ini` (your saved preferences)
— both are created automatically.

## Login file format

Each line is one account:

```
Name|Email|Password
Name|Email|Password|Note
Name|Email|Password|Note|Class|Level|Money|LastLogin
```

Everything after `Password` is optional. `Class`, `Level`, `Money` and
`LastLogin` feed the **Game Info view** (see below); empty trailing fields
are never written, so simple lines stay simple.

- `Name` is just a display label — it doesn't need to be unique.
- `Note` is optional and can be left off entirely on older lines.
- Lines starting with `;` are treated as comments and skipped.
- Fields can't contain a literal `|` character (used as the separator).
- Comments, blank lines, and lines the app can't parse are preserved as-is
  whenever the app rewrites a file (after a credential edit or a note
  autosave). Unparseable lines are counted under the list ("N unreadable
  lines kept in file") so a typo'd line doesn't go unnoticed.

## Hotkeys

Hover any button or toggle in the app for a tooltip explaining it.
Hover **❔ Hotkeys** (bottom row) for this list in-app — or **click it**
to keep the list open in its own window.

These work globally — you don't need this window focused:

| Key | Action |
|---|---|
| `F1` | Paste the current account's email |
| `F2` | Paste the current account's password, then move to the next account |
| `F4` | Full login combo: paste email → Tab → paste password → Enter, then advance |
| `F10` | Pause/resume the paste keys — so a stray `F1`/`F2`/`F4` mid-browsing can't paste credentials into the wrong window |
| `F3` | Switch to the next login file |
| `Shift+F3` | Switch to the previous login file |
| `F5` | Toggle "Auto-next client after login" (see below) |
| `F6` | Cycle the Credentials / Game Info / Session views |
| `F7` | Start/stop macro recording (also aborts a running macro) |
| `F8` | Pick mode — click accounts to build a login queue |
| `F9` | Online view — all linked accounts across files, live |

These only work while the Account Queue window itself is focused:

| Key | Action |
|---|---|
| `Up` / `Down` | Move the selection without pasting anything |
| `Ctrl+F` | Focus the search box |
| `Enter` (in Search) | Jump to the first match and clear the filter |
| `Esc` (in Search) | Clear the filter |

## Daily activity quota

A standing weekly commitment the app enforces for you:

- **Sunday 30 · Monday 10 · Tuesday 10** accounts in Activity mode; other
  days, nothing. ("Today" is the game day, which rolls at 02:00.)
- On a quota day that isn't done, a **popup at startup** reminds you and a
  **red banner** sits under the stat strip. Done — it turns green.
- **The banner is the button:** click it and it picks that many accounts
  at random (across all files, skipping any already done or online),
  confirms the count, and starts Activity for them.
- The **session goal is 45 minutes** by default now — Activity keeps each
  account online for 45, which is also the day board's "done" threshold.
  Change it in ⚙ Preferences; edit `DailyQuotaCount` in the script to
  change the schedule.

### Idle Actions (running 24/7)

Open **🕒 Idle** (or the tray's **Idle Actions…**) for a prioritized list
of jobs the app runs on its own when the PC is idle:

- **Priority order (top to bottom).** When idle long enough, the highest
  job with work to do runs; when it's done for the day, the next one goes.
  Reorder with ▲▼, enable/disable with each row's checkbox.
- **Activity** (built in, on by default) runs the daily quota — keep the
  day's accounts online for the goal, then close them.
- **Chore** jobs pick a macro/routine + accounts (all / one file / your
  ⊕ Pick selection). Each account is logged in, runs the macro **once**,
  then its client is **closed** — and no account repeats a job the same
  day (resets at 02:00).
- **Minimize** hides to the **system tray** for around-the-clock running;
  right-click the tray icon to show, run idle actions now, toggle
  run-when-idle / minimize-to-tray, or exit.
- **Auto-firing** waits for **2 hours away** (tunable in ⚙ → "Auto-run
  idle"), and only runs when unlocked, not already busy, and with Login
  Setup ready. **▶ Run now** ignores the timer.
- "Away" is measured by **pointer position**, not raw input events —
  many mice emit stray events while untouched, and requiring unbroken
  silence meant jobs could never fire. Drift under ~12 px (⚙ → "Away
  mouse slack") isn't counted as you.
- **The window tells you why nothing is running** — a live status line:
  *"Waiting — away 34 of 120 min · next up: Fishing"*, *"Nothing pending
  — every enabled job is done for today"*, *"Login Setup is
  incomplete"*, and so on.
- **A cancel countdown** appears before an auto-run starts (5 s, tunable;
  0 disables) — click **Cancel** or just touch the mouse if you're
  actually there. Manual runs skip it.
- **📜 History** (in the manager, or tray → Idle History) shows what each
  idle run did — per account, green ✔ success / red ✖ failure — and is
  saved to `Logins\idle-history.txt` so you can read it after an
  overnight run.

## The day board

The strip of colored cells between the Search box and the list is the
whole day at a glance — one cell per account across **all** files
(duplicate emails count once):

- **grey** — not started · **amber** — online and counting ·
  **green** — goal reached · **red** — lost its client early

Hover a cell for that account's status; **click it to jump straight to
the account**, switching files if needed (in pick mode, clicking cells
**queues** accounts instead — same as clicking rows). It updates live, and the
**taskbar button and the progress bar under the list fill up** with the
same done/total progress — so you
can track the day from inside the game without switching windows.

## The green dot

Every account that's **online right now** (linked to a client) shows a
**green ●** at the start of its row — in every view, in search
results, everywhere. Dead clients lose their dot within seconds.

## Routines — building programs out of your macros

A recorded macro is a straight line of clicks. A **routine** is a
program built out of macros, with real logic. Open **🎬 Macros → 🧩
Routine Maker**:

- **Add step** inserts an instruction after the selected line:
  - **Macros** — run a macro (or another routine) N times
  - **Input** — click a point (left/right/middle), send keys, refocus the client
  - **Waiting** — wait, wait a random range, or **wait until a pixel matches**
  - **Flow** — loop N times (0 = forever), while <condition>, if / otherwise,
    break, next pass, stop, report failure, label + go to
  - **Counters** — set/add a number, then compare it in conditions
- **Conditions**: a pixel matches (or doesn't) a captured colour within a
  tolerance, the last pixel-wait (or retry block) succeeded or timed out,
  the client is open or closed, a counter comparison, a random percentage,
  **this account has reached today's goal**, or **minutes left** compared
  to a number.
- **Capture, don't type**: in any point/pixel field click **◉ Capture**,
  hover the exact spot in the game client, press **F12**. Coordinates are
  stored relative to the window and scale to any client size.
- **▶ Test on client** runs what's on screen — no save needed.

Example — farm until the reward stops appearing:

```
log|daily farm started
repeat|3|pixel|640|360|0xC81E1E|24    (try 3x until the icon shows)
  run|remove mail|1
  waitsec|5
endrepeat
if|notok                              (3 tries, still wrong)
  restartclient
endif
loop|0                                (forever)
  if|minsleft|<|5
    break
  endif
  run|claim dailies|2
  waitrand|800|2000
endloop
closeclient
```

Routines are saved in `Logins\Routines\*.txt` — same hand-editable pipe
format as macros — and **work anywhere a macro works**: post-login
playlists, the macro queue, a row's right-click menu, or called from
another routine. Names are shared between macros and routines, so
anything that takes one takes the other.

> `send keys` is for game keys. Never put a password in a routine —
> `F1`/`F2`/`F4` handle credentials without writing them anywhere.

## Hover cards

Hover any row in the list for the account's full card — class, level,
money, note, client number, today's online minutes, and last login —
regardless of which view you're in. (Passwords never appear in cards.)

## Linking game windows

There's nothing to arm: every `F2`/`F4` automatically links the account to
whatever game client window the paste landed in (non-game windows are
ignored), marks that window as *used*, and shows the link in the **Client**
column.

The **➡ Auto-next client after login** checkbox (or `F5`) controls what
happens next:

- **Checked** — after the paste, focus jumps to an open game client that
  hasn't been used yet (left-to-right by screen position), so your next
  `F4` lands on a fresh client. When every open client has been used,
  you'll get a toast — open more clients or click **Forget Used**.
- **Unchecked** — focus stays where it is; it just pastes and links.

Used windows are never jumped to twice. **Forget Used** clears that
tracking if you want to redo clients that were already logged in.

If a client was already logged in *before* you opened the script,
**right-click its row → 🔗 Link to a window** to manually link it to
any currently-open game window, or unlink it from the same menu. The
right-click menu is the per-account command center: **Copy email /
Copy password**, **⊕ Pick / ✖ Unpick this account** (build the login
queue without entering pick mode), **🚀 Launch + log this account in**
when it's offline, and **🗔 Jump to** / **🚪 Close** its client when
it's online (closing banks the online time first).

Double-clicking a row (with Edit Mode off) jumps straight to that
account's linked window. If the account has **no** linked client,
double-clicking instead **launches a client and logs it in**
automatically (Play mode — needs Login Setup done once; `Esc`/`F7`
aborts). Double-click more accounts while a run is going and they
**queue up quietly** — each starts the moment the previous run
finishes (the status line shows "⌛ N next"; stopping the run clears
the waiting list).

## Game Info view

The three square buttons next to the Search box (🔑 / 🎮 / ⏱, or `F6`
to cycle) switch the list between three views of the *same* accounts in
the *same* order — the active view's button is shown pressed/disabled:

- **Credentials** — #, Name, Email, Password, Client, Note (the classic view)
- **Game Info** — #, Name, Class, Level, Money, Note
- **⏱ Session** — #, Name, Client, Online, Left, Last login, Note

### Session view — the "30 accounts × 30 minutes" dashboard

Each account tracks how long it has been **online** (linked to a
client). The clock starts when you log it in (F2/F4), keeps counting
while its client is open, and **banks the time when the client closes**
— so shutting down a finished batch never loses progress, and
re-logging an account later keeps accumulating.

- **Online** — total minutes so far. **Left** — countdown to the goal
  ("18 min left" → "✔ done").
- Row colors tell the story at a glance: **amber** = online and
  counting, **green** = 30 minutes reached, **red with ⚠** = the client
  disappeared before the goal (its clock is stopped — relog to resume).
  The selected row shows the normal selection highlight instead.
- The **stat strip** under the progress bar is the scoreboard, in
  every view: **✔ done** (green) · **▶ online** (amber) · **N to go** ·
  **Σ money** (blue) — counted across **all** login files (duplicate
  emails count once). Session view adds Σ online hours in the dim
  right-hand corner.
- **Everything resets at 02:00** — the game's day boundary. Green stays
  green until then, *including across app restarts*: the day's online
  minutes are saved to `Settings.ini` and restored as long as it's still
  the same game day. Accounts still online at 02:00 simply start
  counting the new day from the boundary.
- Both the goal (30 min) and the reset hour (02:00) — plus every other
  timing knob and the game process name — are editable in **⚙
  Preferences** (bottom row), no script editing needed.

In Game Info view, the edit row under the list shows **Class / Level /
Money** boxes plus the note box. Type into them and they save
automatically a moment after you stop typing — same low-friction behavior
as Notes (no dialog, no confirmation, no Edit Mode needed; these are
game-status facts, not credentials).

**Last login** fills itself in: every `F2`/`F4` password paste stamps the
current date and time on that account.

The view you were on is remembered between runs. **Search looks
through every file at once** — matches for Name, Email, Note, Class,
Level, and Money (in every view) are grouped under 📁 file headings, so
a note or account you half-remember turns up no matter which file
you're viewing. The # column shows each match's number within its own
file, and editing a result (notes, game fields) saves to its own file.

**Money understands numbers**: type `123k`, `3.3m`, `1.2b`, `6,000,000`
or plain digits — the column shows everything standardized to three
decimals of precision ("1.036B", "6.6M"), the **stat strip under the
list shows Σ total across all files in every view**, and Search accepts
value queries like `>6.6m` or `<500k`. Text that isn't a number (e.g.
"xxx") is kept exactly as typed, shown greyed, and left out of the math.

## Pick queue — hand-picked login order

Press **⊕ Pick** (or `F8`), then click accounts in the order you want
them logged in — any files, switch with `F3` while picking, click a row
again to remove it. Queued rows show "»1 »2 …" in the # column. Press
`F8` again (or just start logging in): `F1`/`F2`/`F4` now work through
the queue head-first, jumping the list to the next pick automatically —
even across files. When the queue empties, normal behavior resumes.
Re-entering pick mode always starts a fresh queue.

## Online view

Press **👁** (or `F9`) for a live window of every currently-linked
account across **all** files — client number, online minutes, and time
left to the goal — refreshing every few seconds. Double-click a row to
jump straight to that client.

## Mass Login (auto-login console)

Open clients and log accounts in automatically, from one window.

**Set up once:** ⚙ Preferences → **🎯 Login Setup**. Open one game
client and, for each of the five points — Try Again, the logout→login
button, email field, Start Game, character — hover the exact spot and
press `F12`. Each point also samples its pixel colour, used to detect
that stage on screen. Set the launcher path in ⚙ if it's not the default.

**Use it:** click **🚀 Mass Login** to open the console. There you:
- **➕ Add** accounts (all in file / all files / all not-done) to the
  queue; reorder or remove via right-click.
- **Assign macros** to run after login — as a playlist per account
  (added in order, run round by round); ▶ Run now runs them on
  already-online clients standalone.
- Choose **Play** (log in and leave running) or **Activity** (keep
  *Online cap* accounts online for the *Goal* minutes, then close each
  as it finishes — the idle wait is filled with your macros); set the
  Launch group / Online cap / Goal right there.
- **Start / Stop**, and watch the live overview (done / online / queued /
  ETA), per-account time-left, and exactly what the loop is doing.
  Double-click a row to show that account in the main window.
- Accounts that fail to log in 3 times are dropped and counted
  ("✖ 2 failed last run") — **➕ → Re-add failed** re-queues them.
- When the last account reaches the goal you get a chime and a
  "🎉 all done" toast — once per game day.

Per client the loop: clear stuck loading (Try Again until loaded) →
re-click logout until the login page is detected → email + **F4
immediately** (the game freezes if the login page lingers) → Start Game →
character → link (session clock starts). A client that stays stuck is
closed and relaunched a couple of times, then skipped. **`Esc` or `F7`
aborts;** during Activity's idle wait, only `F7`/Stop halts, and stopping
never closes clients. Passwords are never recorded into a macro.

## Macros (recorded clicks)

For repetitive in-game clicking (claiming dailies, closing popups):

1. Click **🎬 Macros** → **⏺ Record New** (or just press `F7` anywhere).
2. Click through the game once, at your normal pace. Only left-clicks on
   game client windows are recorded; your pauses become the playback
   timing, so waiting for a loading screen while recording is all it
   takes to handle one.
3. Press `F7` to stop, give it a name.
4. Run it: **right-click a linked row → ▶ Run macro / routine on its
   client**, or select one in the manager and hit **▶ Run**.

Playback re-anchors clicks to wherever the target window is (and scales
if it was resized), so one recording works on every client. **`Esc` or
`F7` aborts a running macro instantly.** Macros never record the
keyboard — credentials only ever flow through `F1`/`F2`/`F4`.

Macro files are plain text in `Logins/Macros/` — the manager's
**📝 Open in Editor** lets you tweak coordinates or delays by hand
(`click|x|y|delayMs`, delay is waited *before* that click).

### Queueing macros across clients

The manager's **Queue** section batches jobs — each job is one macro on
one client, run top to bottom with a short breather in between:

- **➕ All clients** — one job per open game window, left-to-right.
- **➕ Linked accounts** — one job per linked account in the current
  file, in list order.
- **➕ Selected** — just the selected account's client.
- **Right-click a row → ➕ Queue macro / routine on its client** —
  compose freely, different macros for different accounts included.

Hit **▶ Start / Resume** and watch the status column (⏳ → ▶ → ✔/✖/⛔).
A closed client fails its own job and the queue continues. `Esc`/`F7`
aborts the current macro and pauses the queue — resume or clear anytime.
While it runs, the main window's status line tracks progress, so you can
close the manager. The queue is session-only; it clears on restart.

## Editing accounts

Credential edits are deliberately a little more involved than everything
else, since they touch sensitive data:

1. Turn on **Edit Mode**.
2. Double-click a row to edit it, or click **+ Add Account** to add a new one.
3. Confirm the change. A timestamped backup of the file is made first.

**Notes**, on the other hand, are meant to be quick and low-stakes: just
select a row and type in the Notes box under the list. It saves automatically
a moment after you stop typing — no dialog, no confirmation.

## Other settings

- **Show Passwords** — reveal passwords in the list instead of masking them.
- **Dark Mode** — switches the whole interface to a dark theme (note: native
  Windows buttons don't fully support dark theming and will stay light-colored
  regardless of theme — this is a Windows limitation, not a bug).
- **Always on Top** — keeps the window above other applications. Turn this off
  if you'd rather it behave like a normal window.
- **Reload** — re-reads all `.txt` files from disk without restarting the app.

Your theme, show-passwords preference, always-on-top preference, window
size **and position**, and the file/account you were last on are all
remembered automatically between runs.

## Safety notes

- Your `Logins` folder contains real credentials in plain text. Keep it out of
  version control (see `.gitignore` if you're using this in a repo) and treat
  it like any other sensitive local file.
- Backups accumulate in `Logins/Backups/` — the last 15 per file are kept
  automatically, older ones are pruned.

## Running the tests

```powershell
.\tests\run-tests.ps1 -Fast -Quiet
```

~4 seconds, 287 checks, no mouse movement. Drop `-Fast` for the full suite
(adds two files that drive the real mouse and flash a window, so don't run
that while you're working). The runner finds AutoHotkey v2 by itself; set
`AHK_PATH` if yours lives somewhere unusual.

## Related project

[TOS Macro Studio](https://github.com/MotazMSAG/tos-macro-studio) is a fork of
this codebase aimed at a single account in one game: the multi-account
machinery is stripped out and the macro recorder and routine editor are the
centre of the app, with a flow-chart editor for building routines visually.

## License

MIT — see [LICENSE](LICENSE).
