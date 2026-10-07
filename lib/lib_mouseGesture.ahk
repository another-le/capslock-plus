; CapsLock+ adapter for the original Lexikos mouse gesture engine.
; Recognition and gesture lifecycle live in vendor/LexikosGestureEngine.ahk.
; This file only supplies settings, application actions and the safe trail renderer.

mouseGesture_init(){
    global
    if(mouseGestureSettingsFile="")
        mouseGestureSettingsFile:=A_ScriptDir . "\CapsLock+settings.ini"
    mouseGestureState:={trailVisible:false}
    mouseGestureTarget:=""
    mouseGestureHintHwnd:=0
    mouseGestureHintShown:=false
    m_GestureKey:="RButton"
    m_GestureKey2:=""
    m_Interval:=20
    m_HighThreshold:=0
    ; Physical right-button input is withheld until we know click vs gesture.
    m_InitialTimeout:=0
    m_ActiveTimeout:=0
    m_ActiveTimeoutMode:=0
    m_DefaultOnTimeout:=0
    m_Tolerance:=100
    m_ZoneCount:=4
    m_InitialZoneCount:=4
    m_DisableDing:=1
    m_GesturePrefix:="CLMouseGesture"
    m_KeylessPrefix:=""
    m_Delimiter:="_"
    c_Zone4_0:="R"
    c_Zone4_1:="D"
    c_Zone4_2:="L"
    c_Zone4_3:="U"
    m_WaitForRelease:=false
    m_PassKeyUp:=false
    m_LastGestureKey:=""
    ; The upstream default GUI canvas is not used inside the host application.
    hdc_canvas:=0
    mouseGesture_applySettings()
    mouseGesture_loadRules()
    if(!mouseGesture_rendererInit())
        mouseGestureDrawTrail:=false
    OnExit("mouseGesture_onExit")
}

mouseGesture_applySettings(){
    global CLSets, mouseGestureEnabled, mouseGestureDrawTrail
    global mouseGestureThreshold, mouseGestureTimeout
    global m_LowThreshold, m_Timeout

    mouseGestureEnabled:=true
    mouseGestureDrawTrail:=true
    mouseGestureThreshold:=25
    mouseGestureTimeout:=1000

    if(IsObject(CLSets) && IsObject(CLSets.Global))
    {
        if(CLSets.Global.mouseGestureEnabled="0")
            mouseGestureEnabled:=false
        if(CLSets.Global.mouseGestureDrawTrail="0")
            mouseGestureDrawTrail:=false
        if(CLSets.Global.mouseGestureThreshold>=10 && CLSets.Global.mouseGestureThreshold<=100)
            mouseGestureThreshold:=CLSets.Global.mouseGestureThreshold+0
        if(CLSets.Global.mouseGestureTimeout>=300 && CLSets.Global.mouseGestureTimeout<=5000)
            mouseGestureTimeout:=CLSets.Global.mouseGestureTimeout+0
    }
    m_LowThreshold:=mouseGestureThreshold
    m_Timeout:=mouseGestureTimeout
}

mouseGesture_loadRules(){
    global mouseGestureRules
    mouseGestureRules:=mouseGesture_readRules()
}

mouseGesture_readRules(){
    global mouseGestureSettingsFile
    rules:=[]
    IniRead, count, %mouseGestureSettingsFile%, MouseGestureRules, Count, 0
    if count is not integer
        count:=0
    count:=Max(0, Min(count+0, 64))
    Loop, %count%
    {
        index:=A_Index
        IniRead, scope, %mouseGestureSettingsFile%, MouseGestureRules, Scope%index%,
        IniRead, path, %mouseGestureSettingsFile%, MouseGestureRules, Path%index%,
        IniRead, kind, %mouseGestureSettingsFile%, MouseGestureRules, Kind%index%,
        IniRead, value, %mouseGestureSettingsFile%, MouseGestureRules, Value%index%,
        IniRead, name, %mouseGestureSettingsFile%, MouseGestureRules, Name%index%,
        rule:=mouseGesture_makeRule(scope, path, kind, value, name)
        if(IsObject(rule))
            rules.Push(rule)
    }
    return rules
}

