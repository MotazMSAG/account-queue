; --- self-contained fixture: fresh sandbox Logins next to this test ---
DirCreate(A_ScriptDir "\Logins")
__fx := FileOpen(A_ScriptDir "\Logins\Test.txt", "w", "UTF-8")
__fx.Write("; header comment`n`nMain|a@x.com|pw1`nbadline|only2fields`nAlt|b@x.com|pw2|note-b|Warrior|80|123k|2026-07-01 10:00`n; trailing comment")
__fx.Close()
try FileDelete(A_ScriptDir "\Logins\Settings.ini")
FileOpen(A_ScriptDir "\Logins\Settings.ini", "w", "UTF-8").Write("[Preferences]`nAlwaysOnTop=0`n")
try FileDelete(A_ScriptDir "\test-results.txt")

OnError(TestErrHandler)
TestErrHandler(err, mode) {
    try FileAppend("ERROR: " err.Message " @ line " err.Line "`n", A_ScriptDir "\test-results.txt")
    ExitApp(1)
}

; --- desktop hygiene: never disturb the machine the suite runs on ---
; AQ_TEST_QUIET makes the app window come up without taking focus, and
; the settings below keep it off the top of the z-order. AQ_PREV_ACTIVE
; is restored at the end so the foreground window the user was actually
; using stays theirs.
global AQ_TEST_QUIET := true
global AQ_PREV_ACTIVE := 0
try AQ_PREV_ACTIVE := WinExist("A")
AQRestoreForeground() {
    global AQ_PREV_ACTIVE
    if (AQ_PREV_ACTIVE && WinExist("ahk_id " AQ_PREV_ACTIVE))
        try WinActivate("ahk_id " AQ_PREV_ACTIVE)
}
#Include ..\AccountQueue.ahk

results := ""
Check(label, cond) {
    global results
    results .= label ": " (cond ? "PASS" : "FAIL") "`n"
}

; HOUSE RULE: tests must never point Config.GameProcess at the real game.
; The owner runs 30 clients while working; any code path that scans for
; them (auto-next, jump-to-client, the login funnel) will happily
; activate or click a REAL window. Use this name for "no clients exist".
global NO_SUCH_GAME := "AQ_NoSuchProcess.exe"
Config.GameProcess := NO_SUCH_GAME

; The shipped default goal moved to 45 (0.38.0). Assert that, then pin
; it to 30 so the existing session-math checks below (built around a
; 30-min goal) keep asserting what they mean.
Check("goal-ships-at-45", Config.SessionGoalMinutes = 45)
Config.SessionGoalMinutes := 30

f := App.Files[1]
Check("file-count", App.Files.Length = 1)
Check("acct-count", f.Accounts.Length = 2)
Check("unparsed-count", f.UnparsedCount = 1)
Check("raw-before-1", f.Accounts[1].RawBefore.Length = 2)
Check("raw-before-2", f.Accounts[2].RawBefore.Length = 1 && f.Accounts[2].RawBefore[1] = "badline|only2fields")
Check("trailing-raw", f.TrailingRaw.Length = 1 && f.TrailingRaw[1] = "; trailing comment")
Check("note-parsed", f.Accounts[2].Note = "note-b")
Check("game-fields-parsed", f.Accounts[2].Class = "Warrior" && f.Accounts[2].Level = "80"
    && f.Accounts[2].Money = "123k" && f.Accounts[2].LastLogin = "2026-07-01 10:00")
Check("game-fields-default", f.Accounts[1].Class = "" && f.Accounts[1].LastLogin = "")

cloned := CloneAccount(f.Accounts[2])
Check("clone-carries-all", cloned.RawBefore.Length = 1 && cloned.Class = "Warrior" && cloned.Money = "123k")

; Round-trip write: raw lines preserved, 8-field line intact, trailing
; empty fields trimmed (Main gains only |hello, nothing more).
f.Accounts[1].Note := "hello"
WriteAccountsFile(f.Path, f.Accounts, false, f.TrailingRaw)
expected := "; header comment`n`nMain|a@x.com|pw1|hello`nbadline|only2fields`n"
    . "Alt|b@x.com|pw2|note-b|Warrior|80|123k|2026-07-01 10:00`n; trailing comment"
actual := FileRead(f.Path, "UTF-8")
Check("roundtrip-exact", actual == expected)
if (actual != expected)
    results .= "---ACTUAL---`n" actual "`n---EXPECTED---`n" expected "`n"
WriteAccountsFile(f.Path, f.Accounts, false, f.TrailingRaw)
Check("write-stable", FileRead(f.Path, "UTF-8") == actual)

; --- Game Info view (Last login moved OUT of it in 0.11.0) ---
SetViewMode("game", false)
Check("view-game", App.ViewMode = "game")
Check("viewbtn-game-active", !App.Controls.ViewBtnGame.Enabled
    && App.Controls.ViewBtnCred.Enabled && App.Controls.ViewBtnSess.Enabled)
Check("game-cell-class", App.Controls.List.GetText(2, 3) = "Warrior")
Check("game-cell-note", App.Controls.List.GetText(2, 6) = "note-b")
Check("game-edits-visible", App.Controls.ClassEdit.Visible && App.Controls.MoneyEdit.Visible)

; Live edit through the real Change handler (row 1 = Main is selected).
; NOTE: programmatic .Text does NOT raise Change in AHK v2 — only real
; input does — so send actual keystrokes to the control.
ControlSend("Mage", , "ahk_id " App.Controls.ClassEdit.Hwnd)
Sleep(400)
Check("class-live-edit", f.Accounts[1].Class = "Mage")
Check("class-cell-updated", App.Controls.List.GetText(1, 3) = "Mage")

; --- Session view: online-time tracking ---
SetViewMode("session", false)
Check("view-session", App.ViewMode = "session")
Check("viewbtn-session-active", !App.Controls.ViewBtnSess.Enabled
    && App.Controls.ViewBtnCred.Enabled && App.Controls.ViewBtnGame.Enabled)
Check("session-lastlogin-col", App.Controls.List.GetText(2, 6) = "2026-07-01 10:00")

acc1 := f.Accounts[1]
acc1.ClientHwnd := App.Gui.Hwnd ; alive window = "linked"
acc1.ClientSession := 1
acc1.LinkTime := A_TickCount - 10 * 60000 ; linked 10 minutes ago
Check("online-10min", Floor(AccountOnlineMs(acc1) / 60000) = 10)
Check("not-done-yet", !IsAccountDone(acc1))
UpdateAllRowsInPlace()
Check("session-online-cell", App.Controls.List.GetText(1, 4) = "10 min")
Check("session-left-cell", App.Controls.List.GetText(1, 5) = "20 min left")

acc1.LinkTime := A_TickCount - 31 * 60000 ; past the 30-minute goal
Check("done-at-31", IsAccountDone(acc1))
UpdateAllRowsInPlace()
Check("session-done-cell", App.Controls.List.GetText(1, 5) = "✔ done")
RefreshSummary()
Check("summary-stat-strip", App.Controls.StatDone.Value = "✔ 1"
    && App.Controls.StatOnline.Value = "▶ 0")

; Scoreboard is GLOBAL (all files, deduplicated by email)
fakeAcc := { Name: "Z", Email: "z@x.com", Password: "p", Note: "", Class: "", Level: "", Money: "", LastLogin: "", OnlineMs: 31 * 60000 }
App.Files.Push({ Name: "Fake", Path: "", Accounts: [fakeAcc], TrailingRaw: [], UnparsedCount: 0 })
RefreshSummary()
Check("summary-global", App.Controls.StatDone.Value = "✔ 2")
dupAcc := { Name: "MainCopy", Email: "a@x.com", Password: "p", Note: "", Class: "", Level: "", Money: "", LastLogin: "" }
App.Files.Push({ Name: "Fake2", Path: "", Accounts: [dupAcc], TrailingRaw: [], UnparsedCount: 0 })
RefreshSummary()
Check("summary-dedup-by-email", App.Controls.StatDone.Value = "✔ 2") ; a@x.com counted once
App.Files.Pop()
App.Files.Pop()
RefreshSummary()

; Lost-connection state: banked partial time, no client → ⚠ in Left cell
acc2 := f.Accounts[2]
acc2.OnlineMs := 5 * 60000
UpdateAllRowsInPlace()
Check("offline-warn-cell", App.Controls.List.GetText(2, 5) = "⚠ 25 min left")
acc2.DeleteProp("OnlineMs")

; Last-login auto-stamp (what F2/F4 call) updates data + visible cell
StampLastLogin(acc1)
Check("lastlogin-stamped", acc1.LastLogin != "")
Check("lastlogin-cell", App.Controls.List.GetText(1, 6) = acc1.LastLogin)

