; 一个每秒 +1 的计数器，用来验证「防止息屏与睡眠」是否生效。
; 屏幕没黑 → 数字继续涨；屏幕黑了 → 数字停住。

#NoEnv
#SingleInstance force
SetWorkingDir, %A_ScriptDir%

Count := 0

Gui, +AlwaysOnTop
Gui, Color, 1B1B22
Gui, Font, s64 w700 cFFFFFF, Consolas
Gui, Add, Text, x0 y10 w360 h100 Center vNum, 0
Gui, Font, s10 c9AA0B8, Microsoft YaHei UI
Gui, Add, Text, x0 y118 w360 h24 Center, 每秒 +1
Gui, Show, w360 h150, 计数器

SetTimer, Tick, 1000
return

Tick:
Count += 1
GuiControl,, Num, %Count%
return

GuiClose:
GuiEscape:
ExitApp