mouseGesture_rulesSignature(rules){
    signature:=""
    if(!IsObject(rules))
        return signature
    for _, rule in rules
        signature.=StrLen(rule.scope) . ":" . rule.scope
            . StrLen(rule.path) . ":" . rule.path
            . StrLen(rule.kind) . ":" . rule.kind
            . StrLen(rule.value) . ":" . rule.value
            . StrLen(rule.name) . ":" . rule.name . "|"
    return signature
}

mouseGesture_saveRules(rules){
    global mouseGestureRules, mouseGestureSettingsFile
    if(!mouseGesture_validateRules(rules))
        return false
    validated:=[]
    for _, rule in rules
    {
        valid:=mouseGesture_makeRule(rule.scope, rule.path, rule.kind, rule.value, rule.name)
        validated.Push(valid)
    }
    ; IniDelete creates a missing INI in the system ANSI code page. On an
    ; English Windows runner that loses Chinese rule names on the next read.
    if(!FileExist(mouseGestureSettingsFile))
    {
        iniFile:=FileOpen(mouseGestureSettingsFile, "w", "UTF-16")
        if(!IsObject(iniFile))
            return false
        iniFile.Close()
    }
    IniDelete, %mouseGestureSettingsFile%, MouseGestureRules
    for index, rule in validated
    {
        IniWrite, % rule.scope, %mouseGestureSettingsFile%, MouseGestureRules, Scope%index%
        IniWrite, % rule.path, %mouseGestureSettingsFile%, MouseGestureRules, Path%index%
        IniWrite, % rule.kind, %mouseGestureSettingsFile%, MouseGestureRules, Kind%index%
        IniWrite, % rule.value, %mouseGestureSettingsFile%, MouseGestureRules, Value%index%
        IniWrite, % rule.name, %mouseGestureSettingsFile%, MouseGestureRules, Name%index%
    }
    count:=validated.Length()
    IniWrite, %count%, %mouseGestureSettingsFile%, MouseGestureRules, Count
    mouseGestureRules:=validated
    return true
}

mouseGesture_validateRules(rules){
    if(!IsObject(rules) || rules.Length()>64)
        return false
    seen:={}
    for _, rule in rules
    {
        if(!IsObject(rule))
            return false
        valid:=mouseGesture_makeRule(rule.scope, rule.path, rule.kind, rule.value, rule.name)
        if(!IsObject(valid))
            return false
        key:=valid.scope . "|" . valid.path
        if(seen.HasKey(key))
            return false
        seen[key]:=true
    }
    return true
}

mouseGesture_normalizePath(path){
    path:=Trim(path)
    StringUpper, path, path
    path:=StrReplace(path, "↑", "U")
    path:=StrReplace(path, "↓", "D")
    path:=StrReplace(path, "←", "L")
    path:=StrReplace(path, "→", "R")
    path:=StrReplace(path, " ")
    path:=StrReplace(path, "_")
    if(!RegExMatch(path, "^[UDLR]{1,8}$"))
        return ""
    previous:=""
    Loop, Parse, path
    {
        if(A_LoopField=previous)
            return ""
        previous:=A_LoopField
    }
    return path
}

mouseGesture_makeRule(scope, path, kind, value, name){
    scope:=Trim(scope)
    StringLower, scope, scope
    path:=mouseGesture_normalizePath(path)
    kind:=Trim(kind)
    StringLower, kind, kind
    value:=Trim(value)
    name:=Trim(name)
    if((scope!="*" && !RegExMatch(scope, "^[a-z0-9_.-]+\.exe$")) || path=""
        || !RegExMatch(kind, "^(send|url|close|none)$")
        || StrLen(name)>40 || InStr(name, "`n") || InStr(name, "`r")
        || InStr(value, "`n") || InStr(value, "`r"))
        return ""
    if(kind="send" && StrLen(value)>120)
        return ""
    if(kind="url" && (StrLen(value)>2048 || !RegExMatch(value, "i)^https?://")
        || InStr(value, Chr(34))))
        return ""
    if(kind="close" || kind="none")
        value:=""
    return {scope:scope, path:path, kind:kind, value:value, name:name}
}

