; CapsLock+ 保持唤醒（防止息屏 / 休眠）
;
; 机制说明：这里调用的是 Windows 自带的电源管理接口 SetThreadExecutionState，
; 与 PowerToys Awake 使用的是同一个系统能力，效果等价：
;   ES_CONTINUOUS       持续声明需求，直到显式清除
;   ES_SYSTEM_REQUIRED  阻止系统自动睡眠
;   ES_DISPLAY_REQUIRED 阻止显示器自动关闭（永不息屏）
; 只使用系统标志位，没有引入任何第三方源码；托盘菜单与提示窗的写法
; 沿用本仓库已有风格（深色圆角提示窗，与鼠标手势提示同一视觉语言）。
;
; 入口：
;   - 托盘图标右键菜单「防止息屏与睡眠」（带勾选状态）
;   - 托盘右键菜单「唤醒方式」子菜单：屏幕常亮 + 系统不睡眠 / 仅系统不睡眠
;   - Caps+F10（默认绑定，可在 CapsLock+settings.ini 的 [Keys] 中改）

; 本文件只有函数和标签，没有顶层可执行语句。
; 注意：lib_init.ahk 开头的 return 已经结束了 auto-execute 段，
; 所以这里顶层的 global 赋值不会被自动执行，必须由 awake_init() 负责初始化。
global awakeActive
global awakeKeepDisplay
global awakeTrayMenuBuilt
global awakeOsdHwnd
global awakeReassertInterval

; EXECUTION_STATE 标志位
global AWKE_ES_CONTINUOUS
global AWKE_ES_SYSTEM_REQUIRED
global AWKE_ES_DISPLAY_REQUIRED

awake_init(){
    global awakeActive, awakeKeepDisplay, awakeTrayMenuBuilt, awakeOsdHwnd, awakeReassertInterval
    global AWKE_ES_CONTINUOUS, AWKE_ES_SYSTEM_REQUIRED, AWKE_ES_DISPLAY_REQUIRED

    awakeActive:=false
    awakeKeepDisplay:=true
    awakeTrayMenuBuilt:=false
    awakeOsdHwnd:=0
    awakeReassertInterval:=60000

    AWKE_ES_CONTINUOUS:=0x80000000
    AWKE_ES_SYSTEM_REQUIRED:=0x00000001
    AWKE_ES_DISPLAY_REQUIRED:=0x00000002

    awake_readMode()
    SetTimer, awake_reassert, Off
    OnExit("awake_onExit")
    return
}

awake_readMode(){
    global awakeKeepDisplay
    IniRead, awakeMode, CapsLock+settings.ini, Global, awakeMode, display
    awakeKeepDisplay:=(awakeMode!="system")
    awake_applyModeChecks()
    return
}

; 托盘菜单由 lib_settingsGui.ahk 的 settingsGui_init() 在 NoStandard/Standard
; 之间调用，因此这两个菜单项自然落在「设置...」之下、系统标准项之上。
awake_buildTrayMenu(){
    global awakeTrayMenuBuilt
    Menu, Tray, Add, % awake_trayLabel(), awakeMenuToggle
    Menu, AwakeMode, Add, % awake_modeLabel(true), awakeMenuModeDisplay
    Menu, AwakeMode, Add, % awake_modeLabel(false), awakeMenuModeSystem
    Menu, Tray, Add, % awake_modeMenuLabel(), :AwakeMode
    awakeTrayMenuBuilt:=true
    awake_applyModeChecks()
    awake_applyToggleCheck()
    return
}

; 菜单项名称必须保持稳定：Menu 的 Check/Uncheck 是按名称定位的，
; 而按键绑定是可以通过 [Keys] 改掉的，所以按键提示只放进提示窗。
awake_trayLabel(){
    return isLangChinese() ? "防止息屏与睡眠" : "Prevent screen off and sleep"
}

awake_modeMenuLabel(){
    return isLangChinese() ? "唤醒方式" : "Awake mode"
}

