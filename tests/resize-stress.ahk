; --- self-contained fixture: fresh sandbox Logins next to this test ---
DirCreate(A_ScriptDir "\Logins")
__fx := FileOpen(A_ScriptDir "\Logins\Test.txt", "w", "UTF-8")
__fx.Write("; header comment`n`nMain|a@x.com|pw1`nbadline|only2fields`nAlt|b@x.com|pw2|note-b|Warrior|80|123k|2026-07-01 10:00`n; trailing comment")
__fx.Close()
try FileDelete(A_ScriptDir "\Logins\Settings.ini")
FileOpen(A_ScriptDir "\Logins\Settings.ini", "w", "UTF-8").Write("[Preferences]`nAlwaysOnTop=0`n")
try FileDelete(A_ScriptDir "\stress-results.txt")
try FileDelete(A_ScriptDir "\stress-progress.txt")

; Registered BEFORE the include so it catches errors thrown from GUI
; event threads (which otherwise pop a blocking error dialog).
OnError(StressErrHandler)
StressErrHandler(err, mode) {
    try FileAppend("ERROR: " err.Message " @ line " err.Line " (" err.What ")`n", A_ScriptDir "\stress-results.txt")
    ExitApp(1)
}
StressLog(msg) {
    try FileAppend(msg "`n", A_ScriptDir "\stress-progress.txt")
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

StressLog("startup complete")

sizes := [[560, 700], [900, 1000], [420, 600], [800, 640], [620, 860], [500, 980], [740, 700]]
for s in sizes {
    App.Gui.Show("w" s[1] " h" s[2] " NoActivate")
    Sleep(60)
    StressLog("resized to " s[1] "x" s[2])
}

res := ""
App.Gui.GetClientPos(, , &cw, &ch)
App.Controls.List.GetPos(, , &lw, &lh)
expectedH := Max(120, App.Layout.ListH0 + (ch - Config.WindowHeight))
res .= "final client=" cw "x" ch " listH=" lh " expected=" expectedH
    . " => " (Abs(lh - expectedH) <= 2 ? "PASS" : "FAIL") "`n"
res .= "listW: " (Abs(lw - (cw - 32)) <= 2 ? "PASS" : "FAIL") "`n"

deltaY := lh - App.Layout.ListH0
allOk := true
for item in App.Layout.Below {
    item.Ctrl.GetPos(&cx, &cy, &cwid)
    if (Abs(cy - (item.Y0 + deltaY)) > 2)
        allOk := false, res .= "Y drift: " cy " vs " (item.Y0 + deltaY) "`n"
    if (item.FullWidth && Abs(cwid - (cw - 32)) > 2)
        allOk := false, res .= "W drift: " cwid " vs " (cw - 32) "`n"
}
res .= "after-stress layout: " (allOk ? "PASS" : "FAIL") "`n"

App.Gui.Show("w620 h860 NoActivate")
Sleep(60)
App.Controls.List.GetPos(, , , &lh2)
res .= "back-to-design listH=" lh2 " => " (Abs(lh2 - App.Layout.ListH0) <= 2 ? "PASS" : "FAIL") "`n"

FileAppend(res, A_ScriptDir "\stress-results.txt")
AQRestoreForeground()
ExitApp()