mouseGesture_matchRule(path, process){
    global mouseGestureRules
    StringLower, process, process
    if(IsObject(mouseGestureRules))
        for _, rule in mouseGestureRules
            if(rule.path=path && rule.scope=process)
                return rule
    builtin:=mouseGesture_resolveAction(path, process)
    ; Chrome-only built-ins keep their historical priority. Back/forward are
    ; global defaults, so a user-defined global shortcut may replace them.
    if(process="chrome.exe" && builtin && path!="L" && path!="R")
        return {kind:"builtin", action:builtin}
    if(IsObject(mouseGestureRules))
        for _, rule in mouseGestureRules
            if(rule.path=path && rule.scope="*")
                return rule
    return builtin ? {kind:"builtin", action:builtin} : ""
}

mouseGesture_ruleName(rule, path){
    if(!IsObject(rule))
        return mouseGesture_actionName(0, path)
    if(rule.kind="builtin")
        return mouseGesture_actionName(rule.action, path)
    if(rule.kind="none" || (rule.kind="send" && rule.value=""))
        return isLangChinese() ? "不执行" : "No action"
    if(rule.name!="")
        return rule.name
    if(rule.kind="close")
        return mouseGesture_actionName(10, path)
    return rule.kind="url" ? (isLangChinese() ? "打开网址" : "Open URL")
        : (isLangChinese() ? "发送快捷键" : "Send shortcut")
}

mouseGesture_acceptWindow(){
    global settingsGuiHwnd, settingsGuiGestureEditorHwnd
    CoordMode, Mouse, Screen
    MouseGetPos,,, hwnd
    if(!hwnd)
        return false
    rootHwnd:=DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
    if(rootHwnd)
        hwnd:=rootHwnd
    if((settingsGuiHwnd && hwnd=settingsGuiHwnd)
        || (settingsGuiGestureEditorHwnd && hwnd=settingsGuiGestureEditorHwnd))
        return false
    WinGetClass, windowClass, ahk_id %hwnd%
    WinGet, process, ProcessName, ahk_id %hwnd%
    return mouseGesture_acceptTarget(windowClass, process)
}

mouseGesture_acceptTarget(windowClass, process){
    ; Check the root window, not the toolbar child underneath a tray icon.
    if windowClass in Progman,WorkerW,Shell_TrayWnd,Shell_SecondaryTrayWnd,NotifyIconOverflowWindow,TopLevelWindowForOverflowXamlIsland,XamlExplorerHostIslandWindow,#32768
        return false
    ; Explorer.exe also owns shell UI. Only file-manager windows get gestures.
    if(process="explorer.exe" && windowClass!="CabinetWClass"
        && windowClass!="ExploreWClass")
        return false
    return true
}

mouseGesture_isGestureWindow(){
    global mouseGestureEnabled
    return mouseGestureEnabled && mouseGesture_acceptWindow()
}

mouseGesture_replayRightClick(){
    ; The physical press/release was withheld to prevent right-drag in every app.
    ; Reproduce only a completed click at the pointer's current position.
    SendEvent, {RButton Down}
    Sleep, 25
    SendEvent, {RButton Up}
}

mouseGesture_beginPress(){
    global m_Gesture, m_GestureLength, mouseGestureMoved
    ; A quick click may release before the imported engine reaches its own
    ; initialization. Never carry the previous gesture into a new press.
    m_Gesture:=""
    m_GestureLength:=0
    mouseGestureMoved:=false
}

mouseGesture_captureTarget(){
    global mouseGestureTarget
    MouseGetPos,,, hwnd
    rootHwnd:=DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
    if(rootHwnd)
        hwnd:=rootHwnd
    WinGet, process, ProcessName, ahk_id %hwnd%
    WinGetClass, windowClass, ahk_id %hwnd%
    mouseGestureTarget:={hwnd:hwnd, process:process, class:windowClass}
}

