; CapsLock+ adapter for the original Lexikos mouse gesture engine.
; Recognition and gesture lifecycle live in vendor/LexikosGestureEngine.ahk.
; This file only supplies settings, application actions and the safe trail renderer.

mouseGesture_init(){
    global
    mouseGestureState:={trailVisible:false}
    mouseGestureTarget:=""
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
    if(!mouseGesture_rendererInit())
        mouseGestureDrawTrail:=false
    mouseGesture_hintInit()
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

mouseGesture_acceptWindow(){
    global settingsGuiHwnd
    CoordMode, Mouse, Screen
    MouseGetPos,,, hwnd
    if(!hwnd)
        return false
    rootHwnd:=DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
    if(rootHwnd)
        hwnd:=rootHwnd
    if(settingsGuiHwnd && hwnd=settingsGuiHwnd)
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
    global mouseGestureTarget, m_Gesture
    if(!IsObject(mouseGestureTarget))
        return false
    target:=mouseGestureTarget
    path:=StrReplace(m_Gesture, "_")
    if(!mouseGesture_resolveAction(path, target.process))
        return false
    return mouseGesture_execute(path, target.hwnd, target.process, target.class)
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
    global m_PassKeyUp, mouseGestureGdipToken
    mouseGesture_trailStop()
    mouseGesture_hintStop()
    Gui, MouseGestureHint:Destroy
    if(mouseGestureGdipToken)
        DllCall("gdiplus\GdiplusShutdown", "Ptr", mouseGestureGdipToken)
    ; A timeout can have forwarded button-down; never leave it held on exit.
    if(m_PassKeyUp)
        SendInput, {RButton Up}
}

mouseGesture_hintInit(){
    global mouseGestureHintHwnd, mouseGestureHintShown, MouseGestureHintText
    mouseGestureHintShown:=false
    Gui, MouseGestureHint:New, +AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale +HwndmouseGestureHintHwnd
    Gui, MouseGestureHint:Color, 241633
    Gui, MouseGestureHint:Font, s23 cFFFFFF, Segoe UI
    Gui, MouseGestureHint:Add, Text, vMouseGestureHintText Center x12 y10 w336 h60, 手势
    Gui, MouseGestureHint:Show, Hide w360 h80 NA
    WinSet, Transparent, 238, ahk_id %mouseGestureHintHwnd%
    WinSet, Region, 0-0 w360 h80 R18-18, ahk_id %mouseGestureHintHwnd%
}

mouseGesture_hintUpdate(){
    global mouseGestureTarget, mouseGestureHintHwnd, mouseGestureHintShown
    global m_Gesture, m_StartX, m_StartY
    ; Only Chrome shows the gesture preview; other applications stay unobstructed.
    if(!IsObject(mouseGestureTarget) || mouseGestureTarget.process!="chrome.exe"
        || !mouseGestureHintHwnd)
        return
    path:=StrReplace(m_Gesture, "_")
    arrows:=""
    Loop, Parse, path
    {
        if(A_LoopField="L")
            arrows.="←"
        else if(A_LoopField="R")
            arrows.="→"
        else if(A_LoopField="U")
            arrows.="↑"
        else if(A_LoopField="D")
            arrows.="↓"
    }
    if(StrLen(arrows)>4)
        arrows:=SubStr(arrows, 1, 4) . "…"
    action:=mouseGesture_resolveAction(path, mouseGestureTarget.process)
    displayText:=arrows . "  " . mouseGesture_actionName(action, path)
    GuiControl, MouseGestureHint:, MouseGestureHintText, %displayText%
    if(mouseGestureHintShown)
        return
    left:=Round((A_ScreenWidth-360)/2)
    top:=Round((A_ScreenHeight-80)/2)
    SysGet, monitorCount, MonitorCount
    Loop, %monitorCount%
    {
        SysGet, area, MonitorWorkArea, %A_Index%
        if(m_StartX>=areaLeft && m_StartX<areaRight
            && m_StartY>=areaTop && m_StartY<areaBottom)
        {
            left:=Round((areaLeft+areaRight-360)/2)
            top:=Round((areaTop+areaBottom-80)/2)
            break
        }
    }
    Gui, MouseGestureHint:Show, x%left% y%top% w360 h80 NA
    mouseGestureHintShown:=true
}

mouseGesture_actionName(action, path){
    if(isLangChinese())
    {
        static namesZh:=["后退", "前进", "新建标签页", "到页面底部", "到页面顶部"
            , "刷新", "左侧标签页", "右侧标签页", "关闭标签页", "关闭窗口"]
        if(action)
            return namesZh[action]
        return (path="U" || path="D") ? "继续滑动" : "未设置动作"
    }
    static namesEn:=["Back", "Forward", "New tab", "Page bottom", "Page top"
        , "Refresh", "Previous tab", "Next tab", "Close tab", "Close window"]
    if(action)
        return namesEn[action]
    return (path="U" || path="D") ? "Keep moving" : "No action"
}

mouseGesture_hintStop(){
    global mouseGestureHintHwnd, mouseGestureHintShown
    if(mouseGestureHintShown && mouseGestureHintHwnd)
        Gui, MouseGestureHint:Hide
    mouseGestureHintShown:=false
}

mouseGesture_execute(path, targetHwnd, targetProcess, targetClass){
    if(!DllCall("IsWindow", "Ptr", targetHwnd))
        return false

    action:=mouseGesture_resolveAction(path, targetProcess)
    if action = 0
        return false

    if action = 10
    {
        if(!mouseGesture_canCloseWindow(targetHwnd, targetClass))
            return false
        DllCall("PostMessage", "Ptr", targetHwnd, "UInt", 0x10, "Ptr", 0, "Ptr", 0)
        return true
    }

    if targetProcess = chrome.exe
    {
        if(!WinActive("ahk_id " . targetHwnd))
        {
            WinActivate, ahk_id %targetHwnd%
            WinWaitActive, ahk_id %targetHwnd%,, 1
        }
        if(!WinActive("ahk_id " . targetHwnd))
            return false

        if action = 1
            SendInput, !{Left}
        if action = 2
            SendInput, !{Right}
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

mouseGesture_resolveAction(g, p){
    ; Exact matching is handled by upstream label dispatch; never accept a prefix.
    static chromeActions:={L:1, R:2, DR:3, RD:4, RU:5, UD:6, UL:7, UR:8, DL:9}
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

    mouseGesture_trailStop()
    if(!mouseGestureGdipToken)
        return
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

CLMouseGesture_L:
CLMouseGesture_R:
CLMouseGesture_R_D:
CLMouseGesture_R_U:
CLMouseGesture_U_D:
CLMouseGesture_U_L:
CLMouseGesture_U_R:
CLMouseGesture_D_L:
CLMouseGesture_D_R:
mouseGesture_dispatch()
return

#Include %A_LineFile%\..\vendor\LexikosGestureEngine.ahk
