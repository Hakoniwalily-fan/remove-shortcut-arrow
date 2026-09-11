<div align="center">

# Remove Shortcut Arrow

**Safely remove the little arrow overlay from Windows 10 / 11 desktop shortcuts.**

[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6?logo=windows&logoColor=white)](#requirements)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[English](#english) · [中文说明](#中文说明)

</div>

---

## One-line install

Open **PowerShell as Administrator** and run:

```powershell
irm https://raw.githubusercontent.com/Hakoniwalily-fan/remove-shortcut-arrow/main/install.ps1 | iex
```

That downloads the script, generates the transparent icon, applies the registry
change, clears the icon cache and restarts Explorer. The arrow disappears.

To put the arrow back:

```powershell
& "$env:LOCALAPPDATA\ShortcutArrow\ShortcutArrow.ps1" -Action Restore
```

Prefer no one-liner? Grab the [latest release](https://github.com/Hakoniwalily-fan/remove-shortcut-arrow/releases/latest)
and double-click `Remove-ShortcutArrow.bat`.

---

## Why not just delete `IsShortcut`?

Almost every "how to remove the shortcut arrow" guide tells you to delete the
`IsShortcut` value under `HKEY_CLASSES_ROOT\lnkfile`. **Don't.** That makes
Windows stop treating `.lnk` as a shortcut at all, and you get:

| Symptom | What actually breaks |
|---|---|
| "Pin to taskbar" / "Pin to Start" vanish or do nothing | Shell no longer recognises the file as a shortcut |
| Double-clicking errors out | *"This file does not have an app associated with it. Please install an app..."* |
| Dragging onto the taskbar stops working | Taskbar pinning path relies on the shortcut association |
| Start menu search behaves oddly | Linking/indexing of shortcuts changes |

Undoing it means adding `IsShortcut` back, rebuilding the icon cache, and
sometimes touching Group Policy — a lot of pain for a cosmetic change.

**This project never touches `IsShortcut`.** It only swaps the *overlay icon*
painted on top of the shortcut icon, so every shortcut behaviour stays intact.

---

## How it works

The shortcut arrow is not part of the icon file. It is an **icon overlay**
registered in the shell:

```
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons
    Value name : 29        (REG_SZ)
    Value data : <path to an icon>
```

`29` is the overlay slot for shortcuts. Point it at a **fully transparent icon**
and the arrow is still drawn — it just draws nothing.

The script builds that transparent `.ico` from scratch at runtime (16 / 32 / 48
px, hand-assembled ICO binary, every pixel Alpha = 0). No bundled binary, no
downloaded asset, nothing to trust.

### Why the icon lives in `%LOCALAPPDATA%`

The registry stores an **absolute path**. Most similar tools generate the icon
next to the script — so the moment you move or rename that folder, the registry
points at a file that no longer exists and the arrow silently comes back after
the next Explorer restart or reboot.

This script stores it at a stable location instead:

```
%LOCALAPPDATA%\ShortcutArrow\blank.ico
```

---

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 (built in) or PowerShell 7+
- Administrator rights (writes to `HKEY_LOCAL_MACHINE`)
- No admin? The script still runs and falls back to `HKEY_CURRENT_USER`, and
  tells you so in the log.

---

## Usage

### Installer (recommended)

```powershell
irm https://raw.githubusercontent.com/Hakoniwalily-fan/remove-shortcut-arrow/main/install.ps1 | iex
```

`install.ps1` downloads the current script into `%LOCALAPPDATA%\ShortcutArrow\`
and re-launches itself elevated if needed.

### Straight from a clone

```powershell
.\ShortcutArrow.ps1 -Action Remove     # remove the arrow
.\ShortcutArrow.ps1 -Action Restore    # put it back
```

### Double-click

| File | Purpose |
|---|---|
| `Remove-ShortcutArrow.bat` | removes the arrow (asks for UAC) |
| `Restore-ShortcutArrow.bat` | restores it |

### Options

| Parameter | Description |
|---|---|
| `-Action Remove` | hide the arrow (default) |
| `-Action Restore` | restore the arrow |
| `-UseSystemIcon` | use the built-in blank icon `imageres.dll,195` instead of generating a `.ico` |
| `-NoRestart` | don't restart Explorer; takes effect after the next restart |

> `-UseSystemIcon` was measured as fully transparent (Alpha = 0) on Windows 11
> build 26200. Icon indices can shift between Windows versions, which is why the
> default is the self-generated `.ico` — that can never point at the wrong icon.

---

## What the script changes

**`-Action Remove`**

1. Generates a fully transparent `blank.ico` in `%LOCALAPPDATA%\ShortcutArrow\`
   (skipped if it already exists)
2. Sets `Shell Icons` value `29` to that icon
   - elevated → `HKLM` (documented location, machine-wide)
   - not elevated → falls back to `HKCU`
3. Clears the icon cache (`IconCache.db`, `iconcache_*.db`, `thumbcache_*.db`)
4. Restarts `explorer.exe`

**`-Action Restore`**

1. Deletes value `29` from `HKLM` and `HKCU`
2. Clears the icon cache
3. Restarts `explorer.exe`

Every run appends to `ShortcutArrow.log` next to the script. Check it first when
something looks wrong.

---

## FAQ

**The arrow is still there.**
Check `ShortcutArrow.log` for `FAIL ... not writable`. You almost certainly ran
it without Administrator rights.

**The arrow came back after a reboot.**
The icon path in the registry went stale — usually because `blank.ico` was
deleted. Re-run the installer.

**The arrow came back after a Windows feature update.**
Cumulative updates sometimes reset this registry key. Re-run the script.

**Now I can't tell shortcuts from real files.**
That is unavoidable — without the arrow they look identical. If what you wanted
was *prettier* rather than *gone*, point value `29` at your own subtle arrow
icon; everything else stays the same.

**Antivirus flagged it.**
The script edits the registry and restarts Explorer, which looks suspicious to
heuristics. The whole thing is one readable PowerShell file.

---

## Uninstall

```powershell
& "$env:LOCALAPPDATA\ShortcutArrow\ShortcutArrow.ps1" -Action Restore
Remove-Item "$env:LOCALAPPDATA\ShortcutArrow" -Recurse -Force
```

### Manual restore

`Win+R` → `regedit` → go to:

```
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons
```

Delete the string value named `29`. Check the same path under
`HKEY_CURRENT_USER` too. Then reboot.

---

## 中文说明

**用「遮挡层图标替换法」去掉 Windows 10 / 11 桌面快捷方式左下角的小箭头，不影响任何快捷方式功能。**

### 一行安装

以**管理员身份**打开 PowerShell，执行：

```powershell
irm https://raw.githubusercontent.com/Hakoniwalily-fan/remove-shortcut-arrow/main/install.ps1 | iex
```

想恢复箭头：

```powershell
& "$env:LOCALAPPDATA\ShortcutArrow\ShortcutArrow.ps1" -Action Restore
```

### 为什么不用网上那个「删除 IsShortcut」的方法

搜「去掉快捷方式箭头」，排前面的几乎都是让你删掉
`HKEY_CLASSES_ROOT\lnkfile` 下的 `IsShortcut` 值。**别这么做**——那会让系统
不再把 `.lnk` 当作快捷方式，后果是：

| 症状 | 原因 |
|---|---|
| 「固定到任务栏」/「固定到开始屏幕」消失或点击无效 | 外壳不再把该文件识别为快捷方式 |
| 双击快捷方式报错 | 「该文件没有与之关联的应用来执行该操作」 |
| 拖放到任务栏失效 | 固定流程依赖快捷方式关联 |
| 开始菜单搜索异常 | 快捷方式的索引行为被改变 |

想恢复还得把 `IsShortcut` 加回去、重建图标缓存，有时还要动组策略。

**本项目完全不碰 `IsShortcut`**，只替换画在图标上的那层覆盖图标，所以快捷方式的
识别、固定、拖放等行为全部正常。

### 原理

箭头是一个**图标覆盖层**，由注册表指定：

```
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons
    值名: 29        (REG_SZ)
    值数据: <图标路径>
```

`29` 就是快捷方式覆盖层的编号。指向一个**全透明图标**，箭头照画，只是画出来什么都没有。

脚本在运行时**自己拼出**这个透明 `.ico`（16 / 32 / 48 三种尺寸，逐像素 Alpha = 0），
不依赖任何预置文件。

### 图标为什么放在 `%LOCALAPPDATA%`

注册表里存的是**绝对路径**。多数同类工具把图标生成在脚本旁边——你一旦移动或重命名
那个文件夹，路径就失效，**重启后箭头会悄悄回来**。

本脚本把它放在固定位置：`%LOCALAPPDATA%\ShortcutArrow\blank.ico`

### 文件

| 文件 | 用途 |
|---|---|
| `install.ps1` | 一行安装入口，自动处理提权 |
| `ShortcutArrow.ps1` | 主脚本（Remove / Restore） |
| `Remove-ShortcutArrow.bat` | 双击去箭头 |
| `Restore-ShortcutArrow.bat` | 双击恢复箭头 |

### 参数

| 参数 | 说明 |
|---|---|
| `-Action Remove` | 去掉箭头（默认） |
| `-Action Restore` | 恢复箭头 |
| `-UseSystemIcon` | 用系统自带空白图标 `imageres.dll,195`，不生成 .ico |
| `-NoRestart` | 不重启 explorer，下次重启后生效 |

---

## License

[MIT](LICENSE)