mouseGesture_dispatch(){
    global mouseGestureTarget, m_Gesture, mouseGestureMoved
    ; A click cannot dispatch a remembered direction, even if an early
    ; release interrupted the imported recognizer before it reset its path.
    if(!mouseGestureMoved)
    {
        mouseGesture_replayRightClick()
        return true
    }
    if(!IsObject(mouseGestureTarget))
        return false
    target:=mouseGestureTarget
    path:=StrReplace(m_Gesture, "_")
    rule:=mouseGesture_matchRule(path, target.process)
    if(!IsObject(rule))
        return false
    ; Recognition already enforces the configured stroke threshold. Do not
    ; show a recognized action and silently reject it at a second distance gate.
    return mouseGesture_execute(rule, target.hwnd, target.process, target.class)
}

mouseGesture_lexRelease(){
    global m_LastGestureKey, m_Gesture, m_EndX, m_EndY, lastX, lastY
    if(m_LastGestureKey!="RButton")
        return
    ; A direction already visible in the hint is the direction to execute.
    ; Do not let a final pointer wobble add an unseen segment after button-up.
    if(m_Gesture!="")
    {
        m_EndX:=lastX
        m_EndY:=lastY
    }
}

mouseGesture_lexTrailDraw(x, y){
    global mouseGestureDrawTrail, mouseGestureState, m_LastGestureKey
    global m_StartX, m_StartY, m_LowThreshold, m_WaitForRelease
    global mouseGestureMoved
    if(!m_LastGestureKey)
        return
    dx:=x-m_StartX
    dy:=y-m_StartY
    if(Sqrt(dx*dx+dy*dy)>m_LowThreshold)
        mouseGestureMoved:=true
    if(!mouseGestureDrawTrail || !m_WaitForRelease)
        return
    if(!mouseGestureState.trailVisible)
    {
        if(Sqrt(dx*dx+dy*dy)<=m_LowThreshold)
            return
        mouseGesture_trailStart(m_StartX, m_StartY)
    }
    mouseGesture_trailLine(x, y)
}

mouseGesture_onExit(exitReason, exitCode){
    global m_PassKeyUp, mouseGestureEnabled
    global mouseGestureExitCleaned
    if(mouseGestureExitCleaned)
        return
    mouseGestureExitCleaned:=true
    ; Stop accepting gestures before cleaning up the layered trail. Suspending
    ; hotkeys here crashes AHK v1 after a real trail has been rendered.
    mouseGestureEnabled:=false
    ; The host normally runs at High priority. Do not tear down GDI+ and layered
    ; windows at High priority while the user's pointer is still moving.
    Process, Priority,, Normal
    ; A timeout can have forwarded button-down; never leave it held on exit.
    if(m_PassKeyUp)
    {
        SendInput, {RButton Up}
        m_PassKeyUp:=false
    }
    mouseGesture_trailStop()
    mouseGesture_hintStop()
    ; Leave GDI+ shutdown to process termination. Calling GdiplusShutdown from
    ; this callback can crash AHK v1 after a layered trail was rendered.
    ; Likewise, Windows releases the hint GUI on process exit; destroying its
    ; child controls here can crash AHK v1 after a gesture preview was shown.
}

