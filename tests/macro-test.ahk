; --- self-contained fixture: fresh sandbox Logins next to this test ---
DirCreate(A_ScriptDir "\Logins")
__fx := FileOpen(A_ScriptDir "\Logins\Test.txt", "w", "UTF-8")
__fx.Write("; header comment`n`nMain|a@x.com|pw1`nbadline|only2fields`nAlt|b@x.com|pw2|note-b|Warrior|80|123k|2026-07-01 10:00`n; trailing comment")
__fx.Close()
try FileDelete(A_ScriptDir "\Logins\Settings.ini")
FileOpen(A_ScriptDir "\Logins\Settings.ini", "w", "UTF-8").Write("[Preferences]`nAlwaysOnTop=0`n")
try FileDelete(A_ScriptDir "\macro-results.txt")

OnError(MErr)
MErr(err, mode) {
    try FileAppend("ERROR: " err.Message " @ line " err.Line "`n", A_ScriptDir "\macro-results.txt")
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
MCheck(label, cond) {
    global results
    results .= label ": " (cond ? "PASS" : "FAIL") "`n"
}
HasInArray(arr, v) {
    for x in arr
        if (x = v)
            return true
    return false
}

MCheck("sanitize", SanitizeMacroName(' a/b:c*d?"e<f>g|h ') = "abcdefgh")

steps := [{X: 10, Y: 20, Delay: 0}, {X: 30, Y: 40, Delay: 250}]
SaveMacroFile("TestMacro", steps, 200, 150)
m := LoadMacroFile("TestMacro")
MCheck("roundtrip", m.RefW = 200 && m.RefH = 150 && m.Steps.Length = 2
    && m.Steps[2].X = 30 && m.Steps[2].Y = 40 && m.Steps[2].Delay = 250)
MCheck("scan", HasInArray(ScanMacros(), "TestMacro"))

p := MacroStepScreenPos({X: 100, Y: 75}, 200, 150, 1000, 500, 400, 300)
MCheck("scale-2x", p[1] = 1200 && p[2] = 650)
p2 := MacroStepScreenPos({X: 100, Y: 75}, 200, 150, 1000, 500, 200, 150)
MCheck("scale-1x", p2[1] = 1100 && p2[2] = 575)
p3 := MacroStepScreenPos({X: 100, Y: 75}, 0, 0, 50, 60, 400, 300)
MCheck("scale-noref", p3[1] = 150 && p3[2] = 135)

; Two borderless capture windows logging the client coords they receive
global clickLog := Map()
OnMessage(0x0201, CaptureClick) ; WM_LBUTTONDOWN
CaptureClick(wParam, lParam, msg, hwnd) {
    global clickLog
    if clickLog.Has(hwnd)
        clickLog[hwnd].Push([lParam & 0xFFFF, (lParam >> 16) & 0xFFFF])
}
global t1 := Gui("-Caption +AlwaysOnTop +ToolWindow", "MacroTarget1")
global t2 := Gui("-Caption +AlwaysOnTop +ToolWindow", "MacroTarget2")
t1.BackColor := "334455"
t2.BackColor := "554433"
t1.Show("x60 y60 w200 h150 NA")
t2.Show("x300 y60 w200 h150 NA")
clickLog[t1.Hwnd] := []
clickLog[t2.Hwnd] := []
Sleep(200)

; --- direct single run ---
tick0 := A_TickCount
r := RunMacroOnWindow("TestMacro", t1.Hwnd)
elapsed := A_TickCount - tick0
Sleep(200)
got := clickLog[t1.Hwnd]
MCheck("run-result-done", r = "done")
MCheck("clicks-received", got.Length = 2)
if (got.Length = 2) {
    MCheck("click1-pos", Abs(got[1][1] - 10) <= 2 && Abs(got[1][2] - 20) <= 2)
    MCheck("click2-pos", Abs(got[2][1] - 30) <= 2 && Abs(got[2][2] - 40) <= 2)
    MCheck("delay-respected", elapsed >= 350)
}
MCheck("playing-flag-cleared", !App.MacroPlaying)

; --- queue: live job, dead job (must fail and continue), live job ---
clickLog[t1.Hwnd] := []
EnqueueMacroJob("TestMacro", t1.Hwnd, "one")
EnqueueMacroJob("TestMacro", 999999, "ghost")
EnqueueMacroJob("TestMacro", t2.Hwnd, "two")
MCheck("queue-length", App.Queue.Length = 3)

StartQueue()
deadline := A_TickCount + 30000
while (App.QueueRunning && A_TickCount < deadline)
    Sleep(100)
Sleep(200)

MCheck("queue-finished", !App.QueueRunning && !App.QueuePaused)
MCheck("queue-job1-done", App.Queue[1].Status = "done")
MCheck("queue-job2-failed", App.Queue[2].Status = "failed")
MCheck("queue-job3-done", App.Queue[3].Status = "done")
MCheck("queue-clicks-t1", clickLog[t1.Hwnd].Length = 2)
MCheck("queue-clicks-t2", clickLog[t2.Hwnd].Length = 2)

ClearQueue()
MCheck("queue-cleared", App.Queue.Length = 0)

; --- nested runs must NOT restore the pointer (0.37.0 regression) ---
; A macro/routine invoked from inside a routine leaves the pointer where
; it ended; only the OUTERMOST run parks it back. Restoring on every
; nested call both slowed routines and re-fired the "last click lands at
; the moved pointer" bug. TestMacro's last click is client (30,40); at
; 1:1 scale that's screen (t1x+30, t1y+40).
clickLog[t1.Hwnd] := []
savedDelay := Config.MouseRestoreDelayMs
Config.MouseRestoreDelayMs := 150
CoordMode("Mouse", "Screen")
WinGetPos(&t1x, &t1y, , , "ahk_id " t1.Hwnd)
; nested: pointer should end at the macro's last click, not back home
MouseMove(920, 920, 0)
RunMacroOnWindow("TestMacro", t1.Hwnd, true)
MouseGetPos(&nx, &ny)
MCheck("nested-leaves-pointer", Abs(nx - (t1x + 30)) <= 4 && Abs(ny - (t1y + 40)) <= 4)
; outermost: pointer should be parked back where it started
MouseMove(920, 920, 0)
RunMacroOnWindow("TestMacro", t1.Hwnd)
MouseGetPos(&ox2, &oy2)
MCheck("outer-restores-pointer", Abs(ox2 - 920) <= 4 && Abs(oy2 - 920) <= 4)
Config.MouseRestoreDelayMs := savedDelay

t1.Destroy()
t2.Destroy()
Sleep(100)
RunMacroOnWindow("TestMacro", 999999)
MCheck("dead-window-graceful", !App.MacroPlaying)

try FileDelete(Config.MacrosFolder "\TestMacro.txt")
FileAppend(results, A_ScriptDir "\macro-results.txt")
AQRestoreForeground()
ExitApp()
