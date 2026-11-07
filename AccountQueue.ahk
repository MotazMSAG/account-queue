#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; Account Queue
; ------------------------------------------------------------
; Reads one or more "*.txt" files from a "Logins" subfolder
; next to this script. Each line in a file must look like:
;
;     Name|Email|Password
;     Name|Email|Password|Note      (Note is optional)
;
; Comment lines (starting with ";"), blank lines, and lines that don't
; parse are preserved as-is whenever the app rewrites a file.
;
; The GUI lets you page through accounts and paste their email
; or password into whatever window currently has focus (e.g. a
; game client), then automatically advances to the next account.
;
; Hotkeys (work globally, no need to focus this window):
;   F1        Paste current account's email
;   F2        Paste current account's password, then advance
;   F4        Combo: email -> Tab -> password -> Enter, then advance
;   F10       Pause/resume the paste keys (F1/F2/F4)
;   F5        Toggle "Auto-next client after login"
;   F6        Cycle Credentials / Game Info / Session views
;   F7        Start/stop macro recording (also aborts playback)
;   F8        Pick mode (build a login queue by clicking rows)
;   F9        Online view (all linked accounts, live)
;   F3        Next login file
;   Shift+F3  Previous login file
;
; Hotkeys (only while this window is focused):
;   Up / Down Move selection without pasting
;
; Editing accounts (off by default, deliberately):
;   Flip "Edit Mode" on, then double-click a row to edit it, or use
;   "+ Add Account" to add one. Every save/delete asks for confirmation
;   and takes a timestamped backup of the .txt file first (in a
;   "Backups" subfolder), so nothing is overwritten without a fallback.
;
; Linking game windows:
;   There is no arming step. Every F2/F4 automatically links the account
;   to whatever game client window the paste actually landed in (the
;   active window at paste time — non-game windows are ignored), marks
;   that window as "used", and shows the link in the "Client" column.
;
;   The "Auto-next client" checkbox (toggle with F5) controls what
;   happens after the paste: checked, focus jumps to an open game client
;   that hasn't been used yet (left-to-right by screen position), so
;   your next F4 lands on a fresh client; unchecked, focus stays where
;   it is — it just pastes and links.
;
;   Used windows won't be jumped to again. "Forget Used" clears that
;   tracking if you genuinely want to redo windows that were already
;   logged in.
;
;   Every window gets a permanent number the first time it's linked
;   (1, 2, 3, ...), and every account remembers which numbered window it
;   was last pasted into — shown in the "Client" column. With Edit Mode
;   OFF, double-clicking an account activates that window directly (it
;   won't launch a new one — only an already-open client). If that
;   window has since closed, you'll get a toast saying so rather than
;   nothing happening.
;
;   The "Client" column is session-only and never written to the .txt
;   files — it resets every time you restart the tool. Editing an
;   account's Name/Email/Password preserves its Client link (and its
;   Note) — only deleting a row, or explicitly unlinking, clears it.
;
;   Right-click any row to manually link it to any currently-open
;   game window — for clients you logged into before opening the
;   script, which the automated F2/F4 flow never had a chance to tag.
;   The menu shows you if a window's already claimed by another
;   account before you reassign it. Right-click again to unlink.
;
; Macros (recorded click sequences):
;   Click "🎬 Macros" to open the manager, or press F7 anywhere to
;   start/stop recording. While recording, left-clicks on game client
;   windows become steps (clicks anywhere else are ignored), and your
;   real pauses become the playback delays — waiting out a loading
;   screen while recording just works. Clicks are stored relative to
;   the window and scale if it's a different size later. Left-clicks
;   only, deliberately: recorded keystrokes would put passwords into
;   plain-text macro files.
;
;   Run a macro from the manager, or right-click a linked row →
;   "Run macro on its client". Esc or F7 aborts playback instantly.
;   Files are plain text in Logins\Macros\ — hand-editable.
;
; Notes:
;   The box under the list edits the Note for whichever account is
;   currently selected — no dialog, no confirmation, it just autosaves
;   a moment after you stop typing. Unlike credential edits, this
;   doesn't take a backup first (notes are low-stakes and would
;   otherwise flood the Backups folder), but it does still write
;   atomically, so a mid-save crash can't corrupt the file. Notes ARE
;   saved to the .txt files (as an extra field after Password), unlike
;   the Client column.
;
; Settings:
;   Theme, "show passwords", and window size are remembered between
;   runs, saved to Settings.ini inside the Logins folder. The file and
;   account you were on are also remembered — both across restarts,
;   and per-file during a session, so switching files with F3 and
;   coming back to one later returns you to where you left it.
; ============================================================

class Config {
    static Version         := "0.43.0"
    ; One font family everywhere. Segoe UI Variable Text is Win11's UI
    ; face (this machine's OS); on older Windows GDI font-maps it to a
    ; close default — cosmetic either way, nothing breaks.
    static FontMain        := "Segoe UI Variable Text"
    ; DESIGN size — the client-area size BuildGUI lays controls out for.
    ; Never overwrite these with the user's saved size: Gui_Size uses
    ; WindowHeight as the baseline for its resize delta, so it must stay
    ; the height the layout was actually built at. The saved size lives
    ; in App.WinW / App.WinH and is applied at Show() time instead.
    static WindowWidth     := 620
    static WindowHeight    := 860
    static LoginsFolder    := A_ScriptDir "\Logins"
    static SettingsPath    := Config.LoginsFolder "\Settings.ini"
    static ClipRestoreMs   := 150
    static ComboStepDelayMs := 70
    static MaxMaskDots     := 12
    static BackupsToKeep   := 15
    static BackupsFolder   := Config.LoginsFolder "\Backups"
    static MacrosFolder    := Config.LoginsFolder "\Macros"
    static RoutinesFolder  := Config.LoginsFolder "\Routines"
    static MacroMaxStepDelayMs := 120000  ; recorded pauses are capped at 2 min
    static QueueJobGapMs   := 1500       ; breather between queued macro jobs
    ; --- Routines (macros + control flow) ---
    static RoutineMaxSteps := 200000     ; runaway guard: total steps one routine run may execute
    static RoutineMaxDepth := 5          ; how deep routines may call other routines
    static RoutineTraceLines := 60       ; steps kept for the post-mortem written to routine-log.txt
    ; Settle pause before the pointer is parked back where you left it.
    ; BlueStacks-style clients read a tap from the pointer's position at
    ; the moment they process it, so moving the cursor away instantly
    ; made the LAST click of a run land wherever the cursor went.
    ; 0 = never move the pointer back.
    static MouseRestoreDelayMs := 250
    ; --- Auto-login orchestrator (⚙-tunable subset) ---
    static LauncherPath    := "D:\Games\ToW\ToWRR\ToW.exe"
    static LaunchMax       := 4          ; most clients one Launch & Login run will start
    static LoginBootMs     := 16000      ; parallel load wait after launching, before logins
    static LoginAfterCredsMs := 2500     ; wait after F4 credentials before Start Game
    static LoginStartToCharMs := 3000    ; Start Game -> character screen
    static LoginPollMs     := 1500       ; re-check interval while unsticking a stuck load
    static LoginColorTol   := 24         ; per-channel tolerance for both loaded-state probes
    ; --- login page (freeze-sensitive: the game briefly freezes if the
    ;     login page stays open >~2s, so F4 must fire fast once it opens) ---
    static LoginEmailToF4Ms := 120       ; gap between clicking Email and firing F4 — keep short
    static LoginPagePollMs := 150        ; how often to check the Email probe (fast = quick F4)
    static LoginLogoutRetryMs := 500     ; re-click Logout this often until the login page opens
    ; not surfaced in Preferences (sane fixed values):
    static LoginStepMs     := 600        ; tiny pause between adjacent clicks
    static LoginMaxWaitMs  := 90000      ; give up on a stuck LOAD after this long
    static LoginPageMaxMs  := 12000      ; give up reaching the login PAGE after this long
    static LoginStartMaxMs := 20000      ; give up waiting for the Start Game button
    static LoginCharMaxMs  := 20000      ; give up waiting for character selection
    static LoginStartRetryMs := 600      ; re-click Start Game this often until char appears
    static LoginMaxRetries := 2          ; close+relaunch a client this many times on failure
    ; --- Activity mode (keep N online for the session goal, then close) ---
    static OnlineCap       := 10         ; most accounts kept online at once in Activity mode
    static MacroReserveMinutes := 15     ; idle minutes kept macro-free — macros must fit in idle minus this
    static LoginMonitorMs  := 5000       ; how often Activity mode checks online timers
    static SessionGoalMinutes := 45      ; Session view: online time per account to count as done
    static AutoRunIdleMinutes := 120     ; minutes of no input before idle jobs auto-fire (when enabled)
    static IdleGraceSeconds := 5         ; countdown to cancel an auto-firing idle job (0 = fire immediately)
    ; Pointer drift smaller than this (per housekeeping tick) is NOT the
    ; user — plenty of mice emit stray events while untouched, and the
    ; old "unbroken A_TimeIdlePhysical" rule let one twitch reset hours.
    static AwayMouseSlackPx := 12
    static DayResetHour    := 2          ; the game's day flips at 02:00 — all session stats reset
    static HousekeepingPeriodMs := 5000  ; dead-client prune + Session view tick cadence
    static GameProcess     := "ToW.exe"
    static WindowSwitchDelayMs := 120
    static NoteAutosaveDelayMs := 800
}

; Mutable at runtime — ApplyTheme() reassigns these to switch between
; light and dark. Anything that reads Colors.X at the moment it draws
; (rather than caching it) picks up theme changes automatically.
; The visual language, in one place. Rules the whole app follows:
;   - H1 = the file label: s11 Bold, Accent. One per window.
;   - Body = s9 Norm, Text. Buttons, checkboxes, edits, lists.
;   - Strong = s9 Bold, Text. Exactly one live status/scoreboard line
;     per window — bold is reserved for "what's happening right now".
;   - Meta = s8 Italic, TextDim. Counts, hints, version — anything you
;     only read on purpose. Italic + dim marks it as ignorable.
;   - Success/Info/Warning/Danger are the ONLY status hues; anything
;     colored means state (green done, amber counting, red lost,
;     accent-blue selected/queued). Never decorate with color.
class Colors {
    static Bg      := "F5F6FA"
    static Text     := "222222"
    static TextDim  := "777777"
    static Accent   := "3F6FE0"
    ; Semantic status hues (hex RGB, tuned per theme for contrast as TEXT)
    static Success := "2E7D32"
    static Info    := "1565C0"
    static Warning := "B8860B"
    static Danger  := "C62828"
    static ZebraBGR := 0xF7F3F2 ; even list rows (COLORREF = BGR)
    static DoneRowBGR := 0x46961E   ; Session view: reached the goal (COLORREF = BGR, not RGB!)
    static OnlineRowBGR := 0x0B86B8 ; Session view: online, still counting (amber)
    static WarnRowBGR := 0x2828C6   ; Session view: lost its client before the goal (red)
    static QueuedRowBGR := 0xE06F3F ; pick-queue member (accent blue, non-session views)
    ; Day board cell backgrounds (hex RGB, not BGR — these go to +Background)
    static BoardDone   := "1E9646"
    static BoardOnline := "B8860B"
    static BoardWarn   := "C62828"
    static BoardIdle   := "D8DAE2"
}

global App := {
    Files: [],              ; array of {Name, Path, Accounts:[{Name,Email,Password}]}
    CurrentFile: 1,
    Displayed: [],           ; visible rows — ints (current-file indices) or, while searching, {Acc,File,Num}/{Sep} objects; ALWAYS read via RowAccount()
    CurrentDisplayPos: 1,    ; position within Displayed
    ShowPasswords: false,
    FilterText: "",
    ViewMode: "credentials", ; "credentials" | "game" — which column set the list shows
    ListColCount: 6,         ; how many columns the ListView currently has (see SetListColumns)
    EditModeOn: false,
    EditDialogOpen: false,
    AutoNextClient: true,   ; after F2/F4: jump to an unused game client (F5 / checkbox)
    UsedWindowHwnds: Map(),
    WindowSessionNumbers: Map(),
    NextSessionNumber: 0,
    ThemeName: "light",
    SuppressNotesChangeEvent: false,
    PendingNoteSaveFile: "",
    LastPositionPerFile: Map(),
    PendingRestoreAccountEmail: "",
    PendingTipText: "",     ; hover-tooltip text waiting on its show delay
    IsRecording: false,     ; macro recorder armed (F7 toggles)
    MacroPlaying: false,    ; a macro is being played back right now
    RecordingSteps: [],
    RecordingLastTick: 0,
    RecordingRefW: 0,       ; size of the game window at record time —
    RecordingRefH: 0,       ; playback scales clicks if the window resized
    MacroDlg: "",           ; the Macro Manager window, when open
    CurrentGameDay: "",     ; GameDayStamp() of the day the stats belong to
    PickMode: false,        ; clicks on rows add/remove pick-queue members (F8)
    LoginQueue: [],         ; hand-picked accounts, in click order — F1/F2/F4 target its head
    OnlineDlg: "",          ; the live "online accounts" window, when open (F9)
    PrefsDlg: "",           ; the Preferences window, when open (⚙)
    TuningDefaults: "",     ; Config values as shipped, captured before overrides load
    LoginProfile: "",       ; { ProbeColor, Points: Map(key -> {X,Y,RefW,RefH}) }
    LoginRunning: false,    ; the auto-login orchestrator is working
    LoginBatch: [],         ; accounts being logged in this run
    LoginStatusText: "",    ; status line owned by the orchestrator while it runs
    LoginMode: "play",      ; "play" or "activity"
    LoginStopReq: false,    ; soft stop (the console's Stop button)
    LoginMacros: Map(),     ; email -> macro name to run right after that account logs in
    LoginMacroPlayingEmail: "", ; whose post-login macro is running right now
    LoginConsoleDlg: "",    ; the Mass Login console window, when open
    ConsoleHold: false,     ; pause console auto-refresh (context menu open)
    LoginSetupDlg: "",      ; the Login Setup / capture window, when open
    BoardAccounts: [],       ; day board: account per visible cell (email-deduped)
    BoardStates: [],         ; day board: state per visible cell (diffed to avoid repaints)
    BoardSig: "",            ; day board: composition signature (repositions only on change)
    CaptureKey: "",         ; which login point capture is armed for (F12)
    Queue: [],              ; session-only macro jobs: {Macro, Hwnd, Label, Status}
    QueueRunning: false,    ; the queue worker is actively processing jobs
    QueuePaused: false,     ; jobs remain but the worker is stopped (pause/abort)
    AlwaysOnTop: true,
    PastePaused: false,     ; F10: paste keys stood down (session-only, never persisted)
    HotkeysDlg: "",         ; the click-to-open hotkey reference window, when open
    WinW: Config.WindowWidth,   ; actual size to open the window at (saved size once loaded)
    WinH: Config.WindowHeight,
    WinX: "",                   ; saved window position ("" = let Windows place it)
    WinY: "",
    LoginFailedDrops: [],        ; accounts dropped after 3 failed logins this run (session-only)
    PendingSingles: [],          ; double-clicked accounts waiting for the current run to finish
    RoutineDlg: "",              ; the Routine Maker window, when open
    RoutineLastTrace: "",        ; execution trace of the most recent routine run
    RoutineTraceDlg: "",         ; the trace viewer, when open
    QuotaDoneStamp: "",          ; game-day stamp the daily quota was last started for
    AutoRunWhenIdle: true,       ; master switch: run idle jobs after AutoRunIdleMinutes of no input
    MinimizeToTray: true,        ; the minimize button hides to the tray instead
    IdleJobs: [],                ; ordered idle-action jobs (priority = order); see the Idle system
    IdleDone: Map(),             ; "<jobName>|<email>" -> 1 for accounts handled today (game-day scoped)
    IdleDoneDay: "",             ; game-day stamp the IdleDone map belongs to
    ChoreJob: "",                ; the chore job currently being run by RunChore
    IdleDlg: "",                 ; the Idle Actions manager window, when open
    IdleHistory: [],             ; recent idle-run events {Time,Job,Who,Result,Detail} (newest last)
    IdleHistDlg: "",             ; the history viewer, when open
    IdleCountdownActive: false,  ; a pre-run grace countdown is showing
    IdleCountdownJob: "",        ; the job that countdown will start
    IdleCountdownLeft: 0,        ; seconds remaining on the countdown
    IdleCountdownDlg: "",        ; the countdown window
    IdleCountdownX: 0,           ; pointer position when the countdown began
    IdleCountdownY: 0,
    IdleCountdownStart: 0,
    AwayMs: 0,                   ; how long the USER has been away (jitter-tolerant; see UpdateAwayTracking)
    AwayLastX: 0,                ; pointer position at the previous tick
    AwayLastY: 0,
    AwayLastTick: 0,             ; A_TickCount of the previous tick (0 = no baseline yet)
    RoutineCapture: "",          ; armed F12 pixel/point capture: {Fields, RefW, RefH}
    RoutineDepth: 0,             ; nesting depth of routine-calls-routine
    DayCelebrated: false,        ; the all-done fanfare fired for this game day
    SavedClip: "",              ; the user's real clipboard while a paste's deferred restore is pending
    Layout: "",
    Gui: "",
    Controls: {}
}

try {
    CaptureTuningDefaults() ; must run before LoadSettings applies overrides
    LoadLoginFiles()
    LoadSettings()
    App.CurrentGameDay := GameDayStamp()
    LoadSessionTimes() ; restore this game-day's online minutes, if any
    BuildGUI()
    App.Controls.ShowPw.Value := App.ShowPasswords ? 1 : 0
    SetViewMode(App.ViewMode, false) ; builds the right column set before rows exist
    RefreshUI()
    RefreshLinkStatus()
    SetTimer(PeriodicHousekeeping, Config.HousekeepingPeriodMs)
    ApplyTheme(App.ThemeName, false) ; false = don't re-save what we just loaded
    showOpts := "w" App.WinW " h" App.WinH
    if (App.WinX != "" && App.WinY != "" && PosOnAScreen(App.WinX, App.WinY))
        showOpts := "x" App.WinX " y" App.WinY " " showOpts
    ; Test scripts set AQ_TEST_QUIET before #Include-ing this file. The
    ; window then comes up WITHOUT taking focus — otherwise every suite
    ; run steals the foreground, and when the test process exits Windows
    ; promotes whatever was underneath, which on this machine means a
    ; real game client jumps to the front. Tests must never disturb the
    ; desktop they run on.
    if (IsSet(AQ_TEST_QUIET) && AQ_TEST_QUIET)
        showOpts := "NoActivate " showOpts
    App.Gui.Show(showOpts)
    ; Show() at a size other than the design size fires a Size event, but
    ; run the layout pass explicitly too so the restored size is laid out
    ; correctly even if that event is skipped or mistimed.
    App.Gui.GetClientPos(, , &startupW, &startupH)
    Gui_Size(App.Gui, 0, startupW, startupH)
    ; Daily quota: load fulfilment, colour the banner, and (unless a test
    ; is driving) nag if today's quota is still open.
    LoadQuotaState()
    LoadIdleJobs()
    LoadIdleDone()
    LoadIdleHistory()
    RefreshQuotaBanner()
    SetupTray()
    if !(IsSet(AQ_TEST_QUIET) && AQ_TEST_QUIET)
        MaybeWarnQuota()
} catch as err {
    try {
        if (App.Gui != "")
            App.Gui.Opt("-AlwaysOnTop")
    }
    MsgBox(
        "Error:`n" err.Message "`n`nLine: " err.Line "`nFile: " err.File
    )
    ExitApp()
}

; ============================================================
; HOTKEYS
; ============================================================
; IsObject guard: hotkeys are live from script startup, a moment before
; the GUI object exists — without it, pressing Up/Down in that window
; would throw trying to read .Hwnd off an empty string.
#HotIf IsObject(App.Gui) && WinActive("ahk_id " App.Gui.Hwnd)
Up::PreviousAccount
Down::NextAccount
^f::FocusSearch
#HotIf

; Enter/Esc act on the Search box only while it has focus — Enter jumps
; to the first match, Esc clears the filter. Everywhere else both keys
; keep their normal meaning.
#HotIf IsObject(App.Gui) && WinActive("ahk_id " App.Gui.Hwnd) && SearchHasFocus()
Enter::SearchJumpFirst
Esc::SearchClear
#HotIf
F1::PasteEmail
F2::PastePassword
F4::PasteComboLogin
F5::ToggleAutoNextFromHotkey
F6::ToggleViewMode
F7::ToggleMacroRecording
F8::TogglePickMode
F9::OpenOnlineView
F10::TogglePastePause
F3::NextFile
+F3::PreviousFile
#HotIf

; F12 records a point ONLY while Login Setup has armed a capture.
#HotIf App.CaptureKey != ""
F12::DoLoginCapture
#HotIf

; …and the same key serves the Routine Maker's point/pixel pickers.
#HotIf IsObject(App.RoutineCapture)
F12::DoRoutineCapture
#HotIf

; ============================================================
; PASTE ACTIONS
; ============================================================
; One shared gate for F1/F2/F4. Silent only while the edit dialog is
; open (the user is typing there, not aiming a paste) — every other
; refusal SAYS WHY, because a paste key that silently does nothing
; reads as "the app is broken".
PasteKeysReady() {
    global App
    if App.EditDialogOpen
        return false
    if App.PastePaused {
        ShowToast("⏸ Paste keys are paused — F10 resumes them")
        return false
    }
    if App.LoginRunning {
        ShowToast("Paste keys stand down while Mass Login runs — F7 stops it")
        return false
    }
    return true
}

; F10 — safety valve for the global paste keys. They work in ANY window,
; so during normal desktop work a stray F1/F2/F4 pastes credentials into
; a browser, a chat box, whatever has focus. Deliberately session-only:
; every start is live — pausing is a moment's choice, not a setting.
TogglePastePause(*) {
    global App
    App.PastePaused := !App.PastePaused
    if IsObject(App.Gui)
        RefreshTitle() ; "⏸ paused —" title prefix
    RefreshTrayChecks()
    ShowToast(App.PastePaused
        ? "⏸ F1 / F2 / F4 paused — F10 resumes them"
        : "▶ Paste keys active again")
}

PasteEmail() {
    global App
    if !PasteKeysReady()
        return
    acc := GetPasteTarget()
    if !IsObject(acc)
        return
    PasteText(acc.Email)
}

PastePassword() {
    global App
    if !PasteKeysReady()
        return
    acc := GetPasteTarget()
    if !IsObject(acc)
        return
    PasteText(acc.Password)
    StampLastLogin(acc)
    LinkActiveWindowToAccount(acc)
    if (App.LoginQueue.Length && App.LoginQueue[1] = acc)
        AdvanceLoginQueue()
    else
        NextAccount()
    MaybeAdvanceToNextClient()
}

; Auto-stamps "last logged in" whenever a password is pasted (F2/F4) and
; persists it through the low-friction notes autosave pipeline (debounced,
; atomic, no backup) — shown in the Game Info view's "Last login" column.
StampLastLogin(acc) {
    global App
    acc.LastLogin := FormatTime(, "yyyy-MM-dd HH:mm")
    UpdateRowForAccount(acc) ; the paste target may not be the selected row (pick queue)
    ScheduleNoteAutosave(FindFileOfAccount(acc))
}

; Maps a list of (possibly stale) account refs to the freshly-loaded
; objects with the same emails, dropping any that no longer exist —
; used by Reload for the pick queue and the double-click mini queue.
RepointByEmail(oldList) {
    global App
    fresh := []
    for oldAcc in oldList {
        for fNew in App.Files {
            for accNew in fNew.Accounts {
                if (accNew.Email = oldAcc.Email) {
                    fresh.Push(accNew)
                    break 2
                }
            }
        }
    }
    return fresh
}

; The file object an account belongs to (falls back to the current file
; for safety — every real account lives in exactly one file).
FindFileOfAccount(acc) {
    global App
    for f in App.Files {
        for a in f.Accounts {
            if (a = acc)
                return f
        }
    }
    return App.Files[App.CurrentFile]
}

; Combo: pastes email, tabs to the next field, pastes password, then
; submits with Enter. Uses a single save/restore of the clipboard around
; the whole sequence (rather than chaining two PasteText calls) so the
; async clipboard-restore from an earlier step can't clobber a later one.
PasteComboLogin() {
    global App
    if !PasteKeysReady()
        return
    acc := GetPasteTarget()
    if !IsObject(acc)
        return
    if (acc.Email = "" || acc.Password = "") {
        ShowToast("This account is missing its email or password")
        return
    }

    if !IsObject(App.SavedClip)
        App.SavedClip := ClipboardAll()
    ok := false
    try {
        A_Clipboard := acc.Email
        if !ClipWait(1) {
            ShowToast("Clipboard did not become ready")
            return
        }
        Send("^v")
        Sleep(Config.ComboStepDelayMs)
        Send("{Tab}")
        Sleep(Config.ComboStepDelayMs)

        A_Clipboard := acc.Password
        if !ClipWait(1) {
            ShowToast("Clipboard did not become ready")
            return
        }
        Send("^v")
        Sleep(Config.ComboStepDelayMs)
        Send("{Enter}")
        ok := true
    } catch as err {
        ShowToast("Combo paste failed: " err.Message)
    } finally {
        RestoreClipboard()
    }

    if ok {
        StampLastLogin(acc)
        LinkActiveWindowToAccount(acc)
        if (App.LoginQueue.Length && App.LoginQueue[1] = acc)
            AdvanceLoginQueue()
        else
            NextAccount()
        MaybeAdvanceToNextClient()
    }
}

; The clipboard save/restore is a single shared slot (App.SavedClip) with
; one named timer, not a fresh closure per paste. With per-paste closures,
; two F1/F2 presses inside the restore window raced each other: the first
; timer could restore a stale clipboard mid-second-paste, and the second
; paste "saved" the first paste's secret as the user's clipboard. Now the
; FIRST paste of a burst captures the user's real clipboard, each paste
; just pushes the pending restore back (same named timer = debounce, see
; gotcha #9 in CLAUDE.md), and whatever fires/runs first restores once.
PasteText(text) {
    global App
    if (text = "") {
        ShowToast("Nothing to paste — that field is empty")
        return
    }
    if !IsObject(App.SavedClip)
        App.SavedClip := ClipboardAll()
    try {
        A_Clipboard := text
        if !ClipWait(1) {
            ShowToast("Clipboard did not become ready")
            RestoreClipboard()
            return
        }
        Send("^v")
        SetTimer(RestoreClipboard, -Config.ClipRestoreMs)
    } catch as err {
        RestoreClipboard()
        ShowToast("Paste failed: " err.Message)
    }
}

; Safe to call directly even while the timer is still pending: the slot is
; emptied on first restore, so a later firing is a harmless no-op.
RestoreClipboard() {
    global App
    if IsObject(App.SavedClip) {
        A_Clipboard := App.SavedClip
        App.SavedClip := ""
    }
}

; THE one way to resolve a visible row to its account object.
; App.Displayed entries are either an integer (index into the current
; file — normal mode) or, while a search is active, objects:
;   { Acc, File, Num }  — a matching account (Num = its # in its file)
;   { Sep: fileName, Count: n } — a file separator heading
; Returns "" for separators and out-of-range positions, so callers can
; keep their existing IsObject() guards.
RowAccount(pos) {
    global App
    if (pos < 1 || pos > App.Displayed.Length)
        return ""
    e := App.Displayed[pos]
    if IsObject(e)
        return e.HasOwnProp("Acc") ? e.Acc : ""
    return App.Files[App.CurrentFile].Accounts[e]
}

; What the # column shows for a row: the account's number within its
; own file (search mode) or the display position (normal mode — 1:1).
RowNum(pos) {
    global App
    e := App.Displayed[pos]
    if IsObject(e)
        return e.HasOwnProp("Num") ? e.Num : ""
    return pos
}

; First selectable (non-separator) row at or after `from`; 0 if none.
FirstAccountRow(from := 1) {
    global App
    pos := Max(1, from)
    while (pos <= App.Displayed.Length) {
        if IsObject(RowAccount(pos))
            return pos
        pos++
    }
    return 0
}

GetCurrentAccount() {
    global App
    return RowAccount(App.CurrentDisplayPos)
}

; ============================================================
; NAVIGATION
; ============================================================
NextAccount() {
    global App
    pos := App.CurrentDisplayPos + 1
    while (pos <= App.Displayed.Length && !IsObject(RowAccount(pos)))
        pos++ ; hop over search separators
    if (pos > App.Displayed.Length)
        return
    App.CurrentDisplayPos := pos
    App.Controls.List.Modify(App.CurrentDisplayPos, "Select Focus Vis")
    RefreshDetails()
}

PreviousAccount() {
    global App
    pos := App.CurrentDisplayPos - 1
    while (pos >= 1 && !IsObject(RowAccount(pos)))
        pos-- ; hop over search separators
    if (pos < 1)
        return
    App.CurrentDisplayPos := pos
    App.Controls.List.Modify(App.CurrentDisplayPos, "Select Focus Vis")
    RefreshDetails()
}

NextFile() {
    global App
    if App.EditDialogOpen
        return
    RememberPositionForCurrentFile()
    App.CurrentFile++
    if (App.CurrentFile > App.Files.Length)
        App.CurrentFile := 1
    SwitchFile()
}

PreviousFile() {
    global App
    if App.EditDialogOpen
        return
    RememberPositionForCurrentFile()
    App.CurrentFile--
    if (App.CurrentFile < 1)
        App.CurrentFile := App.Files.Length
    SwitchFile()
}

; Records which account we were on in the file we're about to leave, so
; coming back to it later this session (via F3/Shift+F3) returns you to
; the same spot instead of resetting to the top. Keyed by Email rather
; than Name, since Name isn't guaranteed unique (e.g. placeholder names
; like "x" repeated across a whole file) but Email realistically is.
RememberPositionForCurrentFile() {
    global App
    if (App.Files.Length = 0)
        return
    acc := GetCurrentAccount()
    if IsObject(acc)
        App.LastPositionPerFile[App.Files[App.CurrentFile].Name] := acc.Email
}

SwitchFile() {
    global App
    App.CurrentDisplayPos := 1
    RefreshTitle()
    ApplyFilter(App.FilterText)
    RestorePendingAccountPosition()
}

; Jumps to a remembered account by Email within the current file, if one
; is set. Checks an explicit one-shot override first (used by Reload, to
; restore exactly where you were before it ran), then falls back to
; this file's remembered position from LastPositionPerFile.
RestorePendingAccountPosition() {
    global App
    targetEmail := App.PendingRestoreAccountEmail
    App.PendingRestoreAccountEmail := ""

    if (targetEmail = "") {
        fileName := App.Files[App.CurrentFile].Name
        if App.LastPositionPerFile.Has(fileName)
            targetEmail := App.LastPositionPerFile[fileName]
    }
    if (targetEmail = "")
        return

    loop App.Displayed.Length {
        acc := RowAccount(A_Index)
        if (IsObject(acc) && acc.Email = targetEmail) {
            App.CurrentDisplayPos := A_Index
            App.Controls.List.Modify(A_Index, "Select Focus Vis")
            RefreshDetails()
            break
        }
    }
}

; ============================================================
; PICK QUEUE (hand-picked login order, F8)
; ------------------------------------------------------------
; Toggle pick mode, click accounts in ANY files in the order you want
; them logged in (click again to remove), toggle off — or just start
; pressing F4. While the queue has entries, F1/F2/F4 target its HEAD
; instead of the selected row, and each completed login pops the head
; and navigates the list to the next one, switching files as needed.
; Session-only, cleared every time pick mode is re-entered.
; ============================================================
GetPasteTarget() {
    global App
    return App.LoginQueue.Length ? App.LoginQueue[1] : GetCurrentAccount()
}

LoginQueueIndex(acc) {
    global App
    for i, a in App.LoginQueue {
        if (a = acc)
            return i
    }
    return 0
}

TogglePickMode(*) {
    global App
    if (App.EditDialogOpen || App.LoginRunning)
        return
    if !App.PickMode {
        App.PickMode := true
        App.LoginQueue := [] ; fresh pick every time — this is a temp plan
        ShowToast("Pick mode — click accounts in login order (F3 to switch files). F8 to finish.")
    } else {
        App.PickMode := false
        ShowToast(App.LoginQueue.Length
            ? "Queue ready: " App.LoginQueue.Length " account(s) — F4 works through them"
            : "Pick mode off")
        ; Jump the list to the first pick so F4 starts visibly.
        if App.LoginQueue.Length
            FocusAccountInUI(App.LoginQueue[1])
    }
    RefreshPickUI()
    UpdateAllRowsInPlace()
}

; Click handler — only does anything in pick mode (selection sync is
; ItemSelect's job); clicking toggles queue membership.
OnListClick(ctrl, row) {
    global App
    if (!App.PickMode || row < 1)
        return
    acc := RowAccount(row)
    if IsObject(acc) ; separator rows aren't pickable
        TogglePickMembership(acc)
}

; One in/out toggle for the pick queue — list rows and board cells
; share it, so their refresh side effects can't drift apart.
TogglePickMembership(acc) {
    global App
    idx := LoginQueueIndex(acc)
    if idx
        App.LoginQueue.RemoveAt(idx)
    else
        App.LoginQueue.Push(acc)
    RefreshPickUI()
    UpdateAllRowsInPlace() ; queue numbers in the # column shift
    RefreshSummary()
}

AdvanceLoginQueue() {
    global App
    App.LoginQueue.RemoveAt(1)
    if (App.LoginQueue.Length = 0) {
        App.PickMode := false
        ShowToast("Pick queue finished")
        RefreshList()
    } else {
        FocusAccountInUI(App.LoginQueue[1])
        UpdateAllRowsInPlace()
    }
    RefreshPickUI()
    RefreshSummary()
}

; Puts the UI on a specific account: switches to its file if needed and
; selects its row (via the existing email-based position restore).
FocusAccountInUI(acc) {
    global App
    for i, f in App.Files {
        for a in f.Accounts {
            if (a != acc)
                continue
            if (i != App.CurrentFile) {
                RememberPositionForCurrentFile()
                App.CurrentFile := i
                App.PendingRestoreAccountEmail := acc.Email
                SwitchFile()
            } else {
                loop App.Displayed.Length {
                    if (RowAccount(A_Index) = acc) {
                        App.CurrentDisplayPos := A_Index
                        App.Controls.List.Modify(A_Index, "Select Focus Vis")
                        RefreshDetails()
                        break
                    }
                }
            }
            return
        }
    }
}

; Bulk-add accounts to the pick queue (in list order): "file" = current
; file, "all" = every file. Skips ones already queued; no dupes.
PickAll(scope) {
    global App
    App.PickMode := true
    files := (scope = "all") ? App.Files : [App.Files[App.CurrentFile]]
    for f in files {
        for acc in f.Accounts {
            if !LoginQueueIndex(acc)
                App.LoginQueue.Push(acc)
        }
    }
    RefreshPickUI()
    UpdateAllRowsInPlace()
    RefreshSummary()
    ShowToast(App.LoginQueue.Length " account(s) picked")
}

ClearPickQueue() {
    global App
    App.LoginQueue := []
    App.PickMode := false
    RefreshPickUI()
    UpdateAllRowsInPlace()
    RefreshSummary()
    ShowToast("Pick queue cleared")
}

RefreshPickUI() {
    global App
    App.Controls.PickBtn.Text := App.PickMode
        ? "⏹ Picking " App.LoginQueue.Length
        : (App.LoginQueue.Length ? "⊕ " App.LoginQueue.Length " left" : "⊕ Pick")
}

; ============================================================
; ONLINE VIEW (F9 / 👁 button)
; ------------------------------------------------------------
; One live window listing every currently-linked account across ALL
; files: name, file, client #, online minutes, time left. Refreshed by
; the housekeeping tick while open. Double-click a row to jump to its
; client (cloak-aware — works across virtual desktops).
; ============================================================
OpenOnlineView(*) {
    global App
    if IsObject(App.OnlineDlg) {
        try App.OnlineDlg.Show()
        RefreshOnlineView()
        return
    }

    dlg := Gui("+Owner" App.Gui.Hwnd, "Online — Account Queue")
    dlg.BackColor := Colors.Bg
    dlg.MarginX := 12
    dlg.MarginY := 10
    dlg.SetFont("s9 c" Colors.Text, Config.FontMain)

    lv := dlg.Add("ListView", "xm w440 h240 -Multi NoSort", ["Name", "File", "Client", "Online", "Left"])
    lv.ModifyCol(1, 130)
    lv.ModifyCol(2, 100)
    lv.ModifyCol(3, 52)
    lv.ModifyCol(4, 62)
    lv.ModifyCol(5, 80)
    dlg.OnlineList := lv
    dlg.OnlineAccts := []
    lv.OnEvent("DoubleClick", OnlineViewJump)

    dlg.SetFont("s8 Norm Italic c" Colors.TextDim, Config.FontMain)
    dlg.Add("Text", "xm y+6", "double-click = jump to client · live")

    ApplyDialogDarkMode(dlg, [], [lv])
    dlg.OnEvent("Close", (*) => CloseOnlineView(dlg))
    dlg.OnEvent("Escape", (*) => CloseOnlineView(dlg))

    App.OnlineDlg := dlg
    RefreshOnlineView()
    dlg.Show("AutoSize")
}

CloseOnlineView(dlg) {
    global App
    App.OnlineDlg := ""
    try dlg.Destroy()
}

RefreshOnlineView() {
    global App
    if !IsObject(App.OnlineDlg)
        return
    goalMs := Config.SessionGoalMinutes * 60000
    rows := []
    for f in App.Files {
        for acc in f.Accounts {
            if acc.HasOwnProp("ClientHwnd")
                rows.Push({ Acc: acc, FileName: f.Name })
        }
    }
    ; Order by client session number — matches the windows on screen.
    n := rows.Length
    loop n - 1 {
        i := A_Index
        loop n - i {
            j := A_Index
            if (rows[j].Acc.ClientSession > rows[j + 1].Acc.ClientSession) {
                tmp := rows[j]
                rows[j] := rows[j + 1]
                rows[j + 1] := tmp
            }
        }
    }

    lv := App.OnlineDlg.OnlineList
    lv.Delete()
    App.OnlineDlg.OnlineAccts := []
    for r in rows {
        online := AccountOnlineMs(r.Acc)
        leftTxt := (online >= goalMs) ? "✔ done" : Ceil((goalMs - online) / 60000) " min left"
        lv.Add("", r.Acc.Name, r.FileName, "#" r.Acc.ClientSession, Floor(online / 60000) " min", leftTxt)
        App.OnlineDlg.OnlineAccts.Push(r.Acc)
    }
    if (rows.Length = 0)
        lv.Add("", "— nothing online —", "", "", "", "")
}

OnlineViewJump(lv, row) {
    global App
    if (row < 1 || !IsObject(App.OnlineDlg) || row > App.OnlineDlg.OnlineAccts.Length)
        return
    acc := App.OnlineDlg.OnlineAccts[row]
    if !ActivateAnyDesktop(acc.ClientHwnd)
        ShowToast("That client window isn't open anymore")
}

; ============================================================
; WINDOW LINKING
; ------------------------------------------------------------
; No arming step: every F2/F4 links the account to whatever game client
; the paste actually landed in (the active window), and — if Auto-next
; client is on — then activates an open client that hasn't been used
; yet. Purely positional bookkeeping — it doesn't (and can't) know
; whether a client is actually logged in, only which window a paste
; was pointed at.
; ============================================================

; Links an account to the window its password was just pasted into.
; Ignores non-game windows entirely (pasting into a browser or notepad
; links nothing). If another account owned this window, ownership
; transfers — same semantics as the manual right-click link.
LinkActiveWindowToAccount(acc) {
    global App
    hwnd := 0
    try hwnd := WinGetID("A")
    if !hwnd
        return
    procName := ""
    try procName := WinGetProcessName("ahk_id " hwnd)
    if (procName != Config.GameProcess)
        return

    transferred := false
    for f in App.Files {
        for other in f.Accounts {
            if (other.HasOwnProp("ClientHwnd") && other.ClientHwnd = hwnd && other != acc) {
                DetachClient(other) ; banks the other account's online time
                transferred := true
            }
        }
    }

    if !App.WindowSessionNumbers.Has(hwnd) {
        App.NextSessionNumber += 1
        App.WindowSessionNumbers[hwnd] := App.NextSessionNumber
    }
    DetachClient(acc) ; re-login: bank any current period before restarting the clock
    acc.ClientSession := App.WindowSessionNumbers[hwnd]
    acc.ClientHwnd := hwnd
    acc.LinkTime := A_TickCount
    App.UsedWindowHwnds[hwnd] := true

    ; A transfer may have cleared another visible row's Client cell;
    ; otherwise only the target's row changed (which may not be the
    ; selected row when the pick queue is driving).
    if transferred
        RefreshList()
    else
        UpdateRowForAccount(acc)
    RefreshLinkStatus()
}

; After a paste (and only if the checkbox/F5 option is on): activate the
; leftmost open game client that hasn't been used yet, so the next F4
; lands on a fresh client. Left-to-right by screen position — the
; closest reliable equivalent to taskbar order, since taskbar button
; order isn't readable on Windows 11 (gotcha #6).
MaybeAdvanceToNextClient() {
    global App
    if !App.AutoNextClient
        return

    ; Forget any used windows that no longer exist, so stale handles
    ; don't linger in the exclusion set forever.
    PruneUsedWindows()

    found := WinGetList("ahk_exe " Config.GameProcess)
    if (found.Length = 0)
        return ; no clients open at all — user isn't in the window flow

    candidates := []
    for hwnd in found {
        if App.UsedWindowHwnds.Has(hwnd)
            continue
        ; Never jump to a window that's hosting a linked account, even if
        ; the used-set somehow lost it — an occupied client is occupied.
        if (FindAccountNameForWindow(hwnd) != "")
            continue
        candidates.Push(hwnd)
    }
    if (candidates.Length = 0) {
        ShowToast("All open clients are used — open more, or click Forget Used")
        RefreshLinkStatus()
        return
    }

    candidates := SortByScreenPosition(candidates)
    ; Give the client a moment to actually process the paste before we
    ; steal focus away from it.
    Sleep(Config.WindowSwitchDelayMs)
    try WinActivate("ahk_id " candidates[1])
    RefreshLinkStatus()
}

ToggleAutoNextClient(*) {
    global App
    App.AutoNextClient := App.Controls.AutoNextToggle.Value = 1
    RefreshLinkStatus()
    SaveSettings()
}

ToggleAutoNextFromHotkey(*) {
    global App
    if App.EditDialogOpen
        return
    App.Controls.AutoNextToggle.Value := App.AutoNextClient ? 0 : 1
    ToggleAutoNextClient()
    ShowToast("Auto-next client " (App.AutoNextClient ? "ON" : "OFF"))
}

SortByScreenPosition(hwnds) {
    positions := Map()
    for hwnd in hwnds {
        try {
            WinGetPos(&wx, &wy, , , "ahk_id " hwnd)
            positions[hwnd] := { X: wx, Y: wy }
        } catch {
            positions[hwnd] := { X: 999999, Y: 999999 } ; unreadable position sorts last
        }
    }
    n := hwnds.Length
    loop n - 1 {
        i := A_Index
        loop n - i {
            j := A_Index
            a := positions[hwnds[j]]
            b := positions[hwnds[j + 1]]
            if (a.X > b.X || (a.X = b.X && a.Y > b.Y)) {
                tmp := hwnds[j]
                hwnds[j] := hwnds[j + 1]
                hwnds[j + 1] := tmp
            }
        }
    }
    return hwnds
}

; ============================================================
; ONLINE-TIME BOOKKEEPING (Session view)
; ------------------------------------------------------------
; Every account accumulates "online" milliseconds across its link
; periods: LinkTime marks when the current link started; OnlineMs holds
; the banked time from earlier periods. Detaching (window closed,
; unlink, ownership transfer, re-login) BANKS the elapsed time before
; clearing the link — so closing a finished client never loses the 30
; minutes it earned. Session-only, never written to the .txt files.
; ============================================================
AccountOnlineMs(acc) {
    total := acc.HasOwnProp("OnlineMs") ? acc.OnlineMs : 0
    if (acc.HasOwnProp("ClientHwnd") && acc.HasOwnProp("LinkTime"))
        total += A_TickCount - acc.LinkTime
    return total
}

; The game's day flips at Config.DayResetHour (02:00) — so "today" for
; session stats is the calendar date of (now - 2h). Stats reset when
; this stamp changes, and persisted stats from a different stamp are
; discarded on load.
GameDayStamp() {
    return FormatTime(DateAdd(A_Now, -Config.DayResetHour, "Hours"), "yyyyMMdd")
}

; 02:00 rollover: wipe every account's online time. Accounts still
; linked keep their link and start counting the NEW day from now.
ResetSessionStats() {
    global App
    for f in App.Files {
        for acc in f.Accounts {
            acc.DeleteProp("OnlineMs")
            if acc.HasOwnProp("LinkTime")
                acc.LinkTime := A_TickCount
        }
    }
}

; Online minutes survive app restarts WITHIN a game day: persisted to
; Settings.ini [SessionTimes] keyed by email, stamped with the game day
; they belong to. A stamp mismatch on load means the 02:00 boundary
; passed while the app was closed — discard.
SaveSessionTimes() {
    global App
    try IniDelete(Config.SettingsPath, "SessionTimes")
    try IniWrite(App.CurrentGameDay, Config.SettingsPath, "SessionTimes", "__gameday")
    for f in App.Files {
        for acc in f.Accounts {
            total := AccountOnlineMs(acc)
            if (total > 0)
                try IniWrite(total, Config.SettingsPath, "SessionTimes", acc.Email)
        }
    }
}

LoadSessionTimes() {
    global App
    if !FileExist(Config.SettingsPath)
        return
    storedDay := ""
    try storedDay := IniRead(Config.SettingsPath, "SessionTimes", "__gameday", "")
    if (storedDay != App.CurrentGameDay) {
        try IniDelete(Config.SettingsPath, "SessionTimes") ; stale game day
        return
    }
    raw := ""
    try raw := IniRead(Config.SettingsPath, "SessionTimes")
    for line in StrSplit(raw, "`n", "`r") {
        eq := InStr(line, "=")
        if (!eq || SubStr(line, 1, eq - 1) = "__gameday")
            continue
        email := SubStr(line, 1, eq - 1)
        ms := 0
        try ms := Integer(SubStr(line, eq + 1))
        if (ms <= 0)
            continue
        for f in App.Files {
            for acc in f.Accounts {
                if (acc.Email = email)
                    acc.OnlineMs := ms
            }
        }
    }
}

IsAccountDone(acc) {
    return AccountOnlineMs(acc) >= Config.SessionGoalMinutes * 60000
}

; Parks the pointer back where the user left it — but never immediately.
; The final click of a macro/routine is still being processed by the
; game when playback ends; an instant MouseMove made that click register
; at the cursor's destination instead (classically: on the "Test on
; client" button that started the run, following it around the screen).
; Config.MouseRestoreDelayMs = 0 leaves the pointer where playback ended.
RestorePointerAfterPlayback(x, y) {
    if (Config.MouseRestoreDelayMs <= 0)
        return false
    Sleep(Config.MouseRestoreDelayMs)
    MouseMove(x, y, 0)
    return true
}

; Linked AND its client window actually exists (cloak-aware). The one
; way to ask "is this account online right now?" — nine call sites used
; to inline this pair.
AccountIsOnline(acc) {
    return acc.HasOwnProp("ClientHwnd") && WinExistAnyDesktop(acc.ClientHwnd)
}

; Banks the current link period's time, then removes the link. The ONLY
; correct way to clear ClientHwnd/ClientSession — deleting the props
; directly would silently drop earned online time.
DetachClient(acc) {
    if (acc.HasOwnProp("ClientHwnd") && acc.HasOwnProp("LinkTime"))
        acc.OnlineMs := (acc.HasOwnProp("OnlineMs") ? acc.OnlineMs : 0)
            + Max(0, A_TickCount - acc.LinkTime)
    acc.DeleteProp("ClientSession")
    acc.DeleteProp("ClientHwnd")
    acc.DeleteProp("LinkTime")
    acc.DeleteProp("MissingTicks")
    acc.DeleteProp("_macroRan")
    acc.DeleteProp("_macroIdx") ; a relogged account restarts its playlist
}

ClearAccountTagsForWindow(hwnd) {
    global App
    for f in App.Files {
        for acc in f.Accounts {
            if (acc.HasOwnProp("ClientHwnd") && acc.ClientHwnd = hwnd)
                DetachClient(acc)
        }
    }
}

; Activates the client window an account was last pasted into, if it's
; still open. This is what "double-click to jump to a client" calls.
JumpToAccountWindow() {
    global App
    acc := GetCurrentAccount()
    if !IsObject(acc)
        return
    if !acc.HasOwnProp("ClientHwnd") {
        ShowToast("This account hasn't been linked to a client window yet")
        return
    }
    if !ActivateAnyDesktop(acc.ClientHwnd)
        ShowToast("That client window isn't open anymore")
}

; Right-click menu handler: lets you manually link a row to any
; currently-open game window (e.g. one you were already logged into
; before opening the script), or unlink it.
OnListContextMenu(ctrl, itemPos, isRightClick, x, y) {
    global App
    if App.EditDialogOpen
        return
    if (itemPos < 1)
        return
    App.CurrentDisplayPos := itemPos
    RefreshDetails()

    acc := GetCurrentAccount()
    if !IsObject(acc)
        return

    ctxMenu := Menu()
    ; Quick clipboard grabs — for the odd case outside the F1/F2/F4 flow
    ; (registering somewhere, support forms). Deliberately NOT routed
    ; through the paste-restore pipeline: an explicit copy should stay
    ; on the clipboard.
    ctxMenu.Add("📋 Copy email", (*) => (A_Clipboard := acc.Email, ShowToast("Email copied")))
    ctxMenu.Add("📋 Copy password", (*) => (A_Clipboard := acc.Password, ShowToast("Password copied")))
    ctxMenu.Add()

    ; Pick-queue building: THIS account (no pick mode needed — the queue
    ; drives F1/F2/F4 the moment it has entries), or in bulk.
    qi := LoginQueueIndex(acc)
    ctxMenu.Add(qi ? "✖ Unpick this account  (»" qi ")" : "⊕ Pick this account"
        , (*) => TogglePickMembership(acc))
    ctxMenu.Add("➕ Pick all in this file", (*) => PickAll("file"))
    ctxMenu.Add("➕ Pick all (every file)", (*) => PickAll("all"))
    if App.LoginQueue.Length
        ctxMenu.Add("🗑 Clear pick queue (" App.LoginQueue.Length ")", (*) => ClearPickQueue())
    ctxMenu.Add()

    ; The account's client, right here: jump/close when it has one,
    ; launch+login when it doesn't (same gesture as double-click, made
    ; discoverable — its guards just toast, never pop dialogs).
    if acc.HasOwnProp("ClientHwnd") {
        ctxMenu.Add("🗔 Jump to its client  (#" acc.ClientSession ")", (*) => JumpToAccountWindow())
        ctxMenu.Add("🚪 Close its client (time is banked)", (*) => CloseAccountClient(acc))
    } else {
        ctxMenu.Add("🚀 Launch + log this account in", (*) => LaunchLoginSingle(acc))
    }

    ; Manual linking lives in a submenu: 20 open clients used to dump 20
    ; window entries into the middle of this menu.
    linkMenu := Menu()
    found := WinGetList("ahk_exe " Config.GameProcess)
    if (found.Length = 0) {
        linkMenu.Add("No " Config.GameProcess " windows found", (*) => 0)
        linkMenu.Disable("No " Config.GameProcess " windows found")
    } else {
        ; The index prefix keeps every label unique. Menu.Add treats a
        ; same-name add as an UPDATE of the existing item, so two windows
        ; that describe identically (e.g. both unlinked at the same
        ; position) would otherwise collapse into one entry pointing at
        ; only the second window.
        for i, hwnd in found
            linkMenu.Add(i ". " DescribeWindowForMenu(hwnd), LinkAccountToSpecificWindow.Bind(acc, hwnd))
    }
    ctxMenu.Add("🔗 Link to a window", linkMenu)
    if acc.HasOwnProp("ClientHwnd") {
        ctxMenu.Add("Unlink this account's window", (*) => UnlinkAccountWindow(acc))
        ctxMenu.Add()

        ; Run (or queue) any macro OR routine — they're interchangeable
        ; everywhere else (0.32.0); this menu listing only macros was an
        ; oversight, not a decision.
        names := AutomationNames()
        runMenu := Menu()
        queueMenu := Menu()
        if (names.Length = 0) {
            for sub in [runMenu, queueMenu] {
                sub.Add("No macros recorded yet — 🎬 Macros to record one", (*) => 0)
                sub.Disable("No macros recorded yet — 🎬 Macros to record one")
            }
        } else {
            for aName in names {
                runMenu.Add(aName, RunMacroForAccount.Bind(acc, aName))
                queueMenu.Add(aName, QueueMacroForAccount.Bind(acc, aName))
            }
        }
        ctxMenu.Add("▶ Run macro / routine on its client", runMenu)
        ctxMenu.Add("➕ Queue macro / routine on its client", queueMenu)
    }

    ctxMenu.Show()
}

; Builds a menu label that disambiguates otherwise-identical windows by
; session number, current owner (if any), and screen position.
DescribeWindowForMenu(hwnd) {
    global App
    label := App.WindowSessionNumbers.Has(hwnd) ? ("Window #" App.WindowSessionNumbers[hwnd]) : "Unlinked window"
    owner := FindAccountNameForWindow(hwnd)
    if (owner != "")
        label .= " — currently: " owner
    try {
        WinGetPos(&wx, &wy, , , "ahk_id " hwnd)
        label .= "  [" wx "," wy "]"
    }
    return label
}

FindAccountNameForWindow(hwnd) {
    global App
    for f in App.Files {
        for acc in f.Accounts {
            if (acc.HasOwnProp("ClientHwnd") && acc.ClientHwnd = hwnd)
                return acc.Name
        }
    }
    return ""
}

LinkAccountToSpecificWindow(acc, hwnd, *) {
    global App
    if !WinExist("ahk_id " hwnd) {
        ShowToast("That window isn't open anymore")
        return
    }

    prevOwner := FindAccountNameForWindow(hwnd)
    ClearAccountTagsForWindow(hwnd)

    if !App.WindowSessionNumbers.Has(hwnd) {
        App.NextSessionNumber += 1
        App.WindowSessionNumbers[hwnd] := App.NextSessionNumber
    }
    DetachClient(acc) ; bank any current period before switching windows
    acc.ClientSession := App.WindowSessionNumbers[hwnd]
    acc.ClientHwnd := hwnd
    acc.LinkTime := A_TickCount
    ; Also mark it used, so Auto-next client won't jump to this window
    ; and paste a different account into it.
    App.UsedWindowHwnds[hwnd] := true

    RefreshList()
    RefreshLinkStatus()
    msg := acc.Name " linked to window #" acc.ClientSession
    if (prevOwner != "" && prevOwner != acc.Name)
        msg .= " (was: " prevOwner ")"
    ShowToast(msg)
}

UnlinkAccountWindow(acc) {
    DetachClient(acc) ; banks its online time — unlinking isn't forgetting
    RefreshList()
    ShowToast("Unlinked")
}

; Row-menu action: close a linked account's client window from the list
; — the single-account version of the console's "Close done", minus the
; goal check (an explicit menu click is its own confirmation).
; DetachClient banks the online time BEFORE the window goes (invariant).
CloseAccountClient(acc) {
    if !acc.HasOwnProp("ClientHwnd")
        return
    hwnd := acc.ClientHwnd
    DetachClient(acc)
    try WinClose("ahk_id " hwnd)
    RefreshList()
    RefreshLinkStatus()
    RefreshSummary()
    ShowToast(acc.Name " closed — " Round(AccountOnlineMs(acc) / 60000) " min banked today")
}

; Forgets tracked "used" windows so they become linkable again — for when
; you genuinely want to redo a window rather than open a fresh one.
ForgetUsedWindows(*) {
    global App
    App.UsedWindowHwnds := Map()
    ShowToast("Cleared used-window tracking")
    RefreshLinkStatus()
}

; Cloak-aware liveness check: clients on another virtual desktop are
; CLOAKED, which default detection reports as gone (measured on this
; machine — Cloaked=2, ExistOff=0, IsWindow=1). ALL "is this client
; window still alive?" checks must go through this, never raw WinExist.
WinExistAnyDesktop(hwnd) {
    prevDHW := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    found := WinExist("ahk_id " hwnd)
    DetectHiddenWindows(prevDHW)
    return found
}

; Cloak-aware activation — jumping to a client on the other virtual
; desktop takes you there instead of wrongly claiming it closed.
; Returns false if the window is genuinely gone.
ActivateAnyDesktop(hwnd) {
    prevDHW := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    ok := false
    if WinExist("ahk_id " hwnd) {
        try WinActivate("ahk_id " hwnd)
        ok := true
    }
    DetectHiddenWindows(prevDHW)
    return ok
}

PruneUsedWindows() {
    global App
    stale := []
    for hwnd, _ in App.UsedWindowHwnds {
        if !WinExistAnyDesktop(hwnd)
            stale.Push(hwnd)
    }
    for hwnd in stale
        App.UsedWindowHwnds.Delete(hwnd)
}

; Every REAL game client window, whichever virtual desktop it lives on:
; hidden-aware enumeration (so cloaked windows count) filtered by
; IsWindowVisible (so the game's dozens of genuinely hidden helper
; windows don't — measured: 20 real clients, 60 hidden-aware matches).
GetGameClientWindows() {
    prevDHW := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    wins := []
    for hwnd in WinGetList("ahk_exe " Config.GameProcess) {
        if DllCall("IsWindowVisible", "ptr", hwnd)
            wins.Push(hwnd)
    }
    DetectHiddenWindows(prevDHW)
    return wins
}

; Runs every few seconds (started at startup). Two jobs:
; 1. Clear the Client column for accounts whose window has closed —
;    banking their online time first (see DetachClient).
; 2. Keep the Session view's live minute counters ticking.
;
; Two robustness rules, both learned from a real incident where every
; link vanished while all clients were still running:
; - WinExistAnyDesktop: cloaked (other virtual desktop) and hidden
;   windows are still alive; default detection treats them as gone.
; - Two-strike rule: a window must be missing on TWO consecutive ticks
;   before its link is dropped, so a transient flicker can't mass-detach.
PeriodicHousekeeping() {
    global App
    changed := false

    ; 02:00 game-day rollover — reset all session stats the moment the
    ; boundary passes while the app is running.
    if (GameDayStamp() != App.CurrentGameDay) {
        App.CurrentGameDay := GameDayStamp()
        ResetSessionStats()
        SaveSessionTimes()
        changed := true
        ShowToast("New game day (0" Config.DayResetHour ":00) — session timers reset")
        ; A new day resets every idle job's per-account "done" and may
        ; bring a new quota (clears yesterday's).
        ResetIdleDone()
        RefreshQuotaBanner()
    }

    ; Unattended: track how long the user's really been away, then work
    ; through the idle jobs. (Tracking first — the watcher reads AwayMs.)
    UpdateAwayTracking()
    MaybeRunIdleJobs()
    RefreshIdleStatusLine() ; no-op unless the Idle Actions window is open

    for f in App.Files {
        for acc in f.Accounts {
            if !acc.HasOwnProp("ClientHwnd")
                continue
            if WinExistAnyDesktop(acc.ClientHwnd) {
                if acc.HasOwnProp("MissingTicks")
                    acc.DeleteProp("MissingTicks")
                continue
            }
            misses := (acc.HasOwnProp("MissingTicks") ? acc.MissingTicks : 0) + 1
            if (misses >= 2) {
                DetachClient(acc)
                changed := true
            } else {
                acc.MissingTicks := misses
            }
        }
    }
    if changed
        PruneUsedWindows()
    if (changed || App.ViewMode = "session") {
        UpdateAllRowsInPlace()
        ; RefreshSummary, NOT RefreshDetails: the latter rewrites the
        ; note/game edit boxes, which would reset the caret mid-typing.
        RefreshSummary()
    }
    RefreshLinkStatus()
    RefreshBoard() ; day board ticks with the same cadence (diffed — cheap)
    RefreshOnlineView() ; no-op unless the Online window is open

    ; Crash-resilience: persist the day's online minutes about once a
    ; minute (and on close), so a crash can't cost more than that.
    static ticksSinceSave := 0
    ticksSinceSave += 1
    if (ticksSinceSave >= 12) {
        ticksSinceSave := 0
        SaveSessionTimes()
    }
}

; Rewrites every visible row's cells without Delete()+Add — no flicker,
; selection and scroll position untouched. Separator rows are static.
UpdateAllRowsInPlace() {
    global App
    loop App.Displayed.Length {
        acc := RowAccount(A_Index)
        if IsObject(acc)
            App.Controls.List.Modify(A_Index, "", BuildRowCells(RowNum(A_Index), acc)*)
    }
}

RefreshLinkStatus() {
    global App
    ; The auto-login orchestrator owns the status line while it runs.
    if App.LoginRunning {
        App.Controls.LinkStatus.Value := App.LoginStatusText
            . (App.PendingSingles.Length ? "  ·  ⌛ " App.PendingSingles.Length " next" : "")
            . "   (F7 stops)"
        return
    }
    ; While the queue is active (or holding jobs), it owns the status line.
    if App.QueueRunning {
        runningDesc := ""
        for job in App.Queue {
            if (job.Status = "running")
                runningDesc := "  ·  " job.Macro " → " job.Label
        }
        App.Controls.LinkStatus.Value := "Queue " QueueDoneCount() "/" App.Queue.Length runningDesc "   (Esc/F7 stops)"
        return
    }
    if (App.QueuePaused && QueueHasWaiting()) {
        App.Controls.LinkStatus.Value := "Queue paused · " (App.Queue.Length - QueueDoneCount()) " left  →  🎬 Macros"
        return
    }
    total := 0
    unused := 0
    try {
        ; Cloak-aware count — the status line must not claim "no clients
        ; open" just because you're looking from the other virtual desktop.
        found := GetGameClientWindows()
        total := found.Length
        for hwnd in found {
            if !App.UsedWindowHwnds.Has(hwnd)
                unused += 1
        }
    }
    newText := (total = 0)
        ? "No clients open"
        : "Clients: " total " open  ·  " unused " fresh"
    if (App.Controls.LinkStatus.Value != newText)
        App.Controls.LinkStatus.Value := newText
}

; ============================================================
; MACROS (recorded click sequences)
; ------------------------------------------------------------
; Left-clicks only, on purpose: recorded keystrokes would write
; passwords into plain-text macro files — credentials stay on F1/F2/F4.
; Clicks are stored relative to the game WINDOW (plus its size at record
; time), so one macro replays on any client wherever it sits, scaled if
; the window was resized. Real pauses between clicks are recorded as the
; step delays, so "wait here for the loading screen" is just... waiting,
; while recording. Files live in Logins\Macros\<name>.txt, one step per
; line — hand-editable, same pipe format spirit as the login files.
; ============================================================

; --- recording ---
ToggleMacroRecording(*) {
    global App
    if (App.MacroPlaying || App.LoginRunning)
        return ; F7 during playback/login is the abort key, not a record toggle
    if App.IsRecording {
        StopMacroRecording()
        return
    }
    App.IsRecording := true
    App.RecordingSteps := []
    App.RecordingRefW := 0
    App.RecordingRefH := 0
    App.RecordingLastTick := A_TickCount
    Hotkey("~LButton", OnRecordedClick, "On") ; ~ = game still gets the click
    App.Gui.Title := "● RECORDING — click in the game, F7 to stop"
    ShowToast("Recording — click in the game. F7 to stop.")
}

; Pass-through LButton hook, active only while recording. Only clicks
; that land on a game client window become steps; everything else
; (desktop, this app, browser) is ignored.
OnRecordedClick(*) {
    global App
    if !App.IsRecording
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my, &underHwnd)
    if !underHwnd
        return
    procName := ""
    try procName := WinGetProcessName("ahk_id " underHwnd)
    if (procName != Config.GameProcess)
        return
    try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " underHwnd)
    catch
        return

    now := A_TickCount
    delay := now - App.RecordingLastTick
    App.RecordingLastTick := now
    if (App.RecordingSteps.Length = 0) {
        delay := 0 ; time spent before the first click isn't part of the macro
        App.RecordingRefW := ww
        App.RecordingRefH := wh
    }
    App.RecordingSteps.Push({ X: mx - wx, Y: my - wy, Delay: Min(delay, Config.MacroMaxStepDelayMs) })
    ShowToast("Recorded step " App.RecordingSteps.Length)
}

StopMacroRecording() {
    global App
    App.IsRecording := false
    try Hotkey("~LButton", "Off")
    RefreshTitle() ; drop the "● RECORDING" title

    steps := App.RecordingSteps
    App.RecordingSteps := []
    if (steps.Length = 0) {
        ShowToast("Recording stopped — no game clicks captured, nothing saved")
        ShowMacroManagerAgain()
        return
    }

    ; Name it (loop until a usable name, an explicit overwrite, or cancel)
    name := ""
    loop {
        ib := ShowInput("Name this macro (" steps.Length " click(s)):", "Save Macro", name)
        if (ib.Result != "OK") {
            ShowToast("Recording discarded")
            ShowMacroManagerAgain()
            return
        }
        name := SanitizeMacroName(ib.Value)
        if (name = "") {
            ShowConfirm("That name is empty or only had characters that can't be used in a filename.", "Account Queue", "Icon!")
            continue
        }
        if FileExist(Config.MacrosFolder "\" name ".txt") {
            if (ShowConfirm("A macro named `"" name "`" already exists. Overwrite it?", "Confirm Overwrite", "YesNo Icon?") = "Yes")
                break
            continue
        }
        break
    }

    try {
        SaveMacroFile(name, steps, App.RecordingRefW, App.RecordingRefH)
        ShowToast("Macro `"" name "`" saved (" steps.Length " steps)")
    } catch as err {
        ShowConfirm("Could not save macro:`n" err.Message, "Account Queue", "IconX")
    }
    ShowMacroManagerAgain()
}

; --- files ---
SanitizeMacroName(s) {
    for ch in ["\", "/", ":", "*", "?", '"', "<", ">", "|"]
        s := StrReplace(s, ch, "")
    return Trim(s)
}

SaveMacroFile(name, steps, refW, refH) {
    if !DirExist(Config.MacrosFolder)
        DirCreate(Config.MacrosFolder)
    content := "; Account Queue macro — recorded " FormatTime(, "yyyy-MM-dd HH:mm") "`n"
        . "; ref|w|h = game window size at record time (playback scales to fit)`n"
        . "; click|x|y|delayMs — x/y relative to the window, delay waited BEFORE the click`n"
        . "ref|" refW "|" refH "`n"
    for step in steps
        content .= "click|" step.X "|" step.Y "|" step.Delay "`n"

    AtomicWriteText(Config.MacrosFolder "\" name ".txt", content)
}

LoadMacroFile(name) {
    path := Config.MacrosFolder "\" name ".txt"
    macro := { Name: name, RefW: 0, RefH: 0, Steps: [] }
    for line in StrSplit(FileRead(path, "UTF-8"), "`n", "`r") {
        line := Trim(line)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        parts := StrSplit(line, "|")
        if (parts[1] = "ref" && parts.Length >= 3) {
            macro.RefW := Integer(parts[2])
            macro.RefH := Integer(parts[3])
        } else if (parts[1] = "click" && parts.Length >= 4) {
            macro.Steps.Push({ X: Integer(parts[2]), Y: Integer(parts[3])
                , Delay: Min(Max(Integer(parts[4]), 0), Config.MacroMaxStepDelayMs) })
        }
    }
    return macro
}

ScanMacros() {
    names := []
    if DirExist(Config.MacrosFolder) {
        Loop Files Config.MacrosFolder "\*.txt"
            names.Push(SubStr(A_LoopFileName, 1, -4))
    }
    return SortArray(names)
}

; --- playback ---
; Where a recorded step lands on screen right now: window-relative,
; scaled proportionally if the window is a different size than at record
; time. Pure function — unit-tested by the harness.
MacroStepScreenPos(step, refW, refH, wx, wy, ww, wh) {
    sx := (refW > 0 && ww != refW) ? step.X * ww / refW : step.X
    sy := (refH > 0 && wh != refH) ? step.Y * wh / refH : step.Y
    return [wx + Round(sx), wy + Round(sy)]
}

; Sleeps in small slices so Esc/F7 can abort instantly and a closed
; target window stops the run instead of clicking into whatever took
; its screen space. Returns false when the run should stop.
MacroSleep(ms, hwnd) {
    remaining := ms
    loop {
        if (GetKeyState("Esc", "P") || GetKeyState("F7", "P"))
            return false
        if !WinExist("ahk_id " hwnd)
            return false
        if (remaining <= 0)
            return true
        slice := Min(remaining, 50)
        Sleep(slice)
        remaining -= slice
    }
}

; Returns "done", "aborted" (user hit Esc/F7), "failed" (window gone /
; couldn't focus / bad file), or "busy" — the queue engine reacts
; differently to each; direct callers can ignore the return value.
; nested = called from inside a running routine, which already owns the
; MacroPlaying flag and the busy check.
RunMacroOnWindow(name, hwnd, nested := false) {
    global App
    if (!nested && (App.MacroPlaying || App.IsRecording)) {
        ShowToast(App.IsRecording ? "Stop recording first (F7)" : "A macro is already running")
        return "busy"
    }
    macro := ""
    try macro := LoadMacroFile(name)
    catch as err {
        ShowToast("Could not load macro: " err.Message)
        return "failed"
    }
    if (macro.Steps.Length = 0) {
        ShowToast("Macro `"" name "`" has no steps")
        return "failed"
    }
    if !WinExist("ahk_id " hwnd) {
        ShowToast("That client window isn't open anymore")
        return "failed"
    }

    if !nested
        App.MacroPlaying := true
    CoordMode("Mouse", "Screen")
    MouseGetPos(&origX, &origY)
    finished := 0
    try {
        WinActivate("ahk_id " hwnd)
        if !WinWaitActive("ahk_id " hwnd, , 2) {
            ShowToast("Couldn't focus the client window")
            if !nested
                App.MacroPlaying := false
            return "failed"
        }
        Sleep(150) ; let the window settle before the first click

        for step in macro.Steps {
            if !MacroSleep(step.Delay, hwnd)
                break
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
            pos := MacroStepScreenPos(step, macro.RefW, macro.RefH, wx, wy, ww, wh)
            Click(pos[1], pos[2])
            finished += 1
        }
    } catch {
        ; window vanished mid-run or similar — handled by the checks below
    } finally {
        if !nested
            App.MacroPlaying := false
        ; Nested (macro inside a routine): leave the pointer where it is,
        ; the outer run restores it once at the very end. See the helper.
        if !nested
            RestorePointerAfterPlayback(origX, origY)
    }

    if (finished = macro.Steps.Length) {
        ShowToast("Macro `"" name "`" done (" finished " clicks)")
        return "done"
    }
    ShowToast("Macro stopped after " finished " of " macro.Steps.Length " clicks")
    ; Window still there means a human pressed Esc/F7; gone means failure.
    return WinExist("ahk_id " hwnd) ? "aborted" : "failed"
}

; Right-click menu entry point: runs a macro on the client window a row
; is linked to.
RunMacroForAccount(acc, name, *) {
    if !acc.HasOwnProp("ClientHwnd") {
        ShowToast("This account isn't linked to a client window")
        return
    }
    RunAutomationOnWindow(name, acc.ClientHwnd)
}

; ============================================================
; ROUTINES (macros + control flow = programs)
; ------------------------------------------------------------
; A routine is a PROGRAM whose instructions are your recorded macros
; plus flow control: loops, pixel tests, if/else, waits, variables,
; jumps. Files live in Logins\Routines\<name>.txt, same hand-editable
; pipe format as macros, one step per line:
;
;   ref|1280|720                     window size the points were taken at
;   run|Dailies|2                    play macro "Dailies" twice
;   loop|5                           repeat 5 times (0 = until stopped)
;     if|pixel|640|360|0xC81E1E|24   pixel test, window-relative + scaled
;       run|Claim|1
;       break
;     else
;       wait|1500
;     endif
;   endloop
;   stop
;
; Design notes:
;  - Blocks are resolved to jump targets at PARSE time (ParseRoutine is
;    pure and unit-tested); execution is a flat program counter + a loop
;    stack, so nesting, break and continue are all cheap and correct.
;  - Every waiting step goes through MacroSleep, so Esc/F7 abort and a
;    closed client stop a routine instantly — same contract as macros.
;  - Two runaway guards: Config.RoutineMaxSteps (total executed steps)
;    and Config.RoutineMaxDepth (routine calling routine).
;  - `key` sends keystrokes. Recording keystrokes is still forbidden
;    (that's how passwords would end up in plain-text files); typing an
;    explicit game key here is the user's own deliberate choice. The
;    editor warns not to put credentials in it — F1/F2/F4 exist for that.
; ============================================================

; The instruction set. One table drives the Add-step menu, the editor
; dialogs, validation and the human-readable step text — add an entry
; here to add an instruction (same spirit as TuningSchema).
;   Cat    — Add-step submenu it appears under ("" = not user-addable)
;   Block  — "open"/"close"/"mid" for flow control, "" for plain steps
;   Fields — parameter editors, in argument order
RoutineOpSchema() {
    static schema := ""
    if IsObject(schema)
        return schema
    schema := Map(
        "run", { Label: "▶ Run macro / routine", Cat: "Macros", Block: "",
            Fields: [{ Key: "name", Label: "Macro or routine", Type: "automation" }
                   , { Key: "times", Label: "Times", Type: "int", Default: 1 }] },
        "click", { Label: "🖱 Click", Cat: "Input", Block: "",
            Fields: [{ Key: "xy", Label: "Point in the client", Type: "point" }
                   , { Key: "button", Label: "Button", Type: "button", Default: "left" }] },
        "key", { Label: "⌨ Send keys", Cat: "Input", Block: "",
            Fields: [{ Key: "keys", Label: "Keys (e.g. {Escape} or {F5})", Type: "str", Default: "{Escape}" }] },
        "activate", { Label: "🗔 Focus the client", Cat: "Input", Block: "", Fields: [] },
        "closeclient", { Label: "🚪 Close this client (give up)", Cat: "Client", Block: "", Fields: [] },
        "restartclient", { Label: "♻ Restart client + log back in", Cat: "Client", Block: "", Fields: [] },
        "log", { Label: "📝 Write a log line", Cat: "Client", Block: "",
            Fields: [{ Key: "text", Label: "Message", Type: "str", Default: "checkpoint" }] },
        "waitsec", { Label: "⏲ Wait N seconds", Cat: "Waiting", Block: "",
            Fields: [{ Key: "sec", Label: "Seconds", Type: "int", Default: 5 }] },
        "wait", { Label: "⏲ Wait (milliseconds)", Cat: "Waiting", Block: "",
            Fields: [{ Key: "ms", Label: "Milliseconds", Type: "int", Default: 1000 }] },
        "waitrand", { Label: "⏲ Wait (random range)", Cat: "Waiting", Block: "",
            Fields: [{ Key: "min", Label: "Minimum ms", Type: "int", Default: 500 }
                   , { Key: "max", Label: "Maximum ms", Type: "int", Default: 1500 }] },
        "waitpixel", { Label: "👁 Wait for a pixel", Cat: "Waiting", Block: "",
            Fields: [{ Key: "px", Label: "Pixel", Type: "pixel" }
                   , { Key: "timeout", Label: "Give up after (ms)", Type: "int", Default: 10000 }
                   , { Key: "onTimeout", Label: "If it never appears", Type: "timeout", Default: "fail" }] },
        "loop", { Label: "🔁 Loop N times…", Cat: "Flow", Block: "open",
            Fields: [{ Key: "times", Label: "Times (0 = forever)", Type: "int", Default: 3 }] },
        "endloop", { Label: "end loop", Cat: "", Block: "close", Fields: [] },
        "while", { Label: "🔁 While <condition>…", Cat: "Flow", Block: "open",
            Fields: [{ Key: "cond", Label: "Condition", Type: "cond" }] },
        "endwhile", { Label: "end while", Cat: "", Block: "close", Fields: [] },
        ; Try-until: run the body, test after each pass, give up after N.
        ; Afterwards `ok` says whether it worked — the retry-then-escalate
        ; shape ("three tries, still red, close the client").
        "repeat", { Label: "🔂 Try up to N times, until…", Cat: "Flow", Block: "open",
            Fields: [{ Key: "times", Label: "Attempts", Type: "int", Default: 3 }
                   , { Key: "cond", Label: "Until", Type: "cond" }] },
        "endrepeat", { Label: "end try", Cat: "", Block: "close", Fields: [] },
        "if", { Label: "❔ If <condition>…", Cat: "Flow", Block: "open",
            Fields: [{ Key: "cond", Label: "Condition", Type: "cond" }] },
        "else", { Label: "…otherwise", Cat: "", Block: "mid", Fields: [] },
        "endif", { Label: "end if", Cat: "", Block: "close", Fields: [] },
        "break", { Label: "⏏ Break out of the loop", Cat: "Flow", Block: "", Fields: [] },
        "continue", { Label: "↻ Next loop pass", Cat: "Flow", Block: "", Fields: [] },
        "stop", { Label: "⏹ Stop (finished)", Cat: "Flow", Block: "", Fields: [] },
        "fail", { Label: "✖ Stop (report failure)", Cat: "Flow", Block: "", Fields: [] },
        "label", { Label: "🏷 Label", Cat: "Flow", Block: "",
            Fields: [{ Key: "name", Label: "Label name", Type: "str", Default: "top" }] },
        "goto", { Label: "↪ Go to label", Cat: "Flow", Block: "",
            Fields: [{ Key: "name", Label: "Label name", Type: "str", Default: "top" }] },
        "set", { Label: "🔢 Set counter", Cat: "Counters", Block: "",
            Fields: [{ Key: "name", Label: "Counter", Type: "str", Default: "n" }
                   , { Key: "value", Label: "Value", Type: "int", Default: 0 }] },
        "add", { Label: "🔢 Add to counter", Cat: "Counters", Block: "",
            Fields: [{ Key: "name", Label: "Counter", Type: "str", Default: "n" }
                   , { Key: "delta", Label: "Add", Type: "int", Default: 1 }] })
    return schema
}

; Condition types, same table-driven idea. Every one is usable by
; `if` and `while`.
RoutineCondSchema() {
    static schema := ""
    if IsObject(schema)
        return schema
    schema := Map(
        "pixel", { Label: "Pixel matches a colour",
            Fields: [{ Key: "px", Label: "Pixel", Type: "pixel" }] },
        "notpixel", { Label: "Pixel does NOT match",
            Fields: [{ Key: "px", Label: "Pixel", Type: "pixel" }] },
        "ok", { Label: "The last pixel wait succeeded", Fields: [] },
        "notok", { Label: "The last pixel wait timed out", Fields: [] },
        "window", { Label: "The client is still open", Fields: [] },
        "notwindow", { Label: "The client has closed", Fields: [] },
        "var", { Label: "Counter comparison",
            Fields: [{ Key: "name", Label: "Counter", Type: "str", Default: "n" }
                   , { Key: "op", Label: "Is", Type: "op", Default: "=" }
                   , { Key: "value", Label: "Value", Type: "int", Default: 1 }] },
        "chance", { Label: "Random chance (%)",
            Fields: [{ Key: "pct", Label: "Percent", Type: "int", Default: 50 }] },
        ; Session-aware: routines run during Activity's idle time, so
        ; "is this account already done / how long is left" decides
        ; whether a long farm is worth starting.
        "done", { Label: "This account has reached today's goal", Fields: [] },
        "notdone", { Label: "This account is still under the goal", Fields: [] },
        "minsleft", { Label: "Minutes left to the goal",
            Fields: [{ Key: "op", Label: "Is", Type: "op", Default: ">=" }
                   , { Key: "value", Label: "Minutes", Type: "int", Default: 10 }] })
    return schema
}

; The account a client window belongs to (routines get an hwnd, but
; closing/restarting/timing needs the account behind it).
FindAccountByHwnd(hwnd) {
    global App
    for f in App.Files {
        for acc in f.Accounts {
            if (acc.HasOwnProp("ClientHwnd") && acc.ClientHwnd = hwnd)
                return acc
        }
    }
    return ""
}

; --- parsing -------------------------------------------------------
; Pure: text in, program out. Resolves every block to jump targets and
; reports the first structural error instead of half-running something.
; Returns { Steps, RefW, RefH, Labels, Error }.
ParseRoutine(text) {
    prog := { Steps: [], RefW: 0, RefH: 0, Labels: Map(), Error: "" }
    schema := RoutineOpSchema()
    lineNo := 0
    for raw in StrSplit(text, "`n", "`r") {
        lineNo += 1
        line := Trim(raw)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        parts := StrSplit(line, "|")
        op := StrLower(Trim(parts[1]))
        args := []
        loop parts.Length - 1
            args.Push(Trim(parts[A_Index + 1]))
        if (op = "ref") {
            prog.RefW := args.Length >= 1 ? Integer(args[1]) : 0
            prog.RefH := args.Length >= 2 ? Integer(args[2]) : 0
            continue
        }
        if !schema.Has(op) {
            prog.Error := "Line " lineNo ": unknown step '" op "'"
            return prog
        }
        if (op = "label" && args.Length >= 1)
            prog.Labels[StrLower(args[1])] := prog.Steps.Length + 1
        prog.Steps.Push({ Op: op, Args: args, Line: lineNo, Jump: 0, Depth: 0 })
    }

    ; Match blocks with a stack; record jump targets both ways.
    stack := []
    for i, st in prog.Steps {
        switch st.Op {
            case "loop", "while", "if", "repeat":
                stack.Push({ Op: st.Op, Index: i, Mid: 0 })
            case "else":
                if (!stack.Length || stack[stack.Length].Op != "if") {
                    prog.Error := "Line " st.Line ": 'else' without an 'if'"
                    return prog
                }
                stack[stack.Length].Mid := i
            case "endif", "endloop", "endwhile", "endrepeat":
                want := (st.Op = "endif") ? "if" : (st.Op = "endloop") ? "loop"
                    : (st.Op = "endrepeat") ? "repeat" : "while"
                if (!stack.Length || stack[stack.Length].Op != want) {
                    prog.Error := "Line " st.Line ": '" st.Op "' without a matching '" want "'"
                    return prog
                }
                open := stack.Pop()
                if (open.Op = "if") {
                    ; if -> else (or endif); else -> endif
                    prog.Steps[open.Index].Jump := open.Mid ? open.Mid : i
                    if open.Mid
                        prog.Steps[open.Mid].Jump := i
                } else {
                    prog.Steps[open.Index].Jump := i ; loop/while -> its end
                    st.Jump := open.Index            ; end -> its opener
                }
        }
    }
    if stack.Length {
        open := stack[stack.Length]
        prog.Error := "Line " prog.Steps[open.Index].Line ": '" open.Op "' is never closed"
        return prog
    }

    ; Indent depth (display only) + goto target validation.
    depth := 0
    for st in prog.Steps {
        if (st.Op = "endif" || st.Op = "endloop" || st.Op = "endwhile"
            || st.Op = "endrepeat" || st.Op = "else")
            depth := Max(0, depth - 1)
        st.Depth := depth
        if (st.Op = "if" || st.Op = "loop" || st.Op = "while"
            || st.Op = "repeat" || st.Op = "else")
            depth += 1
        if (st.Op = "goto" && (!st.Args.Length || !prog.Labels.Has(StrLower(st.Args[1])))) {
            prog.Error := "Line " st.Line ": no label named '" (st.Args.Length ? st.Args[1] : "") "'"
            return prog
        }
    }
    return prog
}

RoutineToText(prog) {
    out := "; Account Queue routine — edited " FormatTime(, "yyyy-MM-dd HH:mm") "`n"
        . "; steps run top to bottom; see the Routine Maker for the full instruction set`n"
        . "ref|" prog.RefW "|" prog.RefH "`n"
    for st in prog.Steps {
        line := st.Op
        for a in st.Args
            line .= "|" a
        out .= RoutineIndent(st.Depth) line "`n"
    }
    return out
}

RoutineIndent(depth) {
    s := ""
    loop depth
        s .= "  "
    return s
}

; --- conditions ----------------------------------------------------
; args[1] is the condition name, the rest its parameters. ctx carries
; the live client + counters. Pure apart from the pixel/window reads.
EvalRoutineCondition(args, ctx) {
    if !args.Length
        return false
    kind := StrLower(args[1])
    switch kind {
        case "pixel", "notpixel":
            hit := RoutinePixelMatches(args, ctx)
            return (kind = "pixel") ? hit : !hit
        case "ok":
            return ctx.Ok
        case "notok":
            return !ctx.Ok
        case "window":
            return WinExist("ahk_id " ctx.Hwnd) ? true : false
        case "notwindow":
            return WinExist("ahk_id " ctx.Hwnd) ? false : true
        case "chance":
            pct := args.Length >= 2 ? Integer(args[2]) : 50
            return Random(1, 100) <= pct
        case "done", "notdone":
            acc := FindAccountByHwnd(ctx.Hwnd)
            isDone := IsObject(acc) && IsAccountDone(acc)
            return (kind = "done") ? isDone : !isDone
        case "minsleft":
            acc := FindAccountByHwnd(ctx.Hwnd)
            if (!IsObject(acc) || args.Length < 3)
                return false
            mins := Max(0, Config.SessionGoalMinutes - Floor(AccountOnlineMs(acc) / 60000))
            want := Integer(args[3])
            switch args[2] {
                case "=": return mins = want
                case "!=": return mins != want
                case ">": return mins > want
                case "<": return mins < want
                case ">=": return mins >= want
                case "<=": return mins <= want
            }
            return false
        case "var":
            if (args.Length < 4)
                return false
            name := StrLower(args[2])
            have := ctx.Vars.Has(name) ? ctx.Vars[name] : 0
            want := Integer(args[4])
            switch args[3] {
                case "=": return have = want
                case "!=": return have != want
                case ">": return have > want
                case "<": return have < want
                case ">=": return have >= want
                case "<=": return have <= want
            }
            return false
    }
    return false
}

; Reads the pixel at a window-relative point (scaled like macro clicks)
; and compares it to the captured colour within tolerance.
; args: [kind, x, y, color, tol]
RoutinePixelMatches(args, ctx) {
    if (args.Length < 4)
        return false
    if !WinExist("ahk_id " ctx.Hwnd)
        return false
    tol := args.Length >= 5 ? Integer(args[5]) : Config.LoginColorTol
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " ctx.Hwnd)
    pt := MacroStepScreenPos({ X: Integer(args[2]), Y: Integer(args[3]) }
        , ctx.RefW, ctx.RefH, wx, wy, ww, wh)
    CoordMode("Pixel", "Screen")
    got := ""
    try got := PixelGetColor(pt[1], pt[2])
    if (got = "")
        return false
    return ColorsClose(Integer(got), Integer(args[4]), tol)
}

; --- execution -----------------------------------------------------
; Same return contract as RunMacroOnWindow: "done" / "aborted" /
; "failed" / "busy", so the queue, playlists and console treat routines
; exactly like macros.
RunRoutineOnWindow(name, hwnd, nested := false) {
    global App
    prog := ""
    try prog := ParseRoutine(FileRead(Config.RoutinesFolder "\" name ".txt", "UTF-8"))
    catch as err {
        ShowToast("Could not load routine: " err.Message)
        return "failed"
    }
    if (prog.Error != "") {
        ShowToast("Routine '" name "' has an error — " prog.Error)
        return "failed"
    }
    if !prog.Steps.Length {
        ShowToast("Routine '" name "' is empty")
        return "failed"
    }
    if !WinExist("ahk_id " hwnd) {
        ShowToast("That client window isn't open anymore")
        return "failed"
    }

    ; Real runs keep a short rolling trace so a failure leaves a
    ; post-mortem in the log — the answer to "what did it do before it
    ; broke?" when nobody was watching.
    ctx := NewRoutineContext(hwnd, prog.RefW, prog.RefH, Config.RoutineTraceLines)
    CoordMode("Mouse", "Screen")
    MouseGetPos(&origX, &origY)
    WinActivate("ahk_id " hwnd)
    if !WinWaitActive("ahk_id " hwnd, , 2) {
        ShowToast("Couldn't focus the client window")
        return "failed"
    }
    Sleep(120)

    outcome := ExecuteRoutine(prog, ctx, name)
    ; Only the OUTERMOST run parks the pointer. A nested run (routine
    ; called from another routine's `run` step) that restored here would
    ; pause and drag the mouse back mid-routine after every sub-call —
    ; slow, and it re-fires the "last click lands where the pointer moved"
    ; bug. The outer run owns the real origin.
    if !nested
        RestorePointerAfterPlayback(origX, origY)
    App.RoutineLastTrace := ctx.Trace ; the maker's "Last trace" button reads this
    switch outcome {
        case "done": ShowToast("Routine '" name "' finished")
        case "aborted": ShowToast("Routine '" name "' stopped")
        case "failed":
            ShowToast("Routine '" name "' failed — see the trace")
            RoutineLogTrace(name, hwnd, ctx.Trace)
    }
    return outcome
}

; Dumps the tail of a failed run into routine-log.txt, indented, so an
; unattended failure can be read back later.
RoutineLogTrace(name, hwnd, trace) {
    if (!IsObject(trace) || !trace.Length)
        return
    body := ""
    for line in trace
        body .= "      " line "`n"
    RoutineLog(name, hwnd, "FAILED — last " trace.Length " steps:")
    try FileAppend(body, Config.RoutinesFolder "\routine-log.txt", "UTF-8")
}

; One line of the execution trace: which step ran, and what it decided.
; This is what answers "which branch did it take, and where did it die".
TraceAdd(ctx, pc, st, detail := "") {
    if !IsObject(ctx.Trace)
        return
    ctx.Trace.Push(Format("{:4}", pc) "  " RoutineIndent(st.Depth) RoutineStepText(st)
        . (detail != "" ? "   →  " detail : ""))
    ; Bounded ring: drop the oldest half when it grows past twice the cap,
    ; so a million-step loop can't eat memory (trimming per push would be
    ; O(n) on every step).
    if (ctx.Trace.Length > ctx.TraceMax * 2) {
        keep := []
        loop ctx.TraceMax {
            keep.Push(ctx.Trace[ctx.Trace.Length - ctx.TraceMax + A_Index])
        }
        ctx.Trace := keep
    }
}

; A context ready to run. Trace/Dry/OnStep are the debugging channel:
;   Trace  — array of executed-step lines (bounded by TraceMax)
;   Dry    — evaluate everything, but perform no clicks/keys/macros
;   OnStep — called with the pc before each step (live cursor in the maker)
NewRoutineContext(hwnd, refW, refH, traceMax := 0, dry := false, onStep := "") {
    return { Hwnd: hwnd, RefW: refW, RefH: refH, Vars: Map(), Ok: false
        , Trace: traceMax > 0 ? [] : "", TraceMax: traceMax, Dry: dry, OnStep: onStep }
}

; The interpreter: flat program counter + loop stack. Returns
; "done"/"aborted"/"failed".
ExecuteRoutine(prog, ctx, name := "") {
    global App
    steps := prog.Steps
    loops := []          ; {Start, End, Remaining} — innermost last
    pc := 1
    budget := Config.RoutineMaxSteps
    ; Older callers may hand us a bare context; fill in the debug fields.
    if !ctx.HasOwnProp("Trace")
        ctx.Trace := ""
    if !ctx.HasOwnProp("TraceMax")
        ctx.TraceMax := 0
    if !ctx.HasOwnProp("Dry")
        ctx.Dry := false
    if !ctx.HasOwnProp("OnStep")
        ctx.OnStep := ""
    ; Header line: the geometry every click is computed from. If clicks
    ; land in the wrong place, this is the first thing to check —
    ; a ref size that doesn't match the live window means every point
    ; gets scaled off-target.
    if IsObject(ctx.Trace) {
        try {
            WinGetPos(&hwx, &hwy, &hww, &hwh, "ahk_id " ctx.Hwnd)
            ctx.Trace.Push("      client window at " hwx "," hwy "  size " hww "x" hwh
                . (ctx.RefW ? "   ·  points captured at " ctx.RefW "x" ctx.RefH
                    . ((ctx.RefW != hww || ctx.RefH != hwh) ? "  → SCALED" : "  → 1:1")
                    : "   ·  no ref size — points used as-is"))
        }
    }

    while (pc >= 1 && pc <= steps.Length) {
        if (--budget <= 0) {
            ShowToast("Routine '" name "' hit the step limit — stopped")
            if IsObject(ctx.Trace) {
                ctx.Trace.Push("     ✖ step limit reached — stopped")
                ; The usual cause in a dry run isn't a bug in the routine:
                ; nothing is being clicked, so a loop that waits for the
                ; screen to change can never end.
                if ctx.Dry
                    ctx.Trace.Push("       (dry run changes nothing on screen, so "
                        . "'keep going while X is there' loops never finish here — "
                        . "test those with ▶ Test on client)")
            }
            return "failed"
        }
        if (GetKeyState("Esc", "P") || GetKeyState("F7", "P"))
            return "aborted"
        if (!ctx.Dry && !WinExist("ahk_id " ctx.Hwnd)) {
            if IsObject(ctx.Trace)
                ctx.Trace.Push("     ✖ the client window closed")
            return "failed"
        }

        st := steps[pc]
        if IsObject(ctx.OnStep)
            try ctx.OnStep.Call(pc)
        switch st.Op {
            case "run":
                target := st.Args.Length >= 1 ? st.Args[1] : ""
                times := st.Args.Length >= 2 ? Max(1, Integer(st.Args[2])) : 1
                if ctx.Dry {
                    TraceAdd(ctx, pc, st, "skipped (dry run)")
                } else {
                    loop times {
                        res := RunAutomationOnWindow(target, ctx.Hwnd, true)
                        if (res = "aborted") {
                            TraceAdd(ctx, pc, st, "aborted")
                            return "aborted"
                        }
                        if (res = "failed" || res = "busy") {
                            TraceAdd(ctx, pc, st, "FAILED (" res ")")
                            return "failed"
                        }
                    }
                    TraceAdd(ctx, pc, st, "done")
                }
                pc += 1
            case "click":
                if ctx.Dry {
                    TraceAdd(ctx, pc, st, "skipped (dry run)")
                } else {
                    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " ctx.Hwnd)
                    pt := MacroStepScreenPos({ X: Integer(st.Args[1]), Y: Integer(st.Args[2]) }
                        , ctx.RefW, ctx.RefH, wx, wy, ww, wh)
                    btn := st.Args.Length >= 3 && st.Args[3] != "" ? st.Args[3] : "left"
                    Click(pt[1] " " pt[2] " " btn)
                    TraceAdd(ctx, pc, st, "screen " pt[1] "," pt[2])
                }
                pc += 1
            case "key":
                if ctx.Dry {
                    TraceAdd(ctx, pc, st, "skipped (dry run)")
                } else {
                    if st.Args.Length
                        try SendInput(st.Args[1])
                    TraceAdd(ctx, pc, st)
                }
                pc += 1
            case "activate":
                if !ctx.Dry
                    try WinActivate("ahk_id " ctx.Hwnd)
                TraceAdd(ctx, pc, st, ctx.Dry ? "skipped (dry run)" : "")
                pc += 1
            case "wait", "waitsec":
                ms := st.Args.Length ? Integer(st.Args[1]) : 0
                if (st.Op = "waitsec")
                    ms *= 1000
                if ctx.Dry {
                    TraceAdd(ctx, pc, st, "skipped (dry run)")
                    Sleep(-1) ; yield only — a dry run must never crawl
                } else {
                    TraceAdd(ctx, pc, st)
                    if !MacroSleep(ms, ctx.Hwnd)
                        return WinExist("ahk_id " ctx.Hwnd) ? "aborted" : "failed"
                }
                pc += 1
            case "closeclient":
                if ctx.Dry {
                    TraceAdd(ctx, pc, st, "skipped (dry run) — would end here")
                    return "done"
                }
                TraceAdd(ctx, pc, st, "closing")
                RoutineCloseClient(ctx.Hwnd, name)
                return "done" ; the client is gone on purpose — nothing left to run
            case "restartclient":
                if ctx.Dry {
                    TraceAdd(ctx, pc, st, "skipped (dry run)")
                    ctx.Ok := true
                    pc += 1
                    continue
                }
                newHwnd := RoutineRestartClient(ctx.Hwnd, name)
                if !newHwnd {
                    ctx.Ok := false
                    TraceAdd(ctx, pc, st, "FAILED to restart")
                    return "failed"
                }
                ctx.Hwnd := newHwnd
                ctx.Ok := true
                TraceAdd(ctx, pc, st, "back online")
                pc += 1
            case "log":
                if !ctx.Dry
                    RoutineLog(name, ctx.Hwnd, st.Args.Length ? st.Args[1] : "")
                TraceAdd(ctx, pc, st)
                pc += 1
            case "waitrand":
                lo := st.Args.Length >= 1 ? Integer(st.Args[1]) : 0
                hi := st.Args.Length >= 2 ? Integer(st.Args[2]) : lo
                if ctx.Dry {
                    TraceAdd(ctx, pc, st, "shortened (dry run)")
                    Sleep(20)
                } else {
                    picked := Random(Min(lo, hi), Max(lo, hi))
                    TraceAdd(ctx, pc, st, "waiting " picked " ms")
                    if !MacroSleep(picked, ctx.Hwnd)
                        return WinExist("ahk_id " ctx.Hwnd) ? "aborted" : "failed"
                }
                pc += 1
            case "waitpixel":
                ; args: x, y, color, tol, timeoutMs
                timeout := ctx.Dry ? 0 : (st.Args.Length >= 5 ? Integer(st.Args[5]) : 10000)
                waited := 0
                ctx.Ok := false
                loop {
                    if EvalRoutineCondition(["pixel", st.Args[1], st.Args[2], st.Args[3]
                        , st.Args.Length >= 4 ? st.Args[4] : Config.LoginColorTol], ctx) {
                        ctx.Ok := true
                        break
                    }
                    if (waited >= timeout)
                        break
                    if !MacroSleep(150, ctx.Hwnd)
                        return WinExist("ahk_id " ctx.Hwnd) ? "aborted" : "failed"
                    waited += 150
                }
                ; What a timeout MEANS is the step's own choice (6th arg):
                ;   fail     — stop the run and report failure (default for
                ;              new steps: a screen that never appeared is
                ;              almost always a real problem)
                ;   stop     — end the routine quietly as finished
                ;   continue — carry on; branch yourself with `if notok`
                ; Routines saved before 0.36.0 have no 6th arg and keep the
                ; original carry-on behaviour.
                onTimeout := st.Args.Length >= 6 ? StrLower(st.Args[6]) : "continue"
                TraceAdd(ctx, pc, st, ctx.Ok ? "appeared after " waited " ms  → ok"
                    : (ctx.Dry ? "not there right now  → not ok (dry run: no waiting)"
                        : "TIMED OUT after " waited " ms  → not ok"
                            . (onTimeout = "fail" ? "  → stopping, reported as FAILED"
                               : onTimeout = "stop" ? "  → stopping here"
                               : "  → carrying on")))
                if (!ctx.Ok && !ctx.Dry) {
                    if (onTimeout = "fail")
                        return "failed"
                    if (onTimeout = "stop")
                        return "done"
                }
                pc += 1
            case "loop":
                if (!loops.Length || loops[loops.Length].Start != pc) {
                    n := st.Args.Length ? Integer(st.Args[1]) : 0
                    loops.Push({ Start: pc, End: st.Jump, Remaining: n <= 0 ? -1 : n })
                }
                if (loops[loops.Length].Remaining = 0) {
                    loops.Pop()
                    pc := st.Jump + 1
                } else {
                    pc += 1
                }
            case "endloop":
                if loops.Length {
                    top := loops[loops.Length]
                    if (top.Remaining > 0)
                        top.Remaining -= 1
                    pc := top.Start
                } else {
                    pc += 1
                }
            case "while":
                whileOk := EvalRoutineCondition(st.Args, ctx)
                TraceAdd(ctx, pc, st, whileOk ? "true — run the body" : "false — leave the loop")
                if whileOk {
                    if (!loops.Length || loops[loops.Length].Start != pc)
                        loops.Push({ Start: pc, End: st.Jump, Remaining: -1 })
                    pc += 1
                } else {
                    if (loops.Length && loops[loops.Length].Start = pc)
                        loops.Pop()
                    pc := st.Jump + 1
                }
            case "endwhile":
                pc := st.Jump ; back to the while, which re-tests
            case "repeat":
                if (!loops.Length || loops[loops.Length].Start != pc) {
                    n := st.Args.Length ? Max(1, Integer(st.Args[1])) : 1
                    loops.Push({ Start: pc, End: st.Jump, Remaining: n })
                }
                pc += 1 ; the body always runs at least once; the test is at the end
            case "endrepeat":
                if !loops.Length {
                    pc += 1
                } else {
                    top := loops[loops.Length]
                    ; The condition lives on the opening `repeat` step,
                    ; after its attempts count.
                    openArgs := steps[top.Start].Args
                    condArgs := []
                    loop openArgs.Length - 1
                        condArgs.Push(openArgs[A_Index + 1])
                    if EvalRoutineCondition(condArgs, ctx) {
                        ctx.Ok := true ; it worked — leave the block
                        TraceAdd(ctx, pc, st, "condition met → ok")
                        loops.Pop()
                        pc += 1
                    } else {
                        top.Remaining -= 1
                        if (top.Remaining > 0) {
                            TraceAdd(ctx, pc, st, "not met — " top.Remaining " attempt(s) left")
                            pc := top.Start + 1 ; another attempt
                        } else {
                            ctx.Ok := false ; out of attempts — `if notok` catches it
                            TraceAdd(ctx, pc, st, "GAVE UP after all attempts → not ok")
                            loops.Pop()
                            pc += 1
                        }
                    }
                }
            case "if":
                ifOk := EvalRoutineCondition(st.Args, ctx)
                ; Name the branch actually taken — this is the line that
                ; answers "which way did it go?".
                TraceAdd(ctx, pc, st, ifOk ? "TRUE — taking this branch"
                    : (steps[st.Jump].Op = "else" ? "false — jumping to 'otherwise'"
                                                  : "false — skipping the block"))
                pc := ifOk ? pc + 1 : st.Jump + 1
            case "else":
                pc := st.Jump + 1 ; reached by falling out of the true branch
            case "endif":
                pc += 1
            case "break":
                TraceAdd(ctx, pc, st, loops.Length ? "leaving the loop" : "(not in a loop)")
                if loops.Length {
                    top := loops.Pop()
                    pc := top.End + 1
                } else {
                    pc += 1
                }
            case "continue":
                TraceAdd(ctx, pc, st)
                pc := loops.Length ? loops[loops.Length].End : pc + 1
            case "goto":
                TraceAdd(ctx, pc, st, "jumping to line " prog.Labels[StrLower(st.Args[1])])
                pc := prog.Labels[StrLower(st.Args[1])]
            case "label":
                pc += 1
            case "set":
                ctx.Vars[StrLower(st.Args[1])] := st.Args.Length >= 2 ? Integer(st.Args[2]) : 0
                TraceAdd(ctx, pc, st, st.Args[1] " = " ctx.Vars[StrLower(st.Args[1])])
                pc += 1
            case "add":
                key := StrLower(st.Args[1])
                ctx.Vars[key] := (ctx.Vars.Has(key) ? ctx.Vars[key] : 0)
                    + (st.Args.Length >= 2 ? Integer(st.Args[2]) : 1)
                TraceAdd(ctx, pc, st, st.Args[1] " is now " ctx.Vars[key])
                pc += 1
            case "stop":
                TraceAdd(ctx, pc, st, "finished here")
                return "done"
            case "fail":
                TraceAdd(ctx, pc, st, "reported FAILURE here")
                return "failed"
            default:
                pc += 1
        }
    }
    return "done"
}

; --- client control ------------------------------------------------
; Closing a client from a routine must go through DetachClient, or the
; account silently loses the minutes it earned (see the session-time
; invariant). Same rule as everywhere else in the app.
RoutineCloseClient(hwnd, name := "") {
    acc := FindAccountByHwnd(hwnd)
    if IsObject(acc) {
        RoutineLog(name, hwnd, "closing client")
        DetachClient(acc) ; banks the online time first
    }
    try WinClose("ahk_id " hwnd)
    return true
}

; Close → relaunch → log back in → re-link, and hand back the NEW hwnd
; so the routine carries on in the fresh client. Returns 0 if anything
; in that chain fails. Reuses the same funnel the mass-login run uses.
RoutineRestartClient(hwnd, name := "") {
    acc := FindAccountByHwnd(hwnd)
    if !IsObject(acc) {
        ShowToast("Restart needs the client to be linked to an account")
        return 0
    }
    if (!LoginProfileReady() || !FileExist(Config.LauncherPath)) {
        ShowToast("Restart needs Login Setup + a launcher path (⚙)")
        return 0
    }
    RoutineLog(name, hwnd, "restarting client")
    SetLoginStatus("Routine: restarting " acc.Name "…")
    DetachClient(acc) ; bank the time before the window goes
    try WinClose("ahk_id " hwnd)
    if !AbortableSleep(2000)
        return 0

    before := GameWindowSet()
    Run(Config.LauncherPath)
    fresh := WaitForNewGameWindow(before, 15000)
    if !fresh
        return 0
    if !AbortableSleep(Config.LoginBootMs)
        return 0
    if !LoginFunnel(acc, fresh) {
        RoutineLog(name, fresh, "restart failed at login")
        return 0
    }
    LinkAccountToSpecificWindow(acc, fresh)
    RoutineLog(name, fresh, "restart ok")
    return fresh
}

; Plain-text trail for unattended runs: Logins\Routines\routine-log.txt.
; Also surfaces on the status line, so a long routine says what it's up
; to while you're looking at the app.
RoutineLog(name, hwnd, text) {
    acc := FindAccountByHwnd(hwnd)
    who := IsObject(acc) ? acc.Name : "unlinked client"
    line := FormatTime(, "yyyy-MM-dd HH:mm:ss") "  [" (name = "" ? "routine" : name) "]  "
        . who "  —  " text "`n"
    try {
        if !DirExist(Config.RoutinesFolder)
            DirCreate(Config.RoutinesFolder)
        FileAppend(line, Config.RoutinesFolder "\routine-log.txt", "UTF-8")
    }
    SetLoginStatus("Routine: " text " (" who ")")
}

; --- files + dispatch ----------------------------------------------
ScanRoutines() {
    names := []
    if DirExist(Config.RoutinesFolder) {
        Loop Files Config.RoutinesFolder "\*.txt"
            names.Push(SubStr(A_LoopFileName, 1, -4))
    }
    return SortArray(names)
}

IsRoutineName(name) {
    return name != "" && FileExist(Config.RoutinesFolder "\" name ".txt") ? true : false
}

; Every "play this automation" path goes through here: routines and
; macros are interchangeable everywhere (queue, playlists, console,
; row menu, routine `run` steps). nested = called from inside a routine.
RunAutomationOnWindow(name, hwnd, nested := false) {
    global App
    if !nested {
        if (App.MacroPlaying || App.IsRecording) {
            ShowToast(App.IsRecording ? "Stop recording first (F7)" : "Something is already running")
            return "busy"
        }
    }
    ; Get our own windows out of the click path before anything is sent
    ; (see PlaybackWindowsAside — this is the "it clicked my own button"
    ; class of bug). Only the outermost run touches it.
    wasTop := nested ? false : PlaybackWindowsAside()
    try {
        if !IsRoutineName(name)
            return RunMacroOnWindow(name, hwnd, nested)

        if (App.RoutineDepth >= Config.RoutineMaxDepth) {
            ShowToast("Routines are nested too deep (" Config.RoutineMaxDepth ") — check for a loop")
            return "failed"
        }
        App.RoutineDepth += 1
        if !nested
            App.MacroPlaying := true
        try {
            result := RunRoutineOnWindow(name, hwnd, nested)
        } finally {
            App.RoutineDepth -= 1
            if !nested
                App.MacroPlaying := false
        }
        return result
    } finally {
        PlaybackWindowsRestore(wasTop)
    }
}

; Playback sends clicks at SCREEN coordinates. Our main window is
; Always-on-Top by preference, and every owned dialog (Macro Manager,
; Routine Maker) floats with it — so a click aimed at the game client
; landed on whatever of OURS was covering that spot, up to and including
; the "Test on client" button that started the run. Drop the topmost
; flag for the duration; the activated game window then sits above us.
; (Recording already hid the manager for exactly this reason; playback
; never did.) Returns whether it needs restoring.
PlaybackWindowsAside() {
    global App
    if (!App.AlwaysOnTop || !IsObject(App.Gui))
        return false
    try App.Gui.Opt("-AlwaysOnTop")
    return true
}

PlaybackWindowsRestore(wasTop) {
    global App
    if (wasTop && IsObject(App.Gui))
        try App.Gui.Opt("+AlwaysOnTop")
}

; Rough runtime estimate, used by Activity's macro budget. Routines
; are estimated by walking their steps (loops multiply, unbounded loops
; get a nominal 10 passes) — a guess, but a defensible one.
AutomationDurationMs(name, depth := 0) {
    if (!IsRoutineName(name) || depth > 2)
        return MacroDurationMs(name)
    total := 2000
    prog := ""
    try prog := ParseRoutine(FileRead(Config.RoutinesFolder "\" name ".txt", "UTF-8"))
    catch
        return total
    if (!IsObject(prog) || prog.Error != "")
        return total
    mult := 1
    for st in prog.Steps {
        switch st.Op {
            case "loop", "repeat":
                n := st.Args.Length ? Integer(st.Args[1]) : 0
                mult *= (n <= 0 ? 10 : Min(n, 50))
            case "endloop", "endrepeat":
                mult := 1
            case "run":
                times := st.Args.Length >= 2 ? Max(1, Integer(st.Args[2])) : 1
                total += mult * times * AutomationDurationMs(st.Args[1], depth + 1)
            case "wait":
                total += mult * (st.Args.Length ? Integer(st.Args[1]) : 0)
            case "waitsec":
                total += mult * (st.Args.Length ? Integer(st.Args[1]) * 1000 : 0)
            case "restartclient":
                total += Config.LoginBootMs + 20000
            case "waitrand"
                , "waitpixel":
                total += mult * (st.Args.Length >= 2 ? Integer(st.Args[2]) : 1000)
        }
    }
    return total
}

; ============================================================
; ROUTINE MAKER (the visual builder)
; ------------------------------------------------------------
; Steps are built from the same schema tables the engine parses, so the
; editor can never produce a step the interpreter doesn't understand.
; Block instructions are inserted as balanced PAIRS (loop+endloop),
; which makes an unbalanced program impossible to build by clicking.
; The dialog is rebuilt on every open so it always matches the theme.
; ============================================================
OpenRoutineMaker(*) {
    global App
    if IsObject(App.RoutineDlg) {
        try App.RoutineDlg.Show()
        return
    }
    dlg := Gui("+Owner" App.Gui.Hwnd " +Resize +MinSize560x520", "Routine Maker — Account Queue")
    dlg.BackColor := Colors.Bg
    dlg.MarginX := 12
    dlg.MarginY := 10
    dlg.SetFont("s9 Norm c" Colors.Text, Config.FontMain)

    dlg.Prog := { Steps: [], RefW: 0, RefH: 0, Labels: Map(), Error: "" }
    dlg.RoutineName := ""

    dlg.NameDDL := dlg.Add("DropDownList", "xm w200", RoutineChoices())
    dlg.NameDDL.OnEvent("Change", (*) => RoutineMakerOpen(dlg))
    dlg.NameDDL.TipText := "Open a saved routine"
    bNew := dlg.Add("Button", "x+6 yp-1 w60 h24", "📄 New")
    bNew.OnEvent("Click", (*) => RoutineMakerNew(dlg))
    bSave := dlg.Add("Button", "x+4 yp w70 h24", "💾 Save")
    bSave.OnEvent("Click", (*) => RoutineMakerSave(dlg, false))
    bSaveAs := dlg.Add("Button", "x+4 yp w80 h24", "⧉ Save as")
    bSaveAs.OnEvent("Click", (*) => RoutineMakerSave(dlg, true))
    bDel := dlg.Add("Button", "x+4 yp w70 h24", "🗑 Delete")
    bDel.OnEvent("Click", (*) => RoutineMakerDelete(dlg))

    lv := dlg.Add("ListView", "xm y+8 w520 h360 -Multi NoSort", ["#", "Step"])
    lv.ModifyCol(1, 34)
    lv.ModifyCol(2, 460)
    lv.OnEvent("DoubleClick", (ctrl, row) => RoutineMakerEdit(dlg))
    dlg.StepList := lv

    ; --- quick insert: the handful of steps used constantly, one click
    ; each, with their parameter right here instead of behind a dialog.
    dlg.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
    bWait := dlg.Add("Button", "xm y+8 w86 h26", "⏲ Wait")
    bWait.OnEvent("Click", (*) => RoutineQuickWait(dlg))
    bWait.TipText := "Insert a wait of exactly this many seconds — no dialog"
    dlg.WaitSecs := dlg.Add("Edit", "x+4 yp+2 w40 h22", "5")
    dlg.Add("Text", "x+3 yp+4 w12 h20", "s")
    bClick := dlg.Add("Button", "x+8 yp-6 w86 h26", "🖱 Click")
    bClick.OnEvent("Click", (*) => RoutineAddChosen(dlg, "click"))
    bClick.TipText := "Insert a click — capture the point with F12"
    bRun := dlg.Add("Button", "x+8 yp w70 h26", "▶ Run")
    bRun.OnEvent("Click", (*) => RoutineQuickRun(dlg))
    bRun.TipText := "Insert a run of the macro/routine picked to the right"
    dlg.QuickRunDDL := dlg.Add("DropDownList", "x+4 yp w168", AutomationNames())
    try dlg.QuickRunDDL.Choose(1)

    bIf := dlg.Add("Button", "xm y+6 w96 h26", "❔ If pixel")
    bIf.OnEvent("Click", (*) => RoutineAddChosen(dlg, "if"))
    bIf.TipText := "Branch on a pixel (or any other condition)"
    bTry := dlg.Add("Button", "x+6 yp w110 h26", "🔂 Try until")
    bTry.OnEvent("Click", (*) => RoutineAddChosen(dlg, "repeat"))
    bTry.TipText := "Try the block up to N times until a condition comes true"
    bLoop := dlg.Add("Button", "x+6 yp w86 h26", "🔁 Loop")
    bLoop.OnEvent("Click", (*) => RoutineQuickLoop(dlg))
    bLoop.TipText := "Insert a 3× loop (double-click the line to change the count)"
    bAdd := dlg.Add("Button", "x+6 yp w110 h26", "➕ All steps…")
    bAdd.OnEvent("Click", (*) => RoutineAddMenu(dlg))
    bAdd.TipText := "The full instruction set: waits, keys, counters, client control, jumps"

    bEdit := dlg.Add("Button", "xm y+10 w80 h26", "✎ Edit")
    bEdit.OnEvent("Click", (*) => RoutineMakerEdit(dlg))
    bUp := dlg.Add("Button", "x+6 yp w40 h26", "▲")
    bUp.OnEvent("Click", (*) => RoutineMakerMove(dlg, -1))
    bDown := dlg.Add("Button", "x+4 yp w40 h26", "▼")
    bDown.OnEvent("Click", (*) => RoutineMakerMove(dlg, 1))
    bDup := dlg.Add("Button", "x+6 yp w70 h26", "⧉ Copy")
    bDup.OnEvent("Click", (*) => RoutineMakerDuplicate(dlg))
    bRem := dlg.Add("Button", "x+6 yp w80 h26", "🗑 Remove")
    bRem.OnEvent("Click", (*) => RoutineMakerRemove(dlg))

    bDry := dlg.Add("Button", "xm y+10 w130 h28", "🔍 Dry run")
    bDry.OnEvent("Click", (*) => RoutineMakerTest(dlg, true))
    bDry.TipText := "Walk the logic without touching the game: no clicks, no waiting — but pixel checks are read for real, so you see exactly which branches it takes and why"
    bTest := dlg.Add("Button", "x+6 yp w150 h28", "▶ Test on client")
    bTest.OnEvent("Click", (*) => RoutineMakerTest(dlg, false))
    bTest.TipText := "Run these steps for real on the selected account's client, highlighting each step as it goes (Esc/F7 stops)"
    bTrace := dlg.Add("Button", "x+6 yp w110 h28", "📋 Last trace")
    bTrace.OnEvent("Click", (*) => OpenRoutineTrace(false, "previous run"))
    bTrace.TipText := "Reopen the step-by-step trace of the last run"
    bText := dlg.Add("Button", "x+6 yp w110 h28", "📝 As text")
    bText.OnEvent("Click", (*) => RoutineMakerOpenText(dlg))
    bText.TipText := "Edit the saved .txt by hand — same pipe format as macros"

    dlg.SetFont("s9 Bold c" Colors.Accent, Config.FontMain)
    dlg.StatusLine := dlg.Add("Text", "xm y+8 w520 h34", "New routine — add your first step")

    ApplyDialogDarkMode(dlg, [dlg.WaitSecs], [lv])
    dlg.OnEvent("Close", (*) => CloseRoutineMaker(dlg))
    dlg.OnEvent("Escape", (*) => CloseRoutineMaker(dlg))
    App.RoutineDlg := dlg
    RefreshRoutineList(dlg)
    dlg.Show("AutoSize")
}

CloseRoutineMaker(dlg) {
    global App
    App.RoutineCapture := ""
    App.RoutineDlg := ""
    try dlg.Destroy()
}

RoutineChoices() {
    out := ["(new routine)"]
    for r in ScanRoutines()
        out.Push(r)
    return out
}

; Renders the program: indented, human-readable, with the raw op hidden
; behind plain language ("Run macro 'Dailies' × 2").
RefreshRoutineList(dlg) {
    lv := dlg.StepList
    lv.Delete()
    for i, st in dlg.Prog.Steps
        lv.Add("", i, RoutineIndent(st.Depth) RoutineStepText(st))
    n := dlg.Prog.Steps.Length
    dlg.StatusLine.Value := (dlg.RoutineName = "" ? "Unsaved routine" : dlg.RoutineName)
        . " — " n " step" (n = 1 ? "" : "s")
        . (dlg.Prog.RefW ? "   ·   points captured at " dlg.Prog.RefW "×" dlg.Prog.RefH : "")
}

; Plain-language rendering of one step.
RoutineStepText(st) {
    a := st.Args
    switch st.Op {
        case "run":
            return "▶ Run '" (a.Length ? a[1] : "?") "'" (a.Length >= 2 && a[2] != 1 ? " × " a[2] : "")
        case "click":
            return "🖱 " (a.Length >= 3 && a[3] != "left" ? a[3] "-click" : "Click") " at " a[1] "," a[2]
        case "key":
            return "⌨ Send " (a.Length ? a[1] : "")
        case "activate":
            return "🗔 Focus the client"
        case "wait":
            return "⏲ Wait " (a.Length ? a[1] : 0) " ms"
        case "waitsec":
            return "⏲ Wait " (a.Length ? a[1] : 0) " s"
        case "closeclient":
            return "🚪 Close this client — give up on it"
        case "restartclient":
            return "♻ Restart the client and log back in"
        case "log":
            return "📝 Log: " (a.Length ? a[1] : "")
        case "waitrand":
            return "⏲ Wait " (a.Length ? a[1] : 0) "–" (a.Length >= 2 ? a[2] : 0) " ms"
        case "waitpixel":
            ot := a.Length >= 6 ? StrLower(a[6]) : "continue"
            return "👁 Wait for pixel " a[1] "," a[2] " = " (a.Length >= 3 ? a[3] : "")
                . " (up to " (a.Length >= 5 ? a[5] : "?") " ms"
                . (ot = "fail" ? ", else FAIL" : ot = "stop" ? ", else stop" : ", else carry on") ")"
        case "loop":
            n := a.Length ? Integer(a[1]) : 0
            return "🔁 Loop " (n <= 0 ? "forever" : n " times")
        case "endloop":
            return "🔁 end loop"
        case "while":
            return "🔁 While " RoutineCondText(a)
        case "endwhile":
            return "🔁 end while"
        case "repeat":
            rest := []
            loop a.Length - 1
                rest.Push(a[A_Index + 1])
            return "🔂 Try up to " (a.Length ? a[1] : 1) "× until " RoutineCondText(rest)
        case "endrepeat":
            return "🔂 end try  (then: ok / not ok)"
        case "if":
            return "❔ If " RoutineCondText(a)
        case "else":
            return "❔ otherwise"
        case "endif":
            return "❔ end if"
        case "break":
            return "⏏ Break out of the loop"
        case "continue":
            return "↻ Next loop pass"
        case "stop":
            return "⏹ Stop — finished"
        case "fail":
            return "✖ Stop — report failure"
        case "label":
            return "🏷 Label '" (a.Length ? a[1] : "") "'"
        case "goto":
            return "↪ Go to '" (a.Length ? a[1] : "") "'"
        case "set":
            return "🔢 Set " (a.Length ? a[1] : "") " = " (a.Length >= 2 ? a[2] : 0)
        case "add":
            return "🔢 Add " (a.Length >= 2 ? a[2] : 1) " to " (a.Length ? a[1] : "")
    }
    return st.Op
}

RoutineCondText(a) {
    if !a.Length
        return "?"
    switch StrLower(a[1]) {
        case "pixel": return "pixel " a[2] "," a[3] " = " a[4] (a.Length >= 5 ? " ±" a[5] : "")
        case "notpixel": return "pixel " a[2] "," a[3] " ≠ " a[4] (a.Length >= 5 ? " ±" a[5] : "")
        case "ok": return "the last pixel wait succeeded"
        case "notok": return "the last pixel wait timed out"
        case "window": return "the client is open"
        case "notwindow": return "the client has closed"
        case "var": return "counter " a[2] " " a[3] " " a[4]
        case "chance": return a[2] "% of the time"
        case "done": return "this account has reached the goal"
        case "notdone": return "this account is still under the goal"
        case "minsleft": return "minutes left " a[2] " " a[3]
    }
    return a[1]
}

; --- editor actions ---
RoutineMakerNew(dlg) {
    dlg.Prog := { Steps: [], RefW: 0, RefH: 0, Labels: Map(), Error: "" }
    dlg.RoutineName := ""
    try dlg.NameDDL.Choose(1)
    RefreshRoutineList(dlg)
}

RoutineMakerOpen(dlg) {
    name := dlg.NameDDL.Text
    if (name = "" || name = "(new routine)") {
        RoutineMakerNew(dlg)
        return
    }
    prog := ""
    try prog := ParseRoutine(FileRead(Config.RoutinesFolder "\" name ".txt", "UTF-8"))
    catch as err {
        ShowToast("Could not open: " err.Message)
        return
    }
    dlg.Prog := prog
    dlg.RoutineName := name
    RefreshRoutineList(dlg)
    if (prog.Error != "")
        dlg.StatusLine.Value := "⚠ " prog.Error
}

RoutineSelectedRow(dlg) {
    return dlg.StepList.GetNext()
}

; Insert after the selection (or at the end). Block ops go in as a
; balanced pair so the program is always structurally valid.
RoutineInsertStep(dlg, op, args) {
    at := RoutineSelectedRow(dlg)
    if (at < 1 || at > dlg.Prog.Steps.Length)
        at := dlg.Prog.Steps.Length
    schema := RoutineOpSchema()[op]
    dlg.Prog.Steps.InsertAt(at + 1, { Op: op, Args: args, Line: 0, Jump: 0, Depth: 0 })
    if (schema.Block = "open") {
        closer := (op = "if") ? "endif" : (op = "loop") ? "endloop"
            : (op = "repeat") ? "endrepeat" : "endwhile"
        dlg.Prog.Steps.InsertAt(at + 2, { Op: closer, Args: [], Line: 0, Jump: 0, Depth: 0 })
    }
    RoutineReindex(dlg)
    dlg.StepList.Modify(at + 1, "Select Focus Vis")
}

; Re-parses the built program so depths/jumps/labels stay truthful —
; the editor never trusts its own bookkeeping.
RoutineReindex(dlg) {
    text := RoutineToText(dlg.Prog)
    reparsed := ParseRoutine(text)
    if (reparsed.Error = "") {
        reparsed.RefW := dlg.Prog.RefW
        reparsed.RefH := dlg.Prog.RefH
        dlg.Prog := reparsed
    }
    RefreshRoutineList(dlg)
    if (reparsed.Error != "")
        dlg.StatusLine.Value := "⚠ " reparsed.Error
}

RoutineAddMenu(dlg) {
    cats := Map()
    order := ["Macros", "Input", "Waiting", "Flow", "Counters", "Client"]
    for op, spec in RoutineOpSchema() {
        if (spec.Cat = "")
            continue
        if !cats.Has(spec.Cat)
            cats[spec.Cat] := []
        cats[spec.Cat].Push({ Op: op, Spec: spec })
    }
    m := Menu()
    for cat in order {
        if !cats.Has(cat)
            continue
        sub := Menu()
        for item in cats[cat]
            sub.Add(item.Spec.Label, RoutineAddChosen.Bind(dlg, item.Op))
        m.Add(cat, sub)
    }
    ; `else` only makes sense inside an if — offered separately.
    m.Add()
    m.Add("…otherwise (else)", RoutineAddChosen.Bind(dlg, "else"))
    m.Show()
}

; --- quick-insert handlers (no dialog: the parameter is on screen) ---
RoutineQuickWait(dlg) {
    secs := Trim(dlg.WaitSecs.Text)
    if (!IsInteger(secs) || Integer(secs) < 0) {
        ShowToast("Enter whole seconds first")
        return
    }
    RoutineInsertStep(dlg, "waitsec", [Integer(secs)])
}

RoutineQuickRun(dlg) {
    name := dlg.QuickRunDDL.Text
    if (name = "") {
        ShowToast("Record a macro first")
        return
    }
    RoutineInsertStep(dlg, "run", [name, 1])
}

RoutineQuickLoop(dlg) {
    RoutineInsertStep(dlg, "loop", [3])
}

RoutineAddChosen(dlg, op, *) {
    args := RoutineDefaultArgs(op)
    ; Steps with parameters open their editor immediately — adding a
    ; step and configuring it is one gesture, not two.
    if RoutineOpSchema()[op].Fields.Length {
        args := EditRoutineStepArgs(dlg, op, args)
        if !IsObject(args)
            return
    }
    RoutineInsertStep(dlg, op, args)
}

RoutineDefaultArgs(op) {
    args := []
    for f in RoutineOpSchema()[op].Fields {
        switch f.Type {
            case "point": args.Push(0), args.Push(0)
            case "pixel": args.Push(0), args.Push(0), args.Push("0x000000"), args.Push(Config.LoginColorTol)
            case "cond":
                args.Push("pixel"), args.Push(0), args.Push(0)
                args.Push("0x000000"), args.Push(Config.LoginColorTol)
            case "automation":
                names := AutomationNames()
                args.Push(names.Length ? names[1] : "")
            case "timeout": args.Push(f.HasOwnProp("Default") ? f.Default : "fail")
            default: args.Push(f.HasOwnProp("Default") ? f.Default : "")
        }
    }
    return args
}

RoutineMakerEdit(dlg) {
    row := RoutineSelectedRow(dlg)
    if (row < 1)
        return
    st := dlg.Prog.Steps[row]
    if !RoutineOpSchema()[st.Op].Fields.Length {
        ShowToast("This step has nothing to configure")
        return
    }
    newArgs := EditRoutineStepArgs(dlg, st.Op, st.Args)
    if IsObject(newArgs) {
        st.Args := newArgs
        RoutineReindex(dlg)
        dlg.StepList.Modify(row, "Select Focus Vis")
    }
}

RoutineMakerMove(dlg, delta) {
    row := RoutineSelectedRow(dlg)
    if (row < 1)
        return
    target := row + delta
    if (target < 1 || target > dlg.Prog.Steps.Length)
        return
    st := dlg.Prog.Steps.RemoveAt(row)
    dlg.Prog.Steps.InsertAt(target, st)
    RoutineReindex(dlg)
    dlg.StepList.Modify(target, "Select Focus Vis")
}

RoutineMakerDuplicate(dlg) {
    row := RoutineSelectedRow(dlg)
    if (row < 1)
        return
    st := dlg.Prog.Steps[row]
    copy := []
    for a in st.Args
        copy.Push(a)
    dlg.Prog.Steps.InsertAt(row + 1, { Op: st.Op, Args: copy, Line: 0, Jump: 0, Depth: 0 })
    RoutineReindex(dlg)
}

; Removing a block opener takes its matching closer with it (and vice
; versa) — half a block would poison the whole program.
RoutineMakerRemove(dlg) {
    row := RoutineSelectedRow(dlg)
    if (row < 1)
        return
    st := dlg.Prog.Steps[row]
    partner := 0
    if (st.Jump && (st.Op = "loop" || st.Op = "while" || st.Op = "repeat"
        || st.Op = "endloop" || st.Op = "endwhile" || st.Op = "endrepeat"))
        partner := st.Jump
    else if (st.Op = "if" || st.Op = "endif")
        partner := RoutineFindIfPartner(dlg.Prog, row)
    idx := []
    idx.Push(row)
    if (partner && partner != row)
        idx.Push(partner)
    ; remove highest index first so earlier ones stay valid
    if (idx.Length = 2 && idx[1] < idx[2]) {
        t := idx[1], idx[1] := idx[2], idx[2] := t
    }
    for i in idx
        dlg.Prog.Steps.RemoveAt(i)
    RoutineReindex(dlg)
}

RoutineFindIfPartner(prog, row) {
    st := prog.Steps[row]
    if (st.Op = "if")
        return st.Jump && prog.Steps[st.Jump].Op = "else" ? prog.Steps[st.Jump].Jump : st.Jump
    ; endif: walk back for its if
    depth := 0
    i := row - 1
    while (i >= 1) {
        op := prog.Steps[i].Op
        if (op = "endif")
            depth += 1
        else if (op = "if") {
            if (depth = 0)
                return i
            depth -= 1
        }
        i -= 1
    }
    return 0
}

RoutineMakerSave(dlg, saveAs) {
    name := dlg.RoutineName
    if (saveAs || name = "") {
        ib := ShowInput("Name this routine:", "Save Routine", name)
        if (ib.Result != "OK")
            return
        name := SanitizeMacroName(ib.Value)
        if (name = "") {
            ShowToast("That name can't be used")
            return
        }
        ; Names are shared with macros so playlists can hold either.
        if FileExist(Config.MacrosFolder "\" name ".txt") {
            ShowConfirm("A MACRO named `"" name "`" already exists.`n`nRoutines and macros share one name space (so they're interchangeable everywhere) — pick another name.", "Account Queue", "Icon!")
            return
        }
        if (FileExist(Config.RoutinesFolder "\" name ".txt") && name != dlg.RoutineName) {
            if (ShowConfirm("A routine named `"" name "`" already exists. Overwrite it?", "Confirm Overwrite", "YesNo Icon?") != "Yes")
                return
        }
    }
    check := ParseRoutine(RoutineToText(dlg.Prog))
    if (check.Error != "") {
        ShowConfirm("This routine won't run yet:`n`n" check.Error, "Account Queue", "Icon!")
        return
    }
    try {
        if !DirExist(Config.RoutinesFolder)
            DirCreate(Config.RoutinesFolder)
        AtomicWriteText(Config.RoutinesFolder "\" name ".txt", RoutineToText(dlg.Prog))
    } catch as err {
        ShowConfirm("Could not save:`n" err.Message, "Account Queue", "IconX")
        return
    }
    dlg.RoutineName := name
    RoutineRefreshNameDDL(dlg, name)
    ShowToast("Routine `"" name "`" saved")
    RefreshRoutineList(dlg)
}

RoutineRefreshNameDDL(dlg, pick := "") {
    dlg.NameDDL.Delete()
    for c in RoutineChoices()
        dlg.NameDDL.Add([c])
    if (pick != "") {
        try dlg.NameDDL.Choose(pick)
    } else {
        try dlg.NameDDL.Choose(1)
    }
}

RoutineMakerDelete(dlg) {
    if (dlg.RoutineName = "") {
        ShowToast("Nothing saved to delete")
        return
    }
    if (ShowConfirm("Delete the routine `"" dlg.RoutineName "`"?", "Confirm Delete", "YesNo Icon!") != "Yes")
        return
    try FileDelete(Config.RoutinesFolder "\" dlg.RoutineName ".txt")
    ShowToast("Routine deleted")
    RoutineMakerNew(dlg)
    RoutineRefreshNameDDL(dlg)
}

RoutineMakerOpenText(dlg) {
    if (dlg.RoutineName = "") {
        ShowToast("Save it first")
        return
    }
    try Run("notepad.exe `"" Config.RoutinesFolder "\" dlg.RoutineName ".txt`"")
}

; Runs the IN-MEMORY program (no save needed) on the selected account's
; client, or the only open client if nothing is selected.
;   dry = walk the logic and evaluate every condition for real, but
;   perform no clicks/keys/macros and don't actually wait. The fastest
;   way to see which branches a routine takes.
RoutineMakerTest(dlg, dry := false) {
    global App
    if !dlg.Prog.Steps.Length {
        ShowToast("Add a step first")
        return
    }
    check := ParseRoutine(RoutineToText(dlg.Prog))
    if (check.Error != "") {
        ShowConfirm("Fix this first:`n`n" check.Error, "Account Queue", "Icon!")
        return
    }
    hwnd := 0
    acc := GetCurrentAccount()
    if (IsObject(acc) && acc.HasOwnProp("ClientHwnd") && WinExist("ahk_id " acc.ClientHwnd))
        hwnd := acc.ClientHwnd
    else {
        found := GetGameClientWindows()
        if found.Length
            hwnd := found[1]
    }
    if !hwnd {
        ShowToast("No game client to " (dry ? "read pixels from" : "test on")
            . " — open one, or select a linked account")
        return
    }
    if (App.MacroPlaying || App.IsRecording) {
        ShowToast("Something is already running")
        return
    }
    App.MacroPlaying := true
    CoordMode("Mouse", "Screen")
    MouseGetPos(&ox, &oy)
    result := ""
    ; The live cursor: highlight each step in the list as it executes.
    ; "Select Vis" WITHOUT "Focus" — focusing a control in this window
    ; mid-run would pull focus off the game client between clicks.
    onStep := (pc) => (dlg.StepList.Modify(pc, "Select Vis"))
    ; A real test sends clicks at screen coordinates, so this window (and
    ; the Always-on-Top main window it belongs to) must stop floating over
    ; the target first.
    wasTop := dry ? false : PlaybackWindowsAside()
    try {
        if !dry {
            WinActivate("ahk_id " hwnd)
            WinWaitActive("ahk_id " hwnd, , 2)
            Sleep(120)
        }
        ctx := NewRoutineContext(hwnd, check.RefW, check.RefH, 2000, dry, onStep)
        result := ExecuteRoutine(check, ctx, dlg.RoutineName = "" ? "(unsaved)" : dlg.RoutineName)
        App.RoutineLastTrace := ctx.Trace
    } finally {
        App.MacroPlaying := false
        RestorePointerAfterPlayback(ox, oy)
        PlaybackWindowsRestore(wasTop)
    }
    dlg.StatusLine.Value := (dry ? "🔍 Dry run: " : "▶ Test run: ") result
        . "   ·   " (IsObject(App.RoutineLastTrace) ? App.RoutineLastTrace.Length : 0) " steps executed"
    OpenRoutineTrace(dry, result)
}

; The trace viewer: every step that ran, in order, with the decision it
; made. Plain read-only text so it can be selected and pasted.
OpenRoutineTrace(dry := false, outcome := "", *) {
    global App
    trace := App.RoutineLastTrace
    if (!IsObject(trace) || !trace.Length) {
        ShowToast("No trace yet — run or dry-run a routine first")
        return
    }
    if IsObject(App.RoutineTraceDlg) {
        try App.RoutineTraceDlg.Destroy()
        App.RoutineTraceDlg := ""
    }
    body := ""
    for line in trace
        body .= line "`n"

    dlg := Gui("+Owner" App.Gui.Hwnd " +Resize", "Trace — what the routine actually did")
    dlg.BackColor := Colors.Bg
    dlg.MarginX := 12
    dlg.MarginY := 10
    dlg.SetFont("s9 Bold c" (outcome = "failed" ? Colors.Danger
        : outcome = "done" ? Colors.Success : Colors.Text), Config.FontMain)
    dlg.Add("Text", "xm w620", (dry ? "🔍 Dry run" : "▶ Test run") " — " outcome
        . "   ·   " trace.Length " steps"
        . (dry ? "   (no clicks were sent; pixel checks were real)" : ""))
    dlg.SetFont("s9 Norm c" Colors.Text, "Consolas")
    ed := dlg.Add("Edit", "xm y+8 w620 h360 ReadOnly -Wrap +HScroll", body)
    dlg.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
    bCopy := dlg.Add("Button", "xm y+8 w120 h26", "📋 Copy")
    bCopy.OnEvent("Click", (*) => (A_Clipboard := body, ShowToast("Trace copied")))
    bClose := dlg.Add("Button", "x+8 yp w90 h26 Default", "Close")
    bClose.OnEvent("Click", (*) => CloseRoutineTrace(dlg))
    ApplyDialogDarkMode(dlg, [ed])
    dlg.OnEvent("Close", (*) => CloseRoutineTrace(dlg))
    dlg.OnEvent("Escape", (*) => CloseRoutineTrace(dlg))
    App.RoutineTraceDlg := dlg
    dlg.Show("AutoSize")
}

CloseRoutineTrace(dlg) {
    global App
    App.RoutineTraceDlg := ""
    try dlg.Destroy()
}

; --- step parameter dialogs ---
; Expands a step's schema into flat editor rows. point/pixel/cond
; become several rows; cond additionally carries its own type picker.
EditRoutineStepArgs(dlg, op, args) {
    spec := RoutineOpSchema()[op]
    for f in spec.Fields {
        if (f.Type = "cond") {
            ; `repeat` carries an attempts count BEFORE its condition —
            ; the condition dialog grows a leading number field for it.
            lead := (op = "repeat") ? "Attempts" : ""
            return EditRoutineCondArgs(dlg, args, lead)
        }
    }
    return EditRoutineSimpleArgs(dlg, op, spec, args)
}

EditRoutineSimpleArgs(dlg, op, spec, args) {
    global App
    d := Gui("+Owner" dlg.Hwnd " +ToolWindow", RoutineOpSchema()[op].Label)
    d.BackColor := Colors.Bg
    d.MarginX := 12
    d.MarginY := 10
    d.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
    ctrls := []
    edits := []
    ai := 1
    for f in spec.Fields {
        switch f.Type {
            case "point", "pixel":
                isPixel := f.Type = "pixel"
                d.Add("Text", "xm w150 h20 Section", isPixel ? "Pixel X / Y" : "Point X / Y")
                cx := d.Add("Edit", "x+8 ys-2 w60 h22", RoutineArg(args, ai))
                cy := d.Add("Edit", "x+4 ys-2 w60 h22", RoutineArg(args, ai + 1))
                ctrls.Push(cx), ctrls.Push(cy)
                edits.Push(cx), edits.Push(cy)
                cc := "", ct := ""
                if isPixel {
                    d.Add("Text", "xm w150 h20 Section", "Colour / tolerance")
                    cc := d.Add("Edit", "x+8 ys-2 w90 h22", RoutineArg(args, ai + 2))
                    ct := d.Add("Edit", "x+4 ys-2 w50 h22", RoutineArg(args, ai + 3))
                    ctrls.Push(cc), ctrls.Push(ct)
                    edits.Push(cc), edits.Push(ct)
                }
                btn := d.Add("Button", "xm y+6 w200 h26", "◉ Capture with F12")
                btn.OnEvent("Click", RoutineArmCapture.Bind(dlg, cx, cy, cc))
                btn.TipText := "Click this, hover the spot inside the game client, then press F12"
                ai += isPixel ? 4 : 2
            case "automation":
                d.Add("Text", "xm w150 h20 Section", f.Label)
                names := AutomationNames()
                ddl := d.Add("DropDownList", "x+8 ys-2 w220", names)
                cur := RoutineArg(args, ai)
                for i, n in names {
                    if (n = cur)
                        ddl.Choose(i)
                }
                ctrls.Push(ddl)
                ai += 1
            case "button":
                d.Add("Text", "xm w150 h20 Section", f.Label)
                ddl := d.Add("DropDownList", "x+8 ys-2 w120", ["left", "right", "middle"])
                cur := RoutineArg(args, ai)
                ddl.Choose(cur = "right" ? 2 : cur = "middle" ? 3 : 1)
                ctrls.Push(ddl)
                ai += 1
            case "timeout":
                ; Reads as plain language; stores continue/stop/fail.
                d.Add("Text", "xm w150 h20 Section", f.Label)
                ddl := d.Add("DropDownList", "x+8 ys-2 w250"
                    , ["stop and report failure", "stop the routine (done)"
                     , "carry on (branch with: if the last pixel wait timed out)"])
                ddl.ValueMap := ["fail", "stop", "continue"]
                cur := StrLower(RoutineArg(args, ai))
                ddl.Choose(cur = "stop" ? 2 : cur = "continue" ? 3 : 1)
                ddl.TipText := "A pixel that never appears usually means the screen didn't load. Stopping makes that obvious; 'carry on' is for when you want to handle it yourself."
                ctrls.Push(ddl)
                ai += 1
            default:
                d.Add("Text", "xm w150 h20 Section", f.Label)
                ed := d.Add("Edit", "x+8 ys-2 w220 h22", RoutineArg(args, ai))
                ctrls.Push(ed)
                edits.Push(ed)
                ai += 1
        }
    }
    if (op = "key") {
        d.SetFont("s8 Norm Italic c" Colors.TextDim, Config.FontMain)
        d.Add("Text", "xm y+8 w380", "Game keys only — never put a password here (F1/F2/F4 do credentials safely).")
        d.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
    }

    result := ""
    ok := d.Add("Button", "xm y+12 w100 h28 Default", "OK")
    ok.OnEvent("Click", (*) => (result := "ok", d.Hide()))
    cancel := d.Add("Button", "x+8 yp w90 h28", "Cancel")
    cancel.OnEvent("Click", (*) => (result := "", d.Hide()))
    d.OnEvent("Escape", (*) => (result := "", d.Hide()))
    d.OnEvent("Close", (*) => (result := "", d.Hide()))
    ApplyDialogDarkMode(d, edits)
    d.Show("AutoSize")
    WinWaitClose("ahk_id " d.Hwnd)
    App.RoutineCapture := ""
    out := ""
    if (result = "ok") {
        out := []
        for c in ctrls {
            ; Dropdowns that show plain language but store a keyword
            ; carry their own map (see the "timeout" field type).
            if c.HasOwnProp("ValueMap")
                out.Push(c.ValueMap[c.Value])
            else
                out.Push(Trim(c.Text))
        }
    }
    try d.Destroy()
    return out
}

; Condition editor: a type picker plus up to four generic rows that
; relabel themselves for the chosen condition.
EditRoutineCondArgs(dlg, args, leadLabel := "") {
    global App
    schema := RoutineCondSchema()
    d := Gui("+Owner" dlg.Hwnd " +ToolWindow", "Condition")
    d.BackColor := Colors.Bg
    d.MarginX := 12
    d.MarginY := 10
    d.SetFont("s9 Norm c" Colors.Text, Config.FontMain)

    ; Optional leading number (repeat's attempt count); when present it
    ; owns args[1] and the condition starts at args[2].
    leadEdit := ""
    if (leadLabel != "") {
        d.Add("Text", "xm w120 h20 Section", leadLabel)
        leadEdit := d.Add("Edit", "x+8 ys-2 w80 h22", args.Length ? args[1] : 3)
        condArgs := []
        loop Max(0, args.Length - 1)
            condArgs.Push(args[A_Index + 1])
        args := condArgs
    }

    kinds := []
    labels := []
    for k, spec in schema {
        kinds.Push(k)
        labels.Push(spec.Label)
    }
    d.Add("Text", "xm w120 h20 Section", "Condition")
    ddl := d.Add("DropDownList", "x+8 ys-2 w260", labels)
    cur := args.Length ? StrLower(args[1]) : "pixel"
    for i, k in kinds {
        if (k = cur)
            ddl.Choose(i)
    }
    if (ddl.Value = 0) ; unknown/empty condition — fall back to the first
        ddl.Choose(1)

    rows := []
    loop 4 {
        lbl := d.Add("Text", "xm y+8 w120 h20 Section Hidden", "")
        ed := d.Add("Edit", "x+8 ys-2 w180 h22 Hidden", "")
        rows.Push({ Label: lbl, Edit: ed })
    }
    ; The op picker (for `var`) shares row 2's slot.
    opDDL := d.Add("DropDownList", "xm y+4 w80 Hidden", ["=", "!=", ">", "<", ">=", "<="])
    capBtn := d.Add("Button", "xm y+8 w200 h26 Hidden", "◉ Capture with F12")

    d.CondKinds := kinds
    d.CondRows := rows
    d.OpDDL := opDDL
    d.CapBtn := capBtn
    d.CondDDL := ddl
    ddl.OnEvent("Change", (*) => RoutineCondLayout(dlg, d, []))
    capBtn.OnEvent("Click", (*) => RoutineArmCapture(dlg, rows[1].Edit, rows[2].Edit, rows[3].Edit))

    result := ""
    ok := d.Add("Button", "xm y+14 w100 h28 Default", "OK")
    ok.OnEvent("Click", (*) => (result := "ok", d.Hide()))
    cancel := d.Add("Button", "x+8 yp w90 h28", "Cancel")
    cancel.OnEvent("Click", (*) => (result := "", d.Hide()))
    d.OnEvent("Escape", (*) => (result := "", d.Hide()))
    d.OnEvent("Close", (*) => (result := "", d.Hide()))

    RoutineCondLayout(dlg, d, args)
    edits := []
    for r in rows
        edits.Push(r.Edit)
    ApplyDialogDarkMode(d, edits)
    d.Show("AutoSize")
    WinWaitClose("ahk_id " d.Hwnd)
    App.RoutineCapture := ""

    out := ""
    if (result = "ok") {
        kind := kinds[d.CondDDL.Value]
        out := IsObject(leadEdit) ? [Trim(leadEdit.Text), kind] : [kind]
        for f in RoutineCondSchema()[kind].Fields {
            switch f.Type {
                case "pixel":
                    out.Push(Trim(rows[1].Edit.Text)), out.Push(Trim(rows[2].Edit.Text))
                    out.Push(Trim(rows[3].Edit.Text)), out.Push(Trim(rows[4].Edit.Text))
                case "op":
                    out.Push(opDDL.Text)
                default:
                    ; name/value rows use slots 1 and 4 (see RoutineCondLayout)
                    out.Push(Trim((f.Key = "name" ? rows[1] : rows[4]).Edit.Text))
            }
        }
    }
    try d.Destroy()
    return out
}

; Shows/labels exactly the rows the selected condition needs.
RoutineCondLayout(dlg, d, args) {
    kind := d.CondKinds[d.CondDDL.Value]
    spec := RoutineCondSchema()[kind]
    for r in d.CondRows {
        r.Label.Visible := false
        r.Edit.Visible := false
    }
    d.OpDDL.Visible := false
    d.CapBtn.Visible := false
    same := args.Length && StrLower(args[1]) = kind

    for f in spec.Fields {
        switch f.Type {
            case "pixel":
                for i, cap in ["Pixel X", "Pixel Y", "Colour", "Tolerance"] {
                    d.CondRows[i].Label.Value := cap
                    d.CondRows[i].Label.Visible := true
                    d.CondRows[i].Edit.Visible := true
                    d.CondRows[i].Edit.Value := same ? RoutineArg(args, i + 1)
                        : (i = 4 ? Config.LoginColorTol : (i = 3 ? "0x000000" : 0))
                }
                d.CapBtn.Visible := true
            case "op":
                d.OpDDL.Visible := true
                if same
                    try d.OpDDL.Choose(RoutineArg(args, 3))
            default:
                slot := (f.Key = "name") ? 1 : 4
                d.CondRows[slot].Label.Value := f.Label
                d.CondRows[slot].Label.Visible := true
                d.CondRows[slot].Edit.Visible := true
                d.CondRows[slot].Edit.Value := same
                    ? RoutineArg(args, f.Key = "name" ? 2 : (kind = "chance" ? 2 : 4))
                    : (f.HasOwnProp("Default") ? f.Default : "")
        }
    }
}

RoutineArg(args, i) {
    return (i >= 1 && i <= args.Length) ? args[i] : ""
}

; Arms F12 to fill the given controls from the game client under the
; mouse — same proven pattern as Login Setup's capture.
RoutineArmCapture(dlg, xCtrl, yCtrl, colorCtrl, *) {
    global App
    App.RoutineCapture := { X: xCtrl, Y: yCtrl, Color: colorCtrl, Dlg: dlg }
    ShowToast("Hover the spot inside the game client, then press F12")
}

DoRoutineCapture() {
    global App
    cap := App.RoutineCapture
    if !IsObject(cap)
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my, &underHwnd)
    proc := ""
    try proc := WinGetProcessName("ahk_id " underHwnd)
    if (proc != Config.GameProcess) {
        ShowToast("Point must be inside a " Config.GameProcess " window")
        return
    }
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " underHwnd)
    CoordMode("Pixel", "Screen")
    color := ""
    try color := PixelGetColor(mx, my)
    try {
        cap.X.Value := mx - wx
        cap.Y.Value := my - wy
        if (IsObject(cap.Color) && color != "")
            cap.Color.Value := color
    }
    ; The routine's reference size = the window points were taken at,
    ; so playback scales to differently-sized clients (like macros).
    if IsObject(cap.Dlg) {
        cap.Dlg.Prog.RefW := ww
        cap.Dlg.Prog.RefH := wh
    }
    ShowToast("Captured " (mx - wx) "," (my - wy) (color != "" ? "  " color : ""))
}

; ============================================================
; MACRO QUEUE
; ------------------------------------------------------------
; A session-only list of (macro → client) jobs, played one at a time
; (playback owns the mouse, so sequential is the only honest mode) with
; a short breather between jobs. A dead client marks its job ✖ failed
; and the queue CONTINUES — one closed window shouldn't kill the batch.
; Esc/F7 aborts the current macro and PAUSES the queue: nothing is
; lost, resume or clear from the Macro Manager. While active, the
; main window's status line shows queue progress.
; ============================================================
EnqueueMacroJob(name, hwnd, label) {
    global App
    App.Queue.Push({ Macro: name, Hwnd: hwnd, Label: label, Status: "waiting" })
    UpdateQueueUI()
    RefreshLinkStatus()
}

; A readable target label: linked account's name if any, else its
; permanent session number, else the raw hwnd.
DescribeWindowShort(hwnd) {
    global App
    owner := FindAccountNameForWindow(hwnd)
    if (owner != "")
        return owner
    if App.WindowSessionNumbers.Has(hwnd)
        return "Window #" App.WindowSessionNumbers[hwnd]
    return "Window " hwnd
}

QueueMacroOnAllClients(name) {
    added := 0
    found := WinGetList("ahk_exe " Config.GameProcess)
    if (found.Length = 0) {
        ShowToast("No " Config.GameProcess " clients open")
        return
    }
    for hwnd in SortByScreenPosition(found) {
        EnqueueMacroJob(name, hwnd, DescribeWindowShort(hwnd))
        added += 1
    }
    ShowToast("Queued `"" name "`" on " added " client(s)")
}

; Every account in the CURRENT file with a live linked client, in list
; order — the queue reads like the roster.
QueueMacroOnLinkedAccounts(name) {
    global App
    added := 0
    for acc in App.Files[App.CurrentFile].Accounts {
        if (AccountIsOnline(acc)) {
            EnqueueMacroJob(name, acc.ClientHwnd, acc.Name)
            added += 1
        }
    }
    ShowToast(added > 0
        ? "Queued `"" name "`" on " added " linked account(s)"
        : "No accounts in this file are linked to an open client")
}

QueueMacroOnSelectedAccount(name) {
    acc := GetCurrentAccount()
    if (!IsObject(acc) || !acc.HasOwnProp("ClientHwnd")) {
        ShowToast("Select an account with a linked client first")
        return
    }
    EnqueueMacroJob(name, acc.ClientHwnd, acc.Name)
    ShowToast("Queued `"" name "`" on " acc.Name)
}

QueueMacroForAccount(acc, name, *) {
    if !acc.HasOwnProp("ClientHwnd") {
        ShowToast("This account isn't linked to a client window")
        return
    }
    EnqueueMacroJob(name, acc.ClientHwnd, acc.Name)
    ShowToast("Queued `"" name "`" on " acc.Name)
}

StartQueue(*) {
    global App
    if App.QueueRunning
        return
    if !QueueHasWaiting() {
        ShowToast("Nothing waiting in the queue")
        return
    }
    if App.IsRecording {
        ShowToast("Stop recording first (F7)")
        return
    }
    App.QueueRunning := true
    App.QueuePaused := false
    UpdateQueueUI()
    ; Run in a timer thread so the button handler returns immediately.
    SetTimer(QueueWorker, -1)
}

PauseQueue(*) {
    global App
    if !App.QueueRunning {
        ShowToast("Queue isn't running")
        return
    }
    App.QueuePaused := true
    ShowToast("Queue will pause after the current macro")
}

ClearQueue(*) {
    global App
    if App.QueueRunning {
        App.QueuePaused := true ; stops after the current job
        ShowToast("Stopping after the current macro, then clearing")
        return
    }
    App.Queue := []
    App.QueuePaused := false
    UpdateQueueUI()
    RefreshLinkStatus()
    ShowToast("Queue cleared")
}

QueueHasWaiting() {
    global App
    for job in App.Queue {
        if (job.Status = "waiting")
            return true
    }
    return false
}

QueueDoneCount() {
    global App
    n := 0
    for job in App.Queue {
        if (job.Status != "waiting" && job.Status != "running")
            n += 1
    }
    return n
}

QueueWorker() {
    global App
    while App.QueueRunning {
        if App.QueuePaused
            break

        job := ""
        for j in App.Queue {
            if (j.Status = "waiting") {
                job := j
                break
            }
        }
        if !IsObject(job) {
            App.QueueRunning := false
            App.QueuePaused := false
            UpdateQueueUI()
            RefreshLinkStatus()
            ShowToast("Queue finished — " QueueDoneCount() " job(s) processed")
            return
        }

        job.Status := "running"
        UpdateQueueUI()
        RefreshLinkStatus()

        result := RunAutomationOnWindow(job.Macro, job.Hwnd)
        job.Status := (result = "done") ? "done" : (result = "aborted") ? "aborted" : "failed"
        UpdateQueueUI()

        if (result = "aborted") {
            ; Human pressed the panic key — pause, don't plow on.
            App.QueuePaused := true
            break
        }

        ; Breather between jobs, still abortable.
        if !AbortableSleep(Config.QueueJobGapMs) {
            App.QueuePaused := true
            break
        }
    }

    App.QueueRunning := false
    UpdateQueueUI()
    RefreshLinkStatus()
    if (App.QueuePaused && QueueHasWaiting())
        ShowToast("Queue paused — resume or clear in 🎬 Macros")
}

; Esc or F7 stops SHORT, attended automation (macro playback, the
; launch/login phases). NOT used during long passive phases — Esc is a
; normal gaming key, and one stray press once closed a whole wave.
AbortPressed() {
    global App
    return App.LoginStopReq || GetKeyState("Esc", "P") || GetKeyState("F7", "P")
}

; F7 only — the stop key for long-running phases (Activity monitoring),
; where Esc presses in the game must not count.
StopPressed() {
    global App
    return App.LoginStopReq || GetKeyState("F7", "P")
}

; The console's Stop button — soft-requests the orchestrator to halt.
StopLoginRun(*) {
    global App
    if App.LoginRunning
        App.LoginStopReq := true
}

MonitorSleep(ms) {
    remaining := ms
    while (remaining > 0) {
        if StopPressed()
            return false
        Sleep(Min(remaining, 100))
        remaining -= 100
    }
    return true
}

; Sleeps in small slices so an abort key stops it near-instantly.
; Returns false if aborted mid-sleep.
AbortableSleep(ms) {
    remaining := ms
    while (remaining > 0) {
        if AbortPressed()
            return false
        Sleep(Min(remaining, 50))
        remaining -= 50
    }
    return true
}

QueueStatusGlyph(status) {
    switch status {
        case "waiting": return "⏳ waiting"
        case "running": return "▶ running"
        case "done": return "✔ done"
        case "aborted": return "⛔ aborted"
        default: return "✖ failed"
    }
}

; Re-renders the queue list in the Macro Manager, if it's open.
UpdateQueueUI() {
    global App
    if !IsObject(App.MacroDlg)
        return
    try {
        lv := App.MacroDlg.QueueList
        lv.Delete()
        for i, job in App.Queue
            lv.Add("", i, job.Macro, job.Label, QueueStatusGlyph(job.Status))
    }
}

; --- Macro Manager window ---
OpenMacroManager(*) {
    global App
    if IsObject(App.MacroDlg) {
        try App.MacroDlg.Show()
        return
    }

    dlg := Gui("+Owner" App.Gui.Hwnd, "Macros — Account Queue")
    dlg.BackColor := Colors.Bg
    dlg.MarginX := 14
    dlg.MarginY := 12
    dlg.SetFont("s9 c" Colors.Text, Config.FontMain)

    lv := dlg.Add("ListView", "xm w400 h180 -Multi NoSort", ["Name", "Kind", "Steps", "Length"])
    lv.TipText := "Recorded macros and built routines together — anywhere you can use one, you can use the other. Right-click a linked row in the main list to run either on its client."
    lv.ModifyCol(1, 168)
    lv.ModifyCol(2, 78)
    lv.ModifyCol(3, 50)
    lv.ModifyCol(4, 84)
    dlg.MacroList := lv

    btnRecord := dlg.Add("Button", "xm y+10 w120 h28", "⏺ Record New")
    btnRecord.OnEvent("Click", (*) => MacroMgrRecord(dlg))
    btnRecord.TipText := "Click through the game once — only left-clicks on game windows are recorded, your pauses become the timing. F7 starts/stops from anywhere."
    btnRun := dlg.Add("Button", "x+8 yp w80 h28", "▶ Run")
    btnRun.OnEvent("Click", (*) => MacroMgrRun(dlg))
    btnRun.TipText := "Run the selected macro on the selected account's client. Esc/F7 aborts."
    btnRename := dlg.Add("Button", "x+8 yp w90 h28", "✏ Rename")
    btnRename.OnEvent("Click", (*) => MacroMgrRename(dlg))
    btnDelete := dlg.Add("Button", "x+8 yp w90 h28", "🗑 Delete")
    btnDelete.OnEvent("Click", (*) => MacroMgrDelete(dlg))

    btnRoutine := dlg.Add("Button", "xm y+8 w150 h26", "🧩 Routine Maker")
    btnRoutine.OnEvent("Click", (*) => OpenRoutineMaker())
    btnRoutine.TipText := "Build programs out of your macros: loops, pixel checks, if/else, waits, counters — anything the game needs"
    btnEdit := dlg.Add("Button", "x+8 yp w120 h26", "📝 Open in Editor")
    btnEdit.OnEvent("Click", (*) => MacroMgrEdit(dlg))
    btnEdit.TipText := "Open the selected file in Notepad — hand-edit coordinates, delays or routine steps"
    btnRefresh := dlg.Add("Button", "x+8 yp w90 h26", "⟳ Refresh")
    btnRefresh.OnEvent("Click", (*) => RefreshMacroList(dlg))

    ; --- queue section ---
    dlg.Add("Text", "xm y+12 w400 h2 0x10") ; etched divider
    dlg.SetFont("s9 Bold c" Colors.Text, Config.FontMain)
    qHdr := dlg.Add("Text", "xm y+8", "Queue")
    qHdr.TipText := "Batches jobs — each is one macro on one client — using the macro selected above; runs top to bottom with a breather in between"

    dlg.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
    btnQAll := dlg.Add("Button", "xm y+6 w128 h26", "➕ All clients")
    btnQAll.OnEvent("Click", (*) => MacroMgrQueueAdd(dlg, "all"))
    btnQAll.TipText := "One job per open game client, left-to-right, with the selected macro"
    btnQLinked := dlg.Add("Button", "x+8 yp w150 h26", "➕ Linked accounts")
    btnQLinked.OnEvent("Click", (*) => MacroMgrQueueAdd(dlg, "linked"))
    btnQLinked.TipText := "One job per linked account in the current file, in list order"
    btnQSel := dlg.Add("Button", "x+8 yp w106 h26", "➕ Selected")
    btnQSel.OnEvent("Click", (*) => MacroMgrQueueAdd(dlg, "selected"))
    btnQSel.TipText := "One job on the selected account's client"

    qlv := dlg.Add("ListView", "xm y+8 w400 h140 -Multi NoSort", ["#", "Macro", "Target", "Status"])
    qlv.ModifyCol(1, 28)
    qlv.ModifyCol(2, 140)
    qlv.ModifyCol(3, 128)
    qlv.ModifyCol(4, 88)
    dlg.QueueList := qlv

    btnQStart := dlg.Add("Button", "xm y+8 w140 h28", "▶ Start / Resume")
    btnQStart.OnEvent("Click", StartQueue)
    btnQStart.TipText := "Work through every waiting job, one macro at a time"
    btnQPause := dlg.Add("Button", "x+8 yp w90 h28", "⏸ Pause")
    btnQPause.OnEvent("Click", PauseQueue)
    btnQPause.TipText := "Finish the current macro, then hold the rest (Esc/F7 also pauses)"
    btnQClear := dlg.Add("Button", "x+8 yp w90 h28", "🗑 Clear")
    btnQClear.OnEvent("Click", ClearQueue)
    btnQClear.TipText := "Empty the queue (stops first if it's running)"

    ApplyDialogDarkMode(dlg, [], [lv, qlv])

    dlg.OnEvent("Close", (*) => CloseMacroManager(dlg))
    dlg.OnEvent("Escape", (*) => CloseMacroManager(dlg))

    App.MacroDlg := dlg
    RefreshMacroList(dlg)
    UpdateQueueUI()
    dlg.Show("AutoSize")
}

CloseMacroManager(dlg) {
    global App
    App.MacroDlg := ""
    try dlg.Destroy()
}

; Recording hides the manager so it isn't hovering (topmost, via its
; owner) over the game while you click; StopMacroRecording re-shows it.
ShowMacroManagerAgain() {
    global App
    if IsObject(App.MacroDlg) {
        try App.MacroDlg.Show()
        try RefreshMacroList(App.MacroDlg)
    }
}

RefreshMacroList(dlg) {
    lv := dlg.MacroList
    lv.Delete()
    ; Routines first (they're the composed, higher-level things), then
    ; the raw recordings they're built from.
    for name in ScanRoutines() {
        steps := 0
        try {
            prog := ParseRoutine(FileRead(Config.RoutinesFolder "\" name ".txt", "UTF-8"))
            steps := prog.Steps.Length
        }
        lv.Add("", name, "🧩 routine", steps, "~" Round(AutomationDurationMs(name) / 1000.0, 1) " s")
    }
    for name in ScanMacros() {
        steps := 0
        totalMs := 0
        try {
            m := LoadMacroFile(name)
            steps := m.Steps.Length
            for s in m.Steps
                totalMs += s.Delay
        }
        lv.Add("", name, "macro", steps, Round(totalMs / 1000.0, 1) " s")
    }
}

; The folder a saved automation lives in — routines and macros share a
; name space, so the name alone decides.
AutomationFolder(name) {
    return IsRoutineName(name) ? Config.RoutinesFolder : Config.MacrosFolder
}

MacroMgrSelectedName(dlg) {
    lv := dlg.MacroList
    row := lv.GetNext()
    if (row < 1) {
        ShowToast("Select a macro in the list first")
        return ""
    }
    return lv.GetText(row, 1)
}

MacroMgrRecord(dlg) {
    global App
    if App.IsRecording
        return
    dlg.Hide()
    ToggleMacroRecording()
}

MacroMgrQueueAdd(dlg, mode) {
    name := MacroMgrSelectedName(dlg)
    if (name = "")
        return
    switch mode {
        case "all": QueueMacroOnAllClients(name)
        case "linked": QueueMacroOnLinkedAccounts(name)
        default: QueueMacroOnSelectedAccount(name)
    }
}

MacroMgrRun(dlg) {
    global App
    name := MacroMgrSelectedName(dlg)
    if (name = "")
        return
    acc := GetCurrentAccount()
    if (!IsObject(acc) || !acc.HasOwnProp("ClientHwnd")) {
        ShowToast("Select an account with a linked client first (or right-click a row)")
        return
    }
    RunAutomationOnWindow(name, acc.ClientHwnd)
}

MacroMgrRename(dlg) {
    name := MacroMgrSelectedName(dlg)
    if (name = "")
        return
    ib := ShowInput("New name for `"" name "`":", "Rename Macro", name)
    if (ib.Result != "OK")
        return
    newName := SanitizeMacroName(ib.Value)
    if (newName = "" || newName = name)
        return
    folder := AutomationFolder(name)
    ; The new name must be free in BOTH folders — one shared name space.
    if (FileExist(Config.MacrosFolder "\" newName ".txt")
        || FileExist(Config.RoutinesFolder "\" newName ".txt")) {
        if (ShowConfirm("Something named `"" newName "`" already exists. Overwrite it?", "Confirm Overwrite", "YesNo Icon?") != "Yes")
            return
    }
    try {
        FileMove(folder "\" name ".txt", folder "\" newName ".txt", 1)
        ShowToast("Renamed to `"" newName "`"")
    } catch as err {
        ShowConfirm("Could not rename:`n" err.Message, "Account Queue", "IconX")
    }
    RefreshMacroList(dlg)
}

MacroMgrDelete(dlg) {
    name := MacroMgrSelectedName(dlg)
    if (name = "")
        return
    kind := IsRoutineName(name) ? "routine" : "macro"
    if (ShowConfirm("Delete " kind " `"" name "`"?`n`nThis removes its file permanently.", "Confirm Delete", "YesNo Icon!") != "Yes")
        return
    try FileDelete(AutomationFolder(name) "\" name ".txt")
    ShowToast(kind = "routine" ? "Routine deleted" : "Macro deleted")
    RefreshMacroList(dlg)
}

MacroMgrEdit(dlg) {
    name := MacroMgrSelectedName(dlg)
    if (name = "")
        return
    try Run('notepad.exe "' AutomationFolder(name) "\" name '.txt"')
    ShowToast("Click ⟳ Refresh after saving your edits")
}

; ============================================================
; SETTINGS (Theme, show-passwords, window size — Settings.ini
; inside the Logins folder)
; ============================================================
LoadSettings() {
    global App
    theme := "light"
    showPw := "0"
    onTop := "1"
    autoNext := "1"
    autoIdle := "1"
    minTray := "1"
    viewMode := "credentials"
    winW := Config.WindowWidth
    winH := Config.WindowHeight
    lastFile := ""

    if FileExist(Config.SettingsPath) {
        try theme := IniRead(Config.SettingsPath, "Preferences", "Theme", "light")
        try showPw := IniRead(Config.SettingsPath, "Preferences", "ShowPasswords", "0")
        try onTop := IniRead(Config.SettingsPath, "Preferences", "AlwaysOnTop", "1")
        try autoNext := IniRead(Config.SettingsPath, "Preferences", "AutoNextClient", "1")
        try autoIdle := IniRead(Config.SettingsPath, "Preferences", "AutoRunWhenIdle", "1")
        try minTray := IniRead(Config.SettingsPath, "Preferences", "MinimizeToTray", "1")
        try viewMode := IniRead(Config.SettingsPath, "Preferences", "ViewMode", "credentials")
        try winW := Integer(IniRead(Config.SettingsPath, "Preferences", "WindowWidth", Config.WindowWidth))
        try winH := Integer(IniRead(Config.SettingsPath, "Preferences", "WindowHeight", Config.WindowHeight))
        try lastFile := IniRead(Config.SettingsPath, "Preferences", "LastFile", "")
        ; Saved position (0.28.0) — validated against the current
        ; monitors at Show time, so a detached screen can't strand us.
        wx := "", wy := ""
        try wx := IniRead(Config.SettingsPath, "Preferences", "WindowX", "")
        try wy := IniRead(Config.SettingsPath, "Preferences", "WindowY", "")
        if (IsInteger(wx) && IsInteger(wy)) {
            App.WinX := Integer(wx)
            App.WinY := Integer(wy)
        }
    }

    App.ThemeName := (theme = "dark") ? "dark" : "light"
    App.ShowPasswords := (showPw = "1")
    App.AlwaysOnTop := (onTop = "1")
    App.AutoNextClient := (autoNext = "1")
    App.AutoRunWhenIdle := (autoIdle = "1")
    App.MinimizeToTray := (minTray = "1")
    App.ViewMode := (viewMode = "game") ? "game" : (viewMode = "session") ? "session" : "credentials"
    ; Saved size goes into App.WinW/WinH (applied at Show time), NOT into
    ; Config.WindowWidth/Height — those must stay the design size Gui_Size
    ; uses as its resize baseline. Overwriting them made a restored window
    ; open with the layout stuck at design positions: bottom controls cut
    ; off if the saved window was shorter, dead space if taller.
    App.WinW := Max(420, winW)
    App.WinH := Max(600, winH)

    LoadTuning() ; user-tuned Config overrides ([Tuning] section)
    LoadLoginProfile() ; capture points + probe color ([LoginProfile] section)
    LoadPositionsMap()

    ; Jump to the file we were last on, if it still exists. The account
    ; *within* that file is restored later, once the GUI/list exist —
    ; see RestorePendingAccountPosition(), called from RefreshUI().
    if (lastFile != "") {
        for i, f in App.Files {
            if (f.Name = lastFile) {
                App.CurrentFile := i
                break
            }
        }
    }
}

; Loads the whole "which account was I on in each file" map from the
; [Positions] section of Settings.ini (one key per filename).
LoadPositionsMap() {
    global App
    App.LastPositionPerFile := Map()
    if !FileExist(Config.SettingsPath)
        return
    try {
        raw := IniRead(Config.SettingsPath, "Positions")
        for line in StrSplit(raw, "`n", "`r") {
            if (line = "")
                continue
            eqPos := InStr(line, "=")
            if (eqPos = 0)
                continue
            key := SubStr(line, 1, eqPos - 1)
            val := SubStr(line, eqPos + 1)
            App.LastPositionPerFile[key] := val
        }
    } catch {
        ; No [Positions] section yet — fine, map just stays empty.
    }
}

SaveSettings() {
    global App
    try {
        if !DirExist(Config.LoginsFolder)
            DirCreate(Config.LoginsFolder)
        IniWrite(App.ThemeName, Config.SettingsPath, "Preferences", "Theme")
        IniWrite(App.ShowPasswords ? "1" : "0", Config.SettingsPath, "Preferences", "ShowPasswords")
        IniWrite(App.AlwaysOnTop ? "1" : "0", Config.SettingsPath, "Preferences", "AlwaysOnTop")
        IniWrite(App.ViewMode, Config.SettingsPath, "Preferences", "ViewMode")
        IniWrite(App.AutoNextClient ? "1" : "0", Config.SettingsPath, "Preferences", "AutoNextClient")
        IniWrite(App.AutoRunWhenIdle ? "1" : "0", Config.SettingsPath, "Preferences", "AutoRunWhenIdle")
        IniWrite(App.MinimizeToTray ? "1" : "0", Config.SettingsPath, "Preferences", "MinimizeToTray")
        ; GetClientPos, not GetPos: Show() and MinSize both work in
        ; CLIENT-area dimensions, so saving the outer size here (client +
        ; title bar + borders) made the window grow by the chrome size on
        ; every single save/restart. Skipped while maximized/minimized —
        ; those would save a size that means nothing once restored.
        if (App.Gui != "" && WinGetMinMax("ahk_id " App.Gui.Hwnd) = 0) {
            App.Gui.GetClientPos(, , &curW, &curH)
            IniWrite(curW, Config.SettingsPath, "Preferences", "WindowWidth")
            IniWrite(curH, Config.SettingsPath, "Preferences", "WindowHeight")
            ; Position is OUTER coords — that's what Show("x y") takes.
            WinGetPos(&curX, &curY, , , "ahk_id " App.Gui.Hwnd)
            IniWrite(curX, Config.SettingsPath, "Preferences", "WindowX")
            IniWrite(curY, Config.SettingsPath, "Preferences", "WindowY")
        }
        if (App.Files.Length > 0 && App.CurrentFile >= 1 && App.CurrentFile <= App.Files.Length)
            IniWrite(App.Files[App.CurrentFile].Name, Config.SettingsPath, "Preferences", "LastFile")
        SavePositionsMap()
    } catch {
        ; Non-fatal — preferences just won't persist for next time.
    }
}

; Captures exactly where we are right now for the current file (so the
; very last position is always accurate even if you never switched away
; from that file this session), then writes the whole per-file map.
SavePositionsMap() {
    global App
    if (App.Files.Length > 0) {
        acc := GetCurrentAccount()
        if IsObject(acc)
            App.LastPositionPerFile[App.Files[App.CurrentFile].Name] := acc.Email
    }
    for fileName, accEmail in App.LastPositionPerFile {
        try IniWrite(accEmail, Config.SettingsPath, "Positions", fileName)
    }
}

; ============================================================
; AUTO-LOGIN ORCHESTRATOR (🚀 Launch & Login)
; ------------------------------------------------------------
; Fed by the pick queue (or the selected account). Launches one client
; per picked account in parallel, waits the boot time once, then walks
; each new window through a fixed funnel:
;   1. UNSTICK: read the "logout->login" probe pixel; while it isn't the
;      captured color, click Try Again and re-poll (this is the stuck-
;      load fix). Timeout after LoginMaxWaitMs.
;   2. LOGOUT: click the logout->login button (always, to guarantee we
;      land on the login page even if the client auto-logged-in).
;   3. LOGIN: click the Email field, then paste email->Tab->password->
;      Enter (same as F4 — credentials never touch a macro file).
;   4. ENTER: wait, click Start Game, wait, click the Character.
;   5. LINK: tag that account to that window; the session clock starts.
; All five click POINTs and the probe COLOR are captured once via the
; Login Setup window; stored window-relative + scaled like macros.
; Esc/F7 aborts; a window that fails a stage is skipped, batch continues.
; ============================================================
; Every point carries its own probe colour now: X,Y,RefW,RefH,Color.
LoadLoginProfile() {
    global App
    App.LoginProfile := { Points: Map() }
    if !FileExist(Config.SettingsPath)
        return
    for key in ["tryagain", "logout", "email", "start", "char"] {
        raw := ""
        try raw := IniRead(Config.SettingsPath, "LoginProfile", key, "")
        parts := StrSplit(raw, ",")
        if (parts.Length >= 5)
            App.LoginProfile.Points[key] := { X: Integer(parts[1]), Y: Integer(parts[2])
                , RefW: Integer(parts[3]), RefH: Integer(parts[4]), Color: parts[5] }
    }
}

SaveLoginProfile() {
    global App
    for key, p in App.LoginProfile.Points
        try IniWrite(p.X "," p.Y "," p.RefW "," p.RefH "," p.Color, Config.SettingsPath, "LoginProfile", key)
}

LoginProfileReady() {
    global App
    for key in ["tryagain", "logout", "email", "start", "char"] {
        if (!App.LoginProfile.Points.Has(key) || App.LoginProfile.Points[key].Color = "")
            return false
    }
    return true
}

; A captured window-relative point -> current screen coords for a given
; window, scaled if the window is a different size than at capture time
; (reuses the macro scaling math).
LoginPointScreen(key, wx, wy, ww, wh) {
    global App
    p := App.LoginProfile.Points[key]
    return MacroStepScreenPos({ X: p.X, Y: p.Y }, p.RefW, p.RefH, wx, wy, ww, wh)
}

LoginClick(hwnd, key) {
    if !WinExistAnyDesktop(hwnd)
        return false
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
    pos := LoginPointScreen(key, wx, wy, ww, wh)
    CoordMode("Mouse", "Screen")
    Click(pos[1], pos[2])
    return true
}

; Is a given point's captured colour currently showing on the window?
; This is how every stage knows the screen it expects has arrived.
LoginProbe(hwnd, key) {
    global App
    if (!App.LoginProfile.Points.Has(key) || !WinExistAnyDesktop(hwnd))
        return false
    p := App.LoginProfile.Points[key]
    if (p.Color = "")
        return false
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
    pos := LoginPointScreen(key, wx, wy, ww, wh)
    CoordMode("Pixel", "Screen")
    got := 0
    try got := PixelGetColor(pos[1], pos[2])
    catch
        return false
    return ColorsClose(got, p.Color, Config.LoginColorTol)
}

ColorsClose(a, b, tol) {
    a := Integer(a), b := Integer(b)
    dr := Abs(((a >> 16) & 0xFF) - ((b >> 16) & 0xFF))
    dg := Abs(((a >> 8) & 0xFF) - ((b >> 8) & 0xFF))
    db := Abs((a & 0xFF) - (b & 0xFF))
    return (dr <= tol && dg <= tol && db <= tol)
}

; Guards + builds the login batch (pick queue, else selection). Returns
; an array, or "" (with a toast/dialog) if it can't run. Shared by the
; legacy menu path and the Mass Login console.
PrepareLoginBatch() {
    global App
    if (App.LoginRunning || App.MacroPlaying || App.IsRecording || App.QueueRunning) {
        ShowToast("Finish the current automation first")
        return ""
    }
    if !LoginProfileReady() {
        ShowToast("Set up Launch + Login first (⚙ → Login Setup)")
        OpenLoginSetup()
        return ""
    }
    if !FileExist(Config.LauncherPath) {
        ShowConfirm("Launcher not found:`n" Config.LauncherPath "`n`nSet the path in ⚙ Preferences.", "Account Queue", "IconX")
        return ""
    }
    batch := []
    if App.LoginQueue.Length {
        for acc in App.LoginQueue
            batch.Push(acc)
    } else {
        acc := GetCurrentAccount()
        if IsObject(acc)
            batch.Push(acc)
    }
    if (batch.Length = 0) {
        ShowToast("Pick accounts first (⊕ Pick), or select one")
        return ""
    }
    return batch
}

LaunchWithMode(mode, batch) {
    global App
    App.LoginMode := mode
    App.LoginStopReq := false
    App.LoginFailedDrops := [] ; fresh run — last run's casualties are stale
    for acc in batch {
        acc.DeleteProp("_macroRan")   ; fresh run — playlists restart
        acc.DeleteProp("_macroIdx")
        acc.DeleteProp("_loginFails") ; fresh run — failure strikes reset
    }
    App.LoginRunning := true
    App.LoginBatch := batch
    SetTimer(LoginWorker, -1)
}

; Dispatcher: runs on its own timer thread so the button returns.
LoginWorker() {
    global App
    try {
        if (App.LoginMode = "activity")
            RunActivity(App.LoginBatch)
        else if (App.LoginMode = "chore")
            RunChore(App.LoginBatch)
        else
            RunPlay(App.LoginBatch)
    } catch as err {
        ShowToast("Launch + Login stopped: " err.Message)
    }
    stopped := App.LoginStopReq
    App.LoginRunning := false
    App.LoginStopReq := false
    App.LoginStatusText := ""
    if (App.LoginQueue.Length = 0)
        App.PickMode := false
    RefreshPickUI()
    RefreshList()
    RefreshLinkStatus()
    ; Chain the double-click mini queue — unless the user stopped the
    ; run, which cancels anything still waiting.
    if App.PendingSingles.Length {
        if stopped {
            App.PendingSingles := []
            ShowToast("Waiting logins cleared (run was stopped)")
        } else {
            StartNextPendingSingle()
        }
    }
}

; Play mode: log everyone in (in groups of LaunchMax) and leave running.
; Post-login macros run AFTER all logins finish, in one sweep — so
; logins aren't interrupted and every client is up first.
RunPlay(batch) {
    global App
    total := batch.Length
    succeeded := []
    pos := 1
    while (pos <= total && !AbortPressed()) {
        chunk := TakeChunk(batch, &pos, Config.LaunchMax)
        LoginGroup(chunk, succeeded)
    }
    for acc in succeeded {
        idx := LoginQueueIndex(acc)
        if idx
            App.LoginQueue.RemoveAt(idx)
    }
    ; Anyone not logged in by the end of a full (non-aborted) pass is a
    ; casualty — surfaced in the console with one-click re-add.
    if !AbortPressed() {
        for acc in batch {
            if !LoginQueueIndex2(succeeded, acc)
                App.LoginFailedDrops.Push(acc)
        }
    }

    ; Macro playlists, round by round, no time limit in Play mode.
    while (!AbortPressed() && IsObject(macAcc := FirstPendingMacro(succeeded, false))) {
        SetLoginStatus("Macro on " macAcc.Name "…")
        RunAccountMacro(macAcc)
    }
    ShowToast("Play finished — " succeeded.Length " / " total " logged in")
}

; Activity mode: keep OnlineCap accounts online CONCURRENTLY, each until
; it reaches the session goal. OnlineCap is a concurrency limit, not a
; batch size — the instant one client finishes and frees a slot, the
; next queued account is launched to refill it (no waiting for a whole
; "wave" to complete). One continuous loop: reap → refill → wait, repeat.
RunActivity(batch) {
    global App
    queue := []
    for acc in batch
        queue.Push(acc)
    target := queue.Length
    finished := []
    active := []   ; accounts currently online, being kept until the goal

    loop {
        if StopPressed()
            break ; F7 stop — leave every client exactly as it is
        goalMs := Config.SessionGoalMinutes * 60000

        ; 1. REAP: close any active account that hit the goal (freeing its
        ;    slot), requeue any whose client died early; keep the rest.
        active := ReapActive(active, queue, finished)

        ; 2. Everything processed?
        if (queue.Length = 0 && active.Length = 0)
            break

        ; 3. REFILL free slots from the queue. At-goal accounts finish
        ;    without using a slot; already-online ones are adopted; the
        ;    rest form a launch group of up to LaunchMax for this pass.
        launchGroup := []
        while (queue.Length && active.Length + launchGroup.Length < Config.OnlineCap
                && launchGroup.Length < Config.LaunchMax) {
            acc := queue.RemoveAt(1)
            online := AccountIsOnline(acc)
            if (AccountOnlineMs(acc) >= goalMs) {
                if online
                    try WinClose("ahk_id " acc.ClientHwnd)
                DetachClient(acc)
                finished.Push(acc)
            } else if online {
                active.Push(acc)   ; adopt a client that's already running
            } else {
                launchGroup.Push(acc)
            }
        }

        ; 4. Launch + log in this group (attended; Esc aborts). Successes
        ;    join the active set; FAILURES go to the back of the queue
        ;    like dead clients do — dropped only after failing twice.
        if launchGroup.Length {
            loggedIn := []
            LoginGroup(launchGroup, loggedIn)
            if AbortPressed()
                break
            for acc in loggedIn {
                acc.DeleteProp("_loginFails")
                active.Push(acc)
            }
            for acc in launchGroup {
                if LoginQueueIndex2(loggedIn, acc)
                    continue
                fails := (acc.HasOwnProp("_loginFails") ? acc._loginFails : 0) + 1
                if (fails >= 3) {
                    App.LoginFailedDrops.Push(acc) ; surfaced in the console; ➕ → Re-add failed
                    ShowToast(acc.Name " failed to log in repeatedly — dropped from this run")
                } else {
                    acc._loginFails := fails
                    queue.Push(acc)
                }
            }
            continue
        }

        ; 5. Batch is as full as it can get and now idling toward the
        ;    goal — run macro playlists, round by round, REAPING between
        ;    each run. Every macro must FIT THE TIME BUDGET (remaining
        ;    time minus the reserve) — if it doesn't, that account's
        ;    remaining macros are skipped and you get one plain toast.
        skippedT := 0
        while IsObject(macAcc := FirstPendingMacro(active)) {
            if !MacroFitsBudget(macAcc) {
                macAcc._macroIdx := 100000 ; time doesn't allow the rest
                skippedT += 1
                continue
            }
            SetLoginStatus("Macro on " macAcc.Name "…")
            RunAccountMacro(macAcc)
            active := ReapActive(active, queue, finished)
            if StopPressed()
                break
        }
        if skippedT
            ShowToast("⏱ Idle time doesn't allow the remaining macros on " skippedT " account(s)")
        if StopPressed()
            break
        ; If a slot freed while doing macros, go straight back to refill.
        if (active.Length < Config.OnlineCap && queue.Length)
            continue

        ; 6. Nothing to launch, no macros pending — waiting for the
        ;    soonest client to reach the goal so its slot frees.
        soon := 0
        for acc in active {
            l := Config.SessionGoalMinutes * 60000 - AccountOnlineMs(acc)
            if (soon = 0 || l < soon)
                soon := l
        }
        SetLoginStatus(active.Length " online, waiting — next free slot in " MinsLeft(soon)
            (queue.Length ? " (" queue.Length " queued to fill it)" : ""))
        if !MonitorSleep(Config.LoginMonitorMs)
            break
    }

    for acc in finished {
        idx := LoginQueueIndex(acc)
        if idx
            App.LoginQueue.RemoveAt(idx)
    }
    IdleHist("Activity (daily quota)", "—", finished.Length < target ? "info" : "ok"
        , "finished: " finished.Length " / " target " reached " Config.SessionGoalMinutes " min")
    ShowToast("Activity finished — " finished.Length " / " target " reached " Config.SessionGoalMinutes " min")
}

; Closes any active account that reached the goal (banked + live minutes,
; read live so ⚙ changes apply), requeues any whose client died early
; (banked partial time survives), and returns the accounts still going.
ReapActive(active, queue, finished) {
    goalMs := Config.SessionGoalMinutes * 60000
    stillGoing := []
    for acc in active {
        t := AccountOnlineMs(acc)
        alive := AccountIsOnline(acc)
        if (t >= goalMs) {
            if alive
                try WinClose("ahk_id " acc.ClientHwnd)
            DetachClient(acc)
            finished.Push(acc)
        } else if !alive {
            DetachClient(acc)  ; died early — its banked time is kept
            queue.Push(acc)    ; refill will relaunch it later
        } else {
            stillGoing.Push(acc)
        }
    }
    return stillGoing
}

; Like LoginQueueIndex but against an arbitrary array (object identity).
LoginQueueIndex2(arr, acc) {
    for i, a in arr {
        if (a = acc)
            return i
    }
    return 0
}

; The account whose NEXT macro is earliest in its playlist — this makes
; rounds emerge naturally (everyone's macro 1, then everyone's macro 2).
FirstPendingMacro(arr, checkGoal := true) {
    best := ""
    bestIdx := 0
    for acc in arr {
        if !AccountPendingMacro(acc, checkGoal)
            continue
        i := acc.HasOwnProp("_macroIdx") ? acc._macroIdx : 1
        if (best = "" || i < bestIdx) {
            best := acc
            bestIdx := i
        }
    }
    return best
}

TakeChunk(arr, &pos, size) {
    chunk := []
    loop Min(size, arr.Length - pos + 1) {
        chunk.Push(arr[pos])
        pos += 1
    }
    return chunk
}

; Launches a group of clients (one per account), waits for them to boot,
; then logs each in (with close+relaunch retries). Appends the accounts
; that succeeded to succeededOut.
LoginGroup(chunk, succeededOut) {
    newWindows := []
    for acc in chunk {
        if AbortPressed()
            break
        before := GameWindowSet()
        Run(Config.LauncherPath)
        hwnd := WaitForNewGameWindow(before, 15000)
        if hwnd
            newWindows.Push(hwnd)
        SetLoginStatus("Launching client " newWindows.Length " / " chunk.Length " for " acc.Name "…")
        AbortableSleep(1200) ; stagger launches a touch
    }
    if (newWindows.Length = 0)
        return
    SetLoginStatus("Waiting for " newWindows.Length " client(s) to load (" Round(Config.LoginBootMs / 1000) "s)…")
    if !AbortableSleep(Config.LoginBootMs)
        return
    loop Min(newWindows.Length, chunk.Length) {
        i := A_Index
        acc := chunk[i]
        SetLoginStatus("Logging in " acc.Name "…")
        if LoginWithRetry(acc, newWindows[i])
            succeededOut.Push(acc)
        if AbortPressed()
            break
    }
}

; Runs the funnel on a window; on failure closes that client, relaunches
; a fresh one and retries, up to LoginMaxRetries.
LoginWithRetry(acc, hwnd) {
    tries := 0
    loop {
        if LoginFunnel(acc, hwnd)
            return true
        if AbortPressed()
            return false
        try WinClose("ahk_id " hwnd)
        tries += 1
        if (tries > Config.LoginMaxRetries) {
            ShowToast(acc.Name " failed to log in — skipped")
            return false
        }
        SetLoginStatus("Retry " tries " for " acc.Name " — relaunching…")
        if !AbortableSleep(2000)
            return false
        before := GameWindowSet()
        Run(Config.LauncherPath)
        hwnd := WaitForNewGameWindow(before, 15000)
        if !hwnd
            return false
        if !AbortableSleep(Config.LoginBootMs)
            return false
    }
}

; The full colour-probed funnel for one window. Returns true on success,
; false on any step timing out (the caller then closes + relaunches).
;   can't find try-again nor logout (times out) -> fail
;   try-again until logout detected -> logout until email detected ->
;   email + F4 -> wait for start button -> start until character -> click.
LoginFunnel(acc, hwnd) {
    if !WinExistAnyDesktop(hwnd)
        return false
    try WinActivate("ahk_id " hwnd)
    if !AbortableSleep(Config.LoginStepMs)
        return false

    ; 1. UNSTICK — Try Again until the logout button (loaded) shows, or
    ;    the login page is already open. Neither appearing = timeout.
    SetLoginStatus(acc.Name ": waiting for load / clicking Try Again…")
    dl := A_TickCount + Config.LoginMaxWaitMs
    last := 0
    while !(LoginProbe(hwnd, "logout") || LoginProbe(hwnd, "email")) {
        if (AbortPressed() || !WinExistAnyDesktop(hwnd))
            return false
        if (A_TickCount - last >= Config.LoginPollMs && LoginProbe(hwnd, "tryagain")) {
            LoginClick(hwnd, "tryagain")
            last := A_TickCount
        }
        if (A_TickCount > dl)
            return false
        if !AbortableSleep(Config.LoginPagePollMs)
            return false
    }

    ; 2. LOGOUT until the login page (email probe) opens.
    SetLoginStatus(acc.Name ": clicking Logout → login page…")
    dl := A_TickCount + Config.LoginPageMaxMs
    last := 0
    while !LoginProbe(hwnd, "email") {
        if (AbortPressed() || !WinExistAnyDesktop(hwnd))
            return false
        if (A_TickCount - last >= Config.LoginLogoutRetryMs) {
            LoginClick(hwnd, "logout")
            last := A_TickCount
        }
        if (A_TickCount > dl)
            return false
        if !AbortableSleep(Config.LoginPagePollMs)
            return false
    }

    ; 3. EMAIL + F4 ASAP (login page must not linger — game freezes).
    SetLoginStatus(acc.Name ": entering credentials (F4)…")
    LoginClick(hwnd, "email")
    if !AbortableSleep(Config.LoginEmailToF4Ms)
        return false
    if !TypeCredentialsInto(hwnd, acc)
        return false
    AbortableSleep(Config.LoginAfterCredsMs)

    ; 4. Wait for the Start Game button; timeout -> fail (close+retry).
    SetLoginStatus(acc.Name ": Start Game → selecting character…")
    dl := A_TickCount + Config.LoginStartMaxMs
    while !LoginProbe(hwnd, "start") {
        if (AbortPressed() || !WinExistAnyDesktop(hwnd))
            return false
        if (A_TickCount > dl)
            return false
        if !AbortableSleep(Config.LoginPagePollMs)
            return false
    }

    ; 5. START until character selection appears.
    dl := A_TickCount + Config.LoginCharMaxMs
    last := 0
    while !LoginProbe(hwnd, "char") {
        if (AbortPressed() || !WinExistAnyDesktop(hwnd))
            return false
        if (A_TickCount - last >= Config.LoginStartRetryMs) {
            LoginClick(hwnd, "start")
            last := A_TickCount
        }
        if (A_TickCount > dl)
            return false
        if !AbortableSleep(Config.LoginPagePollMs)
            return false
    }

    ; 6. CHARACTER -> success. Link the account; the session clock starts.
    LoginClick(hwnd, "char")
    if !AbortableSleep(Config.LoginStepMs)
        return false
    try WinActivate("ahk_id " hwnd)
    LinkActiveWindowToAccount2(acc, hwnd)
    return true ; the post-login macro runs later, in the macro phase
}

; --- Macro PLAYLISTS: each account can have several macros assigned
; (App.LoginMacros: email -> array of names). They run in ROUNDS —
; macro 1 across every account, then macro 2 across every account, … —
; tracked by acc._macroIdx (next playlist position; cleared on relogin
; and at the start of a fresh run). ---
AccountMacroList(acc) {
    global App
    return App.LoginMacros.Has(acc.Email) ? App.LoginMacros[acc.Email] : []
}

; Has this account a next macro to run, on a live client? checkGoal:
; Activity skips accounts at the goal; Play passes false.
AccountPendingMacro(acc, checkGoal := true) {
    list := AccountMacroList(acc)
    idx := acc.HasOwnProp("_macroIdx") ? acc._macroIdx : 1
    return (list.Length > 0 && idx <= list.Length)
        && AccountIsOnline(acc)
        && (!checkGoal || AccountOnlineMs(acc) < Config.SessionGoalMinutes * 60000)
}

; Runs the account's NEXT playlist macro and advances its position.
RunAccountMacro(acc) {
    global App
    list := AccountMacroList(acc)
    idx := acc.HasOwnProp("_macroIdx") ? acc._macroIdx : 1
    if (idx > list.Length)
        return
    App.LoginMacroPlayingEmail := acc.Email
    SetLoginStatus("Running '" list[idx] "' on " acc.Name " (" idx " / " list.Length ")…")
    RunAutomationOnWindow(list[idx], acc.ClientHwnd)
    App.LoginMacroPlayingEmail := ""
    acc._macroIdx := idx + 1
}

; Rough runtime of one macro: recorded delays + ~1s per click + settle.
MacroDurationMs(name) {
    total := 3000
    try {
        m := LoadMacroFile(name)
        for s in m.Steps
            total += s.Delay + 1000
    }
    return total
}

; Activity's time budget: the next macro must fit inside this account's
; remaining time to the goal MINUS the reserve. Because remaining time
; shrinks as macros run, total macro time naturally stays within
; "idle minus reserve" (45 min idle, 15 reserve -> up to 30 min of macros).
MacroFitsBudget(acc) {
    list := AccountMacroList(acc)
    idx := acc.HasOwnProp("_macroIdx") ? acc._macroIdx : 1
    if (idx > list.Length)
        return false
    left := Config.SessionGoalMinutes * 60000 - AccountOnlineMs(acc)
    return AutomationDurationMs(list[idx]) + Config.MacroReserveMinutes * 60000 <= left
}

; Pastes email -> Tab -> password -> Enter into a specific window, using
; the same shared-clipboard-slot discipline as PasteComboLogin.
TypeCredentialsInto(hwnd, acc) {
    global App
    if (acc.Email = "" || acc.Password = "")
        return false
    if !WinExistAnyDesktop(hwnd)
        return false
    WinActivate("ahk_id " hwnd)
    if !IsObject(App.SavedClip)
        App.SavedClip := ClipboardAll()
    ok := false
    try {
        A_Clipboard := acc.Email
        if !ClipWait(1)
            throw Error("clipboard")
        Send("^v")
        Sleep(Config.ComboStepDelayMs)
        Send("{Tab}")
        Sleep(Config.ComboStepDelayMs)
        A_Clipboard := acc.Password
        if !ClipWait(1)
            throw Error("clipboard")
        Send("^v")
        Sleep(Config.ComboStepDelayMs)
        Send("{Enter}")
        ok := true
    } catch {
        ok := false
    } finally {
        RestoreClipboard()
    }
    StampLastLogin(acc)
    return ok
}

; ============================================================
; MASS LOGIN CONSOLE (🚀) — add accounts, assign post-login macros,
; pick Play/Activity, and watch live status in one window.
; ============================================================
; Everything runnable, macros and routines alike (names are unique
; across both — the save paths enforce it), so playlists and the queue
; can hold either.
MacroChoices() {
    out := ["(none)"]
    for m in AutomationNames()
        out.Push(m)
    return out
}

AutomationNames() {
    out := []
    for r in ScanRoutines()
        out.Push(r)
    for m in ScanMacros()
        out.Push(m)
    return out
}

ConsoleMacroLabel(acc) {
    list := AccountMacroList(acc)
    if !list.Length
        return "—"
    return list.Length = 1 ? list[1] : list[1] " +" (list.Length - 1)
}

OpenLoginConsole(*) {
    global App
    if IsObject(App.LoginConsoleDlg) {
        try App.LoginConsoleDlg.Show()
        RefreshLoginConsole()
        return
    }
    dlg := Gui("+Owner" App.Gui.Hwnd, "Mass Login — Account Queue")
    dlg.BackColor := Colors.Bg
    dlg.MarginX := 12
    dlg.MarginY := 10
    dlg.SetFont("s9 c" Colors.Text, Config.FontMain)

    ; --- overview stat row (color-coded, grouped) ---
    dlg.SetFont("s11 Bold")
    dlg.StatDone := dlg.Add("Text", "xm w96 Center c" Colors.Success, "✔ 0")
    dlg.StatOnline := dlg.Add("Text", "x+4 yp w96 Center c" Colors.Info, "● 0")
    dlg.StatLeft := dlg.Add("Text", "x+4 yp w96 Center c" Colors.Text, "⏳ 0")
    dlg.StatEta := dlg.Add("Text", "x+4 yp w220 Center c" Colors.Text, "ETA —")
    dlg.SetFont("s7 Norm Italic c" Colors.TextDim)
    dlg.Add("Text", "xm w96 Center", "done")
    dlg.Add("Text", "x+4 yp w96 Center", "online")
    dlg.Add("Text", "x+4 yp w96 Center", "queued")
    dlg.Add("Text", "x+4 yp w220 Center", "est. finish")

    dlg.SetFont("s9 Norm c" Colors.Text)
    bAdd := dlg.Add("Button", "xm y+8 w80 h24", "➕ Add")
    bAdd.OnEvent("Click", (*) => ConsoleAddMenu())
    bAdd.TipText := "Add accounts: all in current file / all files / all not-done (under the goal)"
    b4 := dlg.Add("Button", "x+4 yp w70 h24", "🗑 Clear")
    b4.OnEvent("Click", (*) => (ClearPickQueue(), RefreshLoginConsole()))
    b4.TipText := "Empty the login queue (doesn't touch online clients)"

    lv := dlg.Add("ListView", "xm y+8 w520 h240", ["#", "Account", "File", "Macros", "Left", "Status"])
    lv.ModifyCol(1, 28), lv.ModifyCol(2, 120), lv.ModifyCol(3, 80), lv.ModifyCol(4, 100), lv.ModifyCol(5, 70), lv.ModifyCol(6, 110)
    lv.OnEvent("ContextMenu", (ctrl, *) => ConsoleTableMenu(dlg))
    lv.OnEvent("DoubleClick", (ctrl, row) => ConsoleJumpRow(dlg, row))
    lv.TipText := "Right-click a row: remove · move to top · clear its macros.  Double-click: show it in the main window"
    dlg.ConsoleList := lv
    dlg.ConsoleAccts := []

    ddl := dlg.Add("DropDownList", "xm y+8 w160 Choose1", MacroChoices())
    dlg.MacroDDL := ddl
    ddl.TipText := "Macros run round by round after login — ➕ appends, (none) clears"
    ma1 := dlg.Add("Button", "x+6 yp w100 h24", "➕ Selected")
    ma1.OnEvent("Click", (*) => ConsoleAssignMacro(dlg, false))
    ma2 := dlg.Add("Button", "x+4 yp w80 h24", "➕ All")
    ma2.OnEvent("Click", (*) => ConsoleAssignMacro(dlg, true))
    ma3 := dlg.Add("Button", "x+4 yp w110 h24", "▶ Run now")
    ma3.OnEvent("Click", RunMacrosNow)
    ma3.TipText := "Run every playlist on its ONLINE account right now, in rounds — no launching or login run needed"

    dlg.RPlay := dlg.Add("Radio", "xm y+10 Checked", "▶ Play")
    dlg.RPlay.TipText := "Log everyone in, leave the clients running"
    rAct := dlg.Add("Radio", "x+14 yp", "⏱ Activity")
    rAct.TipText := "Keep up to 'Online cap' accounts online until each reaches the goal, then close it — idle time runs the assigned macros"
    lblLaunch := dlg.Add("Text", "xm y+8 h20", "Launch group")
    dlg.NumLaunch := dlg.Add("Edit", "x+4 yp-2 w40 h22", Config.LaunchMax)
    lblLaunch.TipText := dlg.NumLaunch.TipText := "Clients opened at once per launch wave"
    lblCap := dlg.Add("Text", "x+10 yp+2 h20", "Online cap")
    dlg.NumCap := dlg.Add("Edit", "x+4 yp-2 w40 h22", Config.OnlineCap)
    lblCap.TipText := dlg.NumCap.TipText := "Activity: most accounts kept online at the same time"
    lblGoal := dlg.Add("Text", "x+10 yp+2 h20", "Goal (min)")
    dlg.NumGoal := dlg.Add("Edit", "x+4 yp-2 w40 h22", Config.SessionGoalMinutes)
    lblGoal.TipText := dlg.NumGoal.TipText := "Minutes online for an account to count as done"

    start := dlg.Add("Button", "xm y+12 w150 h30 Default", "🚀 Start")
    start.OnEvent("Click", (*) => ConsoleStart(dlg))
    stop := dlg.Add("Button", "x+8 yp w110 h30", "⏹ Stop")
    stop.OnEvent("Click", StopLoginRun)
    more := dlg.Add("Button", "x+8 yp w50 h30", "⋯")
    more.OnEvent("Click", (*) => ConsoleMoreMenu(dlg))
    more.TipText := "More: close clients that reached the goal"
    dlg.SetFont("s9 Bold c" Colors.Accent)
    dlg.StatusLine := dlg.Add("Text", "xm y+10 w520 h32", "Idle — press Start")

    ApplyDialogDarkMode(dlg, [dlg.NumLaunch, dlg.NumCap, dlg.NumGoal], [lv])
    dlg.OnEvent("Close", (*) => CloseLoginConsole(dlg))
    dlg.OnEvent("Escape", (*) => CloseLoginConsole(dlg))
    App.LoginConsoleDlg := dlg
    RefreshLoginConsole()
    SetTimer(RefreshLoginConsole, 1500)
    dlg.Show("AutoSize")
}

; Double-click a console row → select that account in the main list
; (same cross-file jump the board and online view use).
ConsoleJumpRow(dlg, row) {
    if (row >= 1 && row <= dlg.ConsoleAccts.Length)
        JumpToAccount(dlg.ConsoleAccts[row])
}

CloseLoginConsole(dlg) {
    global App
    SetTimer(RefreshLoginConsole, 0)
    App.LoginConsoleDlg := ""
    try dlg.Destroy()
}

; Live view: online accounts first (with what macro is running, if any),
; then the queued ones with the first marked "next".
; IMPORTANT: when the row set hasn't changed, cells are updated IN PLACE
; (no Delete+Add) — a rebuild every tick was resetting the scroll to the
; top, killing selections and yanking open right-click menus.
RefreshLoginConsole(*) {
    global App
    if (!IsObject(App.LoginConsoleDlg) || App.ConsoleHold)
        return
    dlg := App.LoginConsoleDlg
    lv := dlg.ConsoleList
    goalMs := Config.SessionGoalMinutes * 60000

    rows := []
    onlineN := 0, doneN := 0, maxLeftMs := 0
    for f in App.Files {
        for acc in f.Accounts {
            if !(AccountIsOnline(acc))
                continue
            onlineN += 1
            atGoal := AccountOnlineMs(acc) >= goalMs
            if atGoal
                doneN += 1
            leftMs := Max(0, goalMs - AccountOnlineMs(acc))
            if (leftMs > maxLeftMs)
                maxLeftMs := leftMs
            st := (App.LoginMacroPlayingEmail = acc.Email) ? "▶ macro" : (atGoal ? "✔ done" : "● online")
            rows.Push({ Acc: acc, FileName: f.Name, St: st, Left: atGoal ? "done" : MinsLeft(leftMs) })
        }
    }
    first := true
    for acc in App.LoginQueue {
        if (AccountIsOnline(acc))
            continue
        rows.Push({ Acc: acc, FileName: FindFileOfAccount(acc).Name, St: first ? "→ next" : "queued"
            , Left: (AccountOnlineMs(acc) > 0 ? MinsLeft(goalMs - AccountOnlineMs(acc)) : "—") })
        first := false
    }

    same := rows.Length = dlg.ConsoleAccts.Length
    if same {
        for i, r in rows {
            if (dlg.ConsoleAccts[i] != r.Acc) {
                same := false
                break
            }
        }
    }
    if same {
        for i, r in rows
            lv.Modify(i, "", i, r.Acc.Name, r.FileName, ConsoleMacroLabel(r.Acc), r.Left, r.St)
    } else {
        selected := ConsoleSelectedAccts(dlg)
        lv.Delete()
        accts := []
        for i, r in rows {
            accts.Push(r.Acc)
            lv.Add("", i, r.Acc.Name, r.FileName, ConsoleMacroLabel(r.Acc), r.Left, r.St)
        }
        dlg.ConsoleAccts := accts
        for selAcc in selected {
            idx := LoginQueueIndex2(accts, selAcc)
            if idx
                lv.Modify(idx, "Select")
        }
    }

    ; --- overview stats + ETA ---
    queuedN := 0
    for acc in App.LoginQueue {
        if !(AccountIsOnline(acc))
            queuedN += 1
    }
    SetConsoleStat(dlg.StatDone, "✔ " doneN)
    SetConsoleStat(dlg.StatOnline, "● " onlineN)
    SetConsoleStat(dlg.StatLeft, "⏳ " queuedN)
    SetConsoleStat(dlg.StatEta, "ETA " ConsoleEta(queuedN, onlineN, maxLeftMs))

    dlg.StatusLine.Value := App.LoginRunning ? App.LoginStatusText
        : (App.LoginFailedDrops.Length
            ? "Idle — ✖ " App.LoginFailedDrops.Length " failed last run   (➕ → Re-add failed)"
            : "Idle — press Start")
}

MinsLeft(ms) {
    return ms <= 0 ? "0m" : Ceil(ms / 60000) "m"
}

SetConsoleStat(ctrl, txt) {
    if (ctrl.Value != txt)
        ctrl.Value := txt
}

; Rough finish estimate. Play (no goal): just how long the queued logins
; take. Activity: current batch drains in maxLeft, then remaining waves
; each add a full goal + login time.
ConsoleEta(queuedN, onlineN, maxLeftMs) {
    global App
    if (App.LoginMode != "activity" || !App.LoginRunning) {
        ; Play / idle: ~login time per still-queued account.
        if (queuedN = 0)
            return onlineN ? "running" : "—"
        return "~" Ceil(queuedN * (Config.LoginBootMs + 20000) / 60000) "m (logins)"
    }
    goalMs := Config.SessionGoalMinutes * 60000
    waveMs := Config.LoginBootMs + 20000 + goalMs
    remainingWaves := Ceil(queuedN / Config.OnlineCap)
    etaMs := maxLeftMs + remainingWaves * waveMs
    return "~" Ceil(etaMs / 60000) "m"
}

ConsoleSelectedAccts(dlg) {
    out := []
    lv := dlg.ConsoleList
    row := 0
    loop {
        row := lv.GetNext(row)
        if !row
            break
        if (row <= dlg.ConsoleAccts.Length)
            out.Push(dlg.ConsoleAccts[row])
    }
    return out
}

RemoveAcctsFromQueue(arr) {
    global App
    for acc in arr {
        idx := LoginQueueIndex(acc)
        if idx
            App.LoginQueue.RemoveAt(idx)
    }
    if (App.LoginQueue.Length = 0)
        App.PickMode := false
    RefreshPickUI()
    UpdateAllRowsInPlace()
    RefreshLoginConsole()
}

; Appends the chosen macro to each target's playlist; "(none)" clears
; the playlist instead.
ConsoleAssignMacro(dlg, toAll) {
    global App
    name := dlg.MacroDDL.Text
    targets := toAll ? dlg.ConsoleAccts : ConsoleSelectedAccts(dlg)
    if (targets.Length = 0) {
        ShowToast("Select accounts first (or use Add all)")
        return
    }
    for acc in targets {
        if (name = "(none)") {
            try App.LoginMacros.Delete(acc.Email)
            acc.DeleteProp("_macroIdx")
        } else {
            if !App.LoginMacros.Has(acc.Email)
                App.LoginMacros[acc.Email] := []
            App.LoginMacros[acc.Email].Push(name)
        }
    }
    RefreshLoginConsole()
}

ConsoleStart(dlg) {
    ConsoleApplyNumbers(dlg)
    batch := PrepareLoginBatch()
    if !IsObject(batch)
        return
    LaunchWithMode(dlg.RPlay.Value ? "play" : "activity", batch)
    RefreshLoginConsole()
}

; ============================================================
; DAILY ACTIVITY QUOTA
; ------------------------------------------------------------
; A standing weekly commitment: run N accounts in Activity mode on
; certain days. One click (the banner) queues N random accounts and
; starts Activity; a startup popup + a red banner nag until it's done.
; "Today" is the GAME day (rolls at Config.DayResetHour, like the rest
; of the session system), so the weekday and the "done" stamp agree with
; the day board. Fulfilment persists in Settings.ini [Quota].
; ============================================================

; The schedule — edit these to change the commitment. wday: 1=Sun … 7=Sat.
DailyQuotaCount(wday) {
    switch wday {
        case 1: return 30  ; Sunday
        case 2: return 10  ; Monday
        case 3: return 10  ; Tuesday
    }
    return 0
}

; Weekday (1-7) and name of the current GAME day (now minus the reset hour).
GameWeekday() {
    return Integer(FormatTime(DateAdd(A_Now, -Config.DayResetHour, "Hours"), "WDay"))
}
GameDayName() {
    return FormatTime(DateAdd(A_Now, -Config.DayResetHour, "Hours"), "dddd")
}

QuotaFulfilledToday() {
    global App
    return App.QuotaDoneStamp != "" && App.QuotaDoneStamp = GameDayStamp()
}

LoadQuotaState() {
    global App
    try App.QuotaDoneStamp := IniRead(Config.SettingsPath, "Quota", "Done", "")
}

; Accounts eligible for a random pick: one per email (deduped across all
; files), minus any already at today's goal or currently online — no
; point re-queuing a finished or running account.
QuotaEligiblePool() {
    goalMs := Config.SessionGoalMinutes * 60000
    seen := Map()
    pool := []
    for f in App.Files {
        for acc in f.Accounts {
            if seen.Has(acc.Email)
                continue
            seen[acc.Email] := true
            if (AccountOnlineMs(acc) >= goalMs || AccountIsOnline(acc))
                continue
            pool.Push(acc)
        }
    }
    return pool
}

; Fisher–Yates shuffle a copy, take up to n. Pure apart from Random.
QuotaPickRandom(pool, n) {
    arr := []
    for a in pool
        arr.Push(a)
    i := arr.Length
    while (i > 1) {
        j := Random(1, i)
        tmp := arr[i], arr[i] := arr[j], arr[j] := tmp
        i -= 1
    }
    chosen := []
    loop Min(n, arr.Length)
        chosen.Push(arr[A_Index])
    return chosen
}

; The one-click action: queue N random accounts and start Activity.
; auto = fired unattended by the idle watcher — skips the confirm dialog
; (nobody's there to answer) and stays silent on the guards.
DailyQuotaStart(auto := false) {
    global App
    if (App.LoginRunning || App.MacroPlaying || App.IsRecording || App.QueueRunning) {
        if !auto
            ShowToast("Finish the current automation first")
        return
    }
    n := DailyQuotaCount(GameWeekday())
    if (n = 0) {
        if !auto
            ShowConfirm("No activity quota today (" GameDayName() ").`n`nQuota days: Sunday 30 · Monday 10 · Tuesday 10.", "Daily Quota", "Iconi")
        return
    }
    if !LoginProfileReady() {
        if !auto {
            ShowToast("Set up Launch + Login first (⚙ → Login Setup)")
            OpenLoginSetup()
        }
        return
    }
    if !FileExist(Config.LauncherPath) {
        if !auto
            ShowConfirm("Launcher not found:`n" Config.LauncherPath "`n`nSet the path in ⚙ Preferences.", "Daily Quota", "IconX")
        return
    }
    chosen := QuotaPickRandom(QuotaEligiblePool(), n)
    if !chosen.Length {
        if !auto
            ShowConfirm("Every account is already done or online today — nothing to queue for " GameDayName() "'s quota.", "Daily Quota", "Iconi")
        else
            IdleHist("Activity (daily quota)", "—", "info", "skipped: every account already done or online")
        App.QuotaDoneStamp := GameDayStamp() ; nothing to do = satisfied
        try IniWrite(App.QuotaDoneStamp, Config.SettingsPath, "Quota", "Done")
        RefreshQuotaBanner()
        return
    }
    if !auto {
        short := chosen.Length < n
        msg := "Start ACTIVITY on " chosen.Length " random account(s), each kept online for "
            . Config.SessionGoalMinutes " minutes?" (short
                ? "`n`n(Only " chosen.Length " of " n " were eligible — the rest are already done or online.)" : "")
            . "`n`nToday is " GameDayName() " · quota " n "."
        if (ShowConfirm(msg, "Daily Quota — " GameDayName(), "YesNo Icon?") != "Yes")
            return
    }

    App.LoginQueue := chosen
    App.PickMode := false
    App.QuotaDoneStamp := GameDayStamp() ; started = satisfied for today
    try IniWrite(App.QuotaDoneStamp, Config.SettingsPath, "Quota", "Done")
    RefreshPickUI()
    UpdateAllRowsInPlace()
    RefreshQuotaBanner()
    LaunchWithMode("activity", chosen)
    RefreshLoginConsole()
    IdleHist("Activity (daily quota)", "—", "info", "started: " chosen.Length " account(s), "
        GameDayName() " quota " n (auto ? " (idle " Round(A_TimeIdlePhysical / 60000) "m)" : " (manual)"))
    if auto {
        ; The window is probably hidden in the tray — use a real Windows
        ; notification, not an on-screen toast.
        try TrayTip("Account Queue — auto-run", "Started Activity on " chosen.Length
            . " account(s) for " GameDayName() "'s quota (" Config.SessionGoalMinutes " min each).", 0x1)
    } else {
        ShowToast("🚀 Daily quota: Activity started on " chosen.Length
            . " account(s) at " Config.SessionGoalMinutes " min")
    }
}

; --- "is the user away?" ------------------------------------------
; MEASURED PROBLEM (0.42.0): the old rule was A_TimeIdlePhysical >= 2 h,
; i.e. two hours of UNBROKEN silence. On this machine the mouse emits
; stray events while untouched — sampling showed the keyboard idle for
; 19 s straight while the mouse reset the idle timer on nearly every
; 1 s sample. One twitch per two hours is enough to make idle jobs
; NEVER fire, and nothing told the user why.
;
; So: sample the POINTER POSITION once per housekeeping tick instead of
; trusting the event stream. Drift under a few pixels isn't a person.
; Pure function — unit-tested.
UserWasActive(lastX, lastY, x, y, kbdIdleMs, sinceMs, slackPx) {
    if (Abs(x - lastX) > slackPx || Abs(y - lastY) > slackPx)
        return true           ; the pointer really moved
    return kbdIdleMs <= sinceMs ; a key was pressed within this window
}

; Accumulates App.AwayMs. Frozen while OUR automation is running: it
; moves the mouse itself, and a position check can't tell that from a
; person — freezing keeps the pre-run value so the next job in the
; priority list can still start when this one ends.
UpdateAwayTracking() {
    global App
    now := A_TickCount
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    busy := App.LoginRunning || App.MacroPlaying || App.IsRecording || App.QueueRunning
    if (App.AwayLastTick && !busy) {
        since := now - App.AwayLastTick
        App.AwayMs := UserWasActive(App.AwayLastX, App.AwayLastY, mx, my
            , A_TimeIdleKeyboard, since, Config.AwayMouseSlackPx) ? 0 : App.AwayMs + since
    }
    App.AwayLastTick := now, App.AwayLastX := mx, App.AwayLastY := my
}

; Why idle jobs aren't running right now — "" means ready to go. This is
; the answer to "why didn't my macro run?", shown live in the Idle
; Actions window instead of the app silently declining.
IdleBlockReason() {
    global App
    if !App.AutoRunWhenIdle
        return "Auto-run is OFF — tray → “Run idle actions when idle”"
    if App.IdleCountdownActive
        return "Countdown is showing"
    if (App.LoginRunning || App.MacroPlaying || App.IsRecording || App.QueueRunning)
        return "Something is already running"
    if !LoginProfileReady()
        return "Login Setup is incomplete — ⚙ → Login Setup"
    if !FileExist(Config.LauncherPath)
        return "Launcher not found: " Config.LauncherPath
    if SessionLocked()
        return "The screen is locked"
    job := NextIdleJob()
    if !IsObject(job)
        return "Nothing pending — every enabled job is done for today"
    if (App.AwayMs < Config.AutoRunIdleMinutes * 60000)
        return "Waiting — away " Round(App.AwayMs / 60000) " of " Config.AutoRunIdleMinutes " min"
        . "  ·  next up: " job.Name
    return ""
}

; True when the workstation is locked or on the secure desktop —
; OpenInputDesktop fails, or the input desktop isn't the interactive
; "Default" one. Best-effort; any failure is treated as "locked" so we
; err toward NOT auto-launching.
SessionLocked() {
    hDesk := DllCall("OpenInputDesktop", "uint", 0, "int", 0, "uint", 0x0001, "ptr") ; DESKTOP_READOBJECTS
    if !hDesk
        return true
    name := "", len := 0
    try {
        DllCall("GetUserObjectInformationW", "ptr", hDesk, "int", 2, "ptr", 0, "uint", 0, "uint*", &len)
        if (len > 0) {
            buf := Buffer(len)
            if DllCall("GetUserObjectInformationW", "ptr", hDesk, "int", 2, "ptr", buf, "uint", len, "uint*", &len)
                name := StrGet(buf, "UTF-16")
        }
    }
    DllCall("CloseDesktop", "ptr", hDesk)
    return (name != "" && name != "Default")
}

; ============================================================
; IDLE ACTIONS SYSTEM
; ------------------------------------------------------------
; A prioritized list of "idle jobs" the app works through, top to
; bottom, whenever the PC has been idle long enough (the master switch
; + AutoRunIdleMinutes gate the whole thing). Two kinds of job:
;   • activity — the built-in daily quota (keep N online for the goal,
;     then close). Always present, on by default, can't be deleted.
;   • chore    — a macro/routine run over a set of accounts: for each,
;     launch + log in, run the macro ONCE, then CLOSE the client and
;     move to the next. A client never gets the same job's macro twice
;     in a game-day (per-(job,account) done tracking, reset at 02:00).
; Only one job runs at a time; when the top job has no work left today,
; the next enabled job with pending work runs on the following tick.
; Jobs persist in Logins\IdleJobs.txt; done-tracking in Settings.ini.
; ============================================================

IdleJobsPath() => Config.LoginsFolder "\IdleJobs.txt"
IdleHistoryPath() => Config.LoginsFolder "\idle-history.txt"

; --- idle-run history: what the unattended (and manual) runs actually
; did. One structured line per event, appended to idle-history.txt AND
; kept in a bounded in-memory list the viewer reads. result: ok/fail/info.
IdleHist(job, who, result, detail := "") {
    global App
    ev := { Time: FormatTime(, "yyyy-MM-dd HH:mm:ss"), Job: job, Who: who, Result: result, Detail: detail }
    App.IdleHistory.Push(ev)
    while (App.IdleHistory.Length > 500)
        App.IdleHistory.RemoveAt(1)
    try FileAppend(ev.Time " | " job " | " who " | " result " | " detail "`n", IdleHistoryPath(), "UTF-8")
    ; keep the viewer live if it's open
    if IsObject(App.IdleHistDlg)
        try RefreshIdleHistory()
}

; Load the tail of the history file into memory at startup (small file;
; read whole, keep the last 500 events).
LoadIdleHistory() {
    global App
    App.IdleHistory := []
    if !FileExist(IdleHistoryPath())
        return
    lines := StrSplit(FileRead(IdleHistoryPath(), "UTF-8"), "`n", "`r")
    start := Max(1, lines.Length - 500)
    loop (lines.Length - start + 1) {
        line := lines[start + A_Index - 1]
        if (Trim(line) = "")
            continue
        p := StrSplit(line, " | ")
        if (p.Length >= 4)
            App.IdleHistory.Push({ Time: p[1], Job: p[2], Who: p[3], Result: p[4]
                , Detail: p.Length >= 5 ? p[5] : "" })
    }
}

; The one activity job every install starts with.
DefaultActivityJob() {
    return { Name: "Activity (daily quota)", Enabled: true, Kind: "activity", Macro: "", Scope: "all", Emails: [] }
}

LoadIdleJobs() {
    global App
    App.IdleJobs := []
    if FileExist(IdleJobsPath()) {
        for line in StrSplit(FileRead(IdleJobsPath(), "UTF-8"), "`n", "`r") {
            line := Trim(line)
            if (line = "" || SubStr(line, 1, 1) = ";")
                continue
            p := StrSplit(line, "|")
            if (p.Length < 3)
                continue
            emails := (p.Length >= 6 && p[6] != "") ? StrSplit(p[6], ",") : []
            App.IdleJobs.Push({ Name: p[1], Enabled: (p[2] = "1"), Kind: p[3]
                , Macro: p.Length >= 4 ? p[4] : "", Scope: p.Length >= 5 && p[5] != "" ? p[5] : "all"
                , Emails: emails })
        }
    }
    ; Guarantee exactly one activity job exists, and it's first-class.
    hasActivity := false
    for j in App.IdleJobs
        if (j.Kind = "activity")
            hasActivity := true
    if !hasActivity
        App.IdleJobs.InsertAt(1, DefaultActivityJob())
}

SaveIdleJobs() {
    global App
    out := "; Idle Actions — one job per line, in priority order.`n"
        . "; name|enabled(0/1)|kind(activity/chore)|macro|scope(all/file:Name/pick)|emails(csv)`n"
    for j in App.IdleJobs
        out .= j.Name "|" (j.Enabled ? "1" : "0") "|" j.Kind "|" j.Macro "|" j.Scope
            . "|" JoinEmails(j.Emails) "`n"
    try AtomicWriteText(IdleJobsPath(), out)
}

JoinEmails(arr) {
    out := ""
    for e in arr
        out .= (out = "" ? "" : ",") e
    return out
}

; --- per-(job, account) done tracking, game-day scoped ---
LoadIdleDone() {
    global App
    App.IdleDone := Map()
    App.IdleDoneDay := GameDayStamp()
    if !FileExist(Config.SettingsPath)
        return
    day := ""
    try day := IniRead(Config.SettingsPath, "IdleDone", "__gameday", "")
    if (day != GameDayStamp()) {
        try IniDelete(Config.SettingsPath, "IdleDone") ; stale day — wipe
        return
    }
    raw := ""
    try raw := IniRead(Config.SettingsPath, "IdleDone")
    for line in StrSplit(raw, "`n", "`r") {
        eq := InStr(line, "=")
        if (!eq || SubStr(line, 1, eq - 1) = "__gameday")
            continue
        App.IdleDone[SubStr(line, 1, eq - 1)] := 1
    }
}

SaveIdleDone() {
    global App
    try {
        IniDelete(Config.SettingsPath, "IdleDone")
        IniWrite(GameDayStamp(), Config.SettingsPath, "IdleDone", "__gameday")
        for key in App.IdleDone
            IniWrite(1, Config.SettingsPath, "IdleDone", key)
    }
}

IdleDoneKey(job, acc) => job.Name "|" acc.Email

IsIdleDone(job, acc) {
    global App
    return App.IdleDone.Has(IdleDoneKey(job, acc))
}

MarkIdleDone(job, acc) {
    global App
    App.IdleDone[IdleDoneKey(job, acc)] := 1
}

; A new game day means every idle job is pending again.
ResetIdleDone() {
    global App
    App.IdleDone := Map()
    App.IdleDoneDay := GameDayStamp()
    try IniDelete(Config.SettingsPath, "IdleDone")
}

; --- which accounts a chore job targets (deduped by email) ---
IdleScopeAccounts(job) {
    global App
    seen := Map()
    out := []
    wantFile := (SubStr(job.Scope, 1, 5) = "file:") ? SubStr(job.Scope, 6) : ""
    wantPick := (job.Scope = "pick")
    pickSet := Map()
    if wantPick
        for e in job.Emails
            pickSet[e] := 1
    for f in App.Files {
        if (wantFile != "" && f.Name != wantFile)
            continue
        for acc in f.Accounts {
            if seen.Has(acc.Email)
                continue
            if (wantPick && !pickSet.Has(acc.Email))
                continue
            seen[acc.Email] := 1
            out.Push(acc)
        }
    }
    return out
}

; Accounts a chore job still needs to run today: in scope, not already
; done today, not currently online (we launch a fresh client per run).
ChorePendingAccounts(job) {
    pending := []
    for acc in IdleScopeAccounts(job) {
        if (IsIdleDone(job, acc) || AccountIsOnline(acc))
            continue
        pending.Push(acc)
    }
    return pending
}

; Does this job have work left to do right now?
IdleJobHasPending(job) {
    if !job.Enabled
        return false
    if (job.Kind = "activity")
        return DailyQuotaCount(GameWeekday()) > 0 && !QuotaFulfilledToday() && QuotaEligiblePool().Length > 0
    return job.Macro != "" && ChorePendingAccounts(job).Length > 0
}

; The highest-priority enabled job with pending work ("" if none).
NextIdleJob() {
    global App
    for job in App.IdleJobs
        if IdleJobHasPending(job)
            return job
    return ""
}

; Start one idle job. Activity reuses the quota path; chore uses RunChore.
; auto = fired by the idle watcher (silent); false = a deliberate "run
; now", where the activity job still shows its launch confirm.
StartIdleJob(job, auto := true) {
    global App
    if (job.Kind = "activity") {
        DailyQuotaStart(auto)
        return
    }
    batch := ChorePendingAccounts(job)
    if !batch.Length
        return
    App.ChoreJob := job
    IdleHist(job.Name, "—", "info", "started: '" job.Macro "' on " batch.Length " account(s)"
        (auto ? " (idle " Round(A_TimeIdlePhysical / 60000) "m)" : " (run now)"))
    try TrayTip("Account Queue — idle job", "'" job.Name "': running '" job.Macro "' on "
        . batch.Length " account(s), then closing each.", 0x1)
    LaunchWithMode("chore", batch)
}

; Chore run: for each account — log in, run the job's macro ONCE, close
; the client (banking its time), next. Failed logins are left for the
; next idle cycle (not marked done). Groups logins by LaunchMax for
; speed; macros still run one client at a time (playback owns the mouse).
RunChore(batch) {
    global App
    job := App.ChoreJob
    if !IsObject(job)
        return
    total := batch.Length, processed := 0, ok := 0, failed := 0
    pos := 1
    while (pos <= total && !AbortPressed()) {
        chunk := TakeChunk(batch, &pos, Config.LaunchMax)
        loggedIn := []
        LoginGroup(chunk, loggedIn)
        if AbortPressed()
            break
        ; accounts in this group that never logged in = failures (left
        ; un-done so a later cycle retries them)
        for acc in chunk {
            if !LoginQueueIndex2(loggedIn, acc) {
                IdleHist(job.Name, acc.Name, "fail", "login failed")
                failed += 1
            }
        }
        for acc in loggedIn {
            if AbortPressed()
                break
            SetLoginStatus("Idle '" job.Name "': " job.Macro " on " acc.Name " (" (processed + 1) "/" total ")…")
            res := "done"
            if AccountIsOnline(acc)
                res := RunAutomationOnWindow(job.Macro, acc.ClientHwnd, true)
            MarkIdleDone(job, acc)
            processed += 1
            if (res = "done") {
                ok += 1
                IdleHist(job.Name, acc.Name, "ok", "'" job.Macro "' ran, client closed")
            } else {
                failed += 1
                IdleHist(job.Name, acc.Name, "fail", "'" job.Macro "' " res)
            }
            ; close the client, banking its online time first
            h := acc.HasOwnProp("ClientHwnd") ? acc.ClientHwnd : 0
            DetachClient(acc)
            if h
                try WinClose("ahk_id " h)
            AbortableSleep(800)
        }
    }
    SaveIdleDone()
    IdleHist(job.Name, "—", failed ? "info" : "ok", "finished: " ok " ok, " failed " failed of " total)
    ShowToast("Idle job '" job.Name "' — " ok " ok, " failed " failed")
    App.ChoreJob := ""
}

; Manual "run now" (tray / manager button): run the top pending job
; immediately, ignoring the idle timer.
RunIdleJobsNow() {
    global App
    if (App.LoginRunning || App.MacroPlaying || App.IsRecording || App.QueueRunning) {
        ShowToast("Finish the current automation first")
        return
    }
    if (!LoginProfileReady() || !FileExist(Config.LauncherPath)) {
        ShowToast("Set up Login (⚙ → Login Setup) and a launcher path first")
        return
    }
    job := NextIdleJob()
    if !IsObject(job) {
        ShowToast("No idle job has anything to do right now")
        return
    }
    StartIdleJob(job, false)
}

; The idle watcher (runs on the housekeeping tick). Generalizes the old
; quota auto-run: pick the top pending job and start it.
MaybeRunIdleJobs() {
    global App
    if (IsSet(AQ_TEST_QUIET) && AQ_TEST_QUIET)
        return ; never auto-launch clients under the test suite
    if (IdleBlockReason() != "")
        return ; the window shows the reason; nothing to do this tick
    BeginIdleCountdown(NextIdleJob())
}

; --- pre-run grace countdown -------------------------------------
; Before an AUTO idle job launches anything, give a few seconds to bail
; out in case the idle trigger was a false alarm (you were at the PC but
; not touching it). Moving the mouse or clicking Cancel stops it; the
; timer starting it at zero. Manual "Run now" skips this entirely.
BeginIdleCountdown(job) {
    global App
    if (Config.IdleGraceSeconds <= 0) {
        StartIdleJob(job, true)
        return
    }
    App.IdleCountdownActive := true
    App.IdleCountdownJob := job
    App.IdleCountdownLeft := Config.IdleGraceSeconds
    CoordMode("Mouse", "Screen")
    MouseGetPos(&cx, &cy)
    App.IdleCountdownX := cx, App.IdleCountdownY := cy, App.IdleCountdownStart := A_TickCount

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Idle job starting")
    dlg.BackColor := Colors.Bg
    dlg.MarginX := 16
    dlg.MarginY := 14
    dlg.SetFont("s10 Bold c" Colors.Text, Config.FontMain)
    kind := (job.Kind = "activity") ? "the daily quota" : "'" job.Macro "'"
    dlg.Add("Text", "w360", "⏳ About to run " job.Name)
    dlg.SetFont("s9 Norm c" Colors.TextDim, Config.FontMain)
    dlg.Add("Text", "xm y+4 w360", "Running " kind " because the PC has been idle. "
        . "Move the mouse or click Cancel if you're here.")
    dlg.SetFont("s11 Bold c" Colors.Accent, Config.FontMain)
    dlg.CountText := dlg.Add("Text", "xm y+8 w360", "Starting in " App.IdleCountdownLeft " s…")
    dlg.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
    bRun := dlg.Add("Button", "xm y+10 w120 h28 Default", "▶ Run now")
    bRun.OnEvent("Click", (*) => IdleCountdownFinish(true))
    bCancel := dlg.Add("Button", "x+8 yp w120 h28", "✖ Cancel")
    bCancel.OnEvent("Click", (*) => IdleCountdownCancel("cancelled"))
    dlg.OnEvent("Close", (*) => IdleCountdownCancel("cancelled"))
    dlg.OnEvent("Escape", (*) => IdleCountdownCancel("cancelled"))
    ApplyDialogDarkMode(dlg)
    App.IdleCountdownDlg := dlg
    dlg.Show("AutoSize Center")
    SetTimer(IdleCountdownTick, 1000)
}

IdleCountdownTick() {
    global App
    if !App.IdleCountdownActive {
        SetTimer(IdleCountdownTick, 0)
        return
    }
    ; If the user has really touched the PC since the countdown began,
    ; they're clearly here — bail out automatically. Same jitter-tolerant
    ; test as the away tracker, so a twitchy mouse can't cancel it either.
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    if UserWasActive(App.IdleCountdownX, App.IdleCountdownY, mx, my
        , A_TimeIdleKeyboard, A_TickCount - App.IdleCountdownStart, Config.AwayMouseSlackPx) {
        IdleCountdownCancel("you returned")
        return
    }
    App.IdleCountdownLeft -= 1
    if (App.IdleCountdownLeft <= 0) {
        IdleCountdownFinish(false)
        return
    }
    try App.IdleCountdownDlg.CountText.Value := "Starting in " App.IdleCountdownLeft " s…"
}

; Reached zero (or Run now): tear down and launch the job.
IdleCountdownFinish(manual) {
    global App
    SetTimer(IdleCountdownTick, 0)
    job := App.IdleCountdownJob
    CloseIdleCountdown()
    if IsObject(job)
        StartIdleJob(job, true) ; auto path (no per-job confirm)
}

IdleCountdownCancel(why) {
    global App
    SetTimer(IdleCountdownTick, 0)
    job := App.IdleCountdownJob
    CloseIdleCountdown()
    ; Start the away clock over — otherwise the next tick would see the
    ; counter still past the threshold and pop the countdown right back up.
    App.AwayMs := 0
    if IsObject(job)
        IdleHist(job.Name, "—", "info", "auto-run " why " during the countdown")
}

CloseIdleCountdown() {
    global App
    App.IdleCountdownActive := false
    App.IdleCountdownJob := ""
    if IsObject(App.IdleCountdownDlg) {
        try App.IdleCountdownDlg.Destroy()
        App.IdleCountdownDlg := ""
    }
}

; ============================================================
; IDLE ACTIONS — manager window
; ============================================================
OpenIdleActions(*) {
    global App
    if IsObject(App.IdleDlg) {
        try App.IdleDlg.Show()
        RefreshIdleList()
        return
    }
    ShowFromTray() ; make sure the main window is up (may be called from tray)
    dlg := Gui("+Owner" App.Gui.Hwnd, "Idle Actions — Account Queue")
    dlg.BackColor := Colors.Bg
    dlg.MarginX := 12
    dlg.MarginY := 10
    dlg.SetFont("s9 c" Colors.Text, Config.FontMain)

    ; master switch
    cb := dlg.Add("Checkbox", "xm" (App.AutoRunWhenIdle ? " Checked" : ""), "Run these when the PC is idle")
    cb.OnEvent("Click", (ctrl, *) => (App.AutoRunWhenIdle := ctrl.Value = 1, RefreshTrayChecks(), SaveSettings()))
    dlg.MasterCb := cb
    dlg.SetFont("s8 Norm Italic c" Colors.TextDim, Config.FontMain)
    dlg.Add("Text", "x+8 yp+2", "after " Config.AutoRunIdleMinutes " min (⚙ Preferences) · top-to-bottom by priority")

    dlg.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
    lv := dlg.Add("ListView", "xm y+8 w520 h240 Checked -Multi NoSort", ["Job", "Does", "Pending today"])
    lv.ModifyCol(1, 190), lv.ModifyCol(2, 210), lv.ModifyCol(3, 100)
    lv.OnEvent("ItemCheck", IdleListCheck)
    lv.OnEvent("DoubleClick", (*) => IdleMgrEdit())
    dlg.IdleList := lv

    bAdd := dlg.Add("Button", "xm y+8 w110 h26", "➕ Add job")
    bAdd.OnEvent("Click", (*) => IdleMgrAdd())
    bEdit := dlg.Add("Button", "x+6 yp w80 h26", "✎ Edit")
    bEdit.OnEvent("Click", (*) => IdleMgrEdit())
    bDel := dlg.Add("Button", "x+6 yp w80 h26", "🗑 Remove")
    bDel.OnEvent("Click", (*) => IdleMgrRemove())
    bUp := dlg.Add("Button", "x+6 yp w40 h26", "▲")
    bUp.OnEvent("Click", (*) => IdleMgrMove(-1))
    bDown := dlg.Add("Button", "x+4 yp w40 h26", "▼")
    bDown.OnEvent("Click", (*) => IdleMgrMove(1))
    bRun := dlg.Add("Button", "x+6 yp w96 h26", "▶ Run now")
    bRun.OnEvent("Click", (*) => (RunIdleJobsNow(), RefreshIdleList()))
    bRun.TipText := "Run the top job that has work to do, right now (ignores the idle timer)"
    bHist := dlg.Add("Button", "x+6 yp w96 h26", "📜 History")
    bHist.OnEvent("Click", (*) => OpenIdleHistory())
    bHist.TipText := "What the idle runs did — successes and failures"

    ; Live "why isn't it running?" line — the thing that was missing when
    ; an idle job silently never fired.
    dlg.SetFont("s9 Bold c" Colors.Accent, Config.FontMain)
    dlg.StatusLine := dlg.Add("Text", "xm y+10 w520 h20", "")
    dlg.SetFont("s8 Norm Italic c" Colors.TextDim, Config.FontMain)
    dlg.Add("Text", "xm y+6 w520", "The checkbox enables/disables a job. Priority is the order above — drag with ▲▼. "
        . "A chore logs each account in, runs its macro once, then closes the client; no account repeats a job the same day.")

    ApplyDialogDarkMode(dlg, [], [lv])
    dlg.OnEvent("Close", (*) => CloseIdleActions(dlg))
    dlg.OnEvent("Escape", (*) => CloseIdleActions(dlg))
    App.IdleDlg := dlg
    RefreshIdleList()
    dlg.Show("AutoSize")
}

CloseIdleActions(dlg) {
    global App
    App.IdleDlg := ""
    try dlg.Destroy()
}

; --- history viewer: what the idle runs actually did ---
OpenIdleHistory(*) {
    global App
    if IsObject(App.IdleHistDlg) {
        try App.IdleHistDlg.Show()
        RefreshIdleHistory()
        return
    }
    ShowFromTray()
    dlg := Gui("+Owner" App.Gui.Hwnd " +Resize", "Idle History — Account Queue")
    dlg.BackColor := Colors.Bg
    dlg.MarginX := 12
    dlg.MarginY := 10
    dlg.SetFont("s9 c" Colors.Text, Config.FontMain)
    lv := dlg.Add("ListView", "xm w560 h320 -Multi NoSort", ["When", "Job", "Account", "Result"])
    lv.ModifyCol(1, 140), lv.ModifyCol(2, 150), lv.ModifyCol(3, 130), lv.ModifyCol(4, 130)
    lv.OnNotify(-12, OnHistoryCustomDraw) ; NM_CUSTOMDRAW — green ok / red fail
    dlg.HistList := lv
    bRefresh := dlg.Add("Button", "xm y+8 w90 h26", "⟳ Refresh")
    bRefresh.OnEvent("Click", (*) => RefreshIdleHistory())
    bClear := dlg.Add("Button", "x+6 yp w90 h26", "🗑 Clear")
    bClear.OnEvent("Click", (*) => ClearIdleHistory())
    bOpen := dlg.Add("Button", "x+6 yp w120 h26", "📄 Open log file")
    bOpen.OnEvent("Click", (*) => (FileExist(IdleHistoryPath()) ? Run("notepad.exe `"" IdleHistoryPath() "`"") : ShowToast("No history yet")))
    dlg.SetFont("s8 Norm Italic c" Colors.TextDim, Config.FontMain)
    dlg.HistCount := dlg.Add("Text", "x+10 yp+4 w180", "")
    ApplyDialogDarkMode(dlg, [], [lv])
    dlg.OnEvent("Close", (*) => CloseIdleHistory(dlg))
    dlg.OnEvent("Escape", (*) => CloseIdleHistory(dlg))
    App.IdleHistDlg := dlg
    RefreshIdleHistory()
    dlg.Show("AutoSize")
}

CloseIdleHistory(dlg) {
    global App
    App.IdleHistDlg := ""
    try dlg.Destroy()
}

RefreshIdleHistory() {
    global App
    if !IsObject(App.IdleHistDlg)
        return
    lv := App.IdleHistDlg.HistList
    lv.Delete()
    ; newest first
    i := App.IdleHistory.Length
    while (i >= 1) {
        e := App.IdleHistory[i]
        lv.Add("", e.Time, e.Job, e.Who, (e.Result = "ok" ? "✔ " : e.Result = "fail" ? "✖ " : "· ")
            . (e.Detail != "" ? e.Detail : e.Result))
        i -= 1
    }
    try App.IdleHistDlg.HistCount.Value := App.IdleHistory.Length " event(s)"
}

; Green ok rows, red fail rows (COLORREF is BGR; reuse the theme hues).
OnHistoryCustomDraw(lv, lParam) {
    global App
    stage := NumGet(lParam, 24, "UInt")
    if (stage = 0x1)
        return 0x20 ; CDRF_NOTIFYITEMDRAW
    if (stage = 0x10001) {
        pos := NumGet(lParam, 56, "UPtr") + 1
        ; rows are newest-first, so map back to the history index
        idx := App.IdleHistory.Length - pos + 1
        if (idx >= 1 && idx <= App.IdleHistory.Length) {
            r := App.IdleHistory[idx].Result
            if (r = "ok")
                NumPut("UInt", HexToBGR(Colors.Success), lParam, 80)
            else if (r = "fail")
                NumPut("UInt", HexToBGR(Colors.Danger), lParam, 80)
            else
                return 0
            return 0x2
        }
    }
    return 0
}

ClearIdleHistory() {
    global App
    if (ShowConfirm("Clear the idle history?", "Idle History", "YesNo Icon?") != "Yes")
        return
    App.IdleHistory := []
    try FileDelete(IdleHistoryPath())
    RefreshIdleHistory()
}

RefreshIdleList() {
    global App
    if !IsObject(App.IdleDlg)
        return
    lv := App.IdleDlg.IdleList
    sel := lv.GetNext()
    lv.Delete()
    for job in App.IdleJobs
        lv.Add(job.Enabled ? "Check" : "", job.Name, IdleJobDoesText(job), IdleJobPendingText(job))
    if (sel >= 1 && sel <= App.IdleJobs.Length)
        lv.Modify(sel, "Select")
    try App.IdleDlg.MasterCb.Value := App.AutoRunWhenIdle ? 1 : 0
    RefreshIdleStatusLine()
}

; The live status line: either why nothing is running, or that it's ready.
RefreshIdleStatusLine() {
    global App
    if !IsObject(App.IdleDlg)
        return
    reason := IdleBlockReason()
    txt := (reason = "") ? "✓ Ready — starting the next job now…" : reason
    try {
        App.IdleDlg.StatusLine.Value := txt
        App.IdleDlg.StatusLine.SetFont("c" (reason = "" ? Colors.Success : Colors.Accent))
    }
}

IdleJobDoesText(job) {
    if (job.Kind = "activity")
        return "Keep the daily quota online for " Config.SessionGoalMinutes " min"
    scope := (job.Scope = "all") ? "all accounts"
        : (SubStr(job.Scope, 1, 5) = "file:") ? "file " SubStr(job.Scope, 6)
        : "picked (" job.Emails.Length ")"
    return "'" (job.Macro = "" ? "— no macro —" : job.Macro) "' on " scope ", then close"
}

IdleJobPendingText(job) {
    if !job.Enabled
        return "(off)"
    if (job.Kind = "activity") {
        if (DailyQuotaCount(GameWeekday()) = 0)
            return "no quota today"
        return QuotaFulfilledToday() ? "done" : DailyQuotaCount(GameWeekday()) " due"
    }
    n := ChorePendingAccounts(job).Length
    return n ? n " account(s)" : "done"
}

IdleListCheck(ctrl, item, checked) {
    global App
    if (item >= 1 && item <= App.IdleJobs.Length) {
        App.IdleJobs[item].Enabled := checked ? true : false
        SaveIdleJobs()
        ; refresh the "pending" column for this row (off → "(off)")
        ctrl.Modify(item, "Col3", IdleJobPendingText(App.IdleJobs[item]))
    }
}

IdleMgrSelected() {
    global App
    if !IsObject(App.IdleDlg)
        return 0
    row := App.IdleDlg.IdleList.GetNext()
    return (row >= 1 && row <= App.IdleJobs.Length) ? row : 0
}

IdleMgrMove(delta) {
    global App
    row := IdleMgrSelected()
    if !row
        return
    target := row + delta
    if (target < 1 || target > App.IdleJobs.Length)
        return
    j := App.IdleJobs.RemoveAt(row)
    App.IdleJobs.InsertAt(target, j)
    SaveIdleJobs()
    RefreshIdleList()
    App.IdleDlg.IdleList.Modify(target, "Select Focus Vis")
}

IdleMgrRemove() {
    global App
    row := IdleMgrSelected()
    if !row
        return
    job := App.IdleJobs[row]
    if (job.Kind = "activity") {
        ShowToast("The Activity job is built in — disable it with its checkbox instead")
        return
    }
    if (ShowConfirm("Remove the idle job `"" job.Name "`"?", "Idle Actions", "YesNo Icon?") != "Yes")
        return
    App.IdleJobs.RemoveAt(row)
    SaveIdleJobs()
    RefreshIdleList()
}

IdleMgrAdd() {
    IdleJobDialog("")
}

IdleMgrEdit() {
    global App
    row := IdleMgrSelected()
    if !row
        return
    job := App.IdleJobs[row]
    if (job.Kind = "activity") {
        ShowConfirm("The Activity job runs the daily quota (Sun 30 · Mon 10 · Tue 10) and keeps each account online for "
            . Config.SessionGoalMinutes " min.`n`nChange the schedule by editing DailyQuotaCount in the script; the goal, "
            . "idle delay and other timings are in ⚙ Preferences.", "Activity job", "Iconi")
        return
    }
    IdleJobDialog(job)
}

; Add (job="") or edit a chore job: name, macro/routine, and which
; accounts. "Picked" grabs the current F8 pick queue's accounts.
IdleJobDialog(job) {
    global App
    editing := IsObject(job)
    d := Gui("+Owner" App.IdleDlg.Hwnd " +ToolWindow", editing ? "Edit idle job" : "New idle job")
    d.BackColor := Colors.Bg
    d.MarginX := 12
    d.MarginY := 10
    d.SetFont("s9 c" Colors.Text, Config.FontMain)

    d.Add("Text", "xm w90 h22 Section", "Name")
    edName := d.Add("Edit", "x+8 ys-2 w300 h22", editing ? job.Name : "")
    d.Add("Text", "xm w90 h22 Section", "Macro / routine")
    names := AutomationNames()
    ddl := d.Add("DropDownList", "x+8 ys-2 w300", names)
    if editing
        for i, n in names
            if (n = job.Macro)
                ddl.Choose(i)
    if (!editing && names.Length)
        ddl.Choose(1)

    d.Add("Text", "xm w90 h22 Section", "Accounts")
    scopeItems := ["All accounts", "This file (" App.Files[App.CurrentFile].Name ")"
        , "Picked — the current ⊕ Pick queue (" App.LoginQueue.Length ")"]
    scopeDdl := d.Add("DropDownList", "x+8 ys-2 w300", scopeItems)
    curScope := editing ? job.Scope : "all"
    scopeDdl.Choose((curScope = "all") ? 1 : (SubStr(curScope, 1, 5) = "file:") ? 2 : 3)

    d.SetFont("s8 Norm Italic c" Colors.TextDim, Config.FontMain)
    d.Add("Text", "xm y+10 w400", "Each account is logged in, runs the macro once, then its client is closed. "
        . "Pick a set with ⊕ Pick (F8) first if you choose “Picked”.")

    d.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
    result := ""
    ok := d.Add("Button", "xm y+12 w100 h28 Default", editing ? "Save" : "Add")
    ok.OnEvent("Click", (*) => (result := "ok", d.Hide()))
    cancel := d.Add("Button", "x+8 yp w90 h28", "Cancel")
    cancel.OnEvent("Click", (*) => (result := "", d.Hide()))
    d.OnEvent("Escape", (*) => (result := "", d.Hide()))
    d.OnEvent("Close", (*) => (result := "", d.Hide()))
    ApplyDialogDarkMode(d, [edName])
    d.Show("AutoSize")
    WinWaitClose("ahk_id " d.Hwnd)

    if (result = "ok") {
        name := Trim(edName.Text)
        macro := ddl.Text
        scopeSel := scopeDdl.Value
        scope := (scopeSel = 1) ? "all" : (scopeSel = 2) ? ("file:" App.Files[App.CurrentFile].Name) : "pick"
        emails := []
        if (scope = "pick")
            for acc in App.LoginQueue
                emails.Push(acc.Email)
        if (name = "")
            name := macro != "" ? macro : "Idle job"
        if editing {
            job.Name := name, job.Macro := macro, job.Scope := scope, job.Emails := emails
        } else {
            App.IdleJobs.Push({ Name: name, Enabled: true, Kind: "chore", Macro: macro, Scope: scope, Emails: emails })
        }
        SaveIdleJobs()
        RefreshIdleList()
    }
    try d.Destroy()
}

; ============================================================
; SYSTEM TRAY (run 24/7)
; ------------------------------------------------------------
; The minimize button hides the window to the tray (toggleable); the
; tray menu shows/runs/toggles/exits. AHK keeps a tray icon by default.
; ============================================================
SetupTray() {
    global App
    A_IconTip := "Account Queue — running"
    tray := A_TrayMenu
    tray.Delete() ; drop the default Pause/Suspend/etc.
    tray.Add("Show Account Queue", (*) => ShowFromTray())
    tray.Default := "Show Account Queue"
    tray.Add()
    tray.Add("Idle Actions…", (*) => OpenIdleActions())
    tray.Add("Idle History…", (*) => OpenIdleHistory())
    tray.Add("Run idle actions now", (*) => RunIdleJobsNow())
    tray.Add("Run idle actions when idle", TrayToggleAutoRun)
    tray.Add("Pause paste keys (F10)", (*) => TogglePastePause())
    tray.Add("Minimize to tray", TrayToggleMinTray)
    tray.Add()
    tray.Add("Exit", (*) => OnAppClose())
    RefreshTrayChecks()
    ; Intercept the minimize button → hide to tray instead.
    OnMessage(0x0112, OnSysCommand) ; WM_SYSCOMMAND
}

RefreshTrayChecks() {
    global App
    tray := A_TrayMenu
    try (App.AutoRunWhenIdle ? tray.Check("Run idle actions when idle") : tray.Uncheck("Run idle actions when idle"))
    try (App.PastePaused ? tray.Check("Pause paste keys (F10)") : tray.Uncheck("Pause paste keys (F10)"))
    try (App.MinimizeToTray ? tray.Check("Minimize to tray") : tray.Uncheck("Minimize to tray"))
}

TrayToggleAutoRun(*) {
    global App
    App.AutoRunWhenIdle := !App.AutoRunWhenIdle
    RefreshTrayChecks()
    SaveSettings()
    ShowToast(App.AutoRunWhenIdle
        ? "Auto-run ON — the quota fires after " Config.AutoRunIdleMinutes " min idle on quota days"
        : "Auto-run OFF")
}

TrayToggleMinTray(*) {
    global App
    App.MinimizeToTray := !App.MinimizeToTray
    RefreshTrayChecks()
    SaveSettings()
}

ShowFromTray() {
    global App
    try App.Gui.Show()
    try WinActivate("ahk_id " App.Gui.Hwnd)
}

; SC_MINIMIZE on our window → hide to tray (when enabled). Returning 0
; tells Windows we handled it, so the default minimize doesn't also run.
OnSysCommand(wParam, lParam, msg, hwnd) {
    global App
    if (IsObject(App.Gui) && hwnd = App.Gui.Hwnd
        && (wParam & 0xFFF0) = 0xF020 && App.MinimizeToTray) { ; SC_MINIMIZE
        App.Gui.Hide()
        ToolTip() ; clear any hover tip left hanging
        return 0
    }
}

; The NEXT quota day after today (looking 1..7 game-days ahead), for the
; banner's quiet state — "what's coming" beats restating the schedule
; (which lives in the banner's tooltip anyway). "" if no day has one.
NextQuotaText() {
    static names := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    loop 7 {
        w := Mod(GameWeekday() - 1 + A_Index, 7) + 1
        n := DailyQuotaCount(w)
        if (n > 0)
            return (A_Index = 1 ? "tomorrow (" names[w] ")" : names[w]) " · " n " accounts"
    }
    return ""
}

; The banner IS the button: red + clickable when a quota is due, green
; when done, quiet when today has no quota. Rebuilt on startup, theme
; switch, day rollover, and after a run starts.
RefreshQuotaBanner() {
    global App
    if !App.Controls.HasOwnProp("QuotaBanner")
        return
    ban := App.Controls.QuotaBanner
    n := DailyQuotaCount(GameWeekday())
    if (n = 0) {
        nxt := NextQuotaText()
        ban.Value := "  No activity quota today" (nxt != "" ? "  ·  next: " nxt : "")
        try ban.Opt("+Background" Colors.Bg)
        ban.SetFont("norm c" Colors.TextDim)
    } else if QuotaFulfilledToday() {
        ; "started", not "done": the stamp only means it was handled today,
        ; not that every account finished. Live progress is on the board.
        ban.Value := "  ✅ " GameDayName() "'s quota started (" n ") — progress on the ⏱ Session view.  Click to run again."
        try ban.Opt("+Background" Colors.BoardDone)
        ban.SetFont("bold cFFFFFF")
    } else {
        ban.Value := "  ⚠ " StrUpper(GameDayName()) " — " n " accounts DUE in Activity ("
            . Config.SessionGoalMinutes " min).  Click here to queue & start."
        try ban.Opt("+Background" Colors.Danger)
        ban.SetFont("bold cFFFFFF")
    }
    try ban.Redraw()
}

QuotaBannerClick(*) {
    ; No quota today → the banner is just informational. Otherwise start
    ; (or re-start) — DailyQuotaStart confirms, picks only accounts that
    ; still need it, and reports if there's nothing left to do.
    if (DailyQuotaCount(GameWeekday()) > 0)
        DailyQuotaStart()
}

; Strict startup reminder on an unmet quota day.
MaybeWarnQuota() {
    global App
    n := DailyQuotaCount(GameWeekday())
    ; No blocking popup when auto-run is on — it'll handle the day itself,
    ; and the red banner is reminder enough for a 24/7 setup.
    if (n = 0 || QuotaFulfilledToday() || App.AutoRunWhenIdle)
        return
    ShowConfirm("⚠ REMINDER — it's " GameDayName() ".`n`nYou owe " n " accounts in ACTIVITY mode today ("
        . Config.SessionGoalMinutes " min each).`n`nClick the red banner near the top of the window to queue "
        . n " random accounts and start.", "Daily Quota Due", "Iconi")
}

ConsoleAddMenu() {
    global App
    m := Menu()
    m.Add("All in current file", (*) => (PickAll("file"), RefreshLoginConsole()))
    m.Add("All (every file)", (*) => (PickAll("all"), RefreshLoginConsole()))
    m.Add("All not done (under the goal)", (*) => (PickNotDone(), RefreshLoginConsole()))
    if App.LoginFailedDrops.Length
        m.Add("↻ Re-add failed (" App.LoginFailedDrops.Length ")", (*) => ReaddFailed())
    m.Show()
}

; Puts last run's 3-strike casualties back in the queue (deduped).
ReaddFailed(*) {
    global App
    n := 0
    for acc in App.LoginFailedDrops {
        if !LoginQueueIndex(acc) {
            App.LoginQueue.Push(acc)
            n += 1
        }
    }
    App.LoginFailedDrops := []
    RefreshLoginConsole()
    ShowToast(n " account(s) re-queued")
}

; The selection is captured at RIGHT-CLICK time and bound into the menu
; items — the live refresh is held while the menu is open, and even if
; rows shift afterwards the actions hit the accounts you clicked on.
ConsoleTableMenu(dlg) {
    global App
    sel := ConsoleSelectedAccts(dlg)
    if !sel.Length
        return
    App.ConsoleHold := true
    m := Menu()
    m.Add("✖ Remove from queue", (*) => RemoveAcctsFromQueue(sel))
    m.Add("▲ Move to top", (*) => MoveAcctsTop(sel))
    m.Add("Clear macros", (*) => ClearMacrosFor(sel))
    m.Show()
    App.ConsoleHold := false
}

ClearMacrosFor(arr) {
    global App
    for acc in arr {
        try App.LoginMacros.Delete(acc.Email)
        acc.DeleteProp("_macroIdx")
    }
    RefreshLoginConsole()
}

ConsoleMoreMenu(dlg) {
    m := Menu()
    m.Add("🧹 Close clients that reached the goal", (*) => ConsoleCloseDone(dlg))
    m.Show()
}

; The console's inline Launch/Cap/Goal fields — validated through the
; same schema as ⚙ Preferences and persisted the same way.
ConsoleApplyNumbers(dlg) {
    for pair in [["LaunchMax", dlg.NumLaunch], ["OnlineCap", dlg.NumCap], ["SessionGoalMinutes", dlg.NumGoal]] {
        for item in TuningSchema() {
            if (item.Key = pair[1]) {
                ApplyTuningValue(item, pair[2].Text)
                try IniWrite(Config.%item.Key%, Config.SettingsPath, "Tuning", item.Key)
                pair[2].Text := Config.%item.Key% ; show the clamped value
            }
        }
    }
    RefreshSummary()
    UpdateAllRowsInPlace()
}

; Add every account (all files) still under the session goal.
PickNotDone(*) {
    global App
    goalMs := Config.SessionGoalMinutes * 60000
    App.PickMode := true
    for f in App.Files {
        for acc in f.Accounts {
            if (AccountOnlineMs(acc) < goalMs && !LoginQueueIndex(acc))
                App.LoginQueue.Push(acc)
        }
    }
    RefreshPickUI()
    UpdateAllRowsInPlace()
    RefreshSummary()
    ShowToast(App.LoginQueue.Length " account(s) picked")
}

; Move the given QUEUED accounts to the front, keeping their order.
MoveAcctsTop(arr) {
    global App
    qsel := []
    for acc in arr {
        if LoginQueueIndex(acc)
            qsel.Push(acc)
    }
    for acc in qsel
        App.LoginQueue.RemoveAt(LoginQueueIndex(acc))
    n := 0
    for acc in qsel {
        n += 1
        App.LoginQueue.InsertAt(n, acc)
    }
    UpdateAllRowsInPlace()
    RefreshLoginConsole()
}

; Close every online client whose account reached the goal (time is
; banked, so this is provably safe) — Play mode's teardown.
ConsoleCloseDone(dlg) {
    global App
    goalMs := Config.SessionGoalMinutes * 60000
    targets := []
    for f in App.Files {
        for acc in f.Accounts {
            if (AccountIsOnline(acc)
                && AccountOnlineMs(acc) >= goalMs)
                targets.Push(acc)
        }
    }
    if !targets.Length {
        ShowToast("No online account has reached the goal yet")
        return
    }
    if (ShowConfirm("Close " targets.Length " client(s) that reached " Config.SessionGoalMinutes " min?", "Confirm Close", "YesNo Icon?") != "Yes")
        return
    for acc in targets {
        try WinClose("ahk_id " acc.ClientHwnd)
        DetachClient(acc)
    }
    RefreshList()
    RefreshLinkStatus()
    RefreshLoginConsole()
}

; Run every assigned macro on its ONLINE account, right now — no
; launching, no login run needed. Runs in a worker thread; Esc/F7 stops.
RunMacrosNow(*) {
    global App
    if (App.LoginRunning || App.MacroPlaying || App.IsRecording) {
        ShowToast("Finish the current automation first")
        return
    }
    App.LoginStopReq := false
    App.LoginRunning := true
    SetTimer(MacroSweepWorker, -1)
}

MacroSweepWorker() {
    global App
    ; Restart every online account's playlist and run them all, in rounds.
    onl := []
    for f in App.Files {
        for acc in f.Accounts {
            if (AccountMacroList(acc).Length && AccountIsOnline(acc)) {
                acc.DeleteProp("_macroIdx")
                onl.Push(acc)
            }
        }
    }
    ran := 0
    while (!AbortPressed() && IsObject(acc := FirstPendingMacro(onl, false))) {
        SetLoginStatus("Macro on " acc.Name "…")
        RunAccountMacro(acc)
        ran += 1
    }
    App.LoginRunning := false
    App.LoginStatusText := ""
    RefreshLinkStatus()
    RefreshLoginConsole()
    ShowToast("Macro sweep done — " ran " run(s)")
}

; Links a specific window (not necessarily the active one) to an account
; — the orchestrator variant of LinkActiveWindowToAccount.
LinkActiveWindowToAccount2(acc, hwnd) {
    global App
    for f in App.Files {
        for other in f.Accounts {
            if (other.HasOwnProp("ClientHwnd") && other.ClientHwnd = hwnd && other != acc)
                DetachClient(other)
        }
    }
    if !App.WindowSessionNumbers.Has(hwnd) {
        App.NextSessionNumber += 1
        App.WindowSessionNumbers[hwnd] := App.NextSessionNumber
    }
    DetachClient(acc)
    acc.ClientSession := App.WindowSessionNumbers[hwnd]
    acc.ClientHwnd := hwnd
    acc.LinkTime := A_TickCount
    App.UsedWindowHwnds[hwnd] := true
}

GameWindowSet() {
    set := Map()
    for hwnd in GetGameClientWindows()
        set[hwnd] := true
    return set
}

; Polls for a game window that wasn't in the 'before' set.
WaitForNewGameWindow(before, timeoutMs) {
    waited := 0
    loop {
        for hwnd in GetGameClientWindows() {
            if !before.Has(hwnd)
                return hwnd
        }
        if (waited >= timeoutMs || AbortPressed())
            return 0
        Sleep(300)
        waited += 300
    }
}

SetLoginStatus(text) {
    global App
    App.LoginStatusText := text
    RefreshLinkStatus()
}

; --- Login Setup: capture the 5 points + probe color, once ---
OpenLoginSetup(*) {
    global App
    if IsObject(App.LoginSetupDlg) {
        try App.LoginSetupDlg.Show()
        return
    }
    dlg := Gui("+Owner" App.Gui.Hwnd, "Login Setup — Account Queue")
    dlg.BackColor := Colors.Bg
    dlg.MarginX := 14
    dlg.MarginY := 12
    dlg.SetFont("s9 c" Colors.Text, Config.FontMain)

    hdr := dlg.Add("Text", "w460", "Open ONE game client · capture each point with F12")
    hdr.TipText := "Place the client where clients normally sit. For each point: click Capture, hover the exact spot in the client, then press F12. Each point also samples its pixel colour, which the automation uses to detect that stage."

    dlg.Fields := Map()
    for row in [["tryagain", "1. Try Again button", "Clicked repeatedly to clear a stuck loading screen"]
        , ["logout", "2. Logout→login button", "Also the loaded-state probe — its colour tells the automation the client finished loading"]
        , ["email", "3. Email field", "Also the login-page probe — its colour tells the automation the login page is open"]
        , ["start", "4. Start Game button", "Clicked after the credentials go in"]
        , ["char", "5. Character to select", "Clicked until the game world loads"]] {
        btn := dlg.Add("Button", "xm y+6 w110 h24 Section", "◉ Capture")
        btn.OnEvent("Click", ArmCapture.Bind(row[1]))
        btn.TipText := "Arm this point, then hover the spot in the game client and press F12"
        lbl := dlg.Add("Text", "x+8 ys+4 w250 h20", row[2])
        lbl.TipText := row[3]
        st := dlg.Add("Text", "x+6 ys+4 w90 h20 +0x201", CaptureStateText(row[1]))
        if App.LoginProfile.Points.Has(row[1])
            st.SetFont("c" Colors.Success)
        dlg.Fields[row[1]] := st
    }

    dlg.SetFont("s8 Norm Italic c" Colors.TextDim, Config.FontMain)
    dlg.StatusLine := dlg.Add("Text", "xm y+10 w460 +0x200", LoginProfileReady()
        ? "Profile complete — 🚀 Launch + Login is ready."
        : "Capture all five points to enable Launch + Login.")
    if LoginProfileReady()
        dlg.StatusLine.SetFont("c" Colors.Success)

    dlg.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
    btnClose := dlg.Add("Button", "xm y+10 w100 h28 Default", "Done")
    btnClose.OnEvent("Click", (*) => CloseLoginSetup(dlg))

    ApplyDialogDarkMode(dlg)
    dlg.OnEvent("Close", (*) => CloseLoginSetup(dlg))
    dlg.OnEvent("Escape", (*) => CloseLoginSetup(dlg))
    App.LoginSetupDlg := dlg
    dlg.Show("AutoSize")
}

CloseLoginSetup(dlg) {
    global App
    App.CaptureKey := ""
    App.LoginSetupDlg := ""
    try dlg.Destroy()
}

CaptureStateText(key) {
    global App
    return App.LoginProfile.Points.Has(key) ? "✔ captured" : "— not set —"
}

ArmCapture(key, *) {
    global App
    App.CaptureKey := key
    ShowToast("Hover the spot in the game client, then press F12")
}

; F12 while a capture is armed: record the point (window-relative +
; window size) under the mouse, and for the logout point also sample the
; pixel colour used as the loaded-state probe.
DoLoginCapture() {
    global App
    if (App.CaptureKey = "")
        return
    key := App.CaptureKey
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my, &underHwnd)
    proc := ""
    try proc := WinGetProcessName("ahk_id " underHwnd)
    if (proc != Config.GameProcess) {
        ShowToast("Point must be inside a " Config.GameProcess " window")
        return
    }
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " underHwnd)
    ; Every point is also a probe — sample the pixel colour at capture.
    CoordMode("Pixel", "Screen")
    color := ""
    try color := PixelGetColor(mx, my)
    App.LoginProfile.Points[key] := { X: mx - wx, Y: my - wy, RefW: ww, RefH: wh, Color: color }
    SaveLoginProfile()
    App.CaptureKey := ""

    if IsObject(App.LoginSetupDlg) {
        try {
            App.LoginSetupDlg.Fields[key].Value := CaptureStateText(key)
            App.LoginSetupDlg.Fields[key].SetFont("c" Colors.Success)
            App.LoginSetupDlg.StatusLine.Value := LoginProfileReady()
                ? "Profile complete — 🚀 Launch + Login is ready."
                : "Capture all five points to enable Launch + Login."
            App.LoginSetupDlg.StatusLine.SetFont("c" (LoginProfileReady() ? Colors.Success : Colors.TextDim))
        }
    }
    ShowToast("Captured " key)
}

; ============================================================
; PREFERENCES (⚙ — user-tunable Config values)
; ------------------------------------------------------------
; One schema table drives everything: the dialog rows, validation
; ranges, tooltips, and the [Tuning] section of Settings.ini. To make a
; new Config value tunable, add ONE entry here.
; ============================================================
TuningSchema() {
    return [
        { Key: "GameProcess", Label: "Game process", Type: "str",
          Tip: "Process name of the game client windows (e.g. ToW.exe)" },
        { Key: "SessionGoalMinutes", Label: "Session goal (min)", Type: "int", Min: 1, Max: 1440,
          Tip: "Minutes online for an account to count as done — the green threshold" },
        { Key: "DayResetHour", Label: "Day resets at (hour)", Type: "int", Min: 0, Max: 23,
          Tip: "Hour (0-23) when the game's day flips and all session stats reset" },
        { Key: "ComboStepDelayMs", Label: "F4 step delay (ms)", Type: "int", Min: 0, Max: 5000,
          Tip: "Pause between the steps of the F4 combo (email, Tab, password, Enter)" },
        { Key: "WindowSwitchDelayMs", Label: "Auto-next delay (ms)", Type: "int", Min: 0, Max: 5000,
          Tip: "Pause after a paste before focus jumps to the next client" },
        { Key: "ClipRestoreMs", Label: "Clipboard restore (ms)", Type: "int", Min: 50, Max: 5000,
          Tip: "How long after a paste your real clipboard comes back" },
        { Key: "NoteAutosaveDelayMs", Label: "Autosave debounce (ms)", Type: "int", Min: 200, Max: 10000,
          Tip: "Typing pause before notes / game fields save to disk" },
        { Key: "QueueJobGapMs", Label: "Macro queue gap (ms)", Type: "int", Min: 0, Max: 60000,
          Tip: "Breather between macro queue jobs" },
        { Key: "MouseRestoreDelayMs", Label: "Pointer return delay (ms)", Type: "int", Min: 0, Max: 5000,
          Tip: "Pause after playback before the mouse pointer is put back where you left it. Too short and the game reads the LAST click at the pointer's new position instead. 0 = leave the pointer where the run ended." },
        { Key: "BackupsToKeep", Label: "Backups per file", Type: "int", Min: 1, Max: 500,
          Tip: "Timestamped backups kept per login file before old ones are pruned" },
        { Key: "LauncherPath", Label: "Game launcher path", Type: "str", Wide: true,
          Tip: "The .exe that opens one game client (Launch & Login runs it once per account)" },
        { Key: "LaunchMax", Label: "Launch group size", Type: "int", Min: 1, Max: 8,
          Tip: "Most clients one Launch & Login run will open at once" },
        { Key: "LoginBootMs", Label: "Boot wait (ms)", Type: "int", Min: 0, Max: 180000,
          Tip: "How long to let clients load after launching, before logging in (all load in parallel)" },
        { Key: "LoginAfterCredsMs", Label: "After credentials (ms)", Type: "int", Min: 0, Max: 30000,
          Tip: "Wait after the F4 credential paste before clicking Start Game" },
        { Key: "LoginStartToCharMs", Label: "Start→character (ms)", Type: "int", Min: 0, Max: 30000,
          Tip: "Wait after Start Game before clicking the character" },
        { Key: "LoginPollMs", Label: "Unstuck poll (ms)", Type: "int", Min: 200, Max: 30000,
          Tip: "Re-check interval while pressing Try Again on a stuck load" },
        { Key: "LoginColorTol", Label: "Color tolerance", Type: "int", Min: 0, Max: 255,
          Tip: "How closely the probe pixels must match their captured colors (0 = exact)" },
        { Key: "LoginEmailToF4Ms", Label: "Email→F4 (ms)", Type: "int", Min: 0, Max: 5000,
          Tip: "Gap between clicking the email field and firing F4 — keep short; the game freezes if the login page lingers" },
        { Key: "LoginPagePollMs", Label: "Page poll (ms)", Type: "int", Min: 50, Max: 5000,
          Tip: "How often to check whether the login page has opened (faster = F4 sooner)" },
        { Key: "LoginLogoutRetryMs", Label: "Logout re-click (ms)", Type: "int", Min: 100, Max: 10000,
          Tip: "Re-click the logout button this often until the login page appears (handles it needing a double-click)" },
        { Key: "LoginMaxRetries", Label: "Close+retry count", Type: "int", Min: 0, Max: 10,
          Tip: "If a client gets stuck at any step, close it and relaunch up to this many times" },
        { Key: "OnlineCap", Label: "Online cap", Type: "int", Min: 1, Max: 50,
          Tip: "Activity mode keeps at most this many accounts online at once, for the session goal, then closes them" },
        { Key: "MacroReserveMinutes", Label: "Macro reserve (min)", Type: "int", Min: 0, Max: 120,
          Tip: "Idle minutes kept macro-free — a macro only runs if it fits in the account's remaining time minus this" },
        { Key: "AutoRunIdleMinutes", Label: "Auto-run idle (min)", Type: "int", Min: 5, Max: 1440,
          Tip: "When 'run idle actions when idle' is on (tray menu), idle jobs fire after this many minutes with no keyboard/mouse input" },
        { Key: "IdleGraceSeconds", Label: "Idle cancel countdown (s)", Type: "int", Min: 0, Max: 60,
          Tip: "Before an idle job auto-starts, a countdown lets you cancel if you're actually there. 0 = start immediately, no countdown" },
    ]
}

CaptureTuningDefaults() {
    global App
    App.TuningDefaults := Map()
    for item in TuningSchema()
        App.TuningDefaults[item.Key] := Config.%item.Key%
}

LoadTuning() {
    for item in TuningSchema() {
        raw := ""
        try raw := IniRead(Config.SettingsPath, "Tuning", item.Key, "")
        if (raw != "")
            ApplyTuningValue(item, raw)
    }
}

; Validates + clamps one value and writes it into Config. Bad input is
; ignored (keeps the current value) rather than erroring.
ApplyTuningValue(item, raw) {
    if (item.Type = "int") {
        v := ""
        try v := Integer(Trim(raw))
        catch
            return
        Config.%item.Key% := Min(Max(v, item.Min), item.Max)
    } else {
        raw := Trim(raw)
        if (raw != "")
            Config.%item.Key% := raw
    }
}

OpenPreferences(*) {
    global App
    if IsObject(App.PrefsDlg) {
        try App.PrefsDlg.Show()
        return
    }

    dlg := Gui("+Owner" App.Gui.Hwnd, "Preferences — Account Queue")
    dlg.BackColor := Colors.Bg
    dlg.MarginX := 14
    dlg.MarginY := 12
    dlg.SetFont("s9 c" Colors.Text, Config.FontMain)

    ; Two grouped columns (schema order is already contiguous per group):
    ; col 1 = General, col 2 = Mass Login automation + Activity.
    dlg.SetFont("s9 Bold c" Colors.TextDim, Config.FontMain)
    dlg.Add("Text", "x14 y12 w200 h18", "General")
    dlg.Add("Text", "x336 y12 w200 h18", "Mass Login")
    dlg.SetFont("s9 Norm c" Colors.Text, Config.FontMain)

    dlg.Fields := Map()
    edits := []
    x := 14, y := 36, edW := 130
    for item in TuningSchema() {
        if (item.Key = "LauncherPath") { ; Mass Login group -> column 2
            x := 336, y := 36, edW := 190
        }
        if (item.Key = "OnlineCap") { ; Activity subheader inside column 2
            dlg.SetFont("s9 Bold c" Colors.TextDim, Config.FontMain)
            dlg.Add("Text", "x" x " y" (y + 8) " w200 h18", "Activity")
            dlg.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
            y += 32
        }
        lbl := dlg.Add("Text", "x" x " y" (y + 2) " w150 h20", item.Label)
        lbl.TipText := item.Tip
        ed := dlg.Add("Edit", "x" (x + 158) " y" y " w" edW " h22", Config.%item.Key%)
        ed.TipText := item.Tip
        dlg.Fields[item.Key] := ed
        edits.Push(ed)
        y += 27
    }

    btnSave := dlg.Add("Button", "x14 y" (y + 14) " w100 h28 Default", "💾 Save")
    btnSave.OnEvent("Click", (*) => PrefsSave(dlg))
    btnCancel := dlg.Add("Button", "x+8 yp w90 h28", "Cancel")
    btnCancel.OnEvent("Click", (*) => ClosePreferences(dlg))
    btnDefaults := dlg.Add("Button", "x+8 yp w100 h28", "↺ Defaults")
    btnDefaults.OnEvent("Click", (*) => PrefsFillDefaults(dlg))
    btnDefaults.TipText := "Fill every field with the shipped default (takes effect on Save)"
    btnLoginSetup := dlg.Add("Button", "x+8 yp w120 h28", "🎯 Login Setup")
    btnLoginSetup.OnEvent("Click", (*) => OpenLoginSetup())
    btnLoginSetup.TipText := "Capture the 5 click points + loaded-state colour for 🚀 Launch & Login"

    ApplyDialogDarkMode(dlg, edits)
    dlg.OnEvent("Close", (*) => ClosePreferences(dlg))
    dlg.OnEvent("Escape", (*) => ClosePreferences(dlg))

    App.PrefsDlg := dlg
    dlg.Show("AutoSize")
}

ClosePreferences(dlg) {
    global App
    App.PrefsDlg := ""
    try dlg.Destroy()
}

PrefsFillDefaults(dlg) {
    global App
    for item in TuningSchema()
        dlg.Fields[item.Key].Text := App.TuningDefaults[item.Key]
}

PrefsSave(dlg) {
    global App
    for item in TuningSchema() {
        ApplyTuningValue(item, dlg.Fields[item.Key].Text)
        try IniWrite(Config.%item.Key%, Config.SettingsPath, "Tuning", item.Key)
    }

    ; Live side effects: a changed goal recolors rows immediately, and a
    ; changed reset hour must ADOPT the new boundary without triggering
    ; a spurious "new game day" reset on the next housekeeping tick.
    App.CurrentGameDay := GameDayStamp()
    SaveSessionTimes()
    UpdateAllRowsInPlace()
    RefreshSummary()
    RefreshLinkStatus()
    RefreshOnlineView()

    ShowToast("Preferences saved")
    ClosePreferences(dlg)
}

; ============================================================
; DAY BOARD (strip above the list — the whole day at a glance)
; ------------------------------------------------------------
; One colored cell per account across ALL files, deduplicated by email
; (same merge rules as the session scoreboard): grey = not started,
; amber = online and counting, green = goal reached, red = lost its
; client early. Hover a cell for the account's card, click it to jump
; there. Cells come from a fixed hidden pool created once in BuildGUI
; (AHK v2 can't destroy individual controls), positioned by
; PositionBoard and recolored only when a state actually changes.
; ============================================================

; Merged per-email day state across all files. Pure aggregation — also
; feeds the taskbar progress. Rank on merge: any linked copy makes the
; email "online", the best time wins (mirrors RefreshSummary's rules).
BoardBuild() {
    global App
    goalMs := Config.SessionGoalMinutes * 60000
    accs := []
    recs := Map()
    for f in App.Files {
        for acc in f.Accounts {
            t := AccountOnlineMs(acc)
            linked := acc.HasOwnProp("ClientHwnd")
            if !recs.Has(acc.Email) {
                accs.Push(acc)
                recs[acc.Email] := { T: t, L: linked }
            } else {
                r := recs[acc.Email]
                if (t > r.T)
                    r.T := t
                if linked
                    r.L := true
            }
        }
    }
    states := []
    done := 0
    online := 0
    totalMs := 0
    for acc in accs {
        r := recs[acc.Email]
        st := (r.T >= goalMs) ? "done" : r.L ? "online" : (r.T > 0) ? "lost" : "idle"
        states.Push(st)
        totalMs += r.T
        if (st = "done")
            done += 1
        else if (st = "online")
            online += 1
    }
    return { Accs: accs, States: states, Done: done, Online: online, Total: accs.Length, TotalMs: totalMs }
}

; "45m" under an hour, "3.4h" from there — for the scoreboard's Σ.
FormatHours(ms) {
    mins := Round(ms / 60000)
    return mins < 60 ? mins "m" : Round(mins / 60.0, 1) "h"
}

BoardColor(state) {
    switch state {
        case "done": return Colors.BoardDone
        case "online": return Colors.BoardOnline
        case "lost": return Colors.BoardWarn
    }
    return Colors.BoardIdle
}

BoardTip(acc, state) {
    mins := Round(AccountOnlineMs(acc) / 60000)
    switch state {
        case "done": s := "✔ done — " mins " min"
        case "online": s := "● online — " mins " of " Config.SessionGoalMinutes " min"
        case "lost": s := "⚠ client lost at " mins " min"
        default: s := "not started"
    }
    return acc.Name "  ·  " s "   (click to jump)"
}

; Recompute states, recolor only cells whose state changed, reposition
; only when the account set itself changed. Cheap enough for every
; housekeeping tick and every summary refresh.
RefreshBoard(force := false, b := "") {
    global App
    if !App.Controls.HasOwnProp("BoardCells")
        return
    if !IsObject(b) ; caller may pass a fresh BoardBuild() to avoid a rebuild
        b := BoardBuild()
    cells := App.Controls.BoardCells

    sig := ""
    for acc in b.Accs
        sig .= acc.Email "|"
    if (force || sig != App.BoardSig) {
        App.BoardSig := sig
        App.BoardAccounts := b.Accs
        App.BoardStates := []
        loop cells.Length
            App.BoardStates.Push("")
        PositionBoard()
    }

    n := Min(b.Accs.Length, cells.Length)
    loop n {
        i := A_Index
        if (App.BoardStates[i] = b.States[i])
            continue
        App.BoardStates[i] := b.States[i]
        cells[i].Opt("+Background" BoardColor(b.States[i]))
        cells[i].TipText := BoardTip(b.Accs[i], b.States[i])
        try cells[i].Redraw()
    }
    UpdateTaskbarProgress(b.Done, b.Total)

    ; One small fanfare the moment the whole day completes — but not on
    ; startup into an already-complete day (that's old news).
    static seeded := false
    complete := b.Total > 0 && b.Done = b.Total
    if !seeded {
        seeded := true
        App.DayCelebrated := complete
    } else if (complete && !App.DayCelebrated) {
        App.DayCelebrated := true
        ShowToast("🎉 All " b.Total " accounts done for today")
        try SoundBeep(880, 120)
        try SoundBeep(1175, 180)
    } else if !complete {
        App.DayCelebrated := false
    }
}

; Lays the visible cells out across the inner width (called on resize
; and whenever the account set changes). Cells keep their build-time Y —
; the board lives above the list, which never moves.
PositionBoard(innerW := 0) {
    global App
    if !App.Controls.HasOwnProp("BoardCells")
        return
    if (innerW <= 0) {
        App.Gui.GetClientPos(, , &cw)
        innerW := cw - 32
    }
    cells := App.Controls.BoardCells
    n := Min(App.BoardAccounts.Length, cells.Length)
    gap := 2
    if (n > 0)
        cellW := Max(4, Min(22, (innerW - (n - 1) * gap) // n))
    x := 16
    loop cells.Length {
        i := A_Index
        if (i > n) {
            cells[i].Visible := false
            continue
        }
        cells[i].Move(x, , cellW)
        cells[i].Visible := true
        x += cellW + gap
    }
}

BoardCellClicked(i, *) {
    global App
    if (i < 1 || i > App.BoardAccounts.Length)
        return
    ; In pick mode the board is a picker too — click cells to queue
    ; accounts (same toggle as clicking list rows). Otherwise: jump.
    if App.PickMode
        TogglePickMembership(App.BoardAccounts[i])
    else
        JumpToAccount(App.BoardAccounts[i])
}

; A saved window position is only trusted if its title-bar area still
; lands on a live monitor's work area (screens get unplugged).
PosOnAScreen(x, y) {
    try {
        loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
            if (x + 60 >= l && x + 60 <= r && y + 20 >= t && y + 20 <= b)
                return true
        }
    }
    return false
}

; Shared by the board and search-jump: clear any active filter
; (it could hide the target row), then select the account cross-file.
JumpToAccount(acc) {
    global App
    if (App.FilterText != "") {
        App.Controls.Search.Text := "" ; programmatic — no Change event (gotcha #13)
        ApplyFilter("")
    }
    FocusAccountInUI(acc)
}

; Day progress on the taskbar button itself (ITaskbarList3) — glanceable
; from inside the game. Best-effort: every call is try-wrapped, a COM
; failure just means no bar.
UpdateTaskbarProgress(done, total) {
    global App
    static tbl := "", inited := false
    if !inited {
        inited := true
        try {
            tbl := ComObject("{56FDF344-FD6D-11d0-958A-006097C9A090}", "{EA1AFB91-9E28-4B86-90E9-9E9F8A5EEFAF}")
            ComCall(3, tbl) ; ITaskbarList::HrInit
        } catch {
            tbl := ""
        }
    }
    if !IsObject(tbl)
        return
    try {
        if (total <= 0 || done <= 0) {
            ComCall(10, tbl, "ptr", App.Gui.Hwnd, "uint", 0) ; SetProgressState TBPF_NOPROGRESS
        } else {
            ComCall(10, tbl, "ptr", App.Gui.Hwnd, "uint", 2) ; SetProgressState TBPF_NORMAL
            ComCall(9, tbl, "ptr", App.Gui.Hwnd, "uint64", done, "uint64", total) ; SetProgressValue
        }
    }
}

; ============================================================
; SEARCH KEYS (Enter = jump to first match, Esc = clear)
; ============================================================
SearchHasFocus() {
    global App
    try return IsObject(App.Gui.FocusedCtrl) && App.Gui.FocusedCtrl = App.Controls.Search
    catch
        return false
}

SearchJumpFirst(*) {
    global App
    first := FirstAccountRow(1)
    if !first
        return
    acc := RowAccount(first)
    SearchClear()
    FocusAccountInUI(acc)
    App.Controls.List.Focus()
}

SearchClear(*) {
    global App
    App.Controls.Search.Text := "" ; programmatic — no Change event (gotcha #13)
    ApplyFilter("")
}

FocusSearch(*) {
    global App
    try App.Controls.Search.Focus()
}

; ============================================================
; THEME
; ============================================================
ApplyTheme(name, persist := true) {
    global App
    isDark := (name = "dark")
    App.ThemeName := isDark ? "dark" : "light"

    if isDark {
        Colors.Bg := "1E1F26"
        Colors.Text := "ECECEC"
        Colors.TextDim := "9A9CA5"
        Colors.Accent := "7C9CFF"
        Colors.DoneRowBGR := 0x8BE37C   ; light green, readable on the dark list
        Colors.OnlineRowBGR := 0x4FD5FF ; warm amber
        Colors.WarnRowBGR := 0x7B7BFF   ; soft red
        Colors.QueuedRowBGR := 0xFF9C7C ; light accent blue
        Colors.BoardDone := "2E9E4F"
        Colors.BoardOnline := "D9A21B"
        Colors.BoardWarn := "D64545"
        Colors.BoardIdle := "3A3B45"
        Colors.Success := "7CE38B"
        Colors.Info := "7CB8FF"
        Colors.Warning := "FFD54F"
        Colors.Danger := "FF7B7B"
        Colors.ZebraBGR := 0x322A29 ; subtle lift over the 23242C list bg
    } else {
        Colors.Bg := "F5F6FA"
        Colors.Text := "222222"
        Colors.TextDim := "777777"
        Colors.Accent := "3F6FE0"
        Colors.DoneRowBGR := 0x46961E   ; deep green, readable on white
        Colors.OnlineRowBGR := 0x0B86B8 ; dark goldenrod
        Colors.WarnRowBGR := 0x2828C6   ; deep red
        Colors.QueuedRowBGR := 0xE06F3F ; accent blue
        Colors.BoardDone := "1E9646"
        Colors.BoardOnline := "B8860B"
        Colors.BoardWarn := "C62828"
        Colors.BoardIdle := "D8DAE2"
        Colors.Success := "2E7D32"
        Colors.Info := "1565C0"
        Colors.Warning := "B8860B"
        Colors.Danger := "C62828"
        Colors.ZebraBGR := 0xF7F3F2 ; subtle shade under the white list bg
    }

    App.Gui.BackColor := Colors.Bg

    App.Controls.VersionLabel.SetFont("c" Colors.TextDim)
    App.Controls.FileLabel.SetFont("c" Colors.Accent)
    App.Controls.CountLabel.SetFont("c" Colors.TextDim)
    App.Controls.StatDone.SetFont("c" Colors.Success)
    App.Controls.StatOnline.SetFont("c" Colors.Warning)
    App.Controls.StatToGo.SetFont("c" Colors.TextDim)
    App.Controls.StatMoney.SetFont("c" Colors.Accent)
    App.Controls.LinkStatus.SetFont("c" Colors.TextDim)
    App.Controls.HotkeysLabel.SetFont("c" Colors.TextDim)
    App.Controls.NotesBox.SetFont("c" Colors.Text)
    App.Controls.ClassEdit.SetFont("c" Colors.Text)
    App.Controls.LevelEdit.SetFont("c" Colors.Text)
    App.Controls.MoneyEdit.SetFont("c" Colors.Text)
    App.Controls.Search.SetFont("c" Colors.Text)
    App.Controls.ShowPw.SetFont("c" Colors.Text)
    App.Controls.AutoNextToggle.SetFont("c" Colors.Text)
    App.Controls.EditMode.SetFont("c" Colors.Text)
    App.Controls.ThemeToggle.SetFont("c" Colors.Text)
    App.Controls.OnTopToggle.SetFont("c" Colors.Text)
    try App.Controls.Progress.Opt("c" Colors.Accent)

    ; Best-effort native dark styling for controls that ignore SetFont
    ; colors (ListView rows/headers, Edit boxes). Reliable on Windows
    ; 10/11; harmless no-op if unsupported. Buttons are deliberately
    ; left alone — native Win32 buttons don't take dark theming well
    ; without heavier custom-draw work, so they stay light either way.
    themeName := isDark ? "DarkMode_Explorer" : ""
    for ctrl in [App.Controls.List, App.Controls.Search, App.Controls.NotesBox,
        App.Controls.ClassEdit, App.Controls.LevelEdit, App.Controls.MoneyEdit] {
        try DllCall("uxtheme\SetWindowTheme", "ptr", ctrl.Hwnd, "str", themeName, "ptr", 0)
    }
    ; SetWindowTheme only darkens the CHROME (scrollbars, list header) —
    ; the client area needs explicit background/text colors or the list
    ; and edit boxes stay glaring white in dark mode.
    if isDark {
        try App.Controls.List.Opt("+Background23242C c" Colors.Text)
        for ctrl in [App.Controls.Search, App.Controls.NotesBox,
            App.Controls.ClassEdit, App.Controls.LevelEdit, App.Controls.MoneyEdit]
            try ctrl.Opt("+Background2A2B33")
    } else {
        try App.Controls.List.Opt("+BackgroundDefault cDefault")
        for ctrl in [App.Controls.Search, App.Controls.NotesBox,
            App.Controls.ClassEdit, App.Controls.LevelEdit, App.Controls.MoneyEdit]
            try ctrl.Opt("+BackgroundDefault")
    }
    try ApplyDarkTitleBar(App.Gui.Hwnd, isDark)

    App.Controls.ThemeToggle.Value := isDark ? 1 : 0
    RefreshList()
    RefreshBoard(true) ; recolor every cell in the new palette
    RefreshQuotaBanner() ; banner colours are theme-tuned too

    if persist
        SaveSettings()
}

ToggleTheme(*) {
    global App
    ApplyTheme(App.Controls.ThemeToggle.Value = 1 ? "dark" : "light", true)
}

ToggleAlwaysOnTop(*) {
    global App
    App.AlwaysOnTop := App.Controls.OnTopToggle.Value = 1
    App.Gui.Opt(App.AlwaysOnTop ? "+AlwaysOnTop" : "-AlwaysOnTop")
    SaveSettings()
}

; Shared best-effort dark styling for owned dialogs: dark title bar,
; DarkMode_Explorer chrome and dark client colors for the given edit
; boxes and list views. No-op in light theme (dialogs read Colors.* at
; build time, so fonts/background already match). Any new dialog must
; call this before Show().
ApplyDialogDarkMode(dlg, editCtrls := [], listViews := []) {
    global App
    ; Title bar blends with the body in BOTH themes (caption = Colors.Bg)
    ApplyDarkTitleBar(dlg.Hwnd, App.ThemeName = "dark")
    if (App.ThemeName != "dark")
        return
    for ctrl in editCtrls {
        try DllCall("uxtheme\SetWindowTheme", "ptr", ctrl.Hwnd, "str", "DarkMode_Explorer", "ptr", 0)
        try ctrl.Opt("+Background2A2B33")
    }
    for lv in listViews {
        try DllCall("uxtheme\SetWindowTheme", "ptr", lv.Hwnd, "str", "DarkMode_Explorer", "ptr", 0)
        try lv.Opt("+Background23242C c" Colors.Text)
    }
}

ApplyDarkTitleBar(hwnd, enable) {
    val := enable ? 1 : 0
    ; DWMWA_USE_IMMERSIVE_DARK_MODE — 20 on Win10 20H1+/Win11, 19 on
    ; earlier Win10 builds. Try both; failures are silently ignored.
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 20, "int*", val, "int", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 19, "int*", val, "int", 4)
    ; Win11 (22000+) only: paint the caption in the app's own background
    ; and text colors, so the title bar reads as part of the window
    ; instead of an OS frame. Silently a no-op on Win10.
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 35, "uint*", HexToBGR(Colors.Bg), "int", 4)   ; DWMWA_CAPTION_COLOR
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 36, "uint*", HexToBGR(Colors.Text), "int", 4) ; DWMWA_TEXT_COLOR
}

; ============================================================
; GUI
; ============================================================
BuildGUI() {
    global App
    innerW := Config.WindowWidth - 32

    guiOpts := "+Resize +MinSize420x600"
    if App.AlwaysOnTop
        guiOpts .= " +AlwaysOnTop"
    App.Gui := Gui(guiOpts, "Account Queue")
    App.Gui.BackColor := Colors.Bg
    App.Gui.MarginX := 16
    App.Gui.MarginY := 14

    ; --- file nav row (top row — the title bar already carries the app
    ; name + version, so no in-window title duplicating it) ---
    App.Gui.SetFont("s12 c" Colors.Text, Config.FontMain)
    App.Controls.PrevBtn := App.Gui.Add("Button", "xm ym w34 h28", "◀")
    App.Controls.PrevBtn.OnEvent("Click", (*) => PreviousFile())

    App.Gui.SetFont("s11 Bold c" Colors.Accent, Config.FontMain)
    App.Controls.FileLabel := App.Gui.Add("Text",
        "x+10 yp+5 w" (innerW - 34 - 34 - 20) " Center", "")

    App.Gui.SetFont("s12 c" Colors.Text, Config.FontMain)
    App.Controls.NextBtn := App.Gui.Add("Button", "x+10 yp-5 w34 h28", "▶")
    App.Controls.NextBtn.OnEvent("Click", (*) => NextFile())

    ; --- search row (+ view switcher). No label — the box carries a
    ; cue banner, same pattern as the quick-edit boxes. ---
    App.Gui.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
    App.Controls.Search := App.Gui.Add("Edit", "xm y+12 w" (innerW - 164) " h22")
    try DllCall("user32\SendMessageW", "ptr", App.Controls.Search.Hwnd, "uint", 0x1501, "ptr", 1, "wstr", "🔍 Search")
    App.Controls.Search.OnEvent("Change", (ctrl, *) => ApplyFilter(ctrl.Text))
    ; Live "online accounts across all files" window (F9)...
    App.Controls.OnlineBtn := App.Gui.Add("Button", "x+8 yp-1 w34 h24", "👁")
    App.Controls.OnlineBtn.OnEvent("Click", OpenOnlineView)
    ; ...then the one-click view switch: three square buttons, one per
    ; view. The ACTIVE view's button is disabled (pressed look). F6 cycles.
    App.Controls.ViewBtnCred := App.Gui.Add("Button", "x+12 yp w34 h24", "🔑")
    App.Controls.ViewBtnCred.OnEvent("Click", (*) => SetViewMode("credentials"))
    App.Controls.ViewBtnGame := App.Gui.Add("Button", "x+4 yp w34 h24", "🎮")
    App.Controls.ViewBtnGame.OnEvent("Click", (*) => SetViewMode("game"))
    App.Controls.ViewBtnSess := App.Gui.Add("Button", "x+4 yp w34 h24", "⏱")
    App.Controls.ViewBtnSess.OnEvent("Click", (*) => SetViewMode("session"))

    ; --- day board: fixed pool of cells, laid out by PositionBoard ---
    App.Controls.BoardCells := []
    loop 120 {
        cell := App.Gui.Add("Text", (A_Index = 1 ? "xm y+10" : "x+2 yp") " w10 h8 Hidden +Background" Colors.BoardIdle, "")
        cell.OnEvent("Click", BoardCellClicked.Bind(A_Index))
        App.Controls.BoardCells.Push(cell)
    }

    ; --- list ---
    ; NoSort: header-click sorting would reorder rows visually WITHOUT
    ; reordering App.Displayed — after a sort, F1/F2/F4 would paste a
    ; different account than the highlighted one. Same bug family as the
    ; ItemSelect desync (gotcha #12); don't re-enable sorting casually.
    App.Controls.List := App.Gui.Add("ListView",
        "xm y+8 w" innerW " h484 -Multi NoSort", ["#", "Name", "Email", "Password", "Client", "Note"])
    App.Controls.List.Opt("+Grid")
    ; ItemSelect (not Click): fires for BOTH mouse clicks and keyboard
    ; navigation inside the list (Home/End/PageUp/PageDown). A Click-only
    ; handler let keyboard nav move the visible selection while
    ; App.CurrentDisplayPos stayed behind — so F1/F2/F4 could paste a
    ; different account than the one highlighted on screen.
    App.Controls.List.OnEvent("ItemSelect", OnListItemSelect)
    App.Controls.List.OnEvent("Click", OnListClick) ; pick-mode toggling only
    App.Controls.List.OnEvent("DoubleClick", OnListDoubleClick)
    App.Controls.List.OnEvent("ContextMenu", OnListContextMenu)
    App.Controls.List.OnNotify(-12, OnListCustomDraw) ; NM_CUSTOMDRAW — Session view row coloring

    ; Column widths/titles live in SetViewMode -> SetListColumns (called
    ; once at startup and on view switches, not in RefreshList) so manual
    ; column resizing survives list refreshes within a view.

    ; ============ below the list: four grouped zones ============
    ; 1) selected account (quick-edit boxes, progress, status/count)
    ; 2) login flow (auto-next client, used-window tracking)
    ; 3) managing accounts (edit mode next to what it gates)
    ; 4) app preferences + hotkey legend

    ; --- zone 1: selected account. Quick-edit row: always live, no
    ; dialog, no confirmation, no caption row — every box carries a grey
    ; cue-banner label instead. Credentials/Session views show just the
    ; full-width note box; Game Info adds Class/Level/Money in front —
    ; see LayoutDynamicRows(). ---
    App.Gui.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
    App.Controls.NotesBox := App.Gui.Add("Edit", "xm y+8 w" innerW " h22", "")
    App.Controls.NotesBox.OnEvent("Change", OnNotesChanged)
    try DllCall("user32\SendMessageW", "ptr", App.Controls.NotesBox.Hwnd, "uint", 0x1501, "ptr", 1, "wstr", "Note — autosaves")
    App.Controls.ClassEdit := App.Gui.Add("Edit", "xm yp w100 h22 Hidden", "")
    App.Controls.LevelEdit := App.Gui.Add("Edit", "x+8 yp w60 h22 Hidden", "")
    App.Controls.MoneyEdit := App.Gui.Add("Edit", "x+8 yp w100 h22 Hidden", "")
    for pair in [["Class", App.Controls.ClassEdit], ["Level", App.Controls.LevelEdit], ["Money", App.Controls.MoneyEdit]] {
        ; EM_SETCUEBANNER: grey in-box label, no layout space needed.
        try DllCall("user32\SendMessageW", "ptr", pair[2].Hwnd, "uint", 0x1501, "ptr", 1, "wstr", pair[1])
        pair[2].OnEvent("Change", GameFieldChanged.Bind(pair[1]))
    }

    ; progress bar, then the STAT STRIP: the day's headline numbers in
    ; big color-coded segments (same language as the console header) —
    ; visible in every view, with the quiet selection/count info pushed
    ; to the dim right-hand label. These are the numbers the app exists
    ; to show; they must not whisper.
    App.Controls.Progress := App.Gui.Add("Progress",
        "xm y+10 w" innerW " h12 c" Colors.Accent, 0)
    App.Gui.SetFont("s11 Bold c" Colors.Success, Config.FontMain)
    App.Controls.StatDone := App.Gui.Add("Text", "xm y+6 w76 h24", "")
    App.Gui.SetFont("c" Colors.Warning)
    App.Controls.StatOnline := App.Gui.Add("Text", "x+4 yp w76 h24", "")
    App.Gui.SetFont("c" Colors.TextDim)
    App.Controls.StatToGo := App.Gui.Add("Text", "x+4 yp w90 h24", "")
    App.Gui.SetFont("c" Colors.Accent)
    App.Controls.StatMoney := App.Gui.Add("Text", "x+4 yp w130 h24", "")
    App.Gui.SetFont("s8 Norm Italic c" Colors.TextDim, Config.FontMain)
    App.Controls.CountLabel := App.Gui.Add("Text", "x+8 yp+8 w210 Right", "")

    App.Controls.Sep1 := App.Gui.Add("Text", "xm y+12 w" innerW " h2 0x10") ; etched divider

    ; --- daily-quota banner: doubles as the one-click trigger. Red +
    ; clickable when a quota is due today, green when done, quiet
    ; otherwise (see RefreshQuotaBanner). Full-width, registered in
    ; CaptureLayout so it moves with the zone on resize. ---
    App.Gui.SetFont("s9 Bold c" Colors.Text, Config.FontMain)
    App.Controls.QuotaBanner := App.Gui.Add("Text", "xm y+10 w" innerW " h24 +0x200 +Border", "")
    App.Controls.QuotaBanner.OnEvent("Click", QuotaBannerClick)
    App.Controls.QuotaBanner.TipText := "Daily activity quota — Sun 30 · Mon 10 · Tue 10. On a quota day this turns red; click it to queue that many random accounts and start Activity."

    ; --- zone 2: login flow. One uniform button row (primary action
    ; first), then the auto-next toggle + live client status on one line. ---
    App.Gui.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
    App.Controls.LoginBtn := App.Gui.Add("Button", "xm y+10 w126 h26", "🚀 Mass Login")
    App.Controls.LoginBtn.OnEvent("Click", OpenLoginConsole)
    App.Controls.PickBtn := App.Gui.Add("Button", "x+7 yp w78 h26", "⊕ Pick")
    App.Controls.PickBtn.OnEvent("Click", TogglePickMode)
    App.Controls.MacrosBtn := App.Gui.Add("Button", "x+7 yp w96 h26", "🎬 Macros")
    App.Controls.MacrosBtn.OnEvent("Click", OpenMacroManager)
    App.Controls.IdleBtn := App.Gui.Add("Button", "x+7 yp w80 h26", "🕒 Idle")
    App.Controls.IdleBtn.OnEvent("Click", OpenIdleActions)
    App.Controls.ForgetBtn := App.Gui.Add("Button", "x+7 yp w86 h26", "↺ Forget")
    App.Controls.ForgetBtn.OnEvent("Click", (*) => ForgetUsedWindows())
    App.Controls.AutoNextToggle := App.Gui.Add("Checkbox", "xm y+8 w230", "➡ Auto-next client after login (F5)")
    App.Controls.AutoNextToggle.Value := App.AutoNextClient ? 1 : 0
    App.Controls.AutoNextToggle.OnEvent("Click", ToggleAutoNextClient)
    App.Gui.SetFont("s8 Norm Italic c" Colors.TextDim, Config.FontMain)
    App.Controls.LinkStatus := App.Gui.Add("Text", "x+8 yp+2 w" (innerW - 238) " Right", "")

    App.Controls.Sep2 := App.Gui.Add("Text", "xm y+10 w" innerW " h2 0x10") ; etched divider

    ; --- zone 3: managing accounts — the gate sits beside what it gates ---
    App.Gui.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
    App.Controls.EditMode := App.Gui.Add("Checkbox", "xm y+10", "🔓 Edit Mode")
    App.Controls.EditMode.OnEvent("Click", (*) => ToggleEditMode())
    App.Controls.AddBtn := App.Gui.Add("Button", "x+12 yp-4 w110 h26", "➕ Add Account")
    App.Controls.AddBtn.OnEvent("Click", (*) => AddNewAccount())
    App.Controls.AddBtn.Enabled := false
    App.Controls.ReloadBtn := App.Gui.Add("Button", "x+8 yp w90 h26", "⟳ Reload")
    App.Controls.ReloadBtn.OnEvent("Click", (*) => ReloadFiles())

    ; --- zone 4: app preferences. Hotkey reference lives in the ❔
    ; label's hover tooltip, not on-screen (see RegisterTooltips). ---
    App.Gui.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
    App.Controls.ShowPw := App.Gui.Add("Checkbox", "xm y+12", "Show passwords")
    App.Controls.ShowPw.OnEvent("Click", (*) => ToggleShowPasswords())
    App.Controls.ThemeToggle := App.Gui.Add("Checkbox", "x+16 yp", "🌙 Dark Mode")
    App.Controls.ThemeToggle.OnEvent("Click", ToggleTheme)
    App.Controls.OnTopToggle := App.Gui.Add("Checkbox", "x+16 yp", "📌 Always on Top")
    App.Controls.OnTopToggle.Value := App.AlwaysOnTop ? 1 : 0
    App.Controls.OnTopToggle.OnEvent("Click", ToggleAlwaysOnTop)
    App.Controls.PrefsBtn := App.Gui.Add("Button", "x+16 yp-3 w32 h24", "⚙")
    App.Controls.PrefsBtn.OnEvent("Click", OpenPreferences)
    App.Gui.SetFont("s9 Norm Italic c" Colors.TextDim, Config.FontMain)
    App.Controls.HotkeysLabel := App.Gui.Add("Text", "x+12 yp+4", "❔ Hotkeys")
    App.Controls.HotkeysLabel.OnEvent("Click", OpenHotkeyReference) ; hover = tooltip, click = a window that stays
    App.Controls.VersionLabel := App.Gui.Add("Text", "x+12 yp", "v" Config.Version)

    App.Gui.OnEvent("Size", Gui_Size)
    App.Gui.OnEvent("Close", OnCloseRequest)

    CaptureLayout()
    RegisterTooltips()
}

; The X button: with minimize-to-tray on, closing hides to the tray
; (so 24/7 automation can't be killed by a stray click) — the tray's
; Exit is the real quit. Off → normal exit.
OnCloseRequest(*) {
    global App
    static told := false
    ; Under the test suite always exit (a hidden window would hang a
    ; headless run waiting for a close that never comes).
    if (IsSet(AQ_TEST_QUIET) && AQ_TEST_QUIET) {
        OnAppClose()
        return
    }
    if App.MinimizeToTray {
        try App.Gui.Hide()
        ToolTip()
        if !told {
            told := true
            try TrayTip("Account Queue", "Still running in the tray. Right-click its icon to exit.", 0x1)
        }
        return
    }
    OnAppClose()
}

OnAppClose(*) {
    FlushPendingNoteSave()
    SaveSessionTimes()
    SaveSettings()
    ExitApp()
}

; Measures the real position of every control below the ListView, once,
; right after the window is built. Gui_Size uses these as ground truth
; instead of guessed pixel budgets, so it can never drift out of sync
; with whatever controls actually exist.
CaptureLayout() {
    global App
    App.Controls.List.GetPos(, &ly, , &lh)
    App.Layout := { ListY: ly, ListH0: lh, Below: [] }

    ; NotesBox, Status and CountLabel are NOT registered full-width:
    ; their x/width are view- or anchor-dependent and handled by
    ; LayoutDynamicRows(), which Gui_Size calls after shifting.
    RecordBelowList(App.Controls.NotesBox, false)
    RecordBelowList(App.Controls.ClassEdit, false)
    RecordBelowList(App.Controls.LevelEdit, false)
    RecordBelowList(App.Controls.MoneyEdit, false)
    RecordBelowList(App.Controls.Progress, true)
    RecordBelowList(App.Controls.StatDone, false)
    RecordBelowList(App.Controls.StatOnline, false)
    RecordBelowList(App.Controls.StatToGo, false)
    RecordBelowList(App.Controls.StatMoney, false)
    RecordBelowList(App.Controls.CountLabel, false)
    RecordBelowList(App.Controls.Sep1, true)
    RecordBelowList(App.Controls.QuotaBanner, true)
    RecordBelowList(App.Controls.AutoNextToggle, false)
    RecordBelowList(App.Controls.LoginBtn, false)
    RecordBelowList(App.Controls.ForgetBtn, false)
    RecordBelowList(App.Controls.MacrosBtn, false)
    RecordBelowList(App.Controls.IdleBtn, false)
    RecordBelowList(App.Controls.PickBtn, false)
    RecordBelowList(App.Controls.LinkStatus, false) ; width handled by LayoutDynamicRows (shares its row with the auto-next toggle)
    RecordBelowList(App.Controls.Sep2, true)
    RecordBelowList(App.Controls.EditMode, false)
    RecordBelowList(App.Controls.AddBtn, false)
    RecordBelowList(App.Controls.ReloadBtn, false)
    RecordBelowList(App.Controls.ShowPw, false)
    RecordBelowList(App.Controls.ThemeToggle, false)
    RecordBelowList(App.Controls.OnTopToggle, false)
    RecordBelowList(App.Controls.PrefsBtn, false)
    RecordBelowList(App.Controls.HotkeysLabel, false)
    RecordBelowList(App.Controls.VersionLabel, false)
}

RecordBelowList(ctrl, fullWidth) {
    global App
    ctrl.GetPos(, &cy)
    App.Layout.Below.Push({ Ctrl: ctrl, Y0: cy, FullWidth: fullWidth })
}

; ============================================================
; HOVER TOOLTIPS
; ------------------------------------------------------------
; Shortcut hints live here instead of taking up window space. AHK has no
; native per-control tooltips, so this is the standard WM_MOUSEMOVE
; pattern: controls carry a TipText property; hovering one for ~400ms
; shows it. Uses ToolTip slot 2 so it can never fight with toasts
; (ShowToast uses the default slot 1).
; ============================================================

; The full hotkey/gesture reference — ONE source of truth for the ❔
; label's hover tooltip AND its click-to-open window. New hotkeys must
; be added here (and to README); there's no other on-screen legend.
HotkeyReferenceText() {
    return "
    (
F1   Paste email
F2   Paste password, then next account
F4   Full login: email → Tab → password → Enter, then next
F10  Pause / resume the paste keys (F1/F2/F4)
F5   Toggle auto-next client
F6   Cycle view: Credentials / Game Info / Session
F7   Start / stop macro recording
F8   Pick mode — click accounts to build a login queue
F9   Online accounts window (all files, live)
F3   Next file        Shift+F3   Previous file
↑ ↓  Move selection (app window focused)
Ctrl+F   Focus the search box
Esc or F7   Abort a running macro
In Search:  Enter jumps to the first match · Esc clears

Hover a row for its full card · hover a board cell up top for its state
Double-click row   Jump to its client · unlinked: launch + log it in
                   (during a run: queues it to start right after ·
                    Edit Mode on: opens the edit dialog instead)
Right-click row    Pick it · launch / jump / close · link a window ·
                   run or queue a macro/routine on its client

Minimize → tray (keeps running 24/7). Right-click the tray icon to
show, run today's quota, pause paste keys, or exit.
    )"
}

; Click ❔ Hotkeys → the same reference in a window that stays open and
; can be copied from. A 30-line list in a tooltip that hides itself
; after 6 seconds was technically documentation.
OpenHotkeyReference(*) {
    global App
    if IsObject(App.HotkeysDlg) {
        try App.HotkeysDlg.Show()
        return
    }
    dlg := Gui("+Owner" App.Gui.Hwnd " +Resize", "Hotkeys — Account Queue")
    dlg.BackColor := Colors.Bg
    dlg.MarginX := 12
    dlg.MarginY := 10
    dlg.SetFont("s9 Norm c" Colors.Text, "Consolas")
    ed := dlg.Add("Edit", "xm w540 h400 ReadOnly -Wrap", HotkeyReferenceText())
    dlg.SetFont("s9 Norm c" Colors.Text, Config.FontMain)
    bClose := dlg.Add("Button", "xm y+8 w90 h26 Default", "Close")
    bClose.OnEvent("Click", (*) => CloseHotkeyReference(dlg))
    ApplyDialogDarkMode(dlg, [ed])
    dlg.OnEvent("Close", (*) => CloseHotkeyReference(dlg))
    dlg.OnEvent("Escape", (*) => CloseHotkeyReference(dlg))
    App.HotkeysDlg := dlg
    dlg.Show("AutoSize")
}

CloseHotkeyReference(dlg) {
    global App
    App.HotkeysDlg := ""
    try dlg.Destroy()
}

RegisterTooltips() {
    global App
    c := App.Controls
    c.PrevBtn.TipText := "Previous login file  (Shift+F3)"
    c.NextBtn.TipText := "Next login file  (F3)"
    c.Search.TipText := "Filter by name, email, note, class, level, money — or by money value: >6.6m, <500k, >=1m. Enter jumps to the first match, Esc clears."
    c.OnlineBtn.TipText := "All online accounts across every file, live  (F9). Double-click a row there to jump to its client."
    c.ViewBtnCred.TipText := "Credentials view — email / password / client  (F6 cycles views)"
    c.ViewBtnGame.TipText := "Game Info view — class / level / money"
    c.ViewBtnSess.TipText := "Session view — online minutes per account. Amber = counting, green = " Config.SessionGoalMinutes " min reached, red = lost its client early"
    c.Progress.TipText := "Today's progress: accounts at the goal / total — same metric as the board and the taskbar bar"
    c.StatDone.TipText := "Accounts that reached today's goal — all files, duplicates count once"
    c.StatOnline.TipText := "Accounts online right now (linked to a client)"
    c.StatToGo.TipText := "Accounts still under today's goal"
    c.StatMoney.TipText := "Σ money across every file (duplicates count once) — the Money column and searches like >6.6m use the same parsing"
    c.NotesBox.TipText := "Saves automatically a moment after you stop typing"
    c.ClassEdit.TipText := "Saves automatically"
    c.LevelEdit.TipText := "Saves automatically"
    c.MoneyEdit.TipText := "Saves automatically. Accepts 123k / 3.3m / 1.2b / 6,000,000 — the column shows it standardized; anything else stays as text, greyed"
    c.AutoNextToggle.TipText := "After each F2/F4 login, jump to an open client that hasn't been used yet  (F5)"
    c.ForgetBtn.TipText := "Clear used-client tracking, so already-used clients can be auto-picked again"
    c.MacrosBtn.TipText := "Record and manage click macros  (F7 starts/stops recording; right-click a linked row to run one)"
    c.IdleBtn.TipText := "Idle Actions — jobs (accounts + a macro) the app runs by priority when the PC is idle. The Activity daily quota is built in. Runs 24/7 from the tray."
    c.PickBtn.TipText := "Pick mode (F8): click accounts in any files, in login order — F1/F2/F4 then work through them head-first. Re-entering pick mode clears the old queue."
    c.LoginBtn.TipText := "Open the Mass Login console — add accounts, assign post-login macros, choose Play/Activity, and watch what's online / running / next. Set it up first via ⚙ → Login Setup."
    c.LinkStatus.TipText := "Fresh = clients nothing has been logged into yet. F2/F4 links the client it pastes into"
        . (" — with Auto-next on, focus then jumps to a fresh one. While a macro queue runs, this line shows its progress.")
    c.EditMode.TipText := "Unlock adding, editing and deleting accounts — double-click a row to edit it while this is on"
    c.AddBtn.TipText := "Add a new account to this file  (needs Edit Mode)"
    c.ReloadBtn.TipText := "Re-read all .txt files from disk without losing your place"
    c.ShowPw.TipText := "Show passwords as plain text in the list"
    c.ThemeToggle.TipText := "Switch between light and dark theme"
    c.OnTopToggle.TipText := "Keep this window above all other windows"
    c.PrefsBtn.TipText := "Preferences — tune the session goal, day-reset hour, delays, game process, backups"
    c.HotkeysLabel.TipText := "Click to keep this list open in its own window.`n`n" HotkeyReferenceText()
    OnMessage(0x0200, TrackTips) ; WM_MOUSEMOVE
}

TrackTips(wParam, lParam, msg, hwnd) {
    global App
    static prevHwnd := 0, prevRow := 0
    ; The account list gets per-ROW hover cards (full account details,
    ; no view switching) instead of one static tip for the whole control.
    if (IsObject(App.Gui) && hwnd = App.Controls.List.Hwnd) {
        row := ListRowFromPoint()
        if (hwnd = prevHwnd && row = prevRow)
            return
        prevHwnd := hwnd
        prevRow := row
        App.PendingTipText := ""
        HideHoverTip()
        acc := RowAccount(row)
        if IsObject(acc) { ; separator rows carry no card
            App.PendingTipText := AccountCardText(acc)
            SetTimer(ShowPendingTip, -400)
        }
        return
    }
    prevRow := 0
    if (hwnd = prevHwnd)
        return
    prevHwnd := hwnd
    App.PendingTipText := ""
    HideHoverTip()
    ctrl := GuiCtrlFromHwnd(hwnd)
    if (IsObject(ctrl) && ctrl.HasOwnProp("TipText")) {
        App.PendingTipText := ctrl.TipText
        SetTimer(ShowPendingTip, -400)
    }
}

; Which list row is under the mouse right now (0 = none). LVM_HITTEST
; with client coords — used only for hover cards, never for selection.
ListRowFromPoint() {
    global App
    pt := Buffer(8)
    DllCall("user32\GetCursorPos", "ptr", pt)
    DllCall("user32\ScreenToClient", "ptr", App.Controls.List.Hwnd, "ptr", pt)
    hti := Buffer(24, 0)
    NumPut("Int", NumGet(pt, 0, "Int"), hti, 0)
    NumPut("Int", NumGet(pt, 4, "Int"), hti, 4)
    DllCall("user32\SendMessageW", "ptr", App.Controls.List.Hwnd, "uint", 0x1012, "ptr", 0, "ptr", hti) ; LVM_HITTEST
    return NumGet(hti, 12, "Int") + 1
}

; The hover card: everything about one account, whatever view is
; active. Pure text builder — unit-tested. Passwords never appear here.
AccountCardText(acc) {
    txt := acc.Name "`n" acc.Email
    info := ""
    if (acc.Class != "" || acc.Level != "")
        info := Trim(acc.Class (acc.Level != "" ? "  Lv " acc.Level : ""))
    if (acc.Money != "") {
        mv := ParseMoney(acc.Money)
        info .= (info != "" ? "  ·  " : "") (mv != "" ? FormatMoney(mv) : acc.Money)
    }
    if (info != "")
        txt .= "`n" info
    if (acc.Note != "")
        txt .= "`n📝 " acc.Note
    mins := Round(AccountOnlineMs(acc) / 60000)
    if IsAccountDone(acc)
        txt .= "`n✔ done — " mins " min today"
    else if acc.HasOwnProp("ClientHwnd")
        txt .= "`n● client #" acc.ClientSession " — " mins " of " Config.SessionGoalMinutes " min"
    else if (mins > 0)
        txt .= "`n⚠ " mins " of " Config.SessionGoalMinutes " min — client lost"
    if (acc.LastLogin != "")
        txt .= "`nLast login  " acc.LastLogin
    return txt
}

ShowPendingTip() {
    global App
    if (App.PendingTipText = "")
        return ; mouse already moved off before the delay elapsed
    ToolTip(App.PendingTipText, , , 2)
    SetTimer(HideHoverTip, -6000)
}

HideHoverTip() {
    ToolTip(, , , 2)
}

Gui_Size(guiObj, MinMax, Width, Height) {
    global App
    if (MinMax = -1) ; minimized
        return
    if !IsObject(App.Layout) ; Size can theoretically fire before layout is captured
        return

    margin := 16
    innerW := Width - margin * 2
    if (innerW < 200)
        innerW := 200

    ; Suspend painting (WM_SETREDRAW off) while the whole batch of controls
    ; gets moved, then re-enable and repaint ONCE at the end. Moving
    ; controls one by one doesn't reliably erase their old spots on the
    ; parent window, so rapid/mixed-direction resizes left stale "ghost"
    ; copies of the bottom checkboxes/buttons and smeared label text
    ; behind. The finally guarantees painting is turned back on even if a
    ; Move throws — a window stuck with redraw off looks frozen.
    ;
    ; Raw DllCalls by hwnd, NOT SendMessage(.., "ahk_id " ..)/WinRedraw():
    ; those do a window *search*, and the Size event fires during Show()
    ; while the window isn't visible yet — the search throws "Target
    ; window not found" (see gotcha #15 in CLAUDE.md).
    try DllCall("user32\SendMessageW", "ptr", guiObj.Hwnd, "uint", 0x000B, "ptr", 0, "ptr", 0)
    try {
        App.Controls.FileLabel.Move(, , innerW - 88)          ; same formula as BuildGUI: innerW - 34 - 34 - 20
        App.Controls.NextBtn.Move(margin + innerW - 34)
        App.Controls.Search.Move(, , innerW - 164)
        App.Controls.OnlineBtn.Move(margin + innerW - 156)
        App.Controls.ViewBtnCred.Move(margin + innerW - 110)
        App.Controls.ViewBtnGame.Move(margin + innerW - 72)
        App.Controls.ViewBtnSess.Move(margin + innerW - 34)

        ; Grow/shrink the list by exactly the same amount the window did...
        listH := App.Layout.ListH0 + (Height - Config.WindowHeight)
        if (listH < 120)
            listH := 120
        App.Controls.List.Move(, , innerW, listH)

        ; ...then shift every control below it by that same delta, so nothing
        ; the list grew into gets covered, and nothing floats away from it
        ; if the list shrinks. Full-width controls also get resized.
        deltaY := listH - App.Layout.ListH0
        for item in App.Layout.Below {
            if item.FullWidth
                item.Ctrl.Move(, item.Y0 + deltaY, innerW)
            else
                item.Ctrl.Move(, item.Y0 + deltaY)
        }

        ; Rows whose x/width aren't a simple full-width rule (quick-edit
        ; boxes, status/count line) — handled by a dedicated helper.
        LayoutDynamicRows(innerW)
        PositionBoard(innerW)
    } finally {
        try DllCall("user32\SendMessageW", "ptr", guiObj.Hwnd, "uint", 0x000B, "ptr", 1, "ptr", 0)
        ; RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW
        try DllCall("user32\RedrawWindow", "ptr", guiObj.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x185)
    }
}

; ============================================================
; VIEW MODES (Credentials vs Game Info — same accounts, same order,
; different columns; switch via the dropdown next to Search or F6)
; ============================================================

; Positions the rows whose x/width can't come from the generic full-width
; rule: the quick-edit row (credentials view gives the note box the full
; width; game view fits Class/Level/Money in front and the note box takes
; the remainder) and the status/count line (status left, count anchored
; right).
LayoutDynamicRows(innerW) {
    global App
    margin := 16
    if (App.ViewMode = "game")
        App.Controls.NotesBox.Move(margin + 284, , innerW - 284)
    else
        App.Controls.NotesBox.Move(margin, , innerW)
    ; Stat-strip segments sit at fixed x; the count label takes the rest,
    ; right-anchored (strip = 384px + 8px gap).
    App.Controls.CountLabel.Move(margin + 392, , Max(60, innerW - 392))
    ; link status shares its row with the fixed-width auto-next toggle
    App.Controls.LinkStatus.Move(margin + 238, , innerW - 238)
}

; Rebuilds the ListView's columns in place (ModifyCol can retitle col 1;
; InsertCol/DeleteCol handle the rest). Rows are cleared first — the
; caller is expected to RefreshList() afterwards.
SetListColumns(cols) {
    global App
    lv := App.Controls.List
    lv.Delete()
    while (App.ListColCount > 1) {
        lv.DeleteCol(2)
        App.ListColCount -= 1
    }
    lv.ModifyCol(1, cols[1][2], cols[1][1])
    for i, c in cols {
        if (i = 1)
            continue
        lv.InsertCol(i, c[2], c[1])
        App.ListColCount += 1
    }
}

SetViewMode(mode, persist := true) {
    global App
    App.ViewMode := (mode = "game") ? "game" : (mode = "session") ? "session" : "credentials"
    isGame := App.ViewMode = "game"

    if isGame
        SetListColumns([["#", 38], ["Name", 105], ["Class", 90], ["Level", 55],
            ["Money", 90], ["Note", 178]])
    else if (App.ViewMode = "session")
        SetListColumns([["#", 38], ["Name", 105], ["Client", 48], ["Online", 68],
            ["Left", 84], ["Last login", 108], ["Note", 108]])
    else
        SetListColumns([["#", 38], ["Name", 105], ["Email", 175], ["Password", 105],
            ["Client", 52], ["Note", 98]])

    App.Controls.ClassEdit.Visible := isGame
    App.Controls.LevelEdit.Visible := isGame
    App.Controls.MoneyEdit.Visible := isGame
    ; The active view's button is disabled — doubles as the indicator.
    App.Controls.ViewBtnCred.Enabled := App.ViewMode != "credentials"
    App.Controls.ViewBtnGame.Enabled := App.ViewMode != "game"
    App.Controls.ViewBtnSess.Enabled := App.ViewMode != "session"

    App.Gui.GetClientPos(, , &cw)
    LayoutDynamicRows(Max(200, cw - 32))

    RefreshList()
    RefreshDetails()
    if persist
        SaveSettings()
}

; Cycles credentials → game → session → credentials (F6 / view button).
ToggleViewMode(*) {
    global App
    if App.EditDialogOpen
        return
    next := (App.ViewMode = "credentials") ? "game"
        : (App.ViewMode = "game") ? "session" : "credentials"
    SetViewMode(next)
}

; One row's cell values for the current view. Every account object is
; guaranteed to carry all fields (see the loader invariant), so these are
; direct property reads.
BuildRowCells(pos, acc) {
    global App
    ; Pick-queue members show their queue order in the # column ("»2").
    qi := App.LoginQueue.Length ? LoginQueueIndex(acc) : 0
    if qi
        pos := "»" qi
    ; Online accounts carry a dot in the # cell — drawn green by the
    ; custom draw (subitem 0). Link presence IS the online signal here
    ; (same as the session amber); housekeeping prunes dead links.
    if acc.HasOwnProp("ClientHwnd")
        pos := "● " pos
    if (App.ViewMode = "game") {
        ; Parseable money shows standardized-compact; anything else
        ; (including empty) shows exactly as typed.
        mv := ParseMoney(acc.Money)
        moneyDisplay := (mv != "") ? FormatMoney(mv) : acc.Money
        return [pos, acc.Name, acc.Class, acc.Level, moneyDisplay, acc.Note]
    }
    if (App.ViewMode = "session") {
        goalMs := Config.SessionGoalMinutes * 60000
        online := AccountOnlineMs(acc)
        linkedNow := acc.HasOwnProp("ClientHwnd")
        onlineTxt := (online > 0 || linkedNow) ? Floor(online / 60000) " min" : ""
        if (online >= goalMs)
            leftTxt := "✔ done"
        else if linkedNow
            leftTxt := Ceil((goalMs - online) / 60000) " min left"
        else if (online > 0) ; had a client, lost it before the goal
            leftTxt := "⚠ " Ceil((goalMs - online) / 60000) " min left"
        else
            leftTxt := ""
        clientDisplay := acc.HasOwnProp("ClientSession") ? ("#" acc.ClientSession) : ""
        return [pos, acc.Name, clientDisplay, onlineTxt, leftTxt, acc.LastLogin, acc.Note]
    }
    pwDisplay := App.ShowPasswords ? acc.Password : MaskString(StrLen(acc.Password))
    clientDisplay := acc.HasOwnProp("ClientSession") ? ("#" acc.ClientSession) : ""
    return [pos, acc.Name, acc.Email, pwDisplay, clientDisplay, acc.Note]
}

; NM_CUSTOMDRAW: in Session view, accounts that reached the goal get
; green row text. Struct offsets are x64 NMLVCUSTOMDRAW: dwDrawStage@24,
; dwItemSpec@56, clrText@80 (COLORREF, BGR order).
OnListCustomDraw(lv, lParam) {
    global App
    stage := NumGet(lParam, 24, "UInt")
    if (stage = 0x1) ; CDDS_PREPAINT
        return 0x20 ; CDRF_NOTIFYITEMDRAW
    if (stage = 0x10001) { ; CDDS_ITEMPREPAINT
        pos := NumGet(lParam, 56, "UPtr") + 1
        if (pos >= 1 && pos <= App.Displayed.Length) {
            acc := RowAccount(pos)
            if !IsObject(acc) { ; file separator row — accent, no zebra
                NumPut("UInt", HexToBGR(Colors.Accent), lParam, 80)
                return 0x2
            }
            ; EVERY view draws per-subitem since 0.31.0 — the online
            ; dot needs cell 0 green independent of the row color.
            return 0x20 ; CDRF_NOTIFYSUBITEMDRAW
        }
    }
    if (stage = 0x30001) { ; CDDS_ITEMPREPAINT|CDDS_SUBITEM — every cell
        pos := NumGet(lParam, 56, "UPtr") + 1
        if (pos >= 1 && pos <= App.Displayed.Length) {
            acc := RowAccount(pos)
            if !IsObject(acc)
                return 0
            clr := HexToBGR(Colors.Text)
            if (App.ViewMode = "session") {
                ; Green: goal reached. Amber: online and counting. Red:
                ; lost its client before the goal. Default: not started.
                if IsAccountDone(acc)
                    clr := Colors.DoneRowBGR
                else if acc.HasOwnProp("ClientHwnd")
                    clr := Colors.OnlineRowBGR
                else if (AccountOnlineMs(acc) > 0)
                    clr := Colors.WarnRowBGR
            } else if (App.LoginQueue.Length && LoginQueueIndex(acc)) {
                clr := Colors.QueuedRowBGR ; pick-queue member
            }
            sub := NumGet(lParam, 88, "Int")
            ; Money column (game view, 0-based subitem 4): unparseable
            ; non-empty text greys out.
            if (App.ViewMode = "game" && sub = 4) {
                raw := Trim(acc.Money)
                if (raw != "" && ParseMoney(raw) = "")
                    clr := HexToBGR(Colors.TextDim)
            }
            ; The # cell's ● dot: green for any linked account, in any
            ; view — the one glance-signal that survives view switching.
            if (sub = 0 && acc.HasOwnProp("ClientHwnd"))
                clr := HexToBGR(Colors.Success)
            NumPut("UInt", clr, lParam, 80)
            ; Zebra: even rows get a faint background lift per cell —
            ; selection highlight still wins natively.
            if (Mod(pos, 2) = 0)
                NumPut("UInt", Colors.ZebraBGR, lParam, 84)
            return 0x2
        }
    }
    return 0
}

OnListItemSelect(ctrl, item, selected) {
    global App
    ; Deselect notifications and rows we're already on are ignored — the
    ; latter also keeps programmatic Modify(.., "Select") calls from
    ; triggering a redundant refresh loop.
    if (!selected || item < 1 || item = App.CurrentDisplayPos)
        return
    App.CurrentDisplayPos := item
    RefreshDetails()
}

ToggleShowPasswords() {
    global App
    App.ShowPasswords := App.Controls.ShowPw.Value = 1
    RefreshList()
    SaveSettings()
}

ToggleEditMode() {
    global App
    App.EditModeOn := App.Controls.EditMode.Value = 1
    App.Controls.AddBtn.Enabled := App.EditModeOn
}

OnListDoubleClick(ctrl, row) {
    global App
    if (row < 1 || !IsObject(RowAccount(row))) ; separators are inert
        return
    App.CurrentDisplayPos := row
    RefreshDetails()

    if App.EditModeOn {
        EditCurrentAccount()
        return
    }

    ; Linked → jump to its client. Unlinked → launch a client and log
    ; this one account in ("just get this one online" gesture). A link
    ; whose window is flickering/hidden still counts as linked — only
    ; housekeeping's two-strike debounce may clear it (see gotcha #15);
    ; launching a duplicate client for a briefly-hidden one would be
    ; the old mass-detach bug wearing a new hat.
    acc := GetCurrentAccount()
    if !IsObject(acc)
        return
    if acc.HasOwnProp("ClientHwnd")
        JumpToAccountWindow()
    else
        LaunchLoginSingle(acc)
}

; Single-account Launch + Login (Play mode), from a double-click.
; Same guards as the console's Start, minus the pick-queue plumbing —
; and deliberately NO dialogs on failure besides toasts: a double-click
; can be accidental, so it must never pop a setup window uninvited.
LaunchLoginSingle(acc) {
    global App
    if (App.MacroPlaying || App.IsRecording || App.QueueRunning) {
        ShowToast("Finish the current automation first")
        return
    }
    if !LoginProfileReady() {
        ShowToast("Set up Launch + Login first (⚙ → Login Setup)")
        return
    }
    if !FileExist(Config.LauncherPath) {
        ShowToast("Launcher not found — set the path in ⚙ Preferences")
        return
    }
    ; A run is already going → this one waits its turn in a mini queue
    ; that auto-starts when the current run finishes (0.29.0).
    if App.LoginRunning {
        if (LoginQueueIndex2(App.PendingSingles, acc)
            || LoginQueueIndex(acc) || LoginQueueIndex2(App.LoginBatch, acc)) {
            ShowToast(acc.Name " is already queued or in the current run")
            return
        }
        App.PendingSingles.Push(acc)
        ShowToast("⌛ " acc.Name " queued — starts after the current run ("
            . App.PendingSingles.Length " waiting)")
        RefreshLinkStatus()
        return
    }
    ShowToast("🚀 Launching + logging in " acc.Name "  (Esc/F7 aborts)")
    LaunchWithMode("play", [acc])
}

; Chains the next waiting double-click login, skipping any that came
; online in the meantime (e.g. the finished run logged it in, or the
; user did it manually).
StartNextPendingSingle() {
    global App
    while App.PendingSingles.Length {
        acc := App.PendingSingles.RemoveAt(1)
        if AccountIsOnline(acc)
            continue
        LaunchLoginSingle(acc)
        return
    }
}

; ============================================================
; REFRESH
; ============================================================
RefreshUI() {
    global App
    App.Displayed := []
    App.CurrentDisplayPos := 1
    App.FilterText := ""
    RefreshTitle()
    ApplyFilter("")
    RestorePendingAccountPosition()
}

RefreshTitle() {
    global App
    currentFile := App.Files[App.CurrentFile]
    App.Controls.FileLabel.Value := currentFile.Name ".txt   ·   " App.CurrentFile " / " App.Files.Length
    App.Gui.Title := (App.PastePaused ? "⏸ paused — " : "")
        . "Account Queue v" Config.Version " — " currentFile.Name
}

ApplyFilter(text := "") {
    global App
    App.FilterText := text
    App.Displayed := []
    needle := StrLower(Trim(text))

    ; Money operator search: ">6.6m", "<500k", ">=1m", "=123k" filters by
    ; parsed money value; accounts with empty/unparseable money never
    ; match an operator query.
    moneyOp := ""
    moneyVal := ""
    if RegExMatch(needle, "^(>=|<=|>|<|=)\s*(.+)$", &m) {
        v := ParseMoney(m[2])
        if (v != "") {
            moneyOp := m[1]
            moneyVal := v
        }
    }

    if (needle = "") {
        ; Normal mode: the current file, 1:1 (integer indices).
        for idx, acc in App.Files[App.CurrentFile].Accounts
            App.Displayed.Push(idx)
    } else {
        ; Search mode (0.29.0): matches from EVERY file, grouped under a
        ; separator row naming the file — a note you remember writing
        ; shouldn't hide because you're looking at the wrong file.
        for f in App.Files {
            firstOfFile := true
            for idx, acc in f.Accounts {
                if !AccountMatchesFilter(acc, needle, moneyOp, moneyVal)
                    continue
                if firstOfFile {
                    firstOfFile := false
                    App.Displayed.Push({ Sep: f.Name })
                }
                App.Displayed.Push({ Acc: acc, File: f, Num: idx })
            }
        }
    }

    if (App.Displayed.Length = 0)
        App.CurrentDisplayPos := 0
    else if (App.CurrentDisplayPos < 1 || App.CurrentDisplayPos > App.Displayed.Length
        || !IsObject(RowAccount(App.CurrentDisplayPos)))
        App.CurrentDisplayPos := FirstAccountRow(1) ; never a separator

    RefreshList()
    RefreshDetails()
}

AccountMatchesFilter(acc, needle, moneyOp, moneyVal) {
    if (moneyOp != "") {
        av := ParseMoney(acc.Money)
        return av != "" && MoneyCompare(av, moneyOp, moneyVal)
    }
    return InStr(StrLower(acc.Name), needle) || InStr(StrLower(acc.Email), needle)
        || InStr(StrLower(acc.Class), needle) || InStr(StrLower(acc.Note), needle)
        || InStr(StrLower(acc.Level), needle) || InStr(StrLower(acc.Money), needle)
}

MoneyCompare(a, op, b) {
    switch op {
        case ">": return a > b
        case "<": return a < b
        case ">=": return a >= b
        case "<=": return a <= b
        default: return a = b
    }
}

RefreshList() {
    global App
    lv := App.Controls.List
    lv.Delete()

    for pos, e in App.Displayed {
        acc := RowAccount(pos)
        if IsObject(acc)
            lv.Add("", BuildRowCells(RowNum(pos), acc)*)
        else ; file separator (search mode) — name in the Name column
            lv.Add("", "", "📁 " e.Sep ".txt")
    }

    if (App.Displayed.Length > 0 && App.CurrentDisplayPos >= 1)
        lv.Modify(App.CurrentDisplayPos, "Select Focus Vis")
}

RefreshDetails() {
    global App
    RefreshSummary()
    if (App.Displayed.Length = 0) {
        SetAccountEditBoxes("")
        SetAccountEditBoxesEnabled(false)
        return
    }
    SetAccountEditBoxesEnabled(true)
    SetAccountEditBoxes(GetCurrentAccount())
}

; Progress bar, status line and count label — everything in the details
; area EXCEPT the edit boxes, so the housekeeping tick can call this
; without stealing the caret from someone typing a note.
RefreshSummary() {
    global App
    currentFile := App.Files[App.CurrentFile]
    ; Rows may include search separators — count/position accounts only.
    total := 0
    curOrd := 0
    loop App.Displayed.Length {
        if IsObject(RowAccount(A_Index)) {
            total += 1
            if (A_Index = App.CurrentDisplayPos)
                curOrd := total
        }
    }

    if (total = 0) {
        selText := (App.FilterText != "") ? "no matches" : "no accounts"
    } else {
        acc := GetCurrentAccount()
        selText := curOrd " / " total "  ·  " (IsObject(acc) ? acc.Name : "—")
    }
    if App.LoginQueue.Length
        selText := "⊕ " App.LoginQueue.Length " queued  ·  " selText

    ; One aggregation feeds everything: stat strip, progress bar, board,
    ; taskbar (BoardBuild — email-deduped across all files).
    b := BoardBuild()

    ; Global money Σ (email-deduped) — a permanent stat-strip segment
    ; in EVERY view; money is one of the headline numbers.
    seenM := Map()
    for f2 in App.Files {
        for a2 in f2.Accounts {
            if !seenM.Has(a2.Email)
                seenM[a2.Email] := ParseMoney(a2.Money)
        }
    }
    totalAll := 0
    for , v in seenM {
        if (v != "")
            totalAll += v
    }

    SetStatText(App.Controls.StatDone, "✔ " b.Done)
    SetStatText(App.Controls.StatOnline, "▶ " b.Online)
    SetStatText(App.Controls.StatToGo, (b.Total - b.Done) " to go")
    SetStatText(App.Controls.StatMoney, totalAll > 0 ? "Σ " FormatMoney(totalAll) : "")

    ; The dim right-hand label: selection info + view-specific extras.
    countText := selText
    if (App.ViewMode = "game" && App.FilterText != "") {
        shownTotal := 0
        loop App.Displayed.Length {
            acc2 := RowAccount(A_Index)
            mv2 := IsObject(acc2) ? ParseMoney(acc2.Money) : ""
            if (mv2 != "")
                shownTotal += mv2
        }
        countText .= "  ·  shown Σ " FormatMoney(shownTotal)
    }
    if (App.ViewMode = "session")
        countText .= "  ·  Σ " FormatHours(b.TotalMs)
    if (currentFile.UnparsedCount > 0)
        countText .= "  ·  " currentFile.UnparsedCount " unreadable"

    ; The bar means THE DAY in every view (same metric as the board and
    ; the taskbar).
    App.Controls.Progress.Value := b.Total > 0 ? Round(b.Done / b.Total * 100) : 0
    if (App.Controls.CountLabel.Value != countText)
        App.Controls.CountLabel.Value := countText
    RefreshBoard(false, b) ; keep the day board in lockstep (state-diffed, cheap)
}

SetStatText(ctrl, txt) {
    if (ctrl.Value != txt)
        ctrl.Value := txt
}

; Updates the quick-edit boxes (Note + Class/Level/Money) without
; triggering their Change handlers, since those are reserved for genuine
; user typing (which is what schedules an autosave) rather than the boxes
; just following the current selection.
SetAccountEditBoxes(acc) {
    global App
    App.SuppressNotesChangeEvent := true
    App.Controls.NotesBox.Text := IsObject(acc) ? acc.Note : ""
    App.Controls.ClassEdit.Text := IsObject(acc) ? acc.Class : ""
    App.Controls.LevelEdit.Text := IsObject(acc) ? acc.Level : ""
    App.Controls.MoneyEdit.Text := IsObject(acc) ? acc.Money : ""
    App.SuppressNotesChangeEvent := false
}

SetAccountEditBoxesEnabled(on) {
    global App
    App.Controls.NotesBox.Enabled := on
    App.Controls.ClassEdit.Enabled := on
    App.Controls.LevelEdit.Enabled := on
    App.Controls.MoneyEdit.Enabled := on
}

; ============================================================
; NOTES (low-friction, no dialog, autosaves — unlike credential edits)
; ============================================================
OnNotesChanged(ctrl, *) {
    global App
    if App.SuppressNotesChangeEvent
        return
    acc := GetCurrentAccount()
    if !IsObject(acc)
        return
    acc.Note := ctrl.Text
    UpdateCurrentRowCells()
    ; FindFileOfAccount, NOT the current file: with cross-file search
    ; results the selected row can belong to another file — saving the
    ; current file would leave the edit in memory only.
    ScheduleNoteAutosave(FindFileOfAccount(acc))
}

; Same low-friction pipeline as notes, for the Game Info view's fields.
; Bound per-control with the property name ("Class"/"Level"/"Money").
GameFieldChanged(propName, ctrl, *) {
    global App
    if App.SuppressNotesChangeEvent
        return
    acc := GetCurrentAccount()
    if !IsObject(acc)
        return
    acc.%propName% := ctrl.Text
    UpdateCurrentRowCells()
    ScheduleNoteAutosave(FindFileOfAccount(acc)) ; row may be from another file (search)
}

; Rewrites just the currently-selected row's cells in place — used by the
; notes box and by window tagging, where a full RefreshList rebuild would
; cause visible flicker on every keystroke / every F2 press.
UpdateCurrentRowCells() {
    global App
    if (App.Displayed.Length = 0)
        return
    acc := GetCurrentAccount()
    if !IsObject(acc)
        return
    pos := App.CurrentDisplayPos
    App.Controls.List.Modify(pos, "", BuildRowCells(RowNum(pos), acc)*)
}

; Refreshes one specific account's row, if it's visible in the current
; file/filter — no-op otherwise (e.g. the pick queue just logged in an
; account from another file).
UpdateRowForAccount(acc) {
    global App
    loop App.Displayed.Length {
        if (RowAccount(A_Index) = acc) {
            App.Controls.List.Modify(A_Index, "", BuildRowCells(RowNum(A_Index), acc)*)
            return
        }
    }
}

; Debounced save: restarting the same timer reference on every keystroke
; means it only actually fires once typing pauses, so a whole sentence
; doesn't trigger a disk write per character.
ScheduleNoteAutosave(fileObj) {
    global App
    ; If a save is still pending for a DIFFERENT file (typed a note, hit
    ; F3, typed another note inside the debounce window), commit it now —
    ; otherwise re-pointing PendingNoteSaveFile below would silently drop
    ; the first file's unsaved note.
    if (IsObject(App.PendingNoteSaveFile) && App.PendingNoteSaveFile != fileObj)
        FlushPendingNoteSave()
    App.PendingNoteSaveFile := fileObj
    SetTimer(CommitNoteAutosave, -Config.NoteAutosaveDelayMs)
}

CommitNoteAutosave() {
    global App
    fileObj := App.PendingNoteSaveFile
    if !IsObject(fileObj)
        return
    App.PendingNoteSaveFile := ""

    newAccounts := []
    for a in fileObj.Accounts
        newAccounts.Push(CloneAccount(a))

    try {
        WriteAccountsFile(fileObj.Path, newAccounts, false, fileObj.TrailingRaw) ; no backup — see header note
    } catch as err {
        ShowToast("Note not saved: " err.Message)
    }
}

; Forces any pending debounced note-save to commit immediately, so a
; note typed just before closing the app or reloading files isn't lost.
FlushPendingNoteSave() {
    global App
    if IsObject(App.PendingNoteSaveFile) {
        SetTimer(CommitNoteAutosave, 0)
        CommitNoteAutosave()
    }
}

; ============================================================
; DATA
; ============================================================
; App-owned .txt files in the Logins root that must never be parsed as
; account files. (Macros/routines live in subfolders and aren't scanned.)
IsReservedLoginsFile(name) {
    for reserved in ["IdleJobs.txt", "quota-log.txt", "routine-log.txt", "idle-history.txt"]
        if (name = reserved)
            return true
    return false
}

; Makes Logins/ exist, with one starter account file in it if the folder is
; brand new. The sample is deliberately obvious fake data in the documented
; format, so a first-time user sees a working list and can edit it in place
; instead of staring at an empty window wondering what the file format is.
; Never touches an existing folder or overwrites an existing file.
EnsureLoginsFolder() {
    if DirExist(Config.LoginsFolder)
        return
    try DirCreate(Config.LoginsFolder)
    if !DirExist(Config.LoginsFolder)
        return
    starter := Config.LoginsFolder "\Accounts.txt"
    if FileExist(starter)
        return
    try AtomicWriteText(starter
        , "; Your accounts live here, one per line.`n"
        . "; Format:  Name|Email|Password            (Note is an optional 4th field)`n"
        . "; Lines starting with a semicolon are comments and are ignored.`n"
        . "; Anything unparseable is PRESERVED when the app saves, so notes are safe.`n"
        . ";`n"
        . "; Replace the examples below with your own, or delete them and add`n"
        . "; accounts from the app with Edit Mode + Add.`n"
        . ";`n"
        . "; NOTE: these are PLAIN TEXT files on your own disk. Anyone with access`n"
        . "; to this folder can read them. See the README before putting real`n"
        . "; passwords in.`n`n"
        . "Main|demo.main@example.com|replace-me`n"
        . "Alt1|demo.alt1@example.com|replace-me|Example note`n")
}

LoadLoginFiles() {
    global App

    ; First run on a fresh copy (the Logins folder is gitignored, so anyone
    ; cloning this gets none): create it and drop in a starter file rather
    ; than refusing to start. Throwing here meant a new user's very first
    ; launch died with "Logins folder not found" and no way forward.
    if !DirExist(Config.LoginsFolder)
        EnsureLoginsFolder()
    if !DirExist(Config.LoginsFolder)
        throw Error("Could not create the Logins folder: " Config.LoginsFolder)

    paths := []
    Loop Files Config.LoginsFolder "\*.txt" {
        ; Skip our own config/log files that live in the Logins root —
        ; they're .txt but they are NOT account files. Without this they'd
        ; load as bogus "accounts" (and show up as junk files in the list).
        if IsReservedLoginsFile(A_LoopFileName)
            continue
        paths.Push(A_LoopFileFullPath)
    }
    paths := SortArray(paths)

    ; Built into a local and only committed to App.Files on success, so a
    ; failed load (e.g. mid-Reload) can't leave the app running with an
    ; empty or half-populated file list.
    loadedFiles := []
    for path in paths {
        SplitPath(path, , , , &nameNoExt)
        loginFile := { Name: nameNoExt, Path: path, Accounts: [], TrailingRaw: [], UnparsedCount: 0 }

        ; Non-account lines — comments, blanks, and lines that don't parse
        ; — are kept verbatim (attached to the account that follows them,
        ; or to the file's tail) and re-emitted by WriteAccountsFile, so a
        ; note autosave or credential edit can't silently strip a user's
        ; comments or a typo'd line from disk. Unparseable lines are also
        ; counted, and surfaced next to the account count in the UI.
        pendingRaw := []
        text := FileRead(path, "UTF-8")
        for line in StrSplit(text, "`n", "`r") {
            trimmed := Trim(line)
            if (trimmed = "" || SubStr(trimmed, 1, 1) = ";") {
                pendingRaw.Push(line)
                continue
            }
            parts := StrSplit(trimmed, "|")
            if (parts.Length < 3) {
                pendingRaw.Push(line)
                loginFile.UnparsedCount += 1
                continue
            }
            ; Invariant: every account object carries ALL of these props
            ; (defaulted to "") — display/filter/save code relies on it
            ; and reads them without HasOwnProp guards. Fields 5-8 are the
            ; Game Info view's data, optional in the file like Note.
            loginFile.Accounts.Push({
                Name: Trim(parts[1]),
                Email: Trim(parts[2]),
                Password: Trim(parts[3]),
                Note: parts.Length >= 4 ? Trim(parts[4]) : "",
                Class: parts.Length >= 5 ? Trim(parts[5]) : "",
                Level: parts.Length >= 6 ? Trim(parts[6]) : "",
                Money: parts.Length >= 7 ? Trim(parts[7]) : "",
                LastLogin: parts.Length >= 8 ? Trim(parts[8]) : "",
                RawBefore: pendingRaw
            })
            pendingRaw := []
        }
        loginFile.TrailingRaw := pendingRaw

        ; Files with zero parseable accounts still get listed — otherwise
        ; deleting the last account in a file and reloading would make the
        ; whole file disappear from the app while still existing on disk.
        loadedFiles.Push(loginFile)
    }

    if (loadedFiles.Length = 0)
        throw Error("No login files (*.txt) found in " Config.LoginsFolder)

    App.Files := loadedFiles
}

ReloadFiles(*) {
    global App
    if App.EditDialogOpen {
        ShowToast("Close the edit dialog first")
        return
    }
    FlushPendingNoteSave()
    try {
        keepName := App.Files.Length ? App.Files[App.CurrentFile].Name : ""
        keepAcc := GetCurrentAccount()
        keepAccEmail := IsObject(keepAcc) ? keepAcc.Email : ""

        ; Reload rebuilds every account object, which would zero the
        ; day's online minutes — snapshot them (live totals) and re-apply.
        keepTimes := Map()
        for fOld in App.Files {
            for accOld in fOld.Accounts {
                t := AccountOnlineMs(accOld)
                if (t > 0)
                    keepTimes[accOld.Email] := t
            }
        }

        LoadLoginFiles()
        for fNew in App.Files {
            for accNew in fNew.Accounts {
                if keepTimes.Has(accNew.Email)
                    accNew.OnlineMs := keepTimes[accNew.Email]
            }
        }

        ; Re-point the pick queue and the double-click mini queue at the
        ; freshly-built account objects.
        App.LoginQueue := RepointByEmail(App.LoginQueue)
        App.PendingSingles := RepointByEmail(App.PendingSingles)
        RefreshPickUI()

        newIndex := 1
        for i, f in App.Files {
            if (f.Name = keepName) {
                newIndex := i
                break
            }
        }
        App.CurrentFile := newIndex
        App.PendingRestoreAccountEmail := keepAccEmail
        RefreshUI()
        ShowToast("Reloaded " App.Files.Length " file(s)")
    } catch as err {
        ShowConfirm("Reload failed: " err.Message)
    }
}

; ============================================================
; EDITING (Add / Edit / Delete accounts, writes back to the .txt)
; ============================================================
EditCurrentAccount(*) {
    global App
    acc := GetCurrentAccount()
    if !IsObject(acc) {
        ShowToast("No account selected")
        return
    }
    ; The editor pipeline (dialog, save, delete) works on the CURRENT
    ; file by integer index. A cross-file search row isn't that — so
    ; jump to the account first (clears the filter, switches file),
    ; which lands us back in normal mode with a valid index.
    if (App.FilterText != "") {
        JumpToAccount(acc)
        acc := GetCurrentAccount()
        if !IsObject(acc)
            return
    }
    accIdx := App.Displayed[App.CurrentDisplayPos]
    OpenAccountEditor("edit", acc, accIdx)
}

AddNewAccount(*) {
    global App
    if !App.EditModeOn {
        ShowToast("Turn on Edit Mode first")
        return
    }
    OpenAccountEditor("add", "", 0)
}

OpenAccountEditor(mode, acc, accIdx) {
    global App
    if App.EditDialogOpen
        return
    App.EditDialogOpen := true

    dlg := Gui("+Owner" App.Gui.Hwnd, mode = "add" ? "Add Account" : "Edit Account")
    dlg.BackColor := Colors.Bg
    dlg.MarginX := 16
    dlg.MarginY := 14
    dlg.SetFont("s10 c" Colors.Text, Config.FontMain)

    dlg.Add("Text", "w80", "Name")
    nameEdit := dlg.Add("Edit", "x+8 w250", mode = "edit" ? acc.Name : "")

    dlg.Add("Text", "xm w80 y+10", "Email")
    emailEdit := dlg.Add("Edit", "x+8 w250", mode = "edit" ? acc.Email : "")

    dlg.Add("Text", "xm w80 y+10", "Password")
    pwEdit := dlg.Add("Edit", "x+8 w250 Password", mode = "edit" ? acc.Password : "")

    revealChk := dlg.Add("Checkbox", "xm y+10", "Show password")
    revealChk.OnEvent("Click", (*) => pwEdit.Opt(revealChk.Value ? "-Password" : "+Password"))

    btnSave := dlg.Add("Button", "xm y+18 w110 h30 Default", mode = "add" ? "Add" : "Save")
    btnSave.OnEvent("Click", (*) => DoSaveFromDialog(dlg, mode, accIdx, nameEdit, emailEdit, pwEdit))

    btnCancel := dlg.Add("Button", "x+10 yp w110 h30", "Cancel")
    btnCancel.OnEvent("Click", (*) => CloseEditDialog(dlg))

    if (mode = "edit") {
        btnDelete := dlg.Add("Button", "x+10 yp w90 h30", "Delete")
        btnDelete.OnEvent("Click", (*) => DoDeleteFromDialog(dlg, accIdx))
    }

    dlg.OnEvent("Close", (*) => CloseEditDialog(dlg))
    dlg.OnEvent("Escape", (*) => CloseEditDialog(dlg))

    ApplyDialogDarkMode(dlg, [nameEdit, emailEdit, pwEdit])

    dlg.Show("AutoSize")
}

CloseEditDialog(dlg) {
    global App
    App.EditDialogOpen := false
    try dlg.Destroy()
}

DoSaveFromDialog(dlg, mode, accIdx, nameEdit, emailEdit, pwEdit) {
    global App
    name := Trim(nameEdit.Text)
    email := Trim(emailEdit.Text)
    pw := Trim(pwEdit.Text)

    if (name = "" || email = "" || pw = "") {
        ShowConfirm("Name, Email, and Password can't be empty.", "Account Queue", "Icon!")
        return
    }
    if (HasInvalidChars(name) || HasInvalidChars(email) || HasInvalidChars(pw)) {
        ShowConfirm("Fields can`'t contain `"|`" or line breaks — those are used as the file separator.",
            "Account Queue", "Icon!")
        return
    }
    if (SubStr(name, 1, 1) = ";") {
        ShowConfirm("Name can`'t start with `";`" — lines starting with a semicolon are treated as comments, so this account would vanish on the next reload.",
            "Account Queue", "Icon!")
        return
    }

    currentFile := App.Files[App.CurrentFile]

    ; Build the prospective file contents WITHOUT touching live state yet,
    ; so a failed write can't leave memory and disk out of sync.
    newAccounts := []
    for a in currentFile.Accounts
        newAccounts.Push(CloneAccount(a))

    if (mode = "add") {
        newAccounts.Push({ Name: name, Email: email, Password: pw, Note: "",
            Class: "", Level: "", Money: "", LastLogin: "" })
        verb := "add a new account"
        target := name
    } else {
        if (accIdx < 1 || accIdx > newAccounts.Length) {
            ShowConfirm("That account no longer exists (the list may have changed).", "Account Queue", "Icon!")
            CloseEditDialog(dlg)
            return
        }
        ; Clone-then-overwrite instead of building a fresh object, so any
        ; field we're not editing here (Note, Client tags, anything added
        ; later) survives automatically rather than needing to be
        ; individually remembered and re-listed by hand.
        updated := CloneAccount(newAccounts[accIdx])
        updated.Name := name
        updated.Email := email
        updated.Password := pw
        newAccounts[accIdx] := updated
        verb := "save changes to"
        target := name
    }

    ; Email is the identity key for position memory and window links, so
    ; a duplicate is worth flagging — but it's the user's data, so fold a
    ; warning into the existing confirmation rather than refusing.
    dupName := ""
    for i, a in newAccounts {
        if (mode = "edit" && i = accIdx) || (mode = "add" && i = newAccounts.Length)
            continue
        if (a.Email = email) {
            dupName := a.Name
            break
        }
    }

    confirmMsg := "Really " verb " `"" target "`" in " currentFile.Name ".txt?`n`n"
        . "A timestamped backup of the file will be made first."
    if (dupName != "")
        confirmMsg .= "`n`nHeads up: `"" dupName "`" already uses this email. Accounts are matched internally by email, so duplicates can confuse position memory and window links."
    if (ShowConfirm(confirmMsg, "Confirm Save", "YesNo Icon?") != "Yes")
        return

    try {
        WriteAccountsFile(currentFile.Path, newAccounts, true, currentFile.TrailingRaw)
    } catch as err {
        ShowConfirm("Could not save file:`n" err.Message, "Account Queue", "IconX")
        return
    }

    currentFile.Accounts := newAccounts
    ShowToast(mode = "add" ? "Account added" : "Account updated")
    CloseEditDialog(dlg)
    if (mode = "add") {
        ; Jump to the account that was just added, wherever it landed.
        App.PendingRestoreAccountEmail := email
        ApplyFilter(App.FilterText)
        RestorePendingAccountPosition()
    } else {
        ApplyFilter(App.FilterText)
    }
}

DoDeleteFromDialog(dlg, accIdx) {
    global App
    currentFile := App.Files[App.CurrentFile]
    if (accIdx < 1 || accIdx > currentFile.Accounts.Length) {
        CloseEditDialog(dlg)
        return
    }
    acc := currentFile.Accounts[accIdx]

    warnLast := (currentFile.Accounts.Length = 1)
        ? "`n`nThis is the only account left in this file — it will become empty."
        : ""
    confirmMsg := "Permanently delete `"" acc.Name "`" (" acc.Email ") from "
        . currentFile.Name ".txt?`n`nA timestamped backup will be made first." warnLast
    if (ShowConfirm(confirmMsg, "Confirm Delete", "YesNo Icon!") != "Yes")
        return

    newAccounts := []
    for i, a in currentFile.Accounts {
        if (i != accIdx)
            newAccounts.Push(CloneAccount(a))
    }

    try {
        WriteAccountsFile(currentFile.Path, newAccounts, true, currentFile.TrailingRaw)
    } catch as err {
        ShowConfirm("Could not save file:`n" err.Message, "Account Queue", "IconX")
        return
    }

    currentFile.Accounts := newAccounts
    ShowToast("Account deleted")
    CloseEditDialog(dlg)

    if (App.CurrentDisplayPos > App.Displayed.Length)
        App.CurrentDisplayPos := Max(1, App.Displayed.Length)
    ApplyFilter(App.FilterText)
}

HasInvalidChars(s) {
    return InStr(s, "|") || InStr(s, "`n") || InStr(s, "`r")
}

SanitizeField(s) {
    s := StrReplace(s, "|", "")
    s := StrReplace(s, "`r", "")
    return StrReplace(s, "`n", " ")
}

; Clones an account's core fields for building a new accounts list, while
; preserving the in-memory (not saved to disk) Client tags, so editing or
; deleting one account doesn't wipe the Client column for the whole file.
CloneAccount(a) {
    clone := { Name: a.Name, Email: a.Email, Password: a.Password,
        Note: a.HasOwnProp("Note") ? a.Note : "",
        Class: a.HasOwnProp("Class") ? a.Class : "",
        Level: a.HasOwnProp("Level") ? a.Level : "",
        Money: a.HasOwnProp("Money") ? a.Money : "",
        LastLogin: a.HasOwnProp("LastLogin") ? a.LastLogin : "" }
    ; Shared by reference on purpose — RawBefore is never mutated after
    ; load, and sharing keeps clones cheap.
    if a.HasOwnProp("RawBefore")
        clone.RawBefore := a.RawBefore
    if a.HasOwnProp("ClientSession")
        clone.ClientSession := a.ClientSession
    if a.HasOwnProp("ClientHwnd")
        clone.ClientHwnd := a.ClientHwnd
    ; Session-only online-time tracking must survive edits too.
    if a.HasOwnProp("LinkTime")
        clone.LinkTime := a.LinkTime
    if a.HasOwnProp("OnlineMs")
        clone.OnlineMs := a.OnlineMs
    return clone
}

; Writes accounts to disk. By default backs up the existing file first
; (aborting the whole save if the backup fails), then writes via a temp
; file + rename so a crash mid-write can never leave a half-written file
; in place. takeBackup=false skips the backup step (used for note
; autosaves, which happen often enough that backing up every single one
; would flood the Backups folder for very low-stakes edits) but the
; atomic write still always happens either way.
WriteAccountsFile(path, accounts, takeBackup := true, trailingRaw := "") {
    if takeBackup
        BackupFile(path)

    lines := []
    for acc in accounts {
        ; Re-emit the comment/blank/unparsed lines that originally sat
        ; above this account, so saving never strips them from the file.
        if acc.HasOwnProp("RawBefore") {
            for rawLine in acc.RawBefore
                lines.Push(rawLine)
        }
        ; Free-text fields (Note + game info) aren't validated on entry
        ; (that's the point — no friction), so sanitize defensively here
        ; instead: strip anything that would break the line-based format.
        ; Trailing empty fields are trimmed so files stay as clean as
        ; whatever the user actually filled in ("a|b|c" stays "a|b|c").
        fields := [acc.Name, acc.Email, acc.Password,
            SanitizeField(acc.Note), SanitizeField(acc.Class), SanitizeField(acc.Level),
            SanitizeField(acc.Money), SanitizeField(acc.LastLogin)]
        n := fields.Length
        while (n > 3 && fields[n] = "")
            n -= 1
        line := ""
        loop n
            line .= (A_Index > 1 ? "|" : "") fields[A_Index]
        lines.Push(line)
    }
    ; ...and the raw lines that sat after the last account (fileObj.TrailingRaw).
    if IsObject(trailingRaw) {
        for rawLine in trailingRaw
            lines.Push(rawLine)
    }
    content := ""
    for i, line in lines
        content .= line (i < lines.Length ? "`n" : "")

    AtomicWriteText(path, content)
}

; Temp file + rename, so a crash mid-write can never leave a
; half-written file in place. Every file write in this app (credentials,
; macros) must go through here.
AtomicWriteText(path, content) {
    tempPath := path ".tmp"
    f := FileOpen(tempPath, "w", "UTF-8")
    if !f
        throw Error("Could not open temp file for writing: " tempPath)
    f.Write(content)
    f.Close()
    FileMove(tempPath, path, 1)
}

BackupFile(path) {
    if !FileExist(path)
        return ; nothing on disk yet to back up (e.g. a brand new file)

    if !DirExist(Config.BackupsFolder)
        DirCreate(Config.BackupsFolder)

    SplitPath(path, &fileName)
    stamp := FormatTime(, "yyyyMMdd_HHmmss")
    backupPath := Config.BackupsFolder "\" fileName "." stamp ".bak"

    FileCopy(path, backupPath, 1)
    PruneBackups(fileName)
}

PruneBackups(fileName) {
    matches := []
    Loop Files Config.BackupsFolder "\" fileName ".*.bak" {
        matches.Push(A_LoopFileFullPath)
    }
    matches := SortArray(matches) ; timestamp-named, so this sorts oldest-first
    while (matches.Length > Config.BackupsToKeep) {
        try FileDelete(matches[1])
        matches.RemoveAt(1)
    }
}

; ============================================================
; HELPERS
; ============================================================
SortArray(arr) {
    n := arr.Length
    loop n - 1 {
        i := A_Index
        loop n - i {
            j := A_Index
            if (StrCompare(arr[j], arr[j + 1]) > 0) {
                tmp := arr[j]
                arr[j] := arr[j + 1]
                arr[j + 1] := tmp
            }
        }
    }
    return arr
}

; ============================================================
; MONEY (human number formats)
; ------------------------------------------------------------
; The user's typed text is stored verbatim (file + edit box); the app
; just UNDERSTANDS it. ParseMoney turns "3.3m" / "123k" / "6,000,000" /
; "1.2b" / "60000" into a number, or "" if it can't — unparseable text
; is kept as-is, shown greyed, and excluded from every calculation.
; ============================================================
ParseMoney(s) {
    s := Trim(s)
    if (s = "")
        return ""
    s := StrReplace(StrReplace(s, ",", ""), " ", "")
    mult := 1
    switch StrLower(SubStr(s, -1)) {
        case "k": mult := 1000
        case "m": mult := 1000000
        case "b": mult := 1000000000
    }
    if (mult > 1)
        s := SubStr(s, 1, -1)
    if !RegExMatch(s, "^\d+(\.\d+)?$")
        return ""
    return Round(Number(s) * mult)
}

; Compact standardized display: 6600000 -> "6.6M", 60000 -> "60K".
; Three decimals of the unit, trailing zeros trimmed: 1,036,000,000 is
; "1.036B", NOT "1B" — 36M is real money. Clean values stay clean
; ("6.6M", "6M").
FormatMoney(n) {
    if (n >= 1000000000)
        return TrimTrailingZeros(Round(n / 1000000000.0, 3)) "B"
    if (n >= 1000000)
        return TrimTrailingZeros(Round(n / 1000000.0, 3)) "M"
    if (n >= 1000)
        return TrimTrailingZeros(Round(n / 1000.0, 3)) "K"
    return n
}

TrimTrailingZeros(v) {
    s := String(v)
    if InStr(s, ".")
        s := RTrim(RTrim(s, "0"), ".")
    return s
}

; RGB hex string ("3F6FE0") -> COLORREF (BGR) for custom draw.
HexToBGR(hex) {
    v := Integer("0x" hex)
    return ((v & 0xFF) << 16) | (v & 0xFF00) | ((v >> 16) & 0xFF)
}

MaskString(len) {
    dots := Min(len, Config.MaxMaskDots)
    out := ""
    loop dots
        out .= "•"
    return out
}

ShowToast(msg) {
    ToolTip(msg)
    ; Duration scales with length (1.2–4 s): a flat 1.2 s cut off the
    ; instructional toasts ("Pick mode — click accounts…") mid-read.
    ; Named function, not a fresh closure: re-toasting inside the window
    ; resets the SAME timer, so an earlier toast's cleanup can't hide a
    ; newer toast early (same principle as gotcha #9).
    SetTimer(HideToast, -Min(4000, Max(1200, StrLen(msg) * 45)))
}

HideToast() {
    ToolTip()
}

; Wraps MsgBox so it can't end up stuck behind an Always-on-Top main
; window: temporarily drops the topmost flag for the dialog's duration,
; then restores whatever the user's actual preference was. Also covers
; dialogs opened via the edit/add window, since that's owned by the main
; window and was inheriting the same z-order fight.
ShowConfirm(text, title := "Account Queue", options := "") {
    global App
    wasTopmost := App.AlwaysOnTop && (App.Gui != "")
    if wasTopmost
        try App.Gui.Opt("-AlwaysOnTop")
    result := MsgBox(text, title, options)
    if wasTopmost
        try App.Gui.Opt("+AlwaysOnTop")
    return result
}

; InputBox with the same Always-on-Top handling as ShowConfirm — any new
; blocking prompt must use this, not a raw InputBox(). Returns the
; InputBox result object ({Result, Value}).
ShowInput(prompt, title := "Account Queue", default := "") {
    global App
    wasTopmost := App.AlwaysOnTop && (App.Gui != "")
    if wasTopmost
        try App.Gui.Opt("-AlwaysOnTop")
    ib := InputBox(prompt, title, "w380 h130", default)
    if wasTopmost
        try App.Gui.Opt("+AlwaysOnTop")
    return ib
}
