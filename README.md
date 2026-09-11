<div align="center">

# Remove Shortcut Arrow

**Hide the arrow and/or the UAC shield overlay on Windows 10 / 11 desktop shortcuts — safely.**

[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6?logo=windows&logoColor=white)](#requirements)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[English](#english) · [中文说明](#中文说明)

</div>

---

## English

### What it does

Windows paints two small overlays onto icons in Explorer. This project replaces
each one with a fully transparent icon, so the overlay is still drawn — it just
draws nothing.

| Overlay | Shell Icons slot | Default |
|---|---|---|
| Shortcut arrow (bottom-left of `.lnk` icons) | `29` | hidden |
| **UAC shield** (blue/yellow shield on elevated programs) | `77` | **left alone unless you ask** |

Nothing else is modified. `IsShortcut` is never touched.

### One-line install

Open **PowerShell as Administrator**:

```powershell
# hide the shortcut arrow
irm https://raw.githubusercontent.com/Hakoniwalily-fan/remove-shortcut-arrow/main/install.ps1 | iex
```

```powershell
# hide the shortcut arrow AND the UAC shield
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Hakoniwalily-fan/remove-shortcut-arrow/main/install.ps1))) -IncludeShield
```

Restore everything (both overlays):

```powershell
& "$env:LOCALAPPDATA\ShortcutArrow\ShortcutArrow.ps1" -Action Restore
```

Prefer no one-liner? Grab the [latest release](https://github.com/Hakoniwalily-fan/remove-shortcut-arrow/releases/latest)
and double-click a `.bat`.

---

### ⚠️ About the UAC shield — read this first

**The shield is a warning, not a protection.**

Hiding it does **not** stop a program from requesting administrator rights. The
UAC prompt still appears, the program still elevates, and your actual security
posture is unchanged. What you lose is the visual hint that a program is about
to ask for admin — which is genuinely useful when deciding whether to click
"Yes" out of habit.

Because of that, hiding the shield is **opt-in** (`-IncludeShield`) and is never
done by default.

**What this project deliberately does not do:**

| Not done | Why |
|---|---|
| Editing an executable's manifest to drop `requireAdministrator` | Silently breaks apps that genuinely need admin, and modifies third-party binaries |
| Disabling UAC | A real security downgrade, not a cosmetic change |
| Setting the "Run as administrator" compatibility flag on `.lnk` files | Same problem as editing manifests, and does not even remove the shield |

If the shield bothers you but you still want the warning, a middle ground is to
point slot `77` at a subtle shield icon of your own instead of a transparent one.

---

### Why not just delete `IsShortcut`?

Almost every "how to remove the shortcut arrow" guide tells you to delete the
`IsShortcut` value under `HKEY_CLASSES_ROOT\lnkfile`. **Don't.** That makes
Windows stop treating `.lnk` as a shortcut at all:

| Symptom | What actually breaks |
|---|---|
| "Pin to taskbar" / "Pin to Start" vanish or do nothing | Shell no longer recognises the file as a shortcut |
| Double-clicking errors out | *"This file does not have an app associated with it. Please install an app..."* |
| Dragging onto the taskbar stops working | Taskbar pinning relies on the shortcut association |
| Start menu search behaves oddly | Linking/indexing of shortcuts changes |

Undoing it means adding `IsShortcut` back, rebuilding the icon cache, and
sometimes touching Group Policy — a lot of pain for a cosmetic change.

**This project never touches `IsShortcut`.** It only swaps the overlay icon, so
every shortcut behaviour stays intact.

---

### How it works

Both overlays are registered in the same shell key:

```
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons
    "29" = <icon>     shortcut arrow overlay
    "77" = <icon>     UAC shield overlay
```

Point a slot at a **fully transparent icon** and the overlay is still painted —
it just paints nothing.

The script builds that transparent `.ico` from scratch at runtime (16 / 32 / 48
px, hand-assembled ICO binary, every pixel `Alpha = 0`). No bundled binary, no
downloaded asset, nothing to trust.

#### Why the icon lives in `%LOCALAPPDATA%`

The registry stores an **absolute path**. Most similar tools generate the icon
next to the script — so the moment you move or rename that folder, the registry
points at a file that no longer exists and the overlay silently comes back after
the next Explorer restart or reboot.

This script stores it at a stable location instead:

```
%LOCALAPPDATA%\ShortcutArrow\blank.ico
```

---

### Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 (built in) or PowerShell 7+
- Administrator rights (writes to `HKEY_LOCAL_MACHINE`)
- Without admin the script still runs and falls back to `HKEY_CURRENT_USER`,
  and says so in the log

---

### Usage

#### Installer (recommended)

```powershell
irm https://raw.githubusercontent.com/Hakoniwalily-fan/remove-shortcut-arrow/main/install.ps1 | iex
```

`install.ps1` downloads the current script into `%LOCALAPPDATA%\ShortcutArrow\`
and re-launches itself elevated if needed.

#### Straight from a clone

```powershell
.\ShortcutArrow.ps1 -Action Remove                    # arrow only
.\ShortcutArrow.ps1 -Action Remove -IncludeShield     # arrow + shield
.\ShortcutArrow.ps1 -Action Restore                   # restore both
```

#### Double-click

| File | Purpose |
|---|---|
| `Remove-ShortcutArrow.bat` | removes the arrow only |
| `Remove-ArrowAndShield.bat` | removes the arrow **and** the UAC shield |
| `Restore-ShortcutArrow.bat` | restores both overlays |

#### Options

| Parameter | Description |
|---|---|
| `-Action Remove` | hide the arrow (default) |
| `-Action Restore` | restore the arrow **and** the shield |
| `-IncludeShield` | also hide the UAC shield overlay (slot `77`) |
| `-UseSystemIcon` | use the built-in blank icon `shell32.dll,50` instead of generating a `.ico` |
| `-NoRestart` | don't restart Explorer; takes effect after the next restart |

> `shell32.dll,50` and `imageres.dll,195` were both measured as fully
> transparent (`Alpha = 0`) on Windows 11 build 26200. Icon indices can shift
> between Windows versions, which is why the default is the self-generated
> `.ico` — that can never point at the wrong icon.

---

### What the script changes

**`-Action Remove`**

1. Generates a fully transparent `blank.ico` in `%LOCALAPPDATA%\ShortcutArrow\`
   (skipped if it already exists)
2. Sets `Shell Icons` slot `29` — and slot `77` too with `-IncludeShield`
   - elevated → `HKLM` (documented location, machine-wide)
   - not elevated → falls back to `HKCU`
3. Clears the icon cache (`IconCache.db`, `iconcache_*.db`, `thumbcache_*.db`)
4. Restarts `explorer.exe`

**`-Action Restore`**

1. Deletes slots `29` **and** `77` from `HKLM` and `HKCU`
2. Clears the icon cache
3. Restarts `explorer.exe`

Restore always clears both slots, even if you never hid the shield. A hidden
security indicator should never be able to linger just because a flag was
forgotten. Each removed value is written to the log with its previous content,
so a custom replacement icon can be put back by hand.

Every run appends to `ShortcutArrow.log` next to the script.

---

### FAQ

**The overlay is still there.**
Check `ShortcutArrow.log` for `FAIL ... not writable`. You almost certainly ran
it without Administrator rights.

**It came back after a reboot.**
The icon path in the registry went stale — usually because `blank.ico` was
deleted. Re-run the installer.

**It came back after a Windows feature update.**
Cumulative updates sometimes reset this registry key. Re-run the script.

**I hid the shield and nothing changed about the UAC prompt.**
Correct — that is by design. The shield is only a warning icon. The prompt comes
from the program's manifest and is not affected.

**Now I can't tell shortcuts from real files.**
Unavoidable — without the arrow they look identical. If what you wanted was
*prettier* rather than *gone*, point slot `29` at your own subtle arrow icon;
everything else stays the same.

**Antivirus flagged it.**
The script edits the registry and restarts Explorer, which looks suspicious to
heuristics. The whole thing is one readable PowerShell file.

---

### Uninstall

```powershell
& "$env:LOCALAPPDATA\ShortcutArrow\ShortcutArrow.ps1" -Action Restore
Remove-Item "$env:LOCALAPPDATA\ShortcutArrow" -Recurse -Force
```

#### Manual restore

`Win+R` → `regedit` → go to:

```
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons
```

Delete any string values named `29` (arrow) and `77` (shield). Check the same
path under `HKEY_CURRENT_USER` too. Then reboot.

---

## 中文说明

**隐藏 Windows 10 / 11 桌面快捷方式上的两个图标覆盖层——小箭头和 UAC 小盾牌。用「遮挡层图标替换法」，不影响任何快捷方式功能。**

| 覆盖层 | Shell Icons 槽位 | 默认行为 |
|---|---|---|
| 快捷方式小箭头（`.lnk` 左下角） | `29` | 隐藏 |
| **UAC 小盾牌**（提权程序上的蓝黄盾牌） | `77` | **除非显式指定，否则不动** |

除了这两个覆盖层，脚本不改动任何东西，**完全不碰 `IsShortcut`**。

### 一行安装

以**管理员身份**打开 PowerShell：

```powershell
# 只去小箭头
irm https://raw.githubusercontent.com/Hakoniwalily-fan/remove-shortcut-arrow/main/install.ps1 | iex
```

```powershell
# 去小箭头 + 去小盾牌
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Hakoniwalily-fan/remove-shortcut-arrow/main/install.ps1))) -IncludeShield
```

恢复（两个都会还原）：

```powershell
& "$env:LOCALAPPDATA\ShortcutArrow\ShortcutArrow.ps1" -Action Restore
```

### ⚠️ 关于小盾牌——请先读这段

**盾牌是「警告提示」，不是「安全防护」。**

隐藏它**不会**阻止程序申请管理员权限：UAC 弹窗照常出现，程序照样提权，你的实际安全
状况没有任何变化。你失去的是「这个程序即将要管理员权限」的视觉提示——而习惯性点
「是」的时候，这个提示其实挺有用的。

所以隐藏盾牌是**可选功能（`-IncludeShield`）**，默认永远不做。

**本项目刻意不做的事：**

| 不做 | 原因 |
|---|---|
| 改 exe 的 manifest 去掉 `requireAdministrator` | 会让确实需要管理员权限的程序静默出错，而且是在改动第三方二进制文件 |
| 关闭 UAC | 那是真的降低安全性，不是美化 |
| 给 `.lnk` 勾上「以管理员身份运行」兼容性标志 | 和改 manifest 一样的问题，而且根本去不掉盾牌 |

如果你既嫌盾牌丑、又想保留提示，折中方案是把槽位 `77` 指向一个你自己做的浅色盾牌图标，
而不是透明图标。

### 为什么不用网上那个「删除 IsShortcut」的方法

搜「去掉快捷方式箭头」，排前面的几乎都是让你删掉
`HKEY_CLASSES_ROOT\lnkfile` 下的 `IsShortcut` 值。**别这么做**——那会让系统不再把
`.lnk` 当作快捷方式，后果是：

| 症状 | 原因 |
|---|---|
| 「固定到任务栏」/「固定到开始屏幕」消失或点击无效 | 外壳不再把该文件识别为快捷方式 |
| 双击快捷方式报错 | 「该文件没有与之关联的应用来执行该操作」 |
| 拖放到任务栏失效 | 固定流程依赖快捷方式关联 |
| 开始菜单搜索异常 | 快捷方式的索引行为被改变 |

想恢复还得把 `IsShortcut` 加回去、重建图标缓存，有时还要动组策略。

**本项目完全不碰 `IsShortcut`**，只替换覆盖层图标，所以快捷方式的识别、固定、拖放
等行为全部正常。

### 原理

两个覆盖层都注册在同一个外壳键下：

```
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons
    "29" = <图标>     快捷方式箭头覆盖层
    "77" = <图标>     UAC 盾牌覆盖层