; 这里的名字必须和开关项（awake_trayLabel）明显不同：
; 子菜单的勾选表示“当前用的是哪种方式”，并不表示“功能已开启”，
; 两者重名时用户会误以为勾着就是开着的。
awake_modeLabel(display){
    if(isLangChinese())
        return display ? "屏幕常亮 + 系统不睡眠" : "仅系统不睡眠"
    return display ? "Display and system stay awake" : "System stays awake only"
}

awake_applyModeChecks(){
    global awakeKeepDisplay, awakeTrayMenuBuilt
    if(!awakeTrayMenuBuilt)
        return
    if(awakeKeepDisplay)
    {
        Menu, AwakeMode, Check, % awake_modeLabel(true)
        Menu, AwakeMode, Uncheck, % awake_modeLabel(false)
    }
    else
    {
        Menu, AwakeMode, Uncheck, % awake_modeLabel(true)
        Menu, AwakeMode, Check, % awake_modeLabel(false)
    }
    return
}

awake_applyToggleCheck(){
    global awakeActive, awakeTrayMenuBuilt
    if(!awakeTrayMenuBuilt)
        return
    if(awakeActive)
        Menu, Tray, Check, % awake_trayLabel()
    else
        Menu, Tray, Uncheck, % awake_trayLabel()
    return
}

; 从当前键位设置里找出真实绑定，提示窗就不会和实际按键脱节
awake_hotkeyHint(){
    global keyset
    if(!IsObject(keyset))
        return ""
    for name, target in keyset
    {
        if(SubStr(name, 1, 5)!="caps_")
            continue
        if(SubStr(target, 1, 19)!="keyFunc_toggleAwake")
            continue
        return "Caps+" . awake_keyName(SubStr(name, 6))
    }
    return ""
}

awake_keyName(key){
    if(RegExMatch(key, "i)^f(\d+)$", m))
        return "F" . m1
    if(key="backquote")
        return "``"
    if(key="minus")
        return "-"
    if(key="equal")
        return "="
    if(key="backspace")
        return "Backspace"
    if(key="space")
        return "Space"
    if(StrLen(key)=1)
    {
        ; AHK v1 没有 StrUpper，用 StringUpper 命令取大写
        StringUpper, keyUpper, key
        return keyUpper
    }
    return key
}

awakeMenuToggle:
awake_toggle()
return

awakeMenuModeDisplay:
awake_setMode(true)
return

awakeMenuModeSystem:
awake_setMode(false)
return

; 切换开关：开 -> 关，关 -> 开
awake_toggle(){
    global awakeActive
    awakeActive:=!awakeActive
    if(awakeActive)
        awake_apply()
    else
        awake_release()
    awake_applyToggleCheck()
    awake_showHint()
    return
}

; 切换唤醒方式（屏幕常亮 / 仅系统不睡眠），开启状态下立即生效
awake_setMode(keepDisplay){
    global awakeActive, awakeKeepDisplay
    if(awakeKeepDisplay=keepDisplay)
    {
        awake_applyModeChecks()
        return
    }
    awakeKeepDisplay:=keepDisplay
    setSettings("Global", "awakeMode", keepDisplay ? "display" : "system")
    awake_applyModeChecks()
    if(awakeActive)
        awake_apply()
    awake_showHint()
    return
}

; 设置文件被外部改动时同步唤醒方式
awake_refreshSettings(){
    awake_readMode()
    if(awakeActive)
        awake_apply()
    return
}

; 向系统声明需求。重复调用是安全的：每次都整体重设本线程的状态。
awake_apply(){
    global awakeKeepDisplay, awakeReassertInterval
    global AWKE_ES_CONTINUOUS, AWKE_ES_SYSTEM_REQUIRED, AWKE_ES_DISPLAY_REQUIRED

    flags:=AWKE_ES_CONTINUOUS | AWKE_ES_SYSTEM_REQUIRED
    if(awakeKeepDisplay)
        flags:=flags | AWKE_ES_DISPLAY_REQUIRED

    ok:=DllCall("SetThreadExecutionState", "UInt", flags, "UInt")
    ; 从睡眠 / 休眠恢复后状态可能被系统重置，定时重新声明一次兜底
    SetTimer, awake_reassert, % awakeReassertInterval
    return ok ? true : false
}

