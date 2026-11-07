; --- self-contained fixture: fresh sandbox Logins next to this test ---
DirCreate(A_ScriptDir "\Logins")
__fx := FileOpen(A_ScriptDir "\Logins\Test.txt", "w", "UTF-8")
__fx.Write("; header comment`n`nMain|a@x.com|pw1`nbadline|only2fields`nAlt|b@x.com|pw2|note-b|Warrior|80|123k|2026-07-01 10:00`n; trailing comment")
__fx.Close()
try FileDelete(A_ScriptDir "\Logins\Settings.ini")
FileOpen(A_ScriptDir "\Logins\Settings.ini", "w", "UTF-8").Write("[Preferences]`nAlwaysOnTop=0`n")
try FileDelete(A_ScriptDir "\audit-results.txt")

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

; Measures the real built layout at design size: every below-list control
; must sit below the list, nothing may overflow the client area, and the
; last control should end near the bottom (no big dead zone, no cutoff).

res := ""
App.Gui.GetClientPos(, , &cw, &ch)
App.Controls.List.GetPos(, &ly, , &lh)
listBottom := ly + lh
res .= "client=" cw "x" ch " list y=" ly " h=" lh " bottom=" listBottom "`n"

maxBottom := 0
aboveList := 0
for item in App.Layout.Below {
    item.Ctrl.GetPos(&cx, &cy, &cwid, &chgt)
    if (cy < listBottom)
        aboveList += 1
    if (cy + chgt > maxBottom)
        maxBottom := cy + chgt
}
res .= "below-list controls: " App.Layout.Below.Length ", above-list violations: " aboveList
    . " => " (aboveList = 0 ? "PASS" : "FAIL") "`n"
gap := ch - maxBottom
res .= "content ends at " maxBottom " of " ch " (bottom gap " gap ") => "
    . ((gap >= 6 && gap <= 40) ? "PASS" : "TUNE") "`n"

; stat strip + count line: count must be right-anchored, past the strip
App.Controls.StatMoney.GetPos(&sx, &sy, &sw)
App.Controls.CountLabel.GetPos(&kx, &ky, &kw)
res .= "strip-end x=" (sx + sw) " | count x=" kx " w=" kw " rightEdge=" (kx + kw)
    . " => " ((kx >= sx + sw && Abs((kx + kw) - (cw - 16)) <= 2) ? "PASS" : "FAIL") "`n"

FileAppend(res, A_ScriptDir "\audit-results.txt")
AQRestoreForeground()
ExitApp()