```

指向一个**全透明图标**，覆盖层照画，只是画出来什么都没有。

脚本在运行时**自己拼出**这个透明 `.ico`（16 / 32 / 48 三种尺寸，逐像素 `Alpha = 0`），
不依赖任何预置文件。

### 图标为什么放在 `%LOCALAPPDATA%`

注册表里存的是**绝对路径**。多数同类工具把图标生成在脚本旁边——你一旦移动或重命名
那个文件夹，路径就失效，**重启后覆盖层会悄悄回来**。

本脚本把它放在固定位置：`%LOCALAPPDATA%\ShortcutArrow\blank.ico`

### 文件

| 文件 | 用途 |
|---|---|
| `install.ps1` | 一行安装入口，自动处理提权 |
| `ShortcutArrow.ps1` | 主脚本（Remove / Restore） |
| `Remove-ShortcutArrow.bat` | 双击去小箭头 |
| `Remove-ArrowAndShield.bat` | 双击去小箭头 + 小盾牌 |
| `Restore-ShortcutArrow.bat` | 双击恢复（两个都还原） |

### 参数

| 参数 | 说明 |
|---|---|
| `-Action Remove` | 去掉小箭头（默认） |
| `-Action Restore` | 恢复小箭头**和**小盾牌 |
| `-IncludeShield` | 同时隐藏 UAC 盾牌覆盖层（槽位 `77`） |
| `-UseSystemIcon` | 用系统自带空白图标 `shell32.dll,50`，不生成 .ico |
| `-NoRestart` | 不重启 explorer，下次重启后生效 |

> `shell32.dll,50` 与 `imageres.dll,195` 在 Windows 11 build 26200 上实测均为完全透明
> （`Alpha = 0`）。图标索引可能随 Windows 版本变动，所以默认走「自己生成 .ico」这条
> 更确定的路——它不可能指向错误的图标。

### 恢复行为说明

`-Action Restore` **总是同时清除 `29` 和 `77` 两个槽位**，即使你从没隐藏过盾牌。
理由是：一个被隐藏的安全提示不应该因为「忘了加参数」而残留。每个被删除的值都会连同
它原来的内容写进日志，方便你手工把自定义图标放回去。

---

## License

[MIT](LICENSE)