; 清除需求，把电源控制交回系统
awake_release(){
    global AWKE_ES_CONTINUOUS
    SetTimer, awake_reassert, Off
    DllCall("SetThreadExecutionState", "UInt", AWKE_ES_CONTINUOUS, "UInt")
    return
}

awake_reassert:
if(!awakeActive)
{
    SetTimer, awake_reassert, Off
    return
}
awake_apply()
return

awake_onExit(exitReason, exitCode){
    ; 进程退出时系统也会回收，这里显式清除一次，避免残留到下次拉起
    awake_release()
    return
}

; ---------------- 提示 ----------------
; 深色圆角小窗，不抢焦点，约 1.8 秒后自动消失
awake_showHint(){
    global awakeActive, awakeKeepDisplay

    hotkey:=awake_hotkeyHint()
    if(hotkey="")
        hotkey:=isLangChinese() ? "未绑定按键" : "no hotkey"
    else
        hotkey:=hotkey . (isLangChinese() ? " 切换" : " toggles")

    if(isLangChinese())
    {
        title:=awakeActive ? "已开启：防止息屏与睡眠" : "已关闭：防止息屏与睡眠"
        if(!awakeActive)
            sub:="已交回系统电源计划 · " . hotkey
        else
            sub:=awakeKeepDisplay
                ? "屏幕不会关闭，系统不会睡眠 · " . hotkey
                : "系统不会睡眠，屏幕仍按计划关闭 · " . hotkey
    }
    else
    {
        title:=awakeActive ? "Keep-awake: on" : "Keep-awake: off"
        if(!awakeActive)
            sub:="Your power plan is back in control · " . hotkey
        else
            sub:=awakeKeepDisplay
                ? "Display and PC stay awake · " . hotkey
                : "PC stays awake, display may still sleep · " . hotkey
    }
    awake_osdShow(title, sub, awakeActive)
    return
}

awake_osdShow(title, sub, isOn){
    global awakeOsdHwnd, awakeOsdTitleHwnd, awakeOsdSubHwnd

    if(!awakeOsdHwnd || !DllCall("IsWindow", "Ptr", awakeOsdHwnd))
        awake_osdInit()
    if(!awakeOsdHwnd)
    {
        ; 提示窗创建失败时退回仓库原有的 ToolTip 提示
        showMsg(title . "`n" . sub)
        return
    }

    ; 刷新控件内容，避免每次切换都重建窗口
    barColor:=isOn ? "4CD07D" : "6B6480"
    GuiControl, AwakeOsd:, AwakeOsdTitle, %title%
    GuiControl, AwakeOsd:, AwakeOsdSub, %sub%
    GuiControl, AwakeOsd:+c%barColor%, AwakeOsdBar

    ; 先量出两行文字的真实像素尺寸，再据此排版。
    ; 不能写死行高：200% 缩放下 12pt 实际高 32px，写死 26px 就会两行叠在一起。
    awake_textSize(awake_osdFontHandle(awakeOsdTitleHwnd), title, titleW, titleH)
    awake_textSize(awake_osdFontHandle(awakeOsdSubHwnd), sub, subW, subH)
    if(titleH<8)
        titleH:=16
    if(titleW<8)
        titleW:=80
    if(subH<8)
        subH:=14
    if(subW<8)
        subW:=60

    ; 用标题字高当排版基准，padding 跟着 DPI 一起放大
    em:=titleH
    padX:=Round(em*0.55)
    barW:=Round(em*0.14)
    if(barW<3)
        barW:=3
    textX:=padX+barW+Round(em*0.55)
    rightPad:=Round(em*0.7)
    titleY:=Round(em*0.34)
    subY:=titleY+titleH+Round(em*0.30)
    barH:=subY+subH-titleY

    contentW:=titleW > subW ? titleW : subW
    textW:=contentW+Round(em*0.2)                ; 留一点余量，免得最后一个字被削
    width:=textX+textW+rightPad
    height:=subY+subH+titleY

    ; 找鼠标所在显示器的工作区，作为居中与上限的依据
    SysGet, monitorCount, MonitorCount
    MouseGetPos, mouseX, mouseY
    areaLeft:=0
    areaTop:=0
    areaRight:=A_ScreenWidth
    areaBottom:=A_ScreenHeight
    Loop, %monitorCount%
    {
        SysGet, wa, MonitorWorkArea, %A_Index%
        if(mouseX>=waLeft && mouseX<waRight && mouseY>=waTop && mouseY<waBottom)
        {
            areaLeft:=waLeft
            areaTop:=waTop
            areaRight:=waRight
            areaBottom:=waBottom
            break
        }
    }

    ; 再长的内容也不超出当前显示器
    maxWidth:=areaRight-areaLeft-40
    if(width>maxWidth)
    {
        width:=maxWidth
        textW:=width-textX-rightPad
        if(textW<40)
            textW:=40
    }

    ; 位置与尺寸都按实测结果设置，控件和窗口同步
    GuiControl, AwakeOsd:MoveDraw, AwakeOsdBar, x%padX% y%titleY% w%barW% h%barH%
    GuiControl, AwakeOsd:MoveDraw, AwakeOsdTitle, x%textX% y%titleY% w%textW% h%titleH%
    GuiControl, AwakeOsd:MoveDraw, AwakeOsdSub, x%textX% y%subY% w%textW% h%subH%

    left:=areaLeft+Round((areaRight-areaLeft-width)/2)
    top:=areaBottom-height-16
    if(top<areaTop)
        top:=areaTop

    Gui, AwakeOsd:Show, x%left% y%top% w%width% h%height% NA
    WinSet, Region, 0-0 w%width% h%height% R16-16, ahk_id %awakeOsdHwnd%
    SetTimer, awake_osdHide, -1800
    return
}

