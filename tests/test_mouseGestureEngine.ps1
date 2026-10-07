param(
    [string]$AhkPath = 'C:\Program Files\AutoHotkey\AutoHotkey.exe'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = [IO.File]::ReadAllText((Join-Path $projectRoot 'lib\vendor\LexikosGestureEngine.ahk')).Replace("`r`n", "`n")
$importedCore = $engine.Substring($engine.IndexOf("CancelGesture:`n")).Trim()
if (-not $importedCore.StartsWith("CancelGesture:`n")) { throw 'Imported gesture core entry point not found.' }

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
if ($engine -notmatch 'GestureKey_Up:\n\s+Hotkey, [^\n]+\n\s+CoordMode, Mouse, Screen[^\n]*\n\s+MouseGetPos, m_EndX, m_EndY') {
    throw 'Right-button release must capture screen coordinates, like right-button press.'
}
if ($adapter -notmatch 'if action = 8\s+SendEvent, \^\{PgDn\}' -or $adapter -notmatch 'if action = 7\s+SendEvent, \^\{PgUp\}') {
    throw 'Chrome tab gestures must send page-up/page-down tab shortcuts.'
}
if ($adapter -notmatch 'if action = 3\s+SendInput, \^t\s+if action = 4') {
    throw 'New-tab gesture must only send Ctrl+T.'
}
$functions = $functions.Replace('SendEvent, {RButton Down}', 'LexTest_Replay("down", 0, 0)').Replace('SendEvent, {RButton Up}', 'LexTest_Replay("up", 0, 0)')
$functions = $functions.Replace('SendInput, % rule.value', 'LexTest_Shortcut(rule.value)')
$functions = $functions.Replace('SendEvent, % rule.value', 'LexTest_Shortcut(rule.value)')
$functions = $functions.Replace('SendInput, !{Left}', 'LexTest_Shortcut("!{Left}")').Replace('SendInput, !{Right}', 'LexTest_Shortcut("!{Right}")')
$functions = $functions.Replace('if(!mouseGesture_activateTarget(targetHwnd))', 'if(!LexTest_ActivateTarget(targetHwnd))')
$dispatchStart = $functions.IndexOf('mouseGesture_dispatch(){')
$dispatchEnd = $functions.IndexOf('mouseGesture_lexTrailDraw(', $dispatchStart)
$realDispatch = $functions.Substring($dispatchStart, $dispatchEnd - $dispatchStart)
$realDispatch = $realDispatch.Replace('mouseGesture_dispatch(){', 'LexTest_RealDispatch(){').Replace('return mouseGesture_execute(', 'return LexTest_Execute(')
$testDispatch = @'
mouseGesture_dispatch(){
    global lexCaptured, m_Gesture
    if(!LexTest_RealDispatch())
        return false
    lexCaptured:=StrReplace(m_Gesture, "_")
    return true
}

'@
$functions = $functions.Substring(0, $dispatchStart) + $testDispatch + $functions.Substring($dispatchEnd)
$labels = @'
LexFixture_L:
LexFixture_R:
LexFixture_R_D:
LexFixture_R_U:
LexFixture_U_D:
LexFixture_U_L:
LexFixture_U_R:
LexFixture_D_L:
LexFixture_D_R:
lexCaptured:=StrReplace(m_Gesture, "_")
return
'@
$settingsGuiSource = [IO.File]::ReadAllText((Join-Path $projectRoot 'lib\lib_settingsGui.ahk')).Replace("`r`n", "`n")
$guiStart = $settingsGuiSource.IndexOf('settingsGui_refreshGestureList(){')
$guiEnd = $settingsGuiSource.IndexOf('settingsGui_loadPhrases(){', $guiStart)
$guiFunctions = $settingsGuiSource.Substring($guiStart, $guiEnd - $guiStart).Replace('Gui, GestureEditor:Show, w480 h350 Center, %title%', 'Gui, GestureEditor:Show, Hide')
$qbarHelperStart = $settingsGuiSource.IndexOf('settingsGui_updateQbarExternalControls(showPath){')
$qbarHelperEnd = $settingsGuiSource.IndexOf('settingsGui_updateColorPreview(', $qbarHelperStart)
$qbarHelper = $settingsGuiSource.Substring($qbarHelperStart, $qbarHelperEnd - $qbarHelperStart)
if ($settingsGuiSource -notmatch 'settingsGui_setPage\(settingsGuiPage\)' -or $qbarHelper -notmatch 'showPath:=showPath && settingsGuiPage="qbar"') {
    throw 'Reopening Settings must restore the active page, and Qbar controls must stay on the Qbar page.'
}
foreach ($row in @(@('General',96), @('Pin',144), @('Qbar',192), @('Hotkeys',246), @('Phrases',300), @('Gestures',348))) {
    $labelPattern = 'Gui, SettingsGui:Add, Text, x12 y' + $row[1] + ' w166 h42 vSettingsNav' + $row[0] + ' Border BackgroundTrans Center \+0x100 \+0x200 gSettingsGuiShow' + $row[0]
    $barPattern = 'Gui, SettingsGui:Add, Progress, x12 y' + $row[1] + ' w4 h42 vSettingsNav' + $row[0] + 'Highlight'
    if ($settingsGuiSource -notmatch $labelPattern -or $settingsGuiSource -notmatch $barPattern) {
        throw "Navigation row $($row[0]) needs a full-size clickable text button and only a narrow selection marker."
    }
}
if ($settingsGuiSource -match 'settingsGui_renderNavigation\(') {
    throw 'Do not repaint transparent navigation text over a full-size progress background.'
}
$editorStart = $settingsGuiSource.IndexOf('settingsGui_gestureEdit(index:=0, builtin:=""){')
$editorEnd = $settingsGuiSource.IndexOf('settingsGui_shortcutToHotkey(shortcut){', $editorStart)
$editorSource = $settingsGuiSource.Substring($editorStart, $editorEnd - $editorStart)
$showEditorAt = $editorSource.IndexOf('Gui, GestureEditor:Show, w480 h350 Center, %title%')
$disableSettingsAt = $editorSource.IndexOf('Gui, SettingsGui:+Disabled')
$hasStaleEditorRecovery = $settingsGuiSource -match 'if\(!settingsGuiGestureEditorHwnd\s*\|\| !DllCall\("IsWindowVisible"[\s\S]+?Gui, SettingsGui:-Disabled'
if ($showEditorAt -lt 0 -or $disableSettingsAt -lt 0 -or $showEditorAt -gt $disableSettingsAt -or -not $hasStaleEditorRecovery) {
    throw 'Settings must remain clickable if its gesture editor fails to appear.'
}
$guiLabelStart = $settingsGuiSource.IndexOf("SettingsGuiGestureAdd:`n")
$guiLabelEnd = $settingsGuiSource.IndexOf("SettingsGuiPhraseListChanged:`n", $guiLabelStart)
$guiLabels = $settingsGuiSource.Substring($guiLabelStart, $guiLabelEnd - $guiLabelStart)

$worker = @'
#NoEnv
#SingleInstance Off
SetBatchLines, -1
testSettingsFile:=A_ScriptDir . "\CapsLock+settings.ini"
IniWrite, 3, %testSettingsFile%, MouseGestureRules, Count
IniWrite, *, %testSettingsFile%, MouseGestureRules, Scope1
IniWrite, U, %testSettingsFile%, MouseGestureRules, Path1
IniWrite, send, %testSettingsFile%, MouseGestureRules, Kind1
IniWrite, !{Up}, %testSettingsFile%, MouseGestureRules, Value1
IniWrite, Global up, %testSettingsFile%, MouseGestureRules, Name1
IniWrite, *, %testSettingsFile%, MouseGestureRules, Scope2
IniWrite, L, %testSettingsFile%, MouseGestureRules, Path2
IniWrite, send, %testSettingsFile%, MouseGestureRules, Kind2
IniWrite, !{Left}, %testSettingsFile%, MouseGestureRules, Value2
IniWrite, Global back, %testSettingsFile%, MouseGestureRules, Name2
IniWrite, *, %testSettingsFile%, MouseGestureRules, Scope3
IniWrite, R, %testSettingsFile%, MouseGestureRules, Path3
IniWrite, send, %testSettingsFile%, MouseGestureRules, Kind3
IniWrite, !{Right}, %testSettingsFile%, MouseGestureRules, Value3
IniWrite, Global forward, %testSettingsFile%, MouseGestureRules, Name3
SetWorkingDir, %A_Temp%
mouseGestureSettingsFile:=""
mouseGesture_init()
LexTest_Assert(mouseGestureSettingsFile=testSettingsFile, "settings path is script-relative even when launched from another directory")
LexTest_Assert(mouseGesture_matchRule("U", "explorer.exe").value="!{Up}", "global rules load from script directory")
LexTest_Assert(mouseGesture_matchRule("L", "explorer.exe").value="!{Left}", "global back rule loads from script directory")
LexTest_Assert(mouseGesture_matchRule("R", "explorer.exe").value="!{Right}", "global forward rule loads from script directory")
LexTest_Assert(mouseGesture_matchRule("L", "chrome.exe").kind="send" && mouseGesture_matchRule("L", "chrome.exe").value="!{Left}", "global back overrides the former Chrome built-in")
LexTest_Assert(mouseGesture_matchRule("R", "chrome.exe").kind="send" && mouseGesture_matchRule("R", "chrome.exe").value="!{Right}", "global forward overrides the former Chrome built-in")
mouseGestureSettingsFile:=A_ScriptDir . "\gesture-rules.ini"
mouseGestureRules:=[]
LexTest_Assert(mouseGesture_matchRule("L", "explorer.exe").action=1 && mouseGesture_matchRule("L", "chrome.exe").action=1, "one default back action covers Explorer and Chrome")
LexTest_Assert(mouseGesture_matchRule("R", "explorer.exe").action=2 && mouseGesture_matchRule("R", "chrome.exe").action=2, "one default forward action covers Explorer and Chrome")
LexTest_Assert(!mouseGestureHintHwnd && !mouseGestureHintShown, "startup must not create or show the gesture hint")
mouseGestureTarget:={process:"chrome.exe"}, m_Gesture:=""
mouseGesture_hintUpdate()
LexTest_Assert(!mouseGestureHintHwnd, "stationary Chrome right-click must not create the hint")
mouseGestureTarget:={process:"notepad.exe"}, m_Gesture:="_U"
mouseGesture_hintUpdate()
GuiControlGet, hintText, MouseGestureHint:, MouseGestureHintText
LexTest_Assert(mouseGestureHintShown && hintText="未设置动作", "first unassigned direction shows recognized path without claiming an action")
arrowOne:=mouseGestureHintArrows[1]
GuiControlGet, arrowTextOne, MouseGestureHint:, %arrowOne%
LexTest_Assert(arrowTextOne="↑", "first direction arrow appears immediately")
hintHwnd:=mouseGestureHintHwnd
mouseGestureTarget:={process:"chrome.exe"}, m_Gesture:="_D"
mouseGesture_hintUpdate()
GuiControlGet, hintText, MouseGestureHint:, MouseGestureHintText
GuiControlGet, arrowTextOne, MouseGestureHint:, %arrowOne%
LexTest_Assert(mouseGestureHintShown && hintText="未设置动作" && arrowTextOne="↓", "down-only Chrome path is visible but has no action")
m_Gesture:="_D_R"
mouseGesture_hintUpdate()
GuiControlGet, hintText, MouseGestureHint:, MouseGestureHintText
LexTest_Assert(mouseGestureHintShown && mouseGestureHintHwnd=hintHwnd && hintText="新建标签页", "down-right updates the existing preview to its action")
mouseGesture_hintStop()
mouseGestureTarget:=""
mouseGestureDrawTrail:=false
m_KeylessPrefix:="LexFixture"
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
cases.Push({name:"close-tab", path:"DL", action:"DL", points:[[0,0],[0,30],[0,60],[-30,60],[-60,60],[-90,60]]})
cases.Push({name:"new-tab", path:"DR", action:"DR", points:[[0,0],[0,30],[0,60],[30,60],[60,60]]})
cases.Push({name:"release-endpoint", path:"L", action:"L", points:[[0,0],[-35,0]]})
cases.Push({name:"click-jitter", path:"", action:"", points:[[0,0],[2,3],[-3,4],[1,-2]]})
cases.Push({name:"jittered-refresh", path:"UD", action:"UD", points:[[0,0],[1,-30],[-2,-70],[1,-40],[0,0]]})
cases.Push({name:"angled-line", path:"R", action:"R", points:[[0,0],[40,10],[80,20]]})
cases.Push({name:"unsupported-full-sequence", path:"RDL", action:"", points:[[0,0],[30,0],[30,30],[0,30],[-30,30]]})
cases.Push({name:"release-timeout", path:"L", action:"", idleAge:1200, points:[[0,0],[-30,0],[-60,0],[-60,0]]})
cases.Push({name:"initial-timeout", path:"", action:"", initialTimeout:250, idleAge:350, points:[[0,0],[2,1],[2,1]]})
cases.Push({name:"release-tail", path:"RD", action:"RD", keyedPath:"R", keyedAction:"R", points:[[0,0],[35,0],[70,0],[105,0],[105,30]]})
for caseIndex, case in cases
{
    lexFixture:=case.points
    lexIndex:=1
    lexCaptured:=""
    lexReplay:=[]
    lexIdleAge:=case.HasKey("idleAge") ? case.idleAge : 0
    m_Timeout:=case.name="release-timeout" ? 1000 : 0
    m_InitialTimeout:=case.HasKey("initialTimeout") ? case.initialTimeout : 0
    gosub GestureKeyless
    path:=StrReplace(m_Gesture, "_")
    LexTest_Assert(path=case.path, case.name . " path: " . path)
    LexTest_Assert(lexCaptured=case.action, case.name . " action: " . lexCaptured)
}
; The real hotkey uses the keyed entry path; exercise it with the same samples.
keyedCases:=[1,6,9,11,12,15,16,18]
mouseGestureTarget:={process:"chrome.exe"}
for _, caseIndex in keyedCases
{
    case:=cases[caseIndex]
    lexFixture:=case.points
    lexIndex:=1
    lexCaptured:=""
    lexReplay:=[]
    lexIdleAge:=case.HasKey("idleAge") ? case.idleAge : 0
    m_Timeout:=case.name="release-timeout" ? 1000 : 0
    m_InitialTimeout:=case.HasKey("initialTimeout") ? case.initialTimeout : 0
    if(case.name="click-jitter")
        m_Gesture:="_L", mouseGestureMoved:=true  ; A previous Back gesture must not leak into a fresh click.
    mouseGesture_beginPress()
    gosub GestureKey_Down
    Hotkey, *RButton Up, GestureKey_Up, Off
    path:=StrReplace(m_Gesture, "_")
    expectedPath:=case.HasKey("keyedPath") ? case.keyedPath : case.path
    expectedAction:=case.HasKey("keyedAction") ? case.keyedAction : case.action
    if(case.name="release-timeout")
        expectedAction:="L"
    LexTest_Assert(path=expectedPath, "keyed " . case.name . " path: " . path)
    LexTest_Assert(lexCaptured=expectedAction, "keyed " . case.name . " action: " . lexCaptured)
    LexTest_Assert(!mouseGestureHintShown, "keyed " . case.name . " must dismiss live hint on release")
    if(case.name="click-jitter")
        LexTest_Assert(lexReplay.Length()=2 && lexReplay[1].kind="down" && lexReplay[2].kind="up", "keyed click replays exactly one normal right click")
    else
        LexTest_Assert(lexReplay.Length()=0, "keyed gesture must not also replay a right click")
}
mouseGestureTarget:={process:"explorer.exe", hwnd:123, class:"CabinetWClass"}
lexFixture:=[[0,0],[0,30],[0,60],[-27,60]]
lexIndex:=1, lexCaptured:="", lexIdleAge:=0
m_Timeout:=0, m_InitialTimeout:=0
mouseGesture_beginPress()
gosub GestureKey_Down
Hotkey, *RButton Up, GestureKey_Up, Off
LexTest_Assert(m_Gesture="_D" && lexCaptured="", "release wobble does not change the shown down path or close Explorer")
LexTest_Assert(mouseGesture_resolveAction("DL", "chrome.exe")=9, "Chrome close-tab mapping")
LexTest_Assert(mouseGesture_resolveAction("DL", "notepad.exe")=10, "global close-window mapping")
LexTest_Assert(mouseGesture_resolveAction("DR", "chrome.exe")=3, "down-right new tab mapping")
LexTest_Assert(mouseGesture_resolveAction("D", "chrome.exe")=0, "down-alone is unassigned")
LexTest_Assert(mouseGesture_resolveAction("L", "notepad.exe")=1 && mouseGesture_resolveAction("R", "notepad.exe")=2, "back and forward are global defaults")
LexTest_Assert(mouseGesture_resolveAction("DLR", "chrome.exe")=0, "no prefix action matching")
LexTest_Assert(!mouseGesture_acceptTarget("Shell_TrayWnd", "explorer.exe"), "taskbar retains native right click")
LexTest_Assert(!mouseGesture_acceptTarget("NotifyIconOverflowWindow", "explorer.exe"), "tray overflow retains native right click")
LexTest_Assert(!mouseGesture_acceptTarget("ToolbarWindow32", "explorer.exe"), "shell child cannot masquerade as file manager")
LexTest_Assert(mouseGesture_acceptTarget("CabinetWClass", "explorer.exe"), "Explorer file window keeps gestures")
LexTest_Assert(mouseGesture_acceptTarget("Chrome_WidgetWin_1", "chrome.exe"), "Chrome keeps gestures")
mouseGestureTarget:={process:"explorer.exe", hwnd:123, class:"CabinetWClass"}
m_Gesture:="_D_L"
mouseGestureMoved:=true
m_LowThreshold:=15, totalDistance:=16
lexExecuted:=""
LexTest_Assert(LexTest_RealDispatch(), "recognized short down-left closes Explorer at 15px threshold")
LexTest_Assert(lexExecuted="builtin:explorer.exe", "Explorer action target")
mouseGestureTarget:={process:"chrome.exe", hwnd:123, class:"Chrome_WidgetWin_1"}
lexExecuted:="", totalDistance:=16
LexTest_Assert(LexTest_RealDispatch() && lexExecuted="builtin:chrome.exe", "recognized short down-left closes Chrome tab")
lexReplay:=[], lexExecuted:="", mouseGestureMoved:=false, m_Gesture:="_L"
LexTest_Assert(LexTest_RealDispatch() && lexExecuted="" && lexReplay.Length()=2, "unmoved click cannot execute an old gesture path")
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
m_Gesture:="_D_L"
mouseGesture_hintUpdate()
GuiControlGet, hintText, MouseGestureHint:, MouseGestureHintText
LexTest_Assert(hintText="关闭窗口", "non-Chrome action is on the second row: " . hintText)
arrowOne:=mouseGestureHintArrows[1], arrowTwo:=mouseGestureHintArrows[2]
GuiControlGet, arrowTextOne, MouseGestureHint:, %arrowOne%
GuiControlGet, arrowTextTwo, MouseGestureHint:, %arrowTwo%
LexTest_Assert(arrowTextOne="↓" && arrowTextTwo="←", "direction arrows occupy separate boxes")
LexTest_Assert(mouseGestureHintShown, "non-Chrome close-window hint shown")
mouseGesture_hintStop()
mouseGestureTarget:={process:"chrome.exe"}
m_Gesture:=""
mouseGesture_hintUpdate()
LexTest_Assert(!mouseGestureHintShown, "stationary Chrome right-click must not show the hint")
m_StartX:=120, m_StartY:=120, m_Gesture:="_U_D"
mouseGesture_hintUpdate()
GuiControlGet, hintText, MouseGestureHint:, MouseGestureHintText
LexTest_Assert(hintText="刷新", "live refresh action on second row: " . hintText)
GuiControlGet, arrowTextOne, MouseGestureHint:, %arrowOne%
GuiControlGet, arrowTextTwo, MouseGestureHint:, %arrowTwo%
LexTest_Assert(arrowTextOne="↑" && arrowTextTwo="↓", "live arrows update without recreating hint")
LexTest_Assert(mouseGestureHintShown, "live hint shown")
mouseGesture_hintStop()
LexTest_Assert(!mouseGestureHintShown, "live hint hidden")
mouseGestureRules.Push(mouseGesture_makeRule("notepad.exe", "LURDLURD", "send", "^t", "Long path"))
mouseGestureTarget:={process:"notepad.exe"}, m_Gesture:="_L_U_R_D_L_U_R_D"
mouseGesture_hintUpdate()
arrowEight:=mouseGestureHintArrows[8]
GuiControlGet, arrowTextEight, MouseGestureHint:, %arrowEight%
LexTest_Assert(arrowTextEight="↓", "eight-direction path retains its final boxed arrow")
mouseGesture_hintStop()
mouseGestureRules:=[]
LexTest_Assert(settingsGui_hotkeyToShortcut("^t")="^t", "Ctrl+T recorder conversion")
LexTest_Assert(settingsGui_hotkeyToShortcut("F5")="{F5}", "F5 recorder conversion")
LexTest_Assert(settingsGui_hotkeyToShortcut("!F4")="!{F4}", "Alt+F4 recorder conversion")
LexTest_Assert(settingsGui_shortcutToHotkey("^{PgDn}")="^PgDn", "saved Ctrl+PageDown prefills recorder")
LexTest_Assert(settingsGui_shortcutToHotkey("#t")="", "Win modifier follows native control limitation")
LexTest_Assert(settingsGui_hotkeyToShortcut("^")="", "incomplete modifier is not accepted")
LexTest_Assert(mouseGesture_normalizePath("→↑")="RU", "arrow path normalization")
LexTest_Assert(mouseGesture_normalizePath("RR")="", "same-direction segments are merged by upstream engine")
LexTest_Assert(!IsObject(mouseGesture_makeRule("explorer", "R", "send", "^t", "")), "application scope requires an exe name")
LexTest_Assert(!IsObject(mouseGesture_makeRule("*", "D", "url", "javascript:alert(1)", "")), "URL action requires HTTP(S)")
LexTest_Assert(IsObject(mouseGesture_makeRule("chrome.exe", "DR", "send", "", "Disable new tab")), "blank shortcut is an intentional no-op")
customRules:=[]
customRules.Push(mouseGesture_makeRule("explorer.exe", "RDL", "none", "", "资源管理器动作"))
customRules.Push(mouseGesture_makeRule("*", "LUR", "send", "^t", "Everywhere"))
customRules.Push(mouseGesture_makeRule("chrome.exe", "DR", "send", "^t", "Custom new tab"))
customRules.Push(mouseGesture_makeRule("*", "UL", "none", "", "Global UL"))
customRules.Push(mouseGesture_makeRule("*", "L", "send", "!{Left}", "后退"))
customRules.Push(mouseGesture_makeRule("*", "R", "send", "!{Right}", "前进"))
customRules.Push(mouseGesture_makeRule("explorer.exe", "U", "send", "!{Up}", "上一级文件夹"))
LexTest_Assert(mouseGesture_saveRules(customRules), "save custom rules to isolated INI")
iniFile:=FileOpen(mouseGestureSettingsFile, "r")
LexTest_Assert(IsObject(iniFile), "saved rules INI exists")
iniFile.Pos:=0
iniEncodingMark:=iniFile.ReadUShort()
iniFile.Close()
LexTest_Assert(iniEncodingMark=0xFEFF, "new rules INI uses UTF-16 on any Windows locale")
LexTest_Assert(mouseGesture_matchRule("U", "explorer.exe").value="!{Up}", "new rule is active immediately without restart")
mouseGestureRules:=[]
mouseGesture_loadRules()
LexTest_Assert(mouseGestureRules.Length()=7, "reload all rules from isolated INI")
LexTest_Assert(mouseGesture_matchRule("RDL", "explorer.exe").name="资源管理器动作", "exact application rule and Unicode INI round-trip")
LexTest_Assert(!IsObject(mouseGesture_matchRule("RDL", "notepad.exe")), "application rule does not leak")
LexTest_Assert(mouseGesture_matchRule("LUR", "notepad.exe").name="Everywhere", "global custom fallback")
LexTest_Assert(mouseGesture_matchRule("DR", "chrome.exe").name="Custom new tab", "Chrome custom overrides built-in")
LexTest_Assert(mouseGesture_matchRule("UL", "chrome.exe").kind="builtin", "Chrome built-in precedes global custom")
LexTest_Assert(mouseGesture_matchRule("UL", "notepad.exe").kind="none", "non-Chrome global custom applies")
LexTest_Assert(mouseGesture_matchRule("DL", "explorer.exe").action=10, "existing global close-window remains")
LexTest_Assert(mouseGesture_matchRule("L", "explorer.exe").value="!{Left}", "global back shortcut reaches Explorer")
LexTest_Assert(mouseGesture_matchRule("R", "explorer.exe").value="!{Right}", "global forward shortcut reaches Explorer")
LexTest_Assert(mouseGesture_matchRule("L", "chrome.exe").kind="send" && mouseGesture_matchRule("R", "chrome.exe").kind="send", "global custom back and forward also reach Chrome")
mouseGestureRules.Push(mouseGesture_makeRule("chrome.exe", "L", "send", "!{Home}", "Chrome-specific back"))
LexTest_Assert(mouseGesture_matchRule("L", "chrome.exe").value="!{Home}" && mouseGesture_matchRule("L", "explorer.exe").value="!{Left}", "application rule overrides global back only in its application")
mouseGestureRules.Pop()
LexTest_Assert(mouseGesture_matchRule("U", "explorer.exe").value="!{Up}", "Explorer up shortcut is an editable rule")
LexTest_Assert(!IsObject(mouseGesture_matchRule("U", "chrome.exe")), "Explorer up shortcut does not leak into Chrome")
Gui, LexTarget:New, +HwndlexTargetHwnd
for _, path in ["L", "R", "U"]
{
    lexSentShortcut:="", lexActivatedHwnd:=0
    rule:=mouseGesture_matchRule(path, "explorer.exe")
    LexTest_Assert(mouseGesture_execute(rule, lexTargetHwnd, "explorer.exe", "CabinetWClass"), "generic shortcut executes for " . path)
    LexTest_Assert(lexSentShortcut=rule.value && lexActivatedHwnd=lexTargetHwnd, "generic shortcut targets Explorer for " . path)
}
savedRules:=mouseGestureRules
mouseGestureRules:=[]
for _, process in ["explorer.exe", "chrome.exe"]
{
    for _, path in ["L", "R"]
    {
        lexSentShortcut:="", lexActivatedHwnd:=0
        rule:=mouseGesture_matchRule(path, process)
        LexTest_Assert(mouseGesture_execute(rule, lexTargetHwnd, process, "CabinetWClass"), "global default " . path . " executes in " . process)
        expectedShortcut:=path="L" ? "!{Left}" : "!{Right}"
        LexTest_Assert(lexSentShortcut=expectedShortcut && lexActivatedHwnd=lexTargetHwnd, "global default " . path . " sends the expected shortcut in " . process)
    }
}
mouseGestureRules:=savedRules
Gui, LexTarget:Destroy
mouseGestureTarget:={process:"explorer.exe", hwnd:123, class:"CabinetWClass"}
m_LastGestureKey:="RButton", m_GesturePrefix:="CLMouseGesture", m_Gesture:="_L"
mouseGestureMoved:=true
lexCaptured:=""
LexTest_Assert(G_PerformAction(m_Gesture) && lexCaptured="L", "single-left gesture dispatches global Explorer rule")
m_Gesture:="_R", lexCaptured:=""
LexTest_Assert(G_PerformAction(m_Gesture) && lexCaptured="R", "single-right gesture dispatches global Explorer rule")
m_Gesture:="_U", lexCaptured:=""
LexTest_Assert(G_PerformAction(m_Gesture) && lexCaptured="U", "single-up gesture dispatches editable Explorer rule")
duplicateRules:=customRules.Clone()
duplicateRules.Push(customRules[1].Clone())
LexTest_Assert(!mouseGesture_saveRules(duplicateRules), "duplicate scope and path rejected before writing")
mouseGestureTarget:={process:"explorer.exe", hwnd:123, class:"CabinetWClass"}
m_LastGestureKey:="RButton", m_GesturePrefix:="CLMouseGesture", m_Gesture:="_R_D_L"
lexCaptured:=""
LexTest_Assert(G_PerformAction(m_Gesture), "dynamic multi-direction path uses imported engine dispatch")
LexTest_Assert(lexCaptured="RDL", "dynamic multi-direction action dispatched")
mouseGestureTarget:={process:"notepad.exe", hwnd:123, class:"Notepad"}
lexCaptured:=""
LexTest_Assert(!G_PerformAction(m_Gesture) && lexCaptured="", "out-of-scope path remains unassigned")
; Open the real editor code against an isolated, hidden GUI and save one rule.
settingsGuiGestureRules:=[]
Gui, SettingsGui:New, +HwndsettingsGuiHwnd
Gui, SettingsGui:Add, ListView, vSettingsGestureList, Gesture|Action|Scope
Gui, SettingsGui:Add, Text, Hidden vSettingsQbarExternalPathLabel +HwndlexQbarPathHwnd, Qbar path
Gui, SettingsGui:Add, Text, Hidden vSettingsQbarExternalPath, Qbar edit
Gui, SettingsGui:Add, Text, Hidden vSettingsQbarChooseExternalPath, Qbar browse
Gui, SettingsGui:Add, Text, Hidden vSettingsQbarExternalPathHint, Qbar hint
settingsGuiPage:="qbar"
settingsGui_updateQbarExternalControls(true)
qbarPathStyle:=DllCall("GetWindowLong", "Ptr", lexQbarPathHwnd, "Int", -16, "Int")
LexTest_Assert(qbarPathStyle & 0x10000000, "Qbar path control is visible on Qbar page")
settingsGuiPage:="gestures"
settingsGui_updateQbarExternalControls(true)
qbarPathStyle:=DllCall("GetWindowLong", "Ptr", lexQbarPathHwnd, "Int", -16, "Int")
LexTest_Assert(!(qbarPathStyle & 0x10000000), "Qbar path control remains hidden on gesture page after settings reload")
mouseGestureRules:=[]
settingsGui_reloadGestureRules()
LexTest_Assert(settingsGuiGestureRules.Length()=7, "editor refreshes rules from disk rather than stale memory")
Gui, SettingsGui:ListView, SettingsGestureList
LexTest_Assert(settingsGuiGestureBuiltinRows=7 && LV_GetCount()=14, "custom rules replace matching global and Chrome default rows")
LV_Modify(8, "Select Focus")
LexTest_Assert(settingsGui_gestureSelectedIndex()=1, "custom row selection tracks hidden duplicate defaults")
LV_Modify(8, "-Select")
LexTest_Assert(mouseGesture_rulesSignature(mouseGesture_readRules())=settingsGuiGestureRulesDiskSignature, "editor snapshots current disk rules")
IniWrite, External change, %mouseGestureSettingsFile%, MouseGestureRules, Name7
LexTest_Assert(mouseGesture_rulesSignature(mouseGesture_readRules())!=settingsGuiGestureRulesDiskSignature, "external rule changes are detectable before save")
IniWrite, 上一级文件夹, %mouseGestureSettingsFile%, MouseGestureRules, Name7
settingsGuiGestureRules:=[]
settingsGui_refreshGestureList()
settingsGui_gestureEdit()
LexTest_Assert(settingsGuiGestureEditorHwnd && DllCall("IsWindow", "Ptr", settingsGuiGestureEditorHwnd), "rule editor opens")
LexTest_Assert(!DllCall("IsWindowEnabled", "Ptr", settingsGuiHwnd), "open editor temporarily disables the settings window")
GuiControl, GestureEditor:, GestureRuleName, Explorer new tab
GuiControl, GestureEditor:, GestureRuleScope, explorer.exe
gosub GestureEditorDown
gosub GestureEditorRight
GuiControl, GestureEditor:, GestureRuleHotkey, ^t
settingsGui_gestureEditorSave()
LexTest_Assert(settingsGuiGestureRules.Length()=1 && settingsGuiGestureRules[1].path="DR", "editor arrow buttons and save")
LexTest_Assert(settingsGuiGestureRules[1].scope="explorer.exe" && settingsGuiGestureRules[1].value="^t", "editor application and action fields")
LexTest_Assert(!settingsGuiGestureEditorHwnd, "editor closes after save")
LexTest_Assert(DllCall("IsWindowEnabled", "Ptr", settingsGuiHwnd), "saving editor re-enables the settings window")
settingsGui_gestureEdit(1)
gosub GestureEditorClearHotkey
settingsGui_gestureEditorSave()
LexTest_Assert(settingsGuiGestureRules[1].kind="send" && settingsGuiGestureRules[1].value="", "editor blank shortcut disables the gesture")
LexTest_Assert(mouseGesture_ruleName(settingsGuiGestureRules[1], "DR")="不执行", "blank shortcut is shown as disabled")
settingsGuiGestureRules[1]:=mouseGesture_makeRule("explorer.exe", "DR", "close", "", "Old action")
settingsGui_gestureEdit(1)
GuiControl, GestureEditor:, GestureRuleHotkey, !F4
settingsGui_gestureEditorSave()
LexTest_Assert(settingsGuiGestureRules[1].kind="send" && settingsGuiGestureRules[1].value="!{F4}", "editing legacy action converts it to a shortcut")
settingsGui_gestureEdit()
settingsGui_gestureEditorClose()
LexTest_Assert(settingsGuiGestureRules.Length()=1, "cancelled editor does not add a rule")
LexTest_Assert(DllCall("IsWindowEnabled", "Ptr", settingsGuiHwnd), "cancelled editor re-enables the settings window")
Gui, SettingsGui:ListView, SettingsGestureList
LV_Modify(11, "Select Focus")
rowCount:=LV_GetCount()
selectedRule:=settingsGui_gestureSelectedIndex()
gosub SettingsGuiGestureDelete
LexTest_Assert(settingsGuiGestureRules.Length()=0, "editor delete removes the selected custom rule (rows " . rowCount . ", selected " . selectedRule . ", remain " . settingsGuiGestureRules.Length() . ")")
Gui, SettingsGui:ListView, SettingsGestureList
LV_Modify(1, "Select Focus")
gosub SettingsGuiGestureEdit
LexTest_Assert(settingsGuiGestureEditorHwnd && IsObject(settingsGuiGestureEditingBuiltin), "default global back opens the same editor")
settingsGui_gestureEditorSave()
LexTest_Assert(settingsGuiGestureRules.Length()=0 && settingsGuiGestureBuiltinRows=10, "saving an unchanged default does not duplicate it")
Gui, SettingsGui:ListView, SettingsGestureList
LV_Modify(1, "Select Focus")
gosub SettingsGuiGestureEdit
GuiControl, GestureEditor:, GestureRuleName, Custom global back
GuiControl, GestureEditor:, GestureRuleHotkey, ^b
settingsGui_gestureEditorSave()
LexTest_Assert(settingsGuiGestureRules.Length()=1 && settingsGuiGestureRules[1].scope="*" && settingsGuiGestureRules[1].path="L" && settingsGuiGestureRules[1].value="^b", "editing a default creates a same-scope override")
Gui, SettingsGui:ListView, SettingsGestureList
LexTest_Assert(settingsGuiGestureBuiltinRows=9 && LV_GetCount()=10, "edited default appears once")
LV_Modify(10, "Select Focus")
gosub SettingsGuiGestureDelete
LexTest_Assert(settingsGuiGestureRules.Length()=0 && settingsGuiGestureBuiltinRows=10, "deleting the override restores the default")
Gui, SettingsGui:ListView, SettingsGestureList
LV_Modify(3, "Select Focus")
gosub SettingsGuiGestureEdit
GuiControl, GestureEditor:, GestureRuleName, Rename global close
settingsGui_gestureEditorSave()
LexTest_Assert(settingsGuiGestureRules.Length()=1 && settingsGuiGestureRules[1].kind="close" && settingsGuiGestureRules[1].path="DL", "renaming default close keeps its directed window-close action")
settingsGui_gestureEdit(1)
GuiControl, GestureEditor:, GestureRuleHotkey, ^x
settingsGui_gestureEditorSave()
LexTest_Assert(settingsGuiGestureRules[1].kind="send" && settingsGuiGestureRules[1].value="^x", "changing default close shortcut creates a shortcut override")
Gui, SettingsGui:Destroy
; Exercise the actual layered/GDI+ trail off-screen before process exit.
mouseGestureDrawTrail:=true
trailX:=A_ScreenWidth+300, trailY:=A_ScreenHeight+300
mouseGesture_trailStart(trailX, trailY)
LexTest_Assert(mouseGestureState.trailVisible, "off-screen layered trail starts")
mouseGestureTrailLastPaint:=A_TickCount-50
mouseGesture_trailLine(trailX+60, trailY+30)
LexTest_Assert(mouseGestureState.trailVisible, "off-screen layered trail renders")
mouseGesture_trailStop()
LexTest_Assert(!mouseGestureState.trailVisible, "rendered trail stops before exit")
FileAppend, % "PASS: " . cases.Length() . " gesture fixtures, " . keyedCases.Length() . " keyed fixtures; scoped rules, INI persistence, editor lifecycle, right-click replay.`n", *
ExitApp, 0

LexTest_ReadPointer(ByRef pointerX, ByRef pointerY){
    global lexFixture, lexIndex
    point:=lexFixture[lexIndex]
    pointerX:=point[1]
    pointerY:=point[2]
}

LexTest_Step(){
    global lexFixture, lexIndex, lexIdleAge, beginTimeout
    global m_WaitForRelease, m_EndX, m_EndY, m_LastGestureKey
    lexIndex++
    if(lexIndex>=lexFixture.Length())
    {
        lexIndex:=lexFixture.Length()
        LexTest_ReadPointer(m_EndX, m_EndY)
        if(lexIdleAge)
            beginTimeout:=A_TickCount-lexIdleAge
        if(m_LastGestureKey="RButton")
            mouseGesture_lexRelease()
        m_WaitForRelease:=false
    }
}

LexTest_Replay(kind, pointerX, pointerY){
    global lexReplay
    lexReplay.Push({kind:kind, x:pointerX, y:pointerY})
}

LexTest_Execute(rule, targetHwnd, targetProcess, targetClass){
    global lexExecuted
    lexExecuted:=rule.kind . ":" . targetProcess
    return true
}

LexTest_ActivateTarget(targetHwnd){
    global lexActivatedHwnd
    lexActivatedHwnd:=targetHwnd
    return true
}

LexTest_Shortcut(shortcut){
    global lexSentShortcut
    lexSentShortcut:=shortcut
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
    [IO.File]::WriteAllText($workerPath, $worker + "`n" + $functions + "`n" + $realDispatch + "`n" + $guiFunctions + "`n" + $qbarHelper + "`n" + $labels + "`n" + $guiLabels + "`n" + $fixtureCore, [Text.UTF8Encoding]::new($true))
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
    if ($testProcess.ExitCode -ne 0 -or $output -notmatch 'PASS: 18 gesture fixtures, 8 keyed fixtures') {
        throw "Gesture regression failed (exit $($testProcess.ExitCode))."
    }
} finally {
    # Remove only the three known generated files, then the empty test directory.
    foreach ($generatedPath in @($workerPath, $stdoutPath, $stderrPath)) {
        if (Test-Path -LiteralPath $generatedPath) { Remove-Item -LiteralPath $generatedPath -Force }
    }
    $isolatedIni = Join-Path $taskTempRoot 'gesture-rules.ini'
    if (Test-Path -LiteralPath $isolatedIni) { Remove-Item -LiteralPath $isolatedIni -Force }
    $testSettingsIni = Join-Path $taskTempRoot 'CapsLock+settings.ini'
    if (Test-Path -LiteralPath $testSettingsIni) { Remove-Item -LiteralPath $testSettingsIni -Force }
    Remove-Item -LiteralPath $taskTempRoot
}
