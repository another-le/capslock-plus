# 开发与发布

面向仓库维护者。使用者请先看 [README](README.md)。

## 防止息屏与睡眠的实现

相关文件：

| 文件 | 作用 |
| --- | --- |
| `lib/lib_awake.ahk` | 状态机、托盘菜单、提示窗、`SetThreadExecutionState` 调用 |
| `lib/lib_init.ahk` | 在 `init()` 里调用 `awake_init()` |
| `lib/lib_settingsGui.ahk` | 在 `NoStandard` / `Standard` 之间挂上托盘菜单 |
| `lib/lib_keysFunction.ahk` | `keyFunc_toggleAwake()`，键盘入口 |
| `lib/lib_keysSet.ahk` | 两套键位方案里都默认绑定 `caps_f10` |
| `lib/lib_settings.ahk` | INI 监听，`awakeMode` 被外部改动时同步 |

直接调用 Windows 的 `SetThreadExecutionState`，以 `ES_CONTINUOUS` 持续声明 `ES_SYSTEM_REQUIRED`（阻止睡眠）和 `ES_DISPLAY_REQUIRED`（阻止息屏）。这与 PowerToys Awake 使用的是同一个系统机制，本仓库没有引入 PowerToys 的代码。

系统在从睡眠或休眠恢复后可能重置该状态，所以开启期间每 60 秒重新声明一次；脚本退出时通过 `OnExit` 显式清除，避免残留到下次启动。

状态模型是两个布尔量 `awakeKeepDisplay` / `awakeKeepSystem`，唯一的方向性约束是「屏幕常亮蕴含系统不睡眠」：

| 操作 | 结果 |
| --- | --- |
| 勾「保持屏幕常亮」 | 两个都为真 |
| 取消「防止系统睡眠」 | 两个都为假 |
| `Caps+F10` 循环 | 全关 → 只防睡眠 → 屏幕常亮 → 全关 |

持久化字段为 `CapsLock+settings.ini` 的 `[Global] awakeMode`，取值 `display` / `system` / `off`。

## 验证「防止息屏与睡眠」是否生效

根目录的 `awake_counter.ahk` 是一个每秒 +1 的计数窗口，用来目视确认屏幕没有被关掉。

1. 用 AutoHotkey v1 运行它并让窗口一直开着。
2. 先不开功能，等到超过电源计划里的「关闭显示器」时间——屏幕应正常黑掉，数字停止增长。
3. 打开功能后再等同样长的时间——屏幕应保持点亮，数字持续增长。

想缩短等待时间，可在「控制面板 → 电源选项」或 `powercfg` 里临时改当前计划的关闭显示器和睡眠时间。

## 手势回归测试

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_mouseGestureEngine.ps1
```

测试使用独立的模拟输入，不会向桌面发送鼠标事件。当前覆盖 18 条手势 fixture、8 条键位 fixture，以及作用域规则、INI 持久化、编辑器生命周期和右键回放。

## 发布 EXE

将 `v` 开头的版本标签（例如 `v0.2`）推送到 GitHub，会触发 [发布工作流](.github/workflows/release.yml)。它使用固定版本的 AutoHotkey v1 和 Ahk2Exe 编译 64 位 `CapsLock+.exe`，通过回归测试后创建对应的 GitHub Release，并上传 EXE 与 SHA-256 校验文件。只修改或推送普通分支不会创建 Release。

如果某个标签的自动构建失败，可在 GitHub Actions 中从 `master` 手动运行同一工作流，输入已有标签名（例如 `v0.2`）；它会重新编译该标签对应的源码，无需移动或重建标签。

## 编辑注意事项

非 ASCII 的 `.ahk` 文件必须是带 BOM 的 UTF-8，否则 AHK v1 会按 ANSI 解析并报出偏移的行号。部分编辑器保存时会丢掉 BOM，改完建议确认文件前三字节为 `EF BB BF`。