mouseGesture_hintInit(){
    global mouseGestureHintHwnd, mouseGestureHintShown, MouseGestureHintText
    global mouseGestureHintBoxes, mouseGestureHintArrows
    mouseGestureHintShown:=false
    mouseGestureHintBoxes:=[]
    mouseGestureHintArrows:=[]
    Gui, MouseGestureHint:New, +AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale +HwndmouseGestureHintHwnd
    Gui, MouseGestureHint:Color, 241633
    Loop, 8
    {
        Gui, MouseGestureHint:Add, Progress, x0 y12 w34 h34 Background3D2A55 c614780 Disabled Hidden +HwndboxHwnd, 100
        Gui, MouseGestureHint:Font, s16 w600 cFFFFFF, Segoe UI Symbol
        Gui, MouseGestureHint:Add, Text, x0 y12 w34 h34 Center +0x200 BackgroundTrans Hidden +HwndarrowHwnd
        mouseGestureHintBoxes.Push(boxHwnd)
        mouseGestureHintArrows.Push(arrowHwnd)
    }
    Gui, MouseGestureHint:Font, s15 w600 cFFFFFF, Microsoft YaHei UI
    Gui, MouseGestureHint:Add, Text, vMouseGestureHintText Center x12 y53 w336 h29 +0x200 BackgroundTrans
    WinSet, Transparent, 238, ahk_id %mouseGestureHintHwnd%
    WinSet, Region, 0-0 w360 h94 R18-18, ahk_id %mouseGestureHintHwnd%
}

mouseGesture_hintUpdate(){
    global mouseGestureTarget, mouseGestureHintHwnd, mouseGestureHintShown
    global mouseGestureHintBoxes, mouseGestureHintArrows
    global m_Gesture, m_StartX, m_StartY
    ; Show every recognized path as soon as its first direction is detected.
    ; An action binding changes the label, not whether the preview exists.
    if(!IsObject(mouseGestureTarget))
        return
    path:=StrReplace(m_Gesture, "_")
    if(path="")
    {
        mouseGesture_hintStop()
        return
    }
    rule:=mouseGesture_matchRule(path, mouseGestureTarget.process)
    if(!mouseGestureHintHwnd)
        mouseGesture_hintInit()
    if(!mouseGestureHintHwnd)
        return
    arrows:={L:"←", R:"→", U:"↑", D:"↓"}
    arrowCount:=Min(StrLen(path), 8)
    firstLeft:=Round((360-(arrowCount*34+(arrowCount-1)*6))/2)
    Loop, 8
    {
        boxHwnd:=mouseGestureHintBoxes[A_Index]
        arrowHwnd:=mouseGestureHintArrows[A_Index]
        if(A_Index>arrowCount)
        {
            GuiControl, MouseGestureHint:Hide, %boxHwnd%
            GuiControl, MouseGestureHint:Hide, %arrowHwnd%
            continue
        }
        boxLeft:=firstLeft+(A_Index-1)*40
        direction:=SubStr(path, A_Index, 1)
        arrowText:=arrows.HasKey(direction) ? arrows[direction] : "?"
        GuiControl, MouseGestureHint:MoveDraw, %boxHwnd%, x%boxLeft% y12 w34 h34
        GuiControl, MouseGestureHint:MoveDraw, %arrowHwnd%, x%boxLeft% y12 w34 h34
        GuiControl, MouseGestureHint:, %arrowHwnd%, %arrowText%
        GuiControl, MouseGestureHint:Show, %boxHwnd%
        GuiControl, MouseGestureHint:Show, %arrowHwnd%
    }
    displayText:=mouseGesture_ruleName(rule, path)
    if(StrLen(displayText)>18)
        displayText:=SubStr(displayText, 1, 17) . "…"
    GuiControl, MouseGestureHint:, MouseGestureHintText, %displayText%
    if(mouseGestureHintShown)
        return
    left:=Round((A_ScreenWidth-360)/2)
    top:=Round((A_ScreenHeight-94)/2)
    SysGet, monitorCount, MonitorCount
    Loop, %monitorCount%
    {
        SysGet, area, MonitorWorkArea, %A_Index%
        if(m_StartX>=areaLeft && m_StartX<areaRight
            && m_StartY>=areaTop && m_StartY<areaBottom)
        {
            left:=Round((areaLeft+areaRight-360)/2)
            top:=Round((areaTop+areaBottom-94)/2)
            break
        }
    }
    Gui, MouseGestureHint:Show, x%left% y%top% w360 h94 NA
    mouseGestureHintShown:=true
}

