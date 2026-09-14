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

### ⚠️ If every shortcut turned into a black square

Some systems composite a **fully transparent 32bpp overlay as opaque black**,
painting a solid black square over the *entire* shortcut icon instead of hiding
a small arrow. This was reproduced first-hand (see
[verified on real hardware](#verified-on-real-hardware)) and is the reason
**v1.3.0 generates 1bpp icons instead**.

| | |
|---|---|
| Symptom | Every shortcut becomes a black square; folders, documents and image icons stay normal |
| Why only shortcuts | They are the only icons that get an overlay painted on top of them |
| Why it is not the icon file | The icon data is correct — it is the *compositing* that goes wrong |
| Fix | Update and re-run; the 1bpp icon is generated and verified automatically |

**Already affected?** Run `-Action Remove` again. The script re-checks the
existing `blank.ico` on every run and regenerates it when it is still in the old
32bpp format. v1.2.0 and earlier only wrote that file when it was missing, so
re-running the old version could never repair an affected machine.

Want out immediately instead? `-Action Restore` puts the stock arrow back.

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

Check what is installed right now (read-only, changes nothing):

```powershell
& "$env:LOCALAPPDATA\ShortcutArrow\ShortcutArrow.ps1" -Action Verify
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

The script builds that transparent `.ico` from scratch at runtime — no bundled
binary, no downloaded asset, nothing to trust.

#### Why the icon is 1bpp (and not the obvious 32bpp)

The intuitive way to build "nothing" is a 32bpp image whose pixels are all
`BGRA 0,0,0,0`. That is what v1.2.0 did, and it is correct on paper — but on
affected systems the alpha channel is not honoured for this overlay and the
pixels are composited as **opaque black**, covering the whole icon.

v1.3.0 therefore writes **1bpp images with an all-ones AND mask**. A 1bpp image
has no alpha channel at all: "leave the screen unchanged" is expressed purely by
the mask, so there is no alpha path left for a compositor to get wrong. Ten
sizes are included (16 / 20 / 24 / 32 / 40 / 48 / 64 / 96 / 128 / 256) so
Explorer never has to scale one image into a different size.

Before the registry is touched, the generated file is parsed as an ICO and
loaded back through the shell's own icon API; the run aborts if the result is
not a safe, fully transparent icon.

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

#### Verified on real hardware

| Machine | Icon format | Result |
|---|---|---|
| Windows 11 25H2 build 26200, Intel iGPU + NVIDIA dGPU laptop | 32bpp, `Alpha = 0` (v1.2.0) | ❌ **every shortcut rendered as a solid black square** |
| same machine, same registry slots, fresh icon cache | **1bpp, AND mask all ones (v1.3.0)** | ✅ overlay invisible, icons untouched |

The failing run was measured from a screenshot: 32 identical pure-black 32×32
squares, one per shortcut, on a white wallpaper. Extracting those shortcuts'
icons through the shell API returned the correct colourful icons — which is what
pinned the fault to the overlay composite rather than the icon data. Deleting
the two registry slots made the squares disappear instantly, and reinstalling
them with the 1bpp icon kept them away. Rebuilding the icon cache alone did not
help, and the built-in `shell32.dll,50` icon is 32bpp, so it is in the same
risky class.

On the same machine both overlays were also confirmed to vanish (arrow **and**
shield), and afterwards the registry was re-read: `HKEY_CLASSES_ROOT\lnkfile\IsShortcut`
matched a stock Windows install exactly — no shortcut behaviour was altered.

---

### Usage

#### Installer (recommended)

```powershell
irm https://raw.githubusercontent.com/Hakoniwalily-fan/remove-shortcut-arrow/main/install.ps1 | iex
```

`install.ps1` downloads the current script into `%LOCALAPPDATA%\ShortcutArrow\`
and re-launches itself elevated if needed. `-Action Verify` is read-only and
therefore never raises a UAC prompt.

#### Straight from a clone

```powershell
.\ShortcutArrow.ps1 -Action Remove                    # arrow only
.\ShortcutArrow.ps1 -Action Remove -IncludeShield     # arrow + shield
.\ShortcutArrow.ps1 -Action Restore                   # restore both
.\ShortcutArrow.ps1 -Action Verify                    # diagnose, read-only
```

#### Double-click

| File | Purpose |
|---|---|
| `Remove-ShortcutArrow.bat` | removes the arrow only |
| `Remove-ArrowAndShield.bat` | removes the arrow **and** the UAC shield |
| `Restore-ShortcutArrow.bat` | restores both overlays |
| `Verify-ShortcutArrow.bat` | read-only diagnostic — changes nothing |

#### Options

| Parameter | Description |
|---|---|
| `-Action Remove` | hide the arrow (default) |
| `-Action Restore` | restore the arrow **and** the shield |
| `-Action Verify` | read-only: report what is applied and whether the icon is safe |
| `-IncludeShield` | also hide the UAC shield overlay (slot `77`) |
| `-IconFormat Mask1bpp` | default: 1bpp mask-based transparency (safe on every system seen so far) |
| `-IconFormat Legacy32bpp` | the pre-1.3.0 format — see the black square warning above |
| `-Force` | regenerate the transparent icon even if it already exists |
| `-UseSystemIcon` | **deprecated** — `shell32.dll,50` is a 32bpp icon, i.e. the risky format class |
| `-NoRestart` | don't restart Explorer; takes effect after the next restart |

> `shell32.dll,50` and `imageres.dll,195` were both measured as fully
> transparent (`Alpha = 0`) on Windows 11 build 26200. But they are 32bpp icons:
> the exact format class that can render as an opaque black square over the whole
> icon. `-UseSystemIcon` is kept for backwards compatibility only, prints a
> warning, and is not the recommended path. Icon indices can also shift between
> Windows versions, so the self-generated `.ico` can never point at the wrong
> icon either.

---

### What the script changes

**`-Action Remove`**

1. Generates a fully transparent `blank.ico` in `%LOCALAPPDATA%\ShortcutArrow\`
   — 1bpp, ten sizes, verified before use. An existing file is re-checked on
   every run and regenerated when it is not in the requested format; `-Force`
   always regenerates
2. Sets `Shell Icons` slot `29` — and slot `77` too with `-IncludeShield`
   - elevated → `HKLM` (documented location, machine-wide)
   - not elevated → falls back to `HKCU`
   - every write is read back and compared, so a silent failure is reported
3. Clears the icon cache (`IconCache.db`, `iconcache_*.db`, `thumbcache_*.db`)
4. Restarts `explorer.exe`

**`-Action Restore`**

1. Deletes slots `29` **and** `77` from `HKLM` and `HKCU`
2. Clears the icon cache
3. Restarts `explorer.exe`

**`-Action Verify`**

Read-only. For every slot in `HKLM` and `HKCU` it prints the value, resolves the
icon it points at, checks the file exists, reads the real format out of the ICO
header, and loads the icon back through the shell API. It exits with a non-zero
code when a slot points at a missing file, at a 32bpp icon, or at anything that
fails verification. Useful when the arrow "came back" or when shortcuts look
wrong.

Restore always clears both slots, even if you never hid the shield. A hidden
security indicator should never be able to linger just because a flag was
forgotten. Each removed value is written to the log with its previous content,
so a custom replacement icon can be put back by hand.

Every run appends to `ShortcutArrow.log` next to the script. The log also records
the generated icon's size, detected format, size list and SHA-256.

---

### FAQ

**The overlay is still there.**
Check `ShortcutArrow.log` for `FAIL ... not writable`. You almost certainly ran
it without Administrator rights.

**Every shortcut turned into a black square.**
That is the 32bpp composite bug described at the top of this page. Run
`-Action Restore` immediately to get the stock arrow back, then update and run
`-Action Remove` again — v1.3.0 writes the 1bpp icon and re-checks the existing
file, so it repairs itself. `-Action Verify` prints which format is installed.

**How do I check what is installed right now?**
`-Action Verify`, or double-click `Verify-ShortcutArrow.bat`. Nothing is
modified except the log.

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

### ⚠️ 如果所有快捷方式都变成了黑色方块

部分系统会把**「全透明的 32bpp 覆盖层」当成不透明黑色来合成**——结果不是遮住一个小箭头，
而是**整张快捷方式图标被盖成一个纯黑方块**。这个问题已真机复现（见
[真机实测验证](#真机实测验证)），也正是 **v1.3.0 改用 1bpp 图标**的原因。

| | |
|---|---|
| 现象 | 所有快捷方式变成黑方块；文件夹、文档、图片图标正常 |
| 为什么只有快捷方式 | 只有快捷方式会被额外叠加一层覆盖图标 |
| 为什么不是图标文件的问题 | 图标数据本身是正确的，出错的是**合成那一步** |
| 怎么修 | 更新后重跑一次，1bpp 图标会自动生成并自检 |

**已经中招了怎么办？** 直接重跑 `-Action Remove`。脚本每次都会重新检查已有的
`blank.ico`，只要它还是旧的 32bpp 格式就会重新生成。**v1.2.0 及更早版本只在文件不存在
时才生成，所以老版本重跑多少次都修不好。**

想立刻摆脱黑方块：跑 `-Action Restore`，小箭头会马上回来。

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

查看当前装的是什么（只读，不改任何东西）：

```powershell
& "$env:LOCALAPPDATA\ShortcutArrow\ShortcutArrow.ps1" -Action Verify
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

脚本在运行时**自己拼出**这个透明 `.ico`，不依赖任何预置文件。

#### 为什么用 1bpp，而不是"看起来更正常"的 32bpp

最直觉的做法是造一张 32bpp、像素全为 `BGRA 0,0,0,0` 的图。v1.2.0 就是这么做的，
理论上完全正确——但在部分系统上，这个覆盖层的 alpha 通道**不会被遵守**，像素会被当成
**不透明黑**合成，把整张图标盖住。

所以 v1.3.0 改为写 **1bpp 图像 + 全 1 的 AND 掩码**。1bpp 图像**根本没有 alpha 通道**：
「保持屏幕不变」完全由掩码表达，合成器没有 alpha 可走错。同时补齐 **10 个尺寸**
（16 / 20 / 24 / 32 / 40 / 48 / 64 / 96 / 128 / 256），避免系统把某一张缩放成别的尺寸。

在真正写注册表之前，脚本会把生成的文件按 ICO 格式解析一遍，并通过系统自带的图标 API
读回来检查；不达标就**中止**，注册表一点都不动。

### 图标为什么放在 `%LOCALAPPDATA%`

注册表里存的是**绝对路径**。多数同类工具把图标生成在脚本旁边——你一旦移动或重命名
那个文件夹，路径就失效，**重启后覆盖层会悄悄回来**。

本脚本把它放在固定位置：`%LOCALAPPDATA%\ShortcutArrow\blank.ico`

### 文件

| 文件 | 用途 |
|---|---|
| `install.ps1` | 一行安装入口，自动处理提权（`Verify` 只读，不会弹 UAC） |
| `ShortcutArrow.ps1` | 主脚本（Remove / Restore / Verify） |
| `Remove-ShortcutArrow.bat` | 双击去小箭头 |
| `Remove-ArrowAndShield.bat` | 双击去小箭头 + 小盾牌 |
| `Restore-ShortcutArrow.bat` | 双击恢复（两个都还原） |
| `Verify-ShortcutArrow.bat` | 双击诊断（只读，不改任何东西） |

### 参数

| 参数 | 说明 |
|---|---|
| `-Action Remove` | 去掉小箭头（默认） |
| `-Action Restore` | 恢复小箭头**和**小盾牌 |
| `-Action Verify` | 只读诊断：当前装了什么、图标格式是否安全 |
| `-IncludeShield` | 同时隐藏 UAC 盾牌覆盖层（槽位 `77`） |
| `-IconFormat Mask1bpp` | 默认：1bpp 掩码透明（目前见过的系统上都安全） |
| `-IconFormat Legacy32bpp` | v1.3.0 之前的旧格式——见上面的黑方块警告 |
| `-Force` | 即使图标已存在也强制重新生成 |
| `-UseSystemIcon` | **已弃用**——`shell32.dll,50` 是 32bpp 图标，属于有风险的格式类别 |
| `-NoRestart` | 不重启 explorer，下次重启后生效 |

> `shell32.dll,50` 与 `imageres.dll,195` 在 Windows 11 build 26200 上实测均为完全透明
> （`Alpha = 0`），但它们都是 **32bpp** —— 正是可能被渲染成整张纯黑方块的那一类格式。
> 因此 `-UseSystemIcon` 仅为兼容旧用法而保留，运行时会打印警告，不是推荐路径。此外图标
> 索引可能随 Windows 版本变动，而自己生成的 `.ico` 不可能指向错误的图标。

### 真机实测验证

| 机器 | 图标格式 | 结果 |
|---|---|---|
| Windows 11 25H2 build 26200，Intel 核显 + NVIDIA 独显笔记本 | 32bpp，`Alpha = 0`（v1.2.0） | ❌ **所有快捷方式被渲染成纯黑方块** |
| 同一台机器、同样的注册表槽位、全新图标缓存 | **1bpp，AND 掩码全 1（v1.3.0）** | ✅ 覆盖层不可见，图标完好 |

失败的那次是从截图里量出来的：白色壁纸上 **32 个完全相同的纯黑 32×32 方块**，一个快捷
方式一个。通过系统 API 提取这些快捷方式的图标，拿到的却是完全正常的彩色图标——正是这
一点把故障定位到**覆盖层合成**而不是图标数据。删掉那两个注册表槽位，黑块立刻消失；
装回 1bpp 图标后黑块不再出现。单纯重建图标缓存**没有用**，而系统自带的 `shell32.dll,50`
也是 32bpp，同样属于有风险的格式。

同一台机器上两个覆盖层（小箭头**和**小盾牌）也都确认消失，事后重新读取注册表核对，
`HKEY_CLASSES_ROOT\lnkfile\IsShortcut` 与 Windows 出厂状态完全一致——没有任何快捷方式
行为被改变。

### 恢复行为说明

`-Action Restore` **总是同时清除 `29` 和 `77` 两个槽位**，即使你从没隐藏过盾牌。
理由是：一个被隐藏的安全提示不应该因为「忘了加参数」而残留。每个被删除的值都会连同
它原来的内容写进日志，方便你手工把自定义图标放回去。

每次运行都会往脚本旁边的 `ShortcutArrow.log` 追加记录，其中包含生成图标的字节数、
检测到的格式、尺寸列表和 SHA-256。

---

## License

[MIT](LICENSE)