; Dead client: housekeeping clears the Client column but BANKS the time.
; Two-strike rule: the FIRST missing tick must NOT detach (protects
; against transient window flicker) — only the second one does.
acc1.ClientHwnd := 999999
PeriodicHousekeeping()
Check("debounce-first-strike", acc1.HasOwnProp("ClientHwnd") && acc1.MissingTicks = 1)
PeriodicHousekeeping()
Check("prune-clears-client", !acc1.HasOwnProp("ClientHwnd") && !acc1.HasOwnProp("ClientSession"))
Check("prune-banks-time", AccountOnlineMs(acc1) >= 31 * 60000 - 5000)
Check("prune-cell-cleared", App.Controls.List.GetText(1, 3) = "")
Check("still-done-after-close", IsAccountDone(acc1))

; Clone carries the session-time props (edits mustn't reset the clock)
clonedTimed := CloneAccount(acc1)
Check("clone-carries-onlinems", clonedTimed.HasOwnProp("OnlineMs") && clonedTimed.OnlineMs >= 31 * 60000 - 5000)

; --- game-day (02:00) reset & persistence ---
Check("gameday-format", GameDayStamp() = FormatTime(DateAdd(A_Now, -2, "Hours"), "yyyyMMdd"))

acc1.OnlineMs := 31 * 60000
SaveSessionTimes()
Check("times-saved", IniRead(Config.SettingsPath, "SessionTimes", "a@x.com", "0") = 31 * 60000)
acc1.DeleteProp("OnlineMs")
LoadSessionTimes()
Check("times-restored", acc1.HasOwnProp("OnlineMs") && acc1.OnlineMs = 31 * 60000)

; A stamp from another game day must be discarded, not restored
IniWrite("20200101", Config.SettingsPath, "SessionTimes", "__gameday")
acc1.DeleteProp("OnlineMs")
LoadSessionTimes()
Check("stale-day-discarded", !acc1.HasOwnProp("OnlineMs"))

; Live rollover: pretend the app has been running since "yesterday" —
; the next housekeeping tick must reset stats but keep live links,
; restarting their clock at the boundary.
acc1.OnlineMs := 31 * 60000
acc1.ClientHwnd := App.Gui.Hwnd
acc1.ClientSession := 9
acc1.LinkTime := A_TickCount - 10 * 60000
App.CurrentGameDay := "19990101"
PeriodicHousekeeping()
Check("rollover-resets", !acc1.HasOwnProp("OnlineMs") && App.CurrentGameDay = GameDayStamp())
Check("rollover-keeps-link", acc1.HasOwnProp("ClientHwnd") && (A_TickCount - acc1.LinkTime) < 6000)
DetachClient(acc1)
acc1.DeleteProp("OnlineMs")

; Debounced autosave flushes to disk, then survives a real reload
FlushPendingNoteSave()
Check("class-persisted", InStr(FileRead(f.Path, "UTF-8"), "Main|a@x.com|pw1|hello|Mage"))
LoadLoginFiles()
Check("reload-class", App.Files[1].Accounts[1].Class = "Mage")
Check("reload-lastlogin", App.Files[1].Accounts[1].LastLogin != "")

; The Reload button must carry the day's minutes across the rebuild
App.Files[1].Accounts[1].OnlineMs := 12 * 60000
ReloadFiles()
Check("reload-keeps-times", App.Files[1].Accounts[1].HasOwnProp("OnlineMs")
    && App.Files[1].Accounts[1].OnlineMs = 12 * 60000)
App.Files[1].Accounts[1].DeleteProp("OnlineMs")

; --- back to credentials view + full cycle ---
SetViewMode("credentials", false)
Check("view-cred", App.ViewMode = "credentials")
Check("viewbtn-cred-active", !App.Controls.ViewBtnCred.Enabled
    && App.Controls.ViewBtnGame.Enabled && App.Controls.ViewBtnSess.Enabled)
Check("cred-cell-email", App.Controls.List.GetText(1, 3) = "a@x.com")
Check("game-edits-hidden", !App.Controls.ClassEdit.Visible)
ToggleViewMode()
cycleOk := App.ViewMode = "game"
ToggleViewMode()
cycleOk := cycleOk && App.ViewMode = "session"
ToggleViewMode()
Check("view-cycle", cycleOk && App.ViewMode = "credentials")
Check("version-label", App.Controls.VersionLabel.Text = "v" Config.Version)
Check("hotkeys-tip-present", App.Controls.HotkeysLabel.HasOwnProp("TipText")
    && InStr(App.Controls.HotkeysLabel.TipText, "F4"))

; --- search covers notes and game fields, grouped per file (0.29.0:
; results come from ALL files, each group under a 📁 separator row) ---
ApplyFilter("note-b")
Check("search-by-note", App.Displayed.Length = 2 && !IsObject(RowAccount(1))
    && RowAccount(2).Name = "Alt" && App.CurrentDisplayPos = 2)
Check("search-rownum-file-index", RowNum(2) = 2) ; Alt = #2 in its file
ApplyFilter("123k")
Check("search-by-money", App.Displayed.Length = 2 && RowAccount(2).Name = "Alt")
ApplyFilter("")
Check("search-cleared", App.Displayed.Length = 2 && App.Displayed[1] = 1
    && IsObject(RowAccount(1)))

; --- money system ---
Check("parse-m", ParseMoney("3.3m") = 3300000)
Check("parse-plain", ParseMoney("60000") = 60000)
Check("parse-commas", ParseMoney("6,000,000") = 6000000)
Check("parse-k", ParseMoney("123k") = 123000)
Check("parse-b", ParseMoney("1.2B") = 1200000000)
Check("parse-bad", ParseMoney("xxx") = "" && ParseMoney("") = "" && ParseMoney("6.6.6m") = "")
Check("format-money", FormatMoney(6600000) = "6.6M" && FormatMoney(6000000) = "6M"
    && FormatMoney(60000) = "60K" && FormatMoney(950) = 950 && FormatMoney(1500) = "1.5K")
Check("format-money-precise", FormatMoney(1036000000) = "1.036B"
    && FormatMoney(2042000000) = "2.042B" && FormatMoney(123456) = "123.456K")
Check("hex-bgr", HexToBGR("FF0000") = 0x0000FF && HexToBGR("3F6FE0") = 0xE06F3F)

SetViewMode("game", false)
Check("money-cell-standardized", App.Controls.List.GetText(2, 5) = "123K")
accM := App.Files[1].Accounts[1]
accM.Money := "xxx"
UpdateAllRowsInPlace()
Check("money-cell-raw-kept", App.Controls.List.GetText(1, 5) = "xxx")

ApplyFilter(">100k")
Check("money-op-gt", App.Displayed.Length = 2 && RowAccount(2).Name = "Alt")
ApplyFilter(">200k")
Check("money-op-gt-none", App.Displayed.Length = 0)
ApplyFilter(">=123k")
Check("money-op-gte", App.Displayed.Length = 2)
ApplyFilter("")
RefreshSummary()
Check("money-total", InStr(App.Controls.StatMoney.Value, "Σ 123K"))
accM.Money := ""
UpdateAllRowsInPlace()
SetViewMode("credentials", false)

; --- pick queue (F8) ---
TogglePickMode()
Check("pick-mode-on", App.PickMode && App.LoginQueue.Length = 0)
OnListClick(App.Controls.List, 2) ; pick Alt first...
OnListClick(App.Controls.List, 1) ; ...then Main
Check("pick-order", App.LoginQueue.Length = 2
    && App.LoginQueue[1].Name = "Alt" && App.LoginQueue[2].Name = "Main")
Check("pick-cell-markers", App.Controls.List.GetText(2, 1) = "»1"
    && App.Controls.List.GetText(1, 1) = "»2")
OnListClick(App.Controls.List, 2) ; click again = unpick Alt
Check("pick-unpick", App.LoginQueue.Length = 1 && App.LoginQueue[1].Name = "Main"
    && App.Controls.List.GetText(1, 1) = "»1")
OnListClick(App.Controls.List, 2) ; re-add Alt -> [Main, Alt]
TogglePickMode() ; finish picking
Check("pick-mode-off", !App.PickMode && App.LoginQueue.Length = 2)
Check("paste-target-is-head", GetPasteTarget().Name = "Main")
Check("pick-status-prefix", InStr(App.Controls.CountLabel.Value, "2 queued"))
AdvanceLoginQueue()
Check("queue-advance", App.LoginQueue.Length = 1 && GetPasteTarget().Name = "Alt")
Check("queue-focus-follows", GetCurrentAccount().Name = "Alt")
AdvanceLoginQueue()
Check("queue-exhausts", App.LoginQueue.Length = 0 && !App.PickMode)
Check("target-falls-back-to-selection", IsObject(GetPasteTarget()))

; Pick queue survives Reload (re-pointed at the rebuilt objects)
TogglePickMode()
OnListClick(App.Controls.List, 1)
TogglePickMode()
ReloadFiles()
Check("pick-survives-reload", App.LoginQueue.Length = 1
    && App.LoginQueue[1].Email = "a@x.com"
    && App.LoginQueue[1] = App.Files[1].Accounts[1])
App.LoginQueue := []
RefreshPickUI()
UpdateAllRowsInPlace()

; --- bulk pick (v0.19.4) ---
PickAll("file")
Check("pickall-file", App.LoginQueue.Length = 2)
PickAll("file")
Check("pickall-nodupes", App.LoginQueue.Length = 2)

; --- Mass Login console (v0.20.0) ---
Check("macro-choices-none", MacroChoices()[1] = "(none)")
a1 := App.Files[1].Accounts[1]
App.LoginMacros := Map()
App.LoginMacros[a1.Email] := ["Dailies"]
Check("console-macro-label", ConsoleMacroLabel(a1) = "Dailies"
    && ConsoleMacroLabel(App.Files[1].Accounts[2]) = "—")
App.LoginMacros[a1.Email] := ["Dailies", "Popups", "AFK"]
Check("console-macro-label-multi", ConsoleMacroLabel(a1) = "Dailies +2")
; soft-stop reaches the abort checks
App.LoginStopReq := true
Check("softstop-aborts", AbortPressed() && StopPressed())
App.LoginStopReq := false

; deferred post-login macro: pending only with a live client, under goal,
; not yet run; marked done after; cleared on relogin (DetachClient)
savedGoalM := Config.SessionGoalMinutes
Config.SessionGoalMinutes := 36
mp := App.Files[1].Accounts[1]
App.LoginMacros := Map(mp.Email, ["m1", "m2"])
mp.DeleteProp("_macroIdx")
mp.ClientHwnd := App.Gui.Hwnd
mp.ClientSession := 77
mp.LinkTime := A_TickCount - 5 * 60000
Check("macro-pending", AccountPendingMacro(mp) && FirstPendingMacro([mp]) = mp)
mp._macroIdx := 2 ; ran m1 — m2 still pending
Check("macro-playlist-continues", AccountPendingMacro(mp))
mp._macroIdx := 3 ; ran both
Check("macro-playlist-done", !AccountPendingMacro(mp))
; rounds: the account earliest in its playlist goes first
mq := App.Files[1].Accounts[2]
App.LoginMacros[mq.Email] := ["m1"]
mq.ClientHwnd := App.Gui.Hwnd
mq.ClientSession := 78
mq.LinkTime := A_TickCount - 5 * 60000
mp._macroIdx := 2
Check("macro-rounds-order", FirstPendingMacro([mp, mq]) = mq) ; mq at idx1 < mp at idx2
; time budget: fits with 31 min left (0-length macro + 15 reserve), not with 11
Check("macro-fits", MacroFitsBudget(mq))
mq.LinkTime := A_TickCount - 25 * 60000 ; 11 min left < 15 reserve
Check("macro-doesnt-fit", !MacroFitsBudget(mq))
; Play mode ignores the goal gate; Activity respects it
mp.LinkTime := A_TickCount - 40 * 60000 ; over the 36-min goal
Check("macro-goal-gate", !AccountPendingMacro(mp) && AccountPendingMacro(mp, false))
DetachClient(mp)
DetachClient(mq)
Check("macro-cleared-on-relogin", !mp.HasOwnProp("_macroIdx"))
mp.DeleteProp("OnlineMs") ; DetachClient banked the backdated time — clean up
mq.DeleteProp("OnlineMs")
Config.SessionGoalMinutes := savedGoalM
App.LoginMacros := Map()

; not-done bulk pick skips at-goal accounts
App.LoginQueue := []
App.Files[1].Accounts[2].OnlineMs := 40 * 60000
PickNotDone()
Check("picknotdone-skips-done", App.LoginQueue.Length = 1
    && App.LoginQueue[1].Name = App.Files[1].Accounts[1].Name)
App.Files[1].Accounts[2].DeleteProp("OnlineMs")
ClearPickQueue()
Check("lqi2", LoginQueueIndex2([mp], mp) = 1 && LoginQueueIndex2([], mp) = 0)
Check("minsleft", MinsLeft(0) = "0m" && MinsLeft(90000) = "2m" && MinsLeft(120000) = "2m")

ClearPickQueue()
Check("clear-pick", App.LoginQueue.Length = 0 && !App.PickMode)

; --- online view (F9) ---
accO := App.Files[1].Accounts[2]
accO.ClientHwnd := App.Gui.Hwnd
accO.ClientSession := 3
accO.LinkTime := A_TickCount - 5 * 60000
OpenOnlineView()
Check("online-open", IsObject(App.OnlineDlg))
lvO := App.OnlineDlg.OnlineList
Check("online-row", lvO.GetCount() = 1 && lvO.GetText(1, 1) = "Alt"
    && lvO.GetText(1, 3) = "#3" && lvO.GetText(1, 4) = "5 min")
DetachClient(accO)
accO.DeleteProp("OnlineMs")
RefreshOnlineView()
Check("online-empty-state", lvO.GetText(1, 1) = "— nothing online —")
CloseOnlineView(App.OnlineDlg)
Check("online-closed", !IsObject(App.OnlineDlg))

; --- preferences / tuning (⚙) ---
Check("tuning-defaults-captured", App.TuningDefaults["SessionGoalMinutes"] = 45) ; shipped default (0.38.0)
IniWrite("40", Config.SettingsPath, "Tuning", "SessionGoalMinutes")
LoadTuning()
Check("tuning-loaded", Config.SessionGoalMinutes = 40)
accT := App.Files[1].Accounts[1]
accT.OnlineMs := 35 * 60000
Check("goal-40-not-done", !IsAccountDone(accT))
Config.SessionGoalMinutes := 30
Check("goal-30-done", IsAccountDone(accT))
accT.DeleteProp("OnlineMs")

; Clamping: out-of-range and garbage input
ApplyTuningValue({ Key: "SessionGoalMinutes", Type: "int", Min: 1, Max: 1440 }, "99999")
Check("tuning-clamped", Config.SessionGoalMinutes = 1440)
ApplyTuningValue({ Key: "SessionGoalMinutes", Type: "int", Min: 1, Max: 1440 }, "banana")
Check("tuning-garbage-ignored", Config.SessionGoalMinutes = 1440)
Config.SessionGoalMinutes := 30

; Dialog round trip: open, edit the goal, save
OpenPreferences()
Check("prefs-open", IsObject(App.PrefsDlg))
Check("prefs-prefilled", App.PrefsDlg.Fields["SessionGoalMinutes"].Text = 30
    && App.PrefsDlg.Fields["GameProcess"].Text = Config.GameProcess)
App.PrefsDlg.Fields["SessionGoalMinutes"].Text := "40"
PrefsSave(App.PrefsDlg)
Check("prefs-saved", Config.SessionGoalMinutes = 40 && !IsObject(App.PrefsDlg)
    && IniRead(Config.SettingsPath, "Tuning", "SessionGoalMinutes", "0") = 40)
Check("prefs-gameday-adopted", App.CurrentGameDay = GameDayStamp())

; Defaults button restores shipped values (on save)
OpenPreferences()
PrefsFillDefaults(App.PrefsDlg)
PrefsSave(App.PrefsDlg)
Check("prefs-defaults-restored", Config.SessionGoalMinutes = 45) ; shipped default (0.38.0)
try IniDelete(Config.SettingsPath, "Tuning")
; PrefsSave just restored the SHIPPED defaults, which include the real
; game process (45-min goal) — put the harmless name back, and re-pin
; the goal to 30 for the session-math checks still to come.
Config.GameProcess := NO_SUCH_GAME
Config.SessionGoalMinutes := 30

; --- auto-login orchestrator (⚙ Launch & Login, v0.18.0) ---
Check("colorsclose-exact", ColorsClose(0x3F6FE0, 0x3F6FE0, 0))
Check("colorsclose-within", ColorsClose(0x3F6FE0, 0x4270E2, 8))
Check("colorsclose-outside", !ColorsClose(0x3F6FE0, 0x3F6F00, 10)) ; blue channel far off
Check("colorsclose-per-channel", !ColorsClose(0xFF0000, 0xEF0000, 8)) ; red off by 16 > 8

App.LoginProfile := { Points: Map(
    "tryagain", { X: 10, Y: 20, RefW: 800, RefH: 600, Color: "0x111111" },
    "logout",   { X: 30, Y: 40, RefW: 800, RefH: 600, Color: "0x123456" },
    "email",    { X: 50, Y: 60, RefW: 800, RefH: 600, Color: "0x654321" },
    "start",    { X: 70, Y: 80, RefW: 800, RefH: 600, Color: "0x222222" },
    "char",     { X: 90, Y: 100, RefW: 800, RefH: 600, Color: "0x333333" }) }
Check("profile-ready", LoginProfileReady())
; every point needs a colour
savedColor := App.LoginProfile.Points["email"].Color
App.LoginProfile.Points["email"].Color := ""
Check("profile-needs-color", !LoginProfileReady())
App.LoginProfile.Points["email"].Color := savedColor
SaveLoginProfile()
App.LoginProfile := { Points: Map() }
Check("profile-cleared", !LoginProfileReady())
LoadLoginProfile()
Check("profile-loaded", LoginProfileReady() && App.LoginProfile.Points["email"].X = 50
    && App.LoginProfile.Points["char"].Y = 100)
Check("profile-colors-loaded", Integer(App.LoginProfile.Points["logout"].Color) = 0x123456
    && Integer(App.LoginProfile.Points["email"].Color) = 0x654321)

; scaling: logout captured at 800x600 (X30,Y40); window now 400x300 → half
sp := LoginPointScreen("logout", 1000, 500, 400, 300)
Check("login-point-scaled", sp[1] = 1015 && sp[2] = 520)

; chunking: a batch bigger than LaunchMax is grouped (LaunchMax stays 4)
Config.LaunchMax := 4
groups := []
posC := 1
totalC := 10
while (posC <= totalC) {
    g := 0
    loop Min(Config.LaunchMax, totalC - posC + 1) {
        g += 1
        posC += 1
    }
    groups.Push(g)
}
Check("chunk-4-4-2", groups.Length = 3 && groups[1] = 4 && groups[2] = 4 && groups[3] = 2)

; --- Activity mode: ReapActive frees slots continuously (v0.19.3) ---
; at-goal (banked) → finished; dead-partial → requeued with time intact;
; still-going (live client, under goal) → kept for the next check.
savedGoalR := Config.SessionGoalMinutes
Config.SessionGoalMinutes := 36
raA := { Name: "raA", Email: "raa@x", Password: "p", Note: "", Class: "", Level: "", Money: "", LastLogin: "", OnlineMs: 40 * 60000 }
raB := { Name: "raB", Email: "rab@x", Password: "p", Note: "", Class: "", Level: "", Money: "", LastLogin: "", OnlineMs: 5 * 60000 }
raC := { Name: "raC", Email: "rac@x", Password: "p", Note: "", Class: "", Level: "", Money: "", LastLogin: "", OnlineMs: 0, ClientHwnd: App.Gui.Hwnd, ClientSession: 99, LinkTime: A_TickCount - 5 * 60000 }
raQ := []
raF := []
still := ReapActive([raA, raB, raC], raQ, raF)
Check("reap-finishes-atgoal", raF.Length = 1 && raF[1].Name = "raA")
Check("reap-requeues-dead", raQ.Length = 1 && raQ[1].Name = "raB" && raQ[1].OnlineMs = 5 * 60000)
Check("reap-keeps-going", still.Length = 1 && still[1].Name = "raC")
Config.SessionGoalMinutes := savedGoalR

; incomplete profile blocks a login run: PrepareLoginBatch (the guard
; every start path funnels through) opens setup and returns "".
App.LoginProfile := { Points: Map() }
App.LoginQueue := []
Check("launch-guard-incomplete", PrepareLoginBatch() = "" && !App.LoginRunning)
if IsObject(App.LoginSetupDlg)
    CloseLoginSetup(App.LoginSetupDlg)
try IniDelete(Config.SettingsPath, "LoginProfile")

; --- Window linking (0.6.0: no arming step) ---
; Pretend our own process is the game so the app's GUI window counts as
; a client; brief focus steal, restored implicitly when the test exits.
Config.GameProcess := "AutoHotkey64.exe"
f2 := App.Files[1]
WinActivate("ahk_id " App.Gui.Hwnd)
if WinWaitActive("ahk_id " App.Gui.Hwnd, , 3) {
    LinkActiveWindowToAccount(f2.Accounts[1])
    Check("link-tags-active-window", f2.Accounts[1].HasOwnProp("ClientHwnd")
        && f2.Accounts[1].ClientHwnd = App.Gui.Hwnd && f2.Accounts[1].ClientSession = 1)
    Check("link-marks-used", App.UsedWindowHwnds.Has(App.Gui.Hwnd))

    ; Second account pasted into the SAME window: ownership transfers
    LinkActiveWindowToAccount(f2.Accounts[2])
    Check("link-transfer", f2.Accounts[2].ClientSession = 1
        && !f2.Accounts[1].HasOwnProp("ClientHwnd"))

    ; Non-game active window links nothing. NEVER use the real game
    ; process name here: the owner usually has clients running, and
    ; MaybeAdvanceToNextClient below would ACTIVATE one of them —
    ; yanking a real game window to the front mid-test.
    Config.GameProcess := NO_SUCH_GAME
    LinkActiveWindowToAccount(f2.Accounts[1])
    Check("link-ignores-non-game", !f2.Accounts[1].HasOwnProp("ClientHwnd"))

    ; Auto-next with no game windows open: must return quietly
    App.AutoNextClient := true
    MaybeAdvanceToNextClient()
    Check("advance-quiet-no-clients", true)

    ; Off-switch short-circuits
    App.AutoNextClient := false
    MaybeAdvanceToNextClient()
    Check("advance-respects-toggle", true)
} else {
    Check("link-window-activate", false)
}

; --- day board + command palette + hover cards + search keys (v0.25.0) ---
f4 := App.Files[1]
for accX in f4.Accounts { ; clean slate: the link tests above leave links behind
    if accX.HasOwnProp("ClientHwnd")
        DetachClient(accX)
    if accX.HasOwnProp("OnlineMs")
        accX.DeleteProp("OnlineMs")
}

b := BoardBuild()
Check("board-idle", b.Total = 2 && b.Done = 0 && b.Online = 0
    && b.States[1] = "idle" && b.States[2] = "idle")
f4.Accounts[2].OnlineMs := 40 * 60000 ; over the 30-min goal
f4.Accounts[1].OnlineMs := 5 * 60000  ; partial, no client
b := BoardBuild()
Check("board-states", b.States[1] = "lost" && b.States[2] = "done"
    && b.Done = 1 && b.Online = 0)
f4.Accounts[1].ClientHwnd := App.Gui.Hwnd
f4.Accounts[1].ClientSession := 42
f4.Accounts[1].LinkTime := A_TickCount
b := BoardBuild()
Check("board-online-wins", b.States[1] = "online" && b.Online = 1)
RefreshBoard()
Check("board-cells", App.BoardAccounts.Length = 2
    && App.Controls.BoardCells[1].Visible && App.Controls.BoardCells[2].Visible
    && !App.Controls.BoardCells[3].Visible)
Check("board-cell-tip", InStr(App.Controls.BoardCells[2].TipText, "Alt")
    && InStr(App.Controls.BoardCells[2].TipText, "done"))

; hover card: everything but the password
card := AccountCardText(f4.Accounts[2])
Check("card-content", InStr(card, "b@x.com") && InStr(card, "note-b")
    && InStr(card, "Warrior") && InStr(card, "✔ done") && !InStr(card, "pw2"))

DetachClient(f4.Accounts[1])
f4.Accounts[1].DeleteProp("OnlineMs")
f4.Accounts[2].DeleteProp("OnlineMs")
RefreshBoard()

; --- v0.28.0 streamline: shared helpers ---
Check("format-hours", FormatHours(45 * 60000) = "45m" && FormatHours(90 * 60000) = "1.5h"
    && FormatHours(0) = "0m")
f4.Accounts[1].ClientHwnd := App.Gui.Hwnd
Check("account-is-online", AccountIsOnline(f4.Accounts[1]) && !AccountIsOnline(f4.Accounts[2]))
Check("online-dot-cell", InStr(BuildRowCells(1, f4.Accounts[1])[1], "●")
    && !InStr(BuildRowCells(2, f4.Accounts[2])[1], "●"))
f4.Accounts[1].DeleteProp("ClientHwnd")
Check("online-dot-clears", !InStr(BuildRowCells(1, f4.Accounts[1])[1], "●"))

f4.Accounts[1].OnlineMs := 40 * 60000
f4.Accounts[2].OnlineMs := 5 * 60000
bb := BoardBuild()
Check("board-total-ms", bb.TotalMs = 45 * 60000)
RefreshSummary()
Check("progress-is-day", App.Controls.Progress.Value = 50) ; 1 done of 2, any view
f4.Accounts[1].DeleteProp("OnlineMs")
f4.Accounts[2].DeleteProp("OnlineMs")

; pick toggle shared by list clicks and board cells
App.LoginQueue := []
TogglePickMembership(f4.Accounts[1])
Check("pick-toggle-add", App.LoginQueue.Length = 1 && App.LoginQueue[1] = f4.Accounts[1])
TogglePickMembership(f4.Accounts[1])
Check("pick-toggle-remove", App.LoginQueue.Length = 0)

; failed-drop re-add: deduped against the queue, then cleared
App.LoginQueue := [f4.Accounts[1]]
App.LoginFailedDrops := [f4.Accounts[1], f4.Accounts[2]]
ReaddFailed()
Check("readd-failed", App.LoginQueue.Length = 2 && App.LoginFailedDrops.Length = 0
    && App.LoginQueue[2] = f4.Accounts[2])
App.LoginQueue := []
RefreshPickUI()

; double-click on an unlinked row = single-account launch+login, but
; only with a complete profile — incomplete just toasts, never runs
; and never opens dialogs (accidental double-clicks must stay cheap)
App.LoginProfile := { Points: Map() }
LaunchLoginSingle(f4.Accounts[1])
Check("dblclick-launch-guard", !App.LoginRunning && !IsObject(App.LoginSetupDlg))

; search keys: Enter = jump to first match + clear, Esc = clear
ApplyFilter("alt")
Check("search-filter-narrowed", App.Displayed.Length = 2 && RowAccount(2).Name = "Alt")
SearchJumpFirst()
Check("search-jump-first", App.FilterText = "" && App.Displayed.Length = 2
    && GetCurrentAccount().Name = "Alt" && App.Controls.Search.Text = "")
ApplyFilter("alt")
SearchClear()
Check("search-esc-clears", App.FilterText = "" && App.Displayed.Length = 2)

; separator rows are skipped by arrow navigation
ApplyFilter("a") ; matches both accounts (a@x.com, b@x.com note...) in one file
Check("search-sep-first", !IsObject(RowAccount(1)) && App.CurrentDisplayPos = 2)
App.CurrentDisplayPos := 3
PreviousAccount()
Check("nav-skips-sep-up", App.CurrentDisplayPos = 2) ; row 1 is the separator — stays put
SearchClear()

; --- double-click mini queue (0.29.0): queued while a run is going ---
App.LoginProfile := { Points: Map(
    "tryagain", { X: 1, Y: 1, RefW: 800, RefH: 600, Color: "0x111111" },
    "logout",   { X: 1, Y: 1, RefW: 800, RefH: 600, Color: "0x111111" },
    "email",    { X: 1, Y: 1, RefW: 800, RefH: 600, Color: "0x111111" },
    "start",    { X: 1, Y: 1, RefW: 800, RefH: 600, Color: "0x111111" },
    "char",     { X: 1, Y: 1, RefW: 800, RefH: 600, Color: "0x111111" }) }
; LaunchLoginSingle refuses early when the launcher file is missing, which
; it always is on a machine without the game installed — so these checks
; never reached the mini queue they exist to test and had been failing on
; any clean checkout. Point it at a file that certainly exists.
savedLauncherPath := Config.LauncherPath
Config.LauncherPath := A_ScriptFullPath
App.LoginRunning := true ; simulate an active run — nothing may launch
App.PendingSingles := []
LaunchLoginSingle(f4.Accounts[2])
Check("minique-queued", App.PendingSingles.Length = 1 && App.PendingSingles[1] = f4.Accounts[2])
LaunchLoginSingle(f4.Accounts[2])
Check("minique-dedup", App.PendingSingles.Length = 1)
App.LoginQueue := [f4.Accounts[1]]
LaunchLoginSingle(f4.Accounts[1])
Check("minique-dedup-vs-run", App.PendingSingles.Length = 1) ; already in the run's queue
App.LoginQueue := []
App.LoginRunning := false
; chain skips accounts that came online while waiting (launches nothing)
f4.Accounts[2].ClientHwnd := App.Gui.Hwnd
StartNextPendingSingle()
Check("minique-skips-online", App.PendingSingles.Length = 0 && !App.LoginRunning)
Config.LauncherPath := savedLauncherPath
f4.Accounts[2].DeleteProp("ClientHwnd")
App.LoginProfile := { Points: Map() }
RefreshPickUI()

; --- routines (v0.32.0): parser is pure; the interpreter is exercised
; for real against this app's own window as the "client" ---
p1 := ParseRoutine("ref|800|600`nset|n|0`nloop|3`nadd|n|2`nendloop`nstop")
Check("routine-parse", p1.Error = "" && p1.Steps.Length = 5
    && p1.RefW = 800 && p1.RefH = 600)
Check("routine-block-jumps", p1.Steps[2].Op = "loop" && p1.Steps[2].Jump = 4
    && p1.Steps[4].Op = "endloop" && p1.Steps[4].Jump = 2)
Check("routine-depth", p1.Steps[3].Depth = 1 && p1.Steps[4].Depth = 0)

pIf := ParseRoutine("if|var|n|=|1`nset|a|1`nelse`nset|a|2`nendif")
Check("routine-if-jumps", pIf.Error = "" && pIf.Steps[1].Jump = 3 && pIf.Steps[3].Jump = 5)

Check("routine-err-unclosed", ParseRoutine("loop|2`nadd|n|1").Error != "")
Check("routine-err-orphan-else", InStr(ParseRoutine("else").Error, "without"))
Check("routine-err-unknown-op", InStr(ParseRoutine("frobnicate|1").Error, "unknown"))
Check("routine-err-bad-goto", InStr(ParseRoutine("goto|nowhere").Error, "label"))
Check("routine-ok-goto", ParseRoutine("label|top`ngoto|top").Error = "")

; text round-trip: build -> text -> parse gives the same program
rt := ParseRoutine(RoutineToText(p1))
Check("routine-roundtrip", rt.Error = "" && rt.Steps.Length = p1.Steps.Length
    && rt.Steps[2].Jump = p1.Steps[2].Jump && rt.RefW = 800)

RunProg(text) { ; helper: execute against the app window, return the vars
    prog := ParseRoutine(text)
    ctx := { Hwnd: App.Gui.Hwnd, RefW: 0, RefH: 0, Vars: Map(), Ok: false }
    res := ExecuteRoutine(prog, ctx, "test")
    return { Res: res, Vars: ctx.Vars, Err: prog.Error }
}

r := RunProg("set|n|0`nloop|5`nadd|n|2`nendloop`nstop")
Check("routine-run-loop", r.Res = "done" && r.Vars["n"] = 10)
r := RunProg("set|n|0`nloop|3`nloop|4`nadd|n|1`nendloop`nendloop")
Check("routine-run-nested-loops", r.Res = "done" && r.Vars["n"] = 12)
r := RunProg("set|n|0`nwhile|var|n|<|3`nadd|n|1`nendwhile")
Check("routine-run-while", r.Res = "done" && r.Vars["n"] = 3)
r := RunProg("set|n|0`nwhile|var|n|>|5`nadd|n|1`nendwhile")
Check("routine-run-while-never", r.Res = "done" && r.Vars["n"] = 0)
r := RunProg("set|n|0`nif|var|n|=|0`nset|a|1`nelse`nset|a|2`nendif")
Check("routine-run-if-true", r.Vars["a"] = 1)
r := RunProg("set|n|9`nif|var|n|=|0`nset|a|1`nelse`nset|a|2`nendif")
Check("routine-run-if-false", r.Vars["a"] = 2)
r := RunProg("set|n|0`nloop|10`nadd|n|1`nif|var|n|>=|4`nbreak`nendif`nendloop")
Check("routine-run-break", r.Res = "done" && r.Vars["n"] = 4)
r := RunProg("set|n|0`nset|s|0`nloop|5`nadd|n|1`nif|var|n|<=|2`ncontinue`nendif`nadd|s|1`nendloop")
Check("routine-run-continue", r.Vars["n"] = 5 && r.Vars["s"] = 3)
r := RunProg("set|n|0`nlabel|top`nadd|n|1`nif|var|n|<|3`ngoto|top`nendif`nstop")
Check("routine-run-goto", r.Res = "done" && r.Vars["n"] = 3)
r := RunProg("set|n|1`nfail")
Check("routine-run-fail", r.Res = "failed")
r := RunProg("set|n|0`nloop|9`nadd|n|1`nstop`nendloop")
Check("routine-run-stop-exits", r.Res = "done" && r.Vars["n"] = 1)

; --- daily activity quota (v0.38.0) ---
Check("quota-schedule", DailyQuotaCount(1) = 30 && DailyQuotaCount(2) = 10
    && DailyQuotaCount(3) = 10 && DailyQuotaCount(4) = 0 && DailyQuotaCount(7) = 0)
Check("quota-weekday-in-range", GameWeekday() >= 1 && GameWeekday() <= 7)

; eligible pool: dedup by email, exclude done + online
qf := { Name: "QF", Path: "", UnparsedCount: 0, TrailingRaw: [], Accounts: [
    { Name: "q1", Email: "q1@x", Password: "p", Note: "", Class: "", Level: "", Money: "", LastLogin: "" },
    { Name: "q2", Email: "q2@x", Password: "p", Note: "", Class: "", Level: "", Money: "", LastLogin: "", OnlineMs: 99 * 60000 }, ; done
    { Name: "q3", Email: "q3@x", Password: "p", Note: "", Class: "", Level: "", Money: "", LastLogin: "", ClientHwnd: App.Gui.Hwnd, ClientSession: 1, LinkTime: A_TickCount }, ; online
    { Name: "q4", Email: "q4@x", Password: "p", Note: "", Class: "", Level: "", Money: "", LastLogin: "" },
    { Name: "q1dup", Email: "q1@x", Password: "p", Note: "", Class: "", Level: "", Money: "", LastLogin: "" }] } ; dup email
App.Files.Push(qf)
pool := QuotaEligiblePool()
poolEmails := ""
for a in pool
    poolEmails .= a.Email ","
Check("quota-pool-excludes-done-online", !InStr(poolEmails, "q2@x") && !InStr(poolEmails, "q3@x"))
Check("quota-pool-dedup-email", (StrLen(poolEmails) - StrLen(StrReplace(poolEmails, "q1@x,", ""))) = 5) ; q1@x appears once
Check("quota-pool-has-eligible", InStr(poolEmails, "q1@x") && InStr(poolEmails, "q4@x"))

; random pick: distinct, capped at pool size
five := [{ Email: "a" }, { Email: "b" }, { Email: "c" }, { Email: "d" }, { Email: "e" }]
pick3 := QuotaPickRandom(five, 3)
seenP := Map()
for a in pick3
    seenP[a.Email] := true
Check("quota-pick-count", pick3.Length = 3 && seenP.Count = 3) ; 3 distinct
Check("quota-pick-caps-at-pool", QuotaPickRandom(five, 99).Length = 5)
Check("quota-pick-empty", QuotaPickRandom([], 5).Length = 0)

; fulfilment stamp: matches game day
App.QuotaDoneStamp := ""
Check("quota-not-fulfilled-blank", !QuotaFulfilledToday())
App.QuotaDoneStamp := GameDayStamp()
Check("quota-fulfilled-today", QuotaFulfilledToday())
App.QuotaDoneStamp := "19990101"
Check("quota-stale-stamp-not-fulfilled", !QuotaFulfilledToday())
App.QuotaDoneStamp := ""
App.Files.Pop()

; banner reflects state (built in BuildGUI, present)
Check("quota-banner-exists", App.Controls.HasOwnProp("QuotaBanner"))
RefreshQuotaBanner()
Check("quota-banner-nonempty", App.Controls.QuotaBanner.Value != "")

; --- idle auto-run decision (v0.42.0) ---
; UserWasActive/IdleBlockReason are pure enough to test without real
; idle time or a real desktop.
savedAuto := App.AutoRunWhenIdle, savedProfile := App.LoginProfile, savedLauncher := Config.LauncherPath
savedIdleMin := Config.AutoRunIdleMinutes
App.LoginRunning := false, App.MacroPlaying := false, App.IsRecording := false, App.QueueRunning := false
App.AutoRunWhenIdle := true
App.QuotaDoneStamp := ""
App.LoginProfile := { Points: Map(
    "tryagain", { X: 1, Y: 1, RefW: 8, RefH: 6, Color: "0x1" }, "logout", { X: 1, Y: 1, RefW: 8, RefH: 6, Color: "0x1" },
    "email", { X: 1, Y: 1, RefW: 8, RefH: 6, Color: "0x1" }, "start", { X: 1, Y: 1, RefW: 8, RefH: 6, Color: "0x1" },
    "char", { X: 1, Y: 1, RefW: 8, RefH: 6, Color: "0x1" }) }
Config.LauncherPath := A_ScriptDir "\Logins\Test.txt" ; a file that exists
Config.AutoRunIdleMinutes := 120
savedAway := App.AwayMs
; --- away detection must tolerate mouse jitter (v0.42.0) -----------
; MEASURED on the owner's machine: the mouse emits stray events while
; untouched, so "unbroken A_TimeIdlePhysical >= 2 h" never came true and
; idle jobs never fired. Position-based checking is the fix.
Check("away-jitter-not-activity", !UserWasActive(500, 500, 505, 497, 999999, 5000, 12))
Check("away-real-move-is-activity", UserWasActive(500, 500, 560, 500, 999999, 5000, 12))
Check("away-keypress-is-activity", UserWasActive(500, 500, 500, 500, 800, 5000, 12))
Check("away-old-keypress-not-activity", !UserWasActive(500, 500, 500, 500, 90000, 5000, 12))
Check("away-diagonal-drift-ok", !UserWasActive(500, 500, 492, 508, 999999, 5000, 12))

; --- the reason string explains every gate ---
; A guaranteed-pending job, so the reason reaches the "waiting" branch
; regardless of what weekday the suite runs on.
fakeProfile := App.LoginProfile ; (the complete 5-point stub set above)
savedJobsR := App.IdleJobs
for accX in f.Accounts { ; make sure nothing counts as "online"
    if accX.HasOwnProp("ClientHwnd")
        DetachClient(accX)
}
App.IdleJobs := [{ Name: "Pending job", Enabled: true, Kind: "chore", Macro: "m", Scope: "all", Emails: [] }]
App.IdleDone := Map(), App.IdleDoneDay := GameDayStamp()
App.AwayMs := 0
Check("reason-waiting", InStr(IdleBlockReason(), "away 0 of 120")
    && InStr(IdleBlockReason(), "Pending job"))
App.AwayMs := 121 * 60000
Check("reason-ready", IdleBlockReason() = "")
App.IdleJobs[1].Enabled := false ; nothing left to do
Check("reason-nothing-pending", InStr(IdleBlockReason(), "Nothing pending"))
App.IdleJobs[1].Enabled := true
App.AutoRunWhenIdle := false
Check("reason-autorun-off", InStr(IdleBlockReason(), "OFF"))
App.AutoRunWhenIdle := true
App.LoginRunning := true
Check("reason-busy", InStr(IdleBlockReason(), "already running"))
App.LoginRunning := false
App.LoginProfile := { Points: Map() } ; incomplete profile
Check("reason-needs-profile", InStr(IdleBlockReason(), "Login Setup"))
App.LoginProfile := fakeProfile
Config.LauncherPath := "Z:\nope\missing.exe"
Check("reason-launcher-missing", InStr(IdleBlockReason(), "Launcher not found"))
Config.LauncherPath := savedLauncher
App.IdleJobs := savedJobsR
; the idle watcher never fires under the test suite, regardless
MaybeRunIdleJobs()
Check("autorun-suppressed-in-tests", !App.LoginRunning) ; nothing launched

; the tracker freezes while our own automation runs (it moves the mouse
; itself, so a position check can't tell that from a person)
App.AwayMs := 60000, App.AwayLastTick := A_TickCount - 5000
App.AwayLastX := 100, App.AwayLastY := 100
App.LoginRunning := true
UpdateAwayTracking()
Check("away-frozen-while-busy", App.AwayMs = 60000)
App.LoginRunning := false

App.AutoRunWhenIdle := savedAuto, App.LoginProfile := savedProfile
Config.LauncherPath := savedLauncher, Config.AutoRunIdleMinutes := savedIdleMin
App.QuotaDoneStamp := "", App.AwayMs := savedAway

; tray toggles flip and persist state
Check("tray-toggle-autorun", (App.AutoRunWhenIdle := false, TrayToggleAutoRun(), App.AutoRunWhenIdle)
    && (TrayToggleAutoRun(), !App.AutoRunWhenIdle))
Check("tray-toggle-mintray", (App.MinimizeToTray := false, TrayToggleMinTray(), App.MinimizeToTray))
App.MinimizeToTray := true

; session-lock probe returns a real bool; the test session is unlocked
Check("session-lock-unlocked", SessionLocked() = false)

; startup popup is suppressed when auto-run is on (banner covers it) —
; MaybeWarnQuota must return without popping in that case. We can't test
; the MsgBox directly, but the guard is: auto-on => no popup path.
Check("warn-suppressed-when-autorun", App.AutoRunWhenIdle = false) ; (left off above)

; banner "started" state says started, not done, and invites re-run
App.QuotaDoneStamp := (DailyQuotaCount(GameWeekday()) > 0) ? GameDayStamp() : ""
RefreshQuotaBanner()
if (DailyQuotaCount(GameWeekday()) > 0)
    Check("banner-started-language", InStr(App.Controls.QuotaBanner.Value, "started")
        && !InStr(App.Controls.QuotaBanner.Value, "done"))
else
    Check("banner-started-language", true) ; not a quota day today — n/a
App.QuotaDoneStamp := ""
RefreshQuotaBanner()

; --- idle actions system (v0.40.0) ---
; save/load round-trip + default seeding
savedJobs := App.IdleJobs
App.IdleJobs := [ DefaultActivityJob()
    , { Name: "Clear mail", Enabled: true, Kind: "chore", Macro: "remove mail", Scope: "all", Emails: [] }
    , { Name: "Boss", Enabled: false, Kind: "chore", Macro: "boss", Scope: "pick", Emails: ["a@x.com", "b@x.com"] } ]
SaveIdleJobs()
App.IdleJobs := []
LoadIdleJobs()
Check("idlejobs-roundtrip", App.IdleJobs.Length = 3
    && App.IdleJobs[1].Kind = "activity" && App.IdleJobs[2].Name = "Clear mail"
    && App.IdleJobs[2].Macro = "remove mail" && !App.IdleJobs[3].Enabled
    && App.IdleJobs[3].Scope = "pick" && App.IdleJobs[3].Emails.Length = 2)
; loading a file with no activity job seeds one
App.IdleJobs := [{ Name: "Only chore", Enabled: true, Kind: "chore", Macro: "m", Scope: "all", Emails: [] }]
SaveIdleJobs()
App.IdleJobs := []
LoadIdleJobs()
hasAct := false
for j in App.IdleJobs
    if (j.Kind = "activity")
        hasAct := true
Check("idlejobs-seeds-activity", hasAct && App.IdleJobs.Length = 2)

; reserved app files in Logins root must NOT be loaded as account files
Check("reserved-files-skipped", IsReservedLoginsFile("IdleJobs.txt")
    && IsReservedLoginsFile("quota-log.txt") && !IsReservedLoginsFile("Alts.txt"))
FileOpen(Config.LoginsFolder "\IdleJobs.txt", "w", "UTF-8").Write("junk|not|accounts")
FileOpen(Config.LoginsFolder "\quota-log.txt", "w", "UTF-8").Write("2026-01-01 log line")
LoadLoginFiles()
badFile := false
for ff in App.Files
    if (ff.Name = "IdleJobs" || ff.Name = "quota-log")
        badFile := true
Check("reserved-not-parsed-as-accounts", !badFile)
f := App.Files[1] ; LoadLoginFiles rebuilt App.Files — re-point the stale handle

; scope resolution + pending (fixture file has a@x.com, b@x.com)
jobAll := { Name: "T", Enabled: true, Kind: "chore", Macro: "m", Scope: "all", Emails: [] }
jobPick := { Name: "P", Enabled: true, Kind: "chore", Macro: "m", Scope: "pick", Emails: ["a@x.com"] }
Check("idle-scope-all", IdleScopeAccounts(jobAll).Length = 2)
Check("idle-scope-pick", IdleScopeAccounts(jobPick).Length = 1
    && IdleScopeAccounts(jobPick)[1].Email = "a@x.com")

; done-tracking excludes handled accounts; game-day scoped
App.IdleDone := Map(), App.IdleDoneDay := GameDayStamp()
Check("chore-pending-full", ChorePendingAccounts(jobAll).Length = 2)
MarkIdleDone(jobAll, f.Accounts[1])
Check("chore-pending-after-done", ChorePendingAccounts(jobAll).Length = 1
    && IsIdleDone(jobAll, f.Accounts[1]) && !IsIdleDone(jobAll, f.Accounts[2]))
; online accounts are skipped too (busy)
f.Accounts[2].ClientHwnd := App.Gui.Hwnd
Check("chore-pending-skips-online", ChorePendingAccounts(jobAll).Length = 0)
f.Accounts[2].DeleteProp("ClientHwnd")
ResetIdleDone()
Check("idle-done-reset", ChorePendingAccounts(jobAll).Length = 2)

; job selection by priority: first enabled job with pending work
App.IdleJobs := [ { Name: "off", Enabled: false, Kind: "chore", Macro: "m", Scope: "all", Emails: [] }
    , { Name: "nomacro", Enabled: true, Kind: "chore", Macro: "", Scope: "all", Emails: [] }
    , { Name: "good", Enabled: true, Kind: "chore", Macro: "m", Scope: "all", Emails: [] } ]
Check("next-idle-job-priority", NextIdleJob().Name = "good") ; skips off + no-macro
App.IdleJobs[3].Enabled := false
Check("next-idle-job-none", NextIdleJob() = "")
App.IdleJobs := savedJobs

; does-text renders macro + scope for chores, and the quota for activity
Check("idle-does-text", InStr(IdleJobDoesText(jobAll), "'m' on all accounts")
    && InStr(IdleJobDoesText(DefaultActivityJob()), "quota"))

; history recorder: appends to the bounded in-memory list + a real bool
App.IdleHistory := []
IdleHist("Job A", "one@x", "ok", "did the thing")
IdleHist("Job A", "two@x", "fail", "login failed")
Check("history-records", App.IdleHistory.Length = 2
    && App.IdleHistory[1].Result = "ok" && App.IdleHistory[2].Who = "two@x"
    && App.IdleHistory[2].Result = "fail")
; bounded at 500
loop 600
    IdleHist("bulk", "x", "info", A_Index)
Check("history-bounded", App.IdleHistory.Length = 500
    && App.IdleHistory[500].Detail = 600) ; newest kept
App.IdleHistory := []
; idle-history.txt is reserved (never an account file)
Check("history-file-reserved", IsReservedLoginsFile("idle-history.txt"))

; countdown grace = 0 fires immediately (no window); >0 arms the state.
; (We don't drive the timer/GUI here — that's manual-verify.)
Check("countdown-off-default-fires", Config.IdleGraceSeconds >= 0) ; sanity: tunable exists

; --- waitpixel timeout behaviour (v0.36.0) ---
; A colour that cannot match (the app window is never pure magenta at
; 5,5), so every wait below times out after ~0ms and takes its branch.
NEVER := "5|5|0xFF00FF|0|0"
r := RunProg("waitpixel|" NEVER "|fail`nset|after|1")
Check("waitpixel-fail-stops", r.Res = "failed" && !r.Vars.Has("after"))
r := RunProg("waitpixel|" NEVER "|stop`nset|after|1")
Check("waitpixel-stop-ends", r.Res = "done" && !r.Vars.Has("after"))
r := RunProg("waitpixel|" NEVER "|continue`nset|after|1")
Check("waitpixel-continue-carries-on", r.Res = "done" && r.Vars["after"] = 1)
; routines saved before this change (5 args, no behaviour) must not break
r := RunProg("waitpixel|" NEVER "`nset|after|1")
Check("waitpixel-legacy-carries-on", r.Res = "done" && r.Vars["after"] = 1)
; and the flag is still there to branch on
r := RunProg("waitpixel|" NEVER "|continue`nif|notok`nset|caught|1`nendif")
Check("waitpixel-sets-notok", r.Vars["caught"] = 1)
; a wait that DOES match continues normally and sets ok
okPix := RunTraced("waitpixel|5|5|" PixelGetColor(0, 0) "|255|500|fail`nset|after|1")
Check("waitpixel-match-continues", okPix.Res = "done" && okPix.Vars["after"] = 1)
Check("waitpixel-step-text-shows-behaviour",
    InStr(RoutineStepText({ Op: "waitpixel", Args: ["1", "2", "0x0", "24", "800", "fail"], Depth: 0 }), "else FAIL")
    && InStr(RoutineStepText({ Op: "waitpixel", Args: ["1", "2", "0x0", "24", "800"], Depth: 0 }), "carry on"))

; --- pointer restore after playback (v0.35.2) ---
; The pointer must NOT snap back instantly: the game is still processing
; the final click and would register it at the pointer's destination.
savedRestore := Config.MouseRestoreDelayMs
MouseMove(500, 500, 0)
Config.MouseRestoreDelayMs := 0
Check("pointer-restore-off", !RestorePointerAfterPlayback(200, 200))
MouseGetPos(&prx, &pry)
; Tolerance, not equality: this machine's mouse emits stray events (see
; gotcha #20), which nudged the cursor a pixel and failed an exact
; check. The bug this guards against would have moved it to 200,200.
Check("pointer-untouched-when-off", Abs(prx - 500) <= 25 && Abs(pry - 500) <= 25)
Config.MouseRestoreDelayMs := 120
t0 := A_TickCount
Check("pointer-restore-on", RestorePointerAfterPlayback(320, 240))
elapsed := A_TickCount - t0
MouseGetPos(&prx2, &pry2)
Check("pointer-moved-back", Abs(prx2 - 320) <= 25 && Abs(pry2 - 240) <= 25) ; tolerance: see above
Check("pointer-restore-waits", elapsed >= 100) ; settle pause actually happened
Config.MouseRestoreDelayMs := savedRestore
Check("pointer-delay-is-tunable", InStr(StrJoin(TuningKeys(), ","), "MouseRestoreDelayMs"))

TuningKeys() {
    out := []
    for item in TuningSchema()
        out.Push(item.Key)
    return out
}

; --- tracing + dry run (v0.34.0) ---
RunTraced(text, dry := false) {
    prog := ParseRoutine(text)
    ctx := NewRoutineContext(App.Gui.Hwnd, 0, 0, 500, dry)
    res := ExecuteRoutine(prog, ctx, "traced")
    joined := ""
    for line in ctx.Trace
        joined .= line "`n"
    return { Res: res, Vars: ctx.Vars, Trace: ctx.Trace, Text: joined }
}

t := RunTraced("set|n|1`nif|var|n|=|1`nset|a|1`nelse`nset|a|2`nendif")
Check("trace-records-steps", t.Trace.Length >= 3)
Check("trace-names-branch", InStr(t.Text, "TRUE") && InStr(t.Text, "taking this branch"))
Check("trace-shows-values", InStr(t.Text, "a = 1") || InStr(t.Text, "n = 1"))
t := RunTraced("set|n|9`nif|var|n|=|1`nset|a|1`nelse`nset|a|2`nendif")
Check("trace-names-else-branch", InStr(t.Text, "jumping to 'otherwise'"))
t := RunTraced("set|n|0`nrepeat|2|var|n|>=|9`nadd|n|1`nendrepeat")
Check("trace-shows-giveup", InStr(t.Text, "GAVE UP"))
t := RunTraced("set|n|0`nloop|3`nadd|n|1`nbreak`nendloop`nfail")
Check("trace-shows-failure-point", InStr(t.Text, "reported FAILURE") && t.Res = "failed")

; the trace is bounded — a long loop can't grow it without limit
t := RunTraced("set|n|0`nloop|900`nadd|n|1`nendloop")
Check("trace-bounded", t.Vars["n"] = 900 && t.Trace.Length <= 1000)

; DRY RUN: conditions are really evaluated, but nothing is performed —
; a run step naming a macro that doesn't exist would fail for real, yet
; passes dry, which proves no macro was played.
Check("dry-run-skips-actions",
    RunTraced("run|NoSuchMacroAnywhere|1`nstop", true).Res = "done")
Check("real-run-would-fail",
    RunTraced("run|NoSuchMacroAnywhere|1`nstop", false).Res = "failed")
t := RunTraced("set|n|1`nif|var|n|=|1`nclick|10|20`nendif`nwaitsec|30", true)
Check("dry-run-marks-skips", InStr(t.Text, "dry run") && t.Res = "done")
Check("dry-run-still-branches", InStr(t.Text, "TRUE"))

; retry block (v0.33.0): body runs, condition is tested AFTER each pass,
; gives up after N attempts and reports through `ok`
r := RunProg("set|n|0`nrepeat|3|var|n|>=|2`nadd|n|1`nendrepeat`nif|ok`nset|res|1`nelse`nset|res|0`nendif")
Check("routine-repeat-succeeds", r.Res = "done" && r.Vars["n"] = 2 && r.Vars["res"] = 1)
r := RunProg("set|n|0`nrepeat|3|var|n|>=|99`nadd|n|1`nendrepeat`nif|notok`nset|res|1`nendif")
Check("routine-repeat-gives-up", r.Res = "done" && r.Vars["n"] = 3 && r.Vars["res"] = 1)
r := RunProg("set|n|0`nrepeat|5|var|n|>=|1`nadd|n|1`nendrepeat")
Check("routine-repeat-runs-body-once", r.Vars["n"] = 1) ; test is at the END
r := RunProg("set|n|0`nloop|2`nrepeat|2|var|n|>=|99`nadd|n|1`nendrepeat`nendloop")
Check("routine-repeat-nested-in-loop", r.Vars["n"] = 4)
pRep := ParseRoutine("repeat|3|pixel|1|2|0x00FF00|24`nwait|100`nendrepeat")
Check("routine-repeat-parses", pRep.Error = "" && pRep.Steps[1].Jump = 3
    && pRep.Steps[3].Jump = 1 && pRep.Steps[2].Depth = 1)
Check("routine-repeat-unclosed", ParseRoutine("repeat|2|ok`nwait|10").Error != "")

; new client / seconds instructions parse and price sensibly
Check("routine-client-ops-parse",
    ParseRoutine("waitsec|3`nlog|hello`ncloseclient").Error = ""
    && ParseRoutine("restartclient").Error = "")

; session-aware conditions read the account behind the client window
accR := App.Files[1].Accounts[1]
accR.ClientHwnd := App.Gui.Hwnd
accR.ClientSession := 55
accR.LinkTime := A_TickCount
accR.OnlineMs := 5 * 60000 ; 25 min left of a 30 min goal
ctxR := { Hwnd: App.Gui.Hwnd, RefW: 0, RefH: 0, Vars: Map(), Ok: false }
Check("routine-cond-notdone", EvalRoutineCondition(["notdone"], ctxR)
    && !EvalRoutineCondition(["done"], ctxR))
Check("routine-cond-minsleft", EvalRoutineCondition(["minsleft", ">=", "20"], ctxR)
    && !EvalRoutineCondition(["minsleft", "<", "10"], ctxR))
Check("routine-finds-account-by-hwnd", FindAccountByHwnd(App.Gui.Hwnd) = accR
    && FindAccountByHwnd(999999) = "")
accR.OnlineMs := 40 * 60000
Check("routine-cond-done", EvalRoutineCondition(["done"], ctxR))
; closing a client from a routine must BANK the time (DetachClient), not
; drop the link raw. Uses a throwaway window as the "client" — pointing
; it at App.Gui would close the app mid-test.
tmpClient := Gui("+ToolWindow", "AQ test client")
tmpClient.Show("w120 h60")
accR.ClientHwnd := tmpClient.Hwnd
accR.LinkTime := A_TickCount
RoutineCloseClient(tmpClient.Hwnd, "test")
Check("routine-close-banks-time", !accR.HasOwnProp("ClientHwnd")
    && accR.OnlineMs >= 40 * 60000)
try tmpClient.Destroy()
accR.DeleteProp("OnlineMs")

; conditions that don't need pixels
ctxC := { Hwnd: App.Gui.Hwnd, RefW: 0, RefH: 0, Vars: Map("n", 5), Ok: true }
Check("routine-cond-var-ops", EvalRoutineCondition(["var", "n", "=", "5"], ctxC)
    && EvalRoutineCondition(["var", "n", ">=", "5"], ctxC)
    && EvalRoutineCondition(["var", "n", "!=", "4"], ctxC)
    && !EvalRoutineCondition(["var", "n", "<", "5"], ctxC))
Check("routine-cond-missing-var-is-zero", EvalRoutineCondition(["var", "zz", "=", "0"], ctxC))
Check("routine-cond-ok", EvalRoutineCondition(["ok"], ctxC) && !EvalRoutineCondition(["notok"], ctxC))
Check("routine-cond-window", EvalRoutineCondition(["window"], ctxC)
    && !EvalRoutineCondition(["notwindow"], ctxC))
Check("routine-cond-chance-bounds", EvalRoutineCondition(["chance", "100"], ctxC)
    && !EvalRoutineCondition(["chance", "0"], ctxC))
Check("routine-cond-unknown-false", !EvalRoutineCondition(["nonsense"], ctxC))

; runaway guard: an endless loop stops instead of hanging
savedMax := Config.RoutineMaxSteps
Config.RoutineMaxSteps := 500
r := RunProg("loop|0`nadd|n|1`nendloop")
Check("routine-step-budget", r.Res = "failed")
Config.RoutineMaxSteps := savedMax

; saved routines are found, dispatched to, and priced by name
DirCreate(Config.RoutinesFolder)
FileOpen(Config.RoutinesFolder "\UnitRoutine.txt", "w", "UTF-8").Write("ref|0|0`nwait|1500`nstop")
Check("routine-is-detected", IsRoutineName("UnitRoutine") && !IsRoutineName("TestMacro"))
Check("routine-in-choices", InStr(StrJoin(AutomationNames(), ","), "UnitRoutine"))
Check("routine-duration-estimate", AutomationDurationMs("UnitRoutine") >= 1500)
FileDelete(Config.RoutinesFolder "\UnitRoutine.txt")

StrJoin(arr, sep) {
    out := ""
    for v in arr
        out .= (out = "" ? "" : sep) v
    return out
}

FileAppend(results, A_ScriptDir "\test-results.txt")
AQRestoreForeground() ; hand the foreground back to whatever the user was on
OnAppClose()