mouseGesture_actionName(action, path){
    if(isLangChinese())
    {
        static namesZh:=["后退", "前进", "新建标签页", "到页面底部", "到页面顶部"
            , "刷新", "左侧标签页", "右侧标签页", "关闭标签页", "关闭窗口"]
        if(action)
            return namesZh[action]
        return "未设置动作"
    }
    static namesEn:=["Back", "Forward", "New tab", "Page bottom", "Page top"
        , "Refresh", "Previous tab", "Next tab", "Close tab", "Close window"]
    if(action)
        return namesEn[action]
    return "No action"
}

mouseGesture_hintStop(){
    global mouseGestureHintHwnd, mouseGestureHintShown
    if(mouseGestureHintShown && mouseGestureHintHwnd)
        Gui, MouseGestureHint:Hide
    mouseGestureHintShown:=false
}

mouseGesture_execute(rule, targetHwnd, targetProcess, targetClass){
    if(!IsObject(rule))
        return false
    if(!DllCall("IsWindow", "Ptr", targetHwnd))
        return false

    if(rule.kind="none")
        return true
    if(rule.kind="url")
    {
        Run, % rule.value, , UseErrorLevel
        return ErrorLevel=0
    }
    if(rule.kind="send")
    {
        if(rule.value="")
            return true
        if(!mouseGesture_activateTarget(targetHwnd))
            return false
        ; Chrome's tab-switch shortcuts need event mode even when a built-in
        ; rule has been edited into a user shortcut with the same keys.
        if(targetProcess="chrome.exe" && (rule.value="^{PgUp}" || rule.value="^{PgDn}"))
            SendEvent, % rule.value
        else
            SendInput, % rule.value
        return true
    }

    if(rule.kind="close" || (rule.kind="builtin" && rule.action=10))
    {
        if(!mouseGesture_canCloseWindow(targetHwnd, targetClass))
            return false
        DllCall("PostMessage", "Ptr", targetHwnd, "UInt", 0x10, "Ptr", 0, "Ptr", 0)
        return true
    }

    action:=rule.kind="builtin" ? rule.action : 0
    if(action=1 || action=2)
    {
        if(!mouseGesture_activateTarget(targetHwnd))
            return false
        if(action=1)
            SendInput, !{Left}
        else
            SendInput, !{Right}
        return true
    }
    if(targetProcess="chrome.exe" && action)
    {
        if(!mouseGesture_activateTarget(targetHwnd))
            return false

        if action = 3
            SendInput, ^t
        if action = 4
            SendInput, ^{End}
        if action = 5
            SendInput, ^{Home}
        if action = 6
            SendInput, {F5}
        if action = 7
            SendEvent, ^{PgUp}
        if action = 8
            SendEvent, ^{PgDn}
        if action = 9
            SendInput, ^w
        return true
    }
    return false
}

mouseGesture_activateTarget(targetHwnd){
    if(!WinActive("ahk_id " . targetHwnd))
    {
        WinActivate, ahk_id %targetHwnd%
        WinWaitActive, ahk_id %targetHwnd%,, 1
    }
    return !!WinActive("ahk_id " . targetHwnd)
}

mouseGesture_resolveAction(g, p){
    ; Back/forward share one default in every captured application.
    if(g="L")
        return 1
    if(g="R")
        return 2
    static chromeActions:={DR:3, RD:4, RU:5, UD:6, UL:7, UR:8, DL:9}
    if(p="chrome.exe")
        return chromeActions.HasKey(g) ? chromeActions[g] : 0
    return g="DL" ? 10 : 0
}

mouseGesture_canCloseWindow(hwnd, windowClass){
    global settingsGuiHwnd

    if(!hwnd || (settingsGuiHwnd && hwnd=settingsGuiHwnd))
        return false
    if windowClass in Progman,WorkerW,Shell_TrayWnd,Shell_SecondaryTrayWnd
        return false
    return DllCall("IsWindow", "Ptr", hwnd)
}

