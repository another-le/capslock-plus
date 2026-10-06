param(
    [string]$AhkPath = 'C:\Program Files\AutoHotkey\AutoHotkey.exe'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$upstream = [IO.File]::ReadAllText((Join-Path $projectRoot 'references\Lexikos-Gestures\Gestures.ahk')).Replace("`r`n", "`n")
$engine = [IO.File]::ReadAllText((Join-Path $projectRoot 'lib\vendor\LexikosGestureEngine.ahk')).Replace("`r`n", "`n")
$coreStart = $upstream.IndexOf("CancelGesture:`n")
$coreEnd = $upstream.IndexOf("/*`n * Tray icon maintenance", $coreStart)
if ($coreStart -lt 0 -or $coreEnd -lt 0) { throw 'Upstream core boundaries not found.' }
$originalCore = $upstream.Substring($coreStart, $coreEnd - $coreStart).Trim()
$importedCore = $engine.Substring($engine.IndexOf("CancelGesture:`n")).Trim()
$drawHook = '            mouseGesture_lexTrailDraw(x, y)  ; CapsLock+ renderer adapter.' + "`n"
$stopHook = '    mouseGesture_trailStop()  ; CapsLock+ renderer cleanup.' + "`n"
$hintUpdateHook = '                    mouseGesture_hintUpdate()  ; CapsLock+ live action preview.' + "`n"
$hintStopHook = '    mouseGesture_hintStop()  ; CapsLock+ preview cleanup.' + "`n"
$releaseHintStopHook = '    mouseGesture_hintStop()  ; Release-endpoint sampling can re-show the hint after button-up.' + "`n"
$movedResetHook = '    mouseGestureMoved:=false  ; CapsLock+ distinguishes a click from a real drag.' + "`n"
$movedExitHook = '    if (m_LastGestureKey="RButton" && mouseGestureMoved)' + "`n" + '        sendkey:=false  ; Only an unmoved press/release may become a right click.' + "`n"
$rightButtonReplayAdaptation = @'
    if (m_LastGestureKey="RButton" && sendkey && !m_WaitForRelease)
    {
        mouseGesture_replayRightClick()
        m_PassKeyUp:=false
        m_WaitForRelease:=false
        return
    }
'@ -replace "`r`n", "`n"
$unadaptedCore = $importedCore.Replace($drawHook, '').Replace($stopHook, '').Replace($hintUpdateHook, '').Replace($hintStopHook, '').Replace($movedResetHook, '').Replace($movedExitHook, '')
$unadaptedCore = $unadaptedCore.Replace("`n" + $releaseHintStopHook + "`n", "`n")
$unadaptedCore = $unadaptedCore.Replace($rightButtonReplayAdaptation + "`n", '')
$unadaptedCore = $unadaptedCore.Replace('m_LastGestureKey := "RButton"  ; CapsLock+ only registers the right button.', 'm_LastGestureKey := A_ThisHotkey')
$unadaptedCore = $unadaptedCore.Replace('Hotkey, *%m_LastGestureKey% Up, GestureKey_Up, On  ; Withhold native release in every app.', 'Hotkey, *%m_LastGestureKey% Up, GestureKey_Up, On')
if ($unadaptedCore -cne $originalCore) {
    throw 'Imported core differs from upstream beyond the documented host adaptations.'
}
Write-Output 'PASS: imported recognition and lifecycle code match upstream after host adaptations.'

# Inject only input, time and native-event recording into an isolated copy.
# The recognition loop, angle/zone functions and lifecycle decisions stay unchanged.
$fixtureCore = $importedCore.Replace('MouseGetPos, lastX, lastY', 'LexTest_ReadPointer(lastX, lastY)')
$fixtureCore = $fixtureCore.Replace('MouseGetPos, x, y', 'LexTest_ReadPointer(x, y)')
$fixtureCore = $fixtureCore.Replace('MouseGetPos, m_EndX, m_EndY', 'LexTest_ReadPointer(m_EndX, m_EndY)')
$fixtureCore = $fixtureCore.Replace('Sleep, m_Interval', 'LexTest_Step()')
$fixtureCore = $fixtureCore.Replace('MouseClick, %btn%, m_StartX, m_StartY,, 1, D', 'LexTest_Replay("down", m_StartX, m_StartY)')
$fixtureCore = $fixtureCore.Replace('MouseMove, m_EndX, m_EndY', 'LexTest_Replay("move", m_EndX, m_EndY)')
$fixtureCore = $fixtureCore.Replace('MouseClick, %btn%, m_EndX, m_EndY,,, U', 'LexTest_Replay("up", m_EndX, m_EndY)')
$fixtureCore = $fixtureCore.Replace('Hotkey, %A_ThisHotkey%, Off', 'LexTest_ReleaseHookDisabled:=true')
$fixtureCore = $fixtureCore.Replace('Send {Blind}{%m_LastGestureKey% Up}', 'LexTest_Replay("up", m_EndX, m_EndY)')

$adapter = [IO.File]::ReadAllText((Join-Path $projectRoot 'lib\lib_mouseGesture.ahk')).Replace("`r`n", "`n")
$functions = $adapter.Substring(0, $adapter.IndexOf("#If mouseGesture_isGestureWindow()"))
if ($adapter -notmatch '(?m)^#If mouseGesture_isGestureWindow\(\)\nRButton::$' -or $adapter -match '(?m)^~RButton::$' -or $engine -notmatch 'Hotkey, \*%m_LastGestureKey% Up, GestureKey_Up, On') {
    throw 'Right-button press and release must be withheld in every gesture-enabled application.'
}
if ($adapter -notmatch 'if action = 8\s+SendEvent, \^\{PgDn\}' -or $adapter -notmatch 'if action = 7\s+SendEvent, \^\{PgUp\}') {
    throw 'Chrome tab gestures must send page-up/page-down tab shortcuts.'
}
if ($adapter -notmatch 'if action = 3\s+SendInput, \^t\s+if action = 4') {
    throw 'New-tab gesture must only send Ctrl+T.'
}
$functions = $functions.Replace('SendEvent, {RButton Down}', 'LexTest_Replay("down", 0, 0)').Replace('SendEvent, {RButton Up}', 'LexTest_Replay("up", 0, 0)')
$dispatchStart = $functions.IndexOf('mouseGesture_dispatch(){')
$dispatchEnd = $functions.IndexOf('mouseGesture_lexTrailDraw(', $dispatchStart)
$realDispatch = $functions.Substring($dispatchStart, $dispatchEnd - $dispatchStart)
$realDispatch = $realDispatch.Replace('mouseGesture_dispatch(){', 'LexTest_RealDispatch(){').Replace('return mouseGesture_execute(', 'return LexTest_Execute(')
$testDispatch = @'
mouseGesture_dispatch(){
    global lexCaptured, m_Gesture
    lexCaptured:=StrReplace(m_Gesture, "_")
    return true
}

'@
$functions = $functions.Substring(0, $dispatchStart) + $testDispatch + $functions.Substring($dispatchEnd)
$labelStart = $adapter.IndexOf('CLMouseGesture_L:')
$labelEnd = $adapter.IndexOf('#Include', $labelStart)
$labels = $adapter.Substring($labelStart, $labelEnd - $labelStart)

$worker = @'
#NoEnv
#SingleInstance Off
SetBatchLines, -1
mouseGesture_init()
mouseGestureDrawTrail:=false
m_KeylessPrefix:="CLMouseGesture"
m_InitialTimeout:=0
m_Timeout:=0
cases:=[]
cases.Push({name:"left", path:"L", action:"L", points:[[0,0],[-30,1],[-60,-2],[-90,3]]})
cases.Push({name:"right", path:"R", action:"R", points:[[0,0],[30,0],[60,0],[90,0]]})
cases.Push({name:"down-unassigned", path:"D", action:"", points:[[0,0],[0,30],[0,60]]})
cases.Push({name:"bottom", path:"RD", action:"RD", points:[[0,0],[30,0],[60,0],[60,30],[60,60]]})
cases.Push({name:"top", path:"RU", action:"RU", points:[[0,0],[30,0],[60,0],[60,-30],[60,-60]]})
cases.Push({name:"refresh", path:"UD", action:"UD", points:[[0,0],[0,-30],[0,-60],[0,-30],[0,0]]})
cases.Push({name:"previous-tab", path:"UL", action:"UL", points:[[0,0],[0,-30],[0,-60],[-30,-60],[-60,-60]]})
cases.Push({name:"next-tab", path:"UR", action:"UR", points:[[0,0],[0,-30],[0,-60],[30,-60],[60,-60]]})
cases.Push({name:"close-tab", path:"DL", action:"DL", points:[[0,0],[0,30],[0,60],[-30,60],[-60,60]]})
cases.Push({name:"new-tab", path:"DR", action:"DR", points:[[0,0],[0,30],[0,60],[30,60],[60,60]]})
cases.Push({name:"release-endpoint", path:"L", action:"L", points:[[0,0],[-35,0]]})
cases.Push({name:"click-jitter", path:"", action:"", points:[[0,0],[2,3],[-3,4],[1,-2]]})
cases.Push({name:"jittered-refresh", path:"UD", action:"UD", points:[[0,0],[1,-30],[-2,-70],[1,-40],[0,0]]})
cases.Push({name:"angled-line", path:"R", action:"R", points:[[0,0],[40,10],[80,20]]})
cases.Push({name:"unsupported-full-sequence", path:"RDL", action:"", points:[[0,0],[30,0],[30,30],[0,30]]})
cases.Push({name:"release-timeout", path:"L", action:"", idleAge:1200, points:[[0,0],[-30,0],[-60,0],[-60,0]]})
cases.Push({name:"initial-timeout", path:"", action:"", initialTimeout:250, idleAge:350, points:[[0,0],[2,1],[2,1]]})
for caseIndex, case in cases
{
    lexFixture:=case.points
    lexIndex:=1
    lexCaptured:=""
    lexIdleAge:=case.HasKey("idleAge") ? case.idleAge : 0
    m_Timeout:=case.name="release-timeout" ? 1000 : 0
    m_InitialTimeout:=case.HasKey("initialTimeout") ? case.initialTimeout : 0
    gosub GestureKeyless
    path:=StrReplace(m_Gesture, "_")
    LexTest_Assert(path=case.path, case.name . " path: " . path)
    LexTest_Assert(lexCaptured=case.action, case.name . " action: " . lexCaptured)
}
; The real hotkey uses the keyed entry path; exercise it with the same samples.
keyedCases:=[1,6,9,12,15]
mouseGestureTarget:={process:"chrome.exe"}
for _, caseIndex in keyedCases
{
    case:=cases[caseIndex]
    lexFixture:=case.points
    lexIndex:=1
    lexCaptured:=""
    lexIdleAge:=0
    m_Timeout:=0
    m_InitialTimeout:=0
    gosub GestureKey_Down
    Hotkey, *RButton Up, GestureKey_Up, Off
    path:=StrReplace(m_Gesture, "_")
    LexTest_Assert(path=case.path, "keyed " . case.name . " path: " . path)
    LexTest_Assert(lexCaptured=case.action, "keyed " . case.name . " action: " . lexCaptured)
    LexTest_Assert(!mouseGestureHintShown, "keyed " . case.name . " must dismiss live hint on release")
}
LexTest_Assert(mouseGesture_resolveAction("DL", "chrome.exe")=9, "Chrome close-tab mapping")
LexTest_Assert(mouseGesture_resolveAction("DL", "notepad.exe")=10, "global close-window mapping")
LexTest_Assert(mouseGesture_resolveAction("DR", "chrome.exe")=3, "down-right new tab mapping")
LexTest_Assert(mouseGesture_resolveAction("D", "chrome.exe")=0, "down-alone is unassigned")
LexTest_Assert(mouseGesture_resolveAction("L", "notepad.exe")=0, "Chrome-only action scope")
LexTest_Assert(mouseGesture_resolveAction("DLR", "chrome.exe")=0, "no prefix action matching")
LexTest_Assert(!mouseGesture_acceptTarget("Shell_TrayWnd", "explorer.exe"), "taskbar retains native right click")
LexTest_Assert(!mouseGesture_acceptTarget("NotifyIconOverflowWindow", "explorer.exe"), "tray overflow retains native right click")
LexTest_Assert(!mouseGesture_acceptTarget("ToolbarWindow32", "explorer.exe"), "shell child cannot masquerade as file manager")
LexTest_Assert(mouseGesture_acceptTarget("CabinetWClass", "explorer.exe"), "Explorer file window keeps gestures")
LexTest_Assert(mouseGesture_acceptTarget("Chrome_WidgetWin_1", "chrome.exe"), "Chrome keeps gestures")
mouseGestureTarget:={process:"explorer.exe", hwnd:123, class:"CabinetWClass"}
m_Gesture:="_D_L"
lexExecuted:=""
LexTest_Assert(LexTest_RealDispatch(), "Explorer close-window dispatch")
LexTest_Assert(lexExecuted="DL:explorer.exe", "Explorer action target")
mouseGestureDrawTrail:=false
mouseGestureMoved:=false
m_LastGestureKey:="RButton", m_WaitForRelease:=true
m_StartX:=0, m_StartY:=0
mouseGesture_lexTrailDraw(50, 0)
LexTest_Assert(mouseGestureMoved, "non-Chrome drag is measured even with trail rendering disabled")

; A normal click is suppressed physically and replayed once after release.
lexReplay:=[]
mouseGestureMoved:=false
m_LastGestureKey:="RButton"
m_WaitForRelease:=false
m_StartX:=10, m_StartY:=20, m_EndX:=30, m_EndY:=40
G_ExitGesture(true)
LexTest_Assert(lexReplay.Length()=2, "normal click must replay one right-button down/up pair")
LexTest_Assert(lexReplay[1].kind="down" && lexReplay[2].kind="up", "normal click replay ordering")
LexTest_Assert(!m_PassKeyUp && !m_WaitForRelease, "normal right-click clears held state")

lexReplay:=[]
mouseGestureMoved:=true
G_ExitGesture(true)
LexTest_Assert(lexReplay.Length()=0, "irregular drag must not replay right click")
mouseGestureMoved:=false
G_ExitGesture(false)
LexTest_Assert(lexReplay.Length()=0, "recognized gesture must not replay right click")
mouseGestureTarget:={process:"notepad.exe"}
mouseGesture_hintUpdate()
LexTest_Assert(!mouseGestureHintShown, "non-Chrome hint remains hidden")
mouseGestureTarget:={process:"chrome.exe"}
m_StartX:=120, m_StartY:=120, m_Gesture:="_U_D"
mouseGesture_hintUpdate()
GuiControlGet, hintText, MouseGestureHint:, MouseGestureHintText
LexTest_Assert(hintText="↑↓  刷新", "live refresh hint: " . hintText)
LexTest_Assert(mouseGestureHintShown, "live hint shown")
mouseGesture_hintStop()
LexTest_Assert(!mouseGestureHintShown, "live hint hidden")
FileAppend, % "PASS: " . cases.Length() . " gesture fixtures, " . keyedCases.Length() . " keyed fixtures; action scope; right-click replay lifecycle.`n", *
ExitApp, 0

LexTest_ReadPointer(ByRef pointerX, ByRef pointerY){
    global lexFixture, lexIndex
    point:=lexFixture[lexIndex]
    pointerX:=point[1]
    pointerY:=point[2]
}

LexTest_Step(){
    global lexFixture, lexIndex, lexIdleAge, beginTimeout
    global m_WaitForRelease, m_EndX, m_EndY
    lexIndex++
    if(lexIndex>=lexFixture.Length())
    {
        lexIndex:=lexFixture.Length()
        LexTest_ReadPointer(m_EndX, m_EndY)
        m_WaitForRelease:=false
        if(lexIdleAge)
            beginTimeout:=A_TickCount-lexIdleAge
    }
}

LexTest_Replay(kind, pointerX, pointerY){
    global lexReplay
    lexReplay.Push({kind:kind, x:pointerX, y:pointerY})
}

LexTest_Execute(path, targetHwnd, targetProcess, targetClass){
    global lexExecuted
    lexExecuted:=path . ":" . targetProcess
    return true
}


LexTest_Assert(condition, message){
    if(!condition)
    {
        FileAppend, % "FAIL: " . message . "`n", *
        ExitApp, 1
    }
}

isLangChinese(){
    return true
}

'@

$taskTempRoot = Join-Path ([IO.Path]::GetTempPath()) ('capslock-lex-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskTempRoot | Out-Null
$workerPath = Join-Path $taskTempRoot 'worker.ahk'
$stdoutPath = Join-Path $taskTempRoot 'stdout.txt'
$stderrPath = Join-Path $taskTempRoot 'stderr.txt'
try {
    [IO.File]::WriteAllText($workerPath, $worker + "`n" + $functions + "`n" + $realDispatch + "`n" + $labels + "`n" + $fixtureCore, [Text.UTF8Encoding]::new($true))
    $testProcess = Start-Process -FilePath $AhkPath -ArgumentList ('/ErrorStdOut "' + $workerPath + '"') -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $null = $testProcess.Handle
    if (-not $testProcess.WaitForExit(15000)) {
        Stop-Process -Id $testProcess.Id -Force
        [void]$testProcess.WaitForExit(3000)
        $partial = if(Test-Path -LiteralPath $stdoutPath){ [IO.File]::ReadAllText($stdoutPath) } else { '' }
        throw "Isolated engine fixture timed out. $partial"
    }
    $testProcess.WaitForExit()
    $output = [IO.File]::ReadAllText($stdoutPath)
    $errors = [IO.File]::ReadAllText($stderrPath)
    if ($output) { Write-Output $output.TrimEnd() }
    if ($errors) { Write-Output $errors.TrimEnd() }
    if ($testProcess.ExitCode -ne 0 -or $output -notmatch 'PASS: 17 gesture fixtures, 5 keyed fixtures') {
        throw "Gesture regression failed (exit $($testProcess.ExitCode))."
    }
} finally {
    # Remove only the three known generated files, then the empty test directory.
    foreach ($generatedPath in @($workerPath, $stdoutPath, $stderrPath)) {
        if (Test-Path -LiteralPath $generatedPath) { Remove-Item -LiteralPath $generatedPath -Force }
    }
    Remove-Item -LiteralPath $taskTempRoot
}
