; --- visual fixture (not part of run-tests.ps1 — stays open for manual/screenshot use) ---
DirCreate(A_ScriptDir "\Logins")
__fx := FileOpen(A_ScriptDir "\Logins\Test.txt", "w", "UTF-8")
__fx.Write("; header comment`nMain|a@x.com|pw1`nLuo|b@x.com|pw2|note-b`nMommo|c@x.com|pw3`nPrincess|d@x.com|pw4")
__fx.Close()
try FileDelete(A_ScriptDir "\Logins\Settings.ini")

#Include ..\AccountQueue.ahk

; Visual fixture for the Session view color language:
; row 1 (selected): never started — default/selection colors
; row 2: online 12 min — AMBER
; row 3: lost its client at 7 min — RED with ⚠
; row 4: 34 min — GREEN, ✔ done

f := App.Files[1]

a2 := f.Accounts[2]
a2.ClientHwnd := App.Gui.Hwnd
a2.ClientSession := 1
a2.LinkTime := A_TickCount - 12 * 60000

a3 := f.Accounts[3]
a3.OnlineMs := 7 * 60000
a3.LastLogin := "2026-07-10 02:41"

a4 := f.Accounts[4]
a4.ClientHwnd := App.Gui.Hwnd
a4.ClientSession := 2
a4.LinkTime := A_TickCount - 34 * 60000
a4.LastLogin := "2026-07-10 02:30"

SetViewMode("session", false)
UpdateAllRowsInPlace()
RefreshSummary()
; stays open for the screenshot