; 取控件当前实际使用的字体句柄
awake_osdFontHandle(hCtrl){
    if(!hCtrl)
        return 0
    return DllCall("SendMessage", "Ptr", hCtrl, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
}

; 用控件当前字体实测文字的像素宽高。
; 200% 缩放下 12pt 实际是 32px 高，只有实测才不会把行高和宽度排错。
awake_textSize(hFont, text, byref w, byref h){
    w:=0
    h:=0
    if(!hFont || text="")
        return
    hdc:=DllCall("GetDC", "Ptr", 0, "Ptr")
    if(!hdc)
        return
    oldFont:=DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr")
    VarSetCapacity(sz, 8, 0)
    DllCall("GetTextExtentPoint32W", "Ptr", hdc, "WStr", text, "Int", StrLen(text), "Ptr", &sz)
    w:=NumGet(sz, 0, "Int")
    h:=NumGet(sz, 4, "Int")
    if(oldFont)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Ptr")
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
    return
}

awake_osdInit(){
    ; AHK v1 要求 Gui Add 的 v 变量在函数内必须是 global/static，否则弹错
    global awakeOsdHwnd, AwakeOsdBar, AwakeOsdTitle, AwakeOsdSub
    global awakeOsdTitleHwnd, awakeOsdSubHwnd
    awakeOsdHwnd:=0
    awakeOsdTitleHwnd:=0
    awakeOsdSubHwnd:=0
    Gui, AwakeOsd:New, +AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale +HwndawakeOsdHwnd
    if(!awakeOsdHwnd)
        return
    Gui, AwakeOsd:Color, 241633
    ; 位置和尺寸都由 awake_osdShow() 按实测文字重新计算，这里只建控件
    Gui, AwakeOsd:Add, Progress, vAwakeOsdBar x20 y14 w4 h40 Background3D2A55 c4CD07D Disabled, 100
    Gui, AwakeOsd:Font, s12 w600 cFFFFFF, Microsoft YaHei UI
    Gui, AwakeOsd:Add, Text, vAwakeOsdTitle x36 y12 w600 +0x200 BackgroundTrans +HwndawakeOsdTitleHwnd
    Gui, AwakeOsd:Font, s9 w400 cB8B2CC, Microsoft YaHei UI
    Gui, AwakeOsd:Add, Text, vAwakeOsdSub x36 y50 w600 +0x200 BackgroundTrans +HwndawakeOsdSubHwnd
    WinSet, Transparent, 240, ahk_id %awakeOsdHwnd%
    return
}
awake_osdHide:
Gui, AwakeOsd:Hide
return