mouseGesture_trailStart(startX, startY){
    global mouseGestureState, mouseGestureTrailPoints, mouseGestureTrailHwnd
    global mouseGestureGdipToken, mouseGestureTrailLastPaint
    global mouseGestureTrailPriorityNormalized

    mouseGesture_trailStop()
    if(!mouseGestureGdipToken)
        return
    if(!mouseGestureTrailPriorityNormalized)
    {
        Process, Priority,, Normal
        mouseGestureTrailPriorityNormalized:=true
    }
    mouseGestureTrailPoints:=[{x:startX, y:startY}]
    ; One layered window begins at 1x1; no uninitialized fullscreen GUI is shown.
    Gui, MouseGestureTrail:New, +AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x80000 -DPIScale +HwndmouseGestureTrailHwnd
    Gui, MouseGestureTrail:Show, x%startX% y%startY% w1 h1 NA
    mouseGestureState.trailVisible:=true
    if(!mouseGesture_trailRender())
        mouseGesture_trailStop()
    else
        mouseGestureTrailLastPaint:=A_TickCount
}

mouseGesture_trailLine(x, y){
    global mouseGestureState, mouseGestureTrailPoints
    global mouseGestureTrailLastPaint

    if(!IsObject(mouseGestureState) || !mouseGestureState.trailVisible
        || !IsObject(mouseGestureTrailPoints))
        return
    previous:=mouseGestureTrailPoints[mouseGestureTrailPoints.Length()]
    if(x=previous.x && y=previous.y)
        return
    mouseGestureTrailPoints.Push({x:x, y:y})
    if(mouseGestureTrailPoints.Length()>256)
        mouseGestureTrailPoints.RemoveAt(1)
    ; Recognition still samples every 20 ms; painting at most 25 FPS avoids
    ; repeatedly rebuilding a large layered bitmap while the pointer moves.
    if(A_TickCount-mouseGestureTrailLastPaint<40)
        return
    mouseGestureTrailLastPaint:=A_TickCount
    if(!mouseGesture_trailRender())
        mouseGesture_trailStop()
}

mouseGesture_rendererInit(){
    global mouseGestureGdipToken
    VarSetCapacity(gdipInput, A_PtrSize=8 ? 24 : 16, 0)
    NumPut(1, gdipInput, 0, "UInt")
    result:=DllCall("gdiplus\GdiplusStartup", "Ptr*", mouseGestureGdipToken
        , "Ptr", &gdipInput, "Ptr", 0, "UInt")
    return result=0 && mouseGestureGdipToken
}

mouseGesture_trailRender(){
    global mouseGestureTrailPoints, mouseGestureTrailHwnd
    if(!mouseGestureTrailHwnd || !IsObject(mouseGestureTrailPoints))
        return false

    first:=mouseGestureTrailPoints[1]
    minX:=maxX:=first.x
    minY:=maxY:=first.y
    for _, point in mouseGestureTrailPoints
    {
        minX:=Min(minX, point.x), maxX:=Max(maxX, point.x)
        minY:=Min(minY, point.y), maxY:=Max(maxY, point.y)
    }
    left:=minX-8, top:=minY-8
    width:=maxX-minX+17, height:=maxY-minY+17
    if(width*height>8000000)
        return false

    screenDC:=DllCall("GetDC", "Ptr", 0, "Ptr")
    memoryDC:=DllCall("gdi32\CreateCompatibleDC", "Ptr", screenDC, "Ptr")
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", screenDC)
    if(!memoryDC)
        return false
    VarSetCapacity(bitmapInfo, 44, 0)
    NumPut(40, bitmapInfo, 0, "UInt")
    NumPut(width, bitmapInfo, 4, "Int")
    NumPut(-height, bitmapInfo, 8, "Int")
    NumPut(1, bitmapInfo, 12, "UShort")
    NumPut(32, bitmapInfo, 14, "UShort")
    bitmap:=DllCall("gdi32\CreateDIBSection", "Ptr", memoryDC, "Ptr", &bitmapInfo
        , "UInt", 0, "Ptr*", pixels, "Ptr", 0, "UInt", 0, "Ptr")
    if(!bitmap || !pixels)
    {
        DllCall("gdi32\DeleteDC", "Ptr", memoryDC)
        return false
    }
    oldBitmap:=DllCall("gdi32\SelectObject", "Ptr", memoryDC, "Ptr", bitmap, "Ptr")
    DllCall("RtlZeroMemory", "Ptr", pixels, "UPtr", width*height*4)
    graphics:=0, pen:=0, brush:=0, rendered:=false
    if(DllCall("gdiplus\GdipCreateFromHDC", "Ptr", memoryDC, "Ptr*", graphics, "UInt")=0
        && DllCall("gdiplus\GdipCreatePen1", "UInt", 0xFFB000FF, "Float", 9.0
            , "Int", 2, "Ptr*", pen, "UInt")=0
        && DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFFB000FF
            , "Ptr*", brush, "UInt")=0)
    {
        DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", graphics, "Int", 4)
        DllCall("gdiplus\GdipSetPenStartCap", "Ptr", pen, "Int", 2)
        DllCall("gdiplus\GdipSetPenEndCap", "Ptr", pen, "Int", 2)
        DllCall("gdiplus\GdipFillEllipseI", "Ptr", graphics, "Ptr", brush
            , "Int", first.x-left-5, "Int", first.y-top-5, "Int", 10, "Int", 10)
        previous:=first
        for index, point in mouseGestureTrailPoints
        {
            if(index>1)
                DllCall("gdiplus\GdipDrawLineI", "Ptr", graphics, "Ptr", pen
                    , "Int", previous.x-left, "Int", previous.y-top
                    , "Int", point.x-left, "Int", point.y-top)
            previous:=point
        }
        VarSetCapacity(destination, 8, 0)
        NumPut(left, destination, 0, "Int"), NumPut(top, destination, 4, "Int")
        VarSetCapacity(size, 8, 0)
        NumPut(width, size, 0, "Int"), NumPut(height, size, 4, "Int")
        VarSetCapacity(source, 8, 0)
        VarSetCapacity(blend, 4, 0)
        NumPut(255, blend, 2, "UChar"), NumPut(1, blend, 3, "UChar")
        rendered:=DllCall("UpdateLayeredWindow", "Ptr", mouseGestureTrailHwnd
            , "Ptr", 0, "Ptr", &destination, "Ptr", &size
            , "Ptr", memoryDC, "Ptr", &source, "UInt", 0
            , "Ptr", &blend, "UInt", 2, "Int")
    }
    if(brush)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
    if(pen)
        DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    if(graphics)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
    if(oldBitmap)
        DllCall("gdi32\SelectObject", "Ptr", memoryDC, "Ptr", oldBitmap)
    DllCall("gdi32\DeleteObject", "Ptr", bitmap)
    DllCall("gdi32\DeleteDC", "Ptr", memoryDC)
    return rendered
}

mouseGesture_trailStop(){
    global mouseGestureState, mouseGestureTrailHwnd, mouseGestureTrailPoints
    global mouseGestureTrailLastPaint
    if(mouseGestureTrailHwnd && DllCall("IsWindow", "Ptr", mouseGestureTrailHwnd))
        Gui, MouseGestureTrail:Destroy
    mouseGestureTrailHwnd:=0
    mouseGestureTrailPoints:=[]
    mouseGestureTrailLastPaint:=0
    if(IsObject(mouseGestureState))
        mouseGestureState.trailVisible:=false
}

#If mouseGesture_isGestureWindow()
RButton::
gosub mouseGesture_KeyDown
return
#If

mouseGesture_KeyDown:
if(m_WaitForRelease && m_LastGestureKey="RButton")
    return
mouseGesture_beginPress()
CoordMode, Mouse, Screen
SendMode, Input
SetMouseDelay, -1
mouseGesture_captureTarget()
gosub GestureKey_Down
mouseGesture_trailStop()
mouseGesture_hintStop()
return

; Keyboard escape hatch remains usable even while regular hotkeys are suspended.
^!+F12::
Suspend, Permit
ExitApp
return

#Include %A_LineFile%\..\vendor\LexikosGestureEngine.ahk
