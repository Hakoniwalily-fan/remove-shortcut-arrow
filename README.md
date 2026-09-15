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

An **empty** overlay icon — one with no opaque or semi-opaque pixels at all — is
composited as an **opaque black square** over the *entire* shortcut icon on some
systems, instead of hiding a small arrow.

This is **not** about the pixel format. Measured on the affected machine
(Windows 11 25H2 build 26200, Intel iGPU + NVIDIA dGPU), with the registry
slots, the icon path and the icon cache all held constant:

| Overlay icon | Ink (pixels with alpha > 0) | Result |
|---|---|---|
| 1bpp, AND mask all ones (v1.3.0's "fix") | 0 | ❌ every shortcut = a black square |
| 32bpp, every pixel `BGRA 0,0,0,0` (v1.2.0) | 0 | ❌ every shortcut = a black square |
| 32bpp, one pixel at `alpha = 2/255` (v1.4.0) | 1 per size | ✅ overlay invisible, icons untouched |

The variable is **"is the icon empty"**. A 1bpp image cannot express "almost
empty": it can only be completely empty or show an opaque black pixel — which is
why v1.3.0's 1bpp rewrite still blackened every icon. v1.4.0 therefore writes a
32bpp icon with a single `alpha = 2/255` pixel (0.8% opacity, invisible to the
eye) and an AND mask that matches it.

Two other suspects were ruled out by measurement rather than by argument:

| Hypothesis | Result |
|---|---|
| The icon path matters (non-ASCII `%LOCALAPPDATA%`) | ❌ not a factor — an ASCII path with the same empty icon blackens identically |
| The bit depth matters | ❌ not a factor |

**Already affected?** Update and re-run `-Action Remove`. v1.4.0 checks the
existing `blank.ico` on every run, and a completely empty icon now fails
verification and gets regenerated. v1.3.0 wrote a *different* empty icon, so
simply re-running it could never repair anything.

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

#### Why the icon is 32bpp but almost empty

The intuitive way to build "nothing" is a 32bpp image whose pixels are all
`BGRA 0,0,0,0`. That is what v1.2.0 did. v1.3.0 replaced it with 1bpp images —
and **both are completely empty**, which is precisely the condition that gets
composited as an opaque black square (see the table at the top of this page).

v1.4.0 writes **32bpp images in which every pixel is transparent except one**, at
`alpha = 2/255`, with the AND-mask bit cleared for that pixel. Ten sizes are
included (16 / 20 / 24 / 32 / 40 / 48 / 64 / 96 / 128 / 256) so Explorer never
has to scale one image into a different size.

Before the registry is touched, the file is parsed straight from its bytes
(`Get-IcoContent`), which counts the ink pixels and checks that the AND mask
agrees with them. An empty icon, an icon containing opaque black pixels, or an
icon whose mask contradicts its ink all abort the run with the registry
untouched.

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

Windows 11 25H2 build 26200, Intel iGPU + NVIDIA dGPU laptop, 15 desktop
shortcuts. Every result below was measured through the shell's own icon API
(`ExtractAssociatedIcon`), counting the opaque-black pixels of each shortcut's
icon.

| Configuration | Ink | Measured |
|---|---|---|
| No overlay registered | n/a | ✅ normal (worst 31.9%) |
| 32bpp, `alpha = 0`, 10 sizes (v1.2.0) | 0 | ❌ 100% — every shortcut a black square |
| 1bpp, AND mask all ones, 10 sizes (v1.3.0) | 0 | ❌ 100% — every shortcut a black square |
| the same empty icon on an ASCII path | 0 | ❌ 100% (so the path is **not** the factor) |
| 32bpp, one pixel at `alpha = 2/255` (v1.4.0) | 1 | ✅ normal (worst 31.9%) |

Two measurement traps turned up while building this, and v1.4.0 handles both:

1. **The process that makes the change cannot see the result.** With an empty
   overlay installed, the script's own process reported 38% ("fine") at t+5s
   through t+60s, while a freshly started process reported 100% at the very same
   moments. The end-to-end check therefore runs in a **child process**.
2. **The shell can serve stale composites for a moment** right after the
   registry change and the cache clear. The check samples over a short window
   and lets the worst reading decide. In the regression test the first
   observation read 38% and the second read 100% — which is what triggers the
   automatic rollback.

The v1.3.0 verification inspected only the icon *file's format*, found nothing
wrong, and printed `no problems found` while every shortcut on the desktop was a
black square. That specific failure is what the new end-to-end check exists to
prevent.

On the same machine both overlays were also confirmed to vanish (arrow **and**
shield), and afterwards the registry was re-read:
`HKEY_CLASSES_ROOT\lnkfile\IsShortcut` matched a stock Windows install exactly —
no shortcut behaviour was altered.

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
| `-Action Verify` | read-only: report what is applied, inspect the icon, and measure the actual desktop |
| `-IncludeShield` | also hide the UAC shield overlay (slot `77`) |
| `-IconFormat Faint32bpp` | default, and the only safe class: 32bpp with a single `alpha = 2/255` pixel |
| `-IconFormat Empty1bpp` | the v1.3.0 icon — completely empty; `-Action Remove` refuses it |
| `-IconFormat Empty32bpp` | the v1.2.0 icon — same defect, same refusal |
| `-IconFormat Mask1bpp` / `Legacy32bpp` | accepted aliases for the two `Empty*` classes |
| `-Force` | regenerate the transparent icon even if it already exists |
| `-UseSystemIcon` | **deprecated** — `shell32.dll,50` is itself a fully transparent (empty) icon |
| `-NoRestart` | don't restart Explorer; takes effect after the next restart |

> The two `Empty*` formats exist so the failure stays reproducible (the test
> suite uses them) and so old command lines keep parsing — but `-Action Remove`
> now **aborts** on them instead of installing an icon that is known to blacken
> every shortcut. To reproduce the broken state deliberately, generate the icon
> with `New-TransparentIco -Format Empty32bpp` and register it by hand.
>
> `shell32.dll,50` and `imageres.dll,195` are fully transparent, i.e. **empty**,
> which puts them in the same risky class. `-UseSystemIcon` is kept only for
> backwards compatibility, prints a warning, and is not the recommended path.
> Icon indices can also shift between Windows versions, whereas the
> self-generated `.ico` can never point at the wrong icon.

#### Tests

```powershell
pwsh -File tests/Test-ShortcutArrow.ps1           # PowerShell 7
powershell -File tests\Test-ShortcutArrow.ps1     # Windows PowerShell 5.1
```

The suite pins the contract this bug broke: the generated icon must **not** be
empty, its ink must stay faint (no opaque pixels), its AND mask must agree with
its ink, and the validator must reject both legacy empty formats.

---

### What the script changes

**`-Action Remove`**

1. Generates the overlay icon in `%LOCALAPPDATA%\ShortcutArrow\` — 32bpp, ten
   sizes, one faint ink pixel, parsed and verified before use. An existing file
   is re-checked on every run and regenerated when it is empty or otherwise
   fails verification; `-Force` always regenerates
2. **Stops `explorer.exe`**, then clears the icon cache (`IconCache.db`,
   `iconcache_*.db`, `thumbcache_*.db`) while the shell is down, and logs how
   many files were actually deleted. Doing this in the other order deletes
   nothing (measured: 30 files present, 0 deleted) and leaves the stale
   composites in place
3. Sets `Shell Icons` slot `29` — and slot `77` too with `-IncludeShield`
   - elevated → `HKLM` (documented location, machine-wide)
   - not elevated → falls back to `HKCU`
   - every write is read back and compared, so a silent failure is reported
4. Starts `explorer.exe`
5. **Measures the result** — in a child process, sampling over a short window —
   and rolls the whole change back automatically if any shortcut came out as a
   black square

**`-Action Restore`**

1. Stops `explorer.exe` and clears the icon cache (same order as above)
2. Deletes slots `29` **and** `77` from `HKLM` and `HKCU`
3. Starts `explorer.exe` and measures the result

**`-Action Verify`**

Read-only. For every slot in `HKLM` and `HKCU` it prints the value, resolves the
icon it points at, checks that the file exists, counts its ink pixels and checks
its AND mask — and then measures the desktop itself, in a child process. It exits
non-zero when a slot points at a missing file, at an empty icon, at anything else
that fails verification, or when shortcuts are painted black right now. Useful
when the arrow "came back" or when the desktop looks wrong.

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
The registered overlay icon is empty (see the top of this page). Run
`-Action Restore` immediately to get the stock arrow back, then update and run
`-Action Remove` again — v1.4.0 regenerates the icon and refuses to install an
empty one. Note that the run which caused this may well have reported success:
the old check only looked at the file format.

**`-Action Remove` exited non-zero and said it rolled back.**
That is the new safety net working: the desktop was measured, shortcuts came out
black, and the change was undone instead of being left in place. Please report it
with `ShortcutArrow.log` and your Windows build.

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

**「全空」的覆盖层图标**（没有任何不透明或半透明像素）在部分系统上会被合成成**不透明黑色**——
结果不是遮住一个小箭头，而是**整张快捷方式图标被盖成一个纯黑方块**。

这**与像素格式无关**。以下结果在出问题的机器上实测（Windows 11 25H2 build 26200，Intel 核显 +
NVIDIA 独显），注册表槽位、图标路径、图标缓存全部保持不变：

| 覆盖层图标 | 墨迹（alpha > 0 的像素数） | 结果 |
|---|---|---|
| 1bpp，AND 掩码全 1（v1.3.0 的「修复」） | 0 | ❌ 每个快捷方式都是黑方块 |
| 32bpp，全部像素 `BGRA 0,0,0,0`（v1.2.0） | 0 | ❌ 每个快捷方式都是黑方块 |
| 32bpp，一个 `alpha = 2/255` 的像素（v1.4.0） | 每个尺寸 1 个 | ✅ 覆盖层不可见，图标完好 |

真正的变量是**「图标是不是全空的」**。1bpp 图像**无法表达「几乎全空」**：它要么完全空，
要么显示一个不透明的黑像素——这就是 v1.3.0 改成 1bpp 之后**照样全黑**的原因。因此 v1.4.0
生成的是 32bpp 图标，其中**只有一个 `alpha = 2/255` 的像素**（0.8% 不透明度，肉眼不可见），
并让 AND 掩码与之一致。

另外两个怀疑对象是靠实测排除的，不是靠推理：

| 怀疑对象 | 结论 |
|---|---|
| 图标路径（带中文的 `%LOCALAPPDATA%`） | ❌ 不是原因——同一张全空图标放到纯 ASCII 路径下一样全黑 |
| 位深 / 格式 | ❌ 不是原因 |

**已经中招了怎么办？** 更新后重跑 `-Action Remove`。v1.4.0 每次都会重新检查已有的
`blank.ico`，**全空图标现在会直接校验失败并被重新生成**。v1.3.0 生成的是**另一种同样全空**
的图标，所以老版本重跑多少次都修不好。

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

#### 为什么是「32bpp 但几乎全空」

最直觉的做法是造一张 32bpp、像素全为 `BGRA 0,0,0,0` 的图。v1.2.0 就是这么做的；
v1.3.0 把它换成了 1bpp 图——而**两者都是「全空」的**，这恰恰就是会被合成为不透明黑方块的
那个条件（见本页开头的表格）。

v1.4.0 生成的是**每个像素都透明、只有一个像素例外**的 32bpp 图：那一个像素的
`alpha = 2/255`，并把它的 AND 掩码位清 0。同时补齐 **10 个尺寸**
（16 / 20 / 24 / 32 / 40 / 48 / 64 / 96 / 128 / 256），避免系统把某一张缩放成别的尺寸。

在真正写注册表之前，脚本会**直接从字节解析**生成的文件（`Get-IcoContent`）：统计墨迹像素数，
并检查 AND 掩码是否与墨迹一致。图标全空、含不透明黑像素、或掩码与墨迹矛盾，都会**中止**，
注册表一点都不动。

### 图标为什么放在 `%LOCALAPPDATA%`

注册表里存的是**绝对路径**。多数同类工具把图标生成在脚本旁边——你一旦移动或重命名
那个文件夹，路径就失效，**重启后覆盖层会悄悄回来**。

本脚本把它放在固定位置：`%LOCALAPPDATA%\ShortcutArrow\blank.ico`

### 文件

| 文件 | 用途 |
|---|---|
| `install.ps1` | 一行安装入口，自动处理提权（`Verify` 只读，不会弹 UAC） |
| `ShortcutArrow.ps1` | 主脚本（Remove / Restore / Verify） |
| `tests/Test-ShortcutArrow.ps1` | 测试套件（不依赖 Pester，失败时退出码非 0） |
| `Remove-ShortcutArrow.bat` | 双击去小箭头 |
| `Remove-ArrowAndShield.bat` | 双击去小箭头 + 小盾牌 |
| `Restore-ShortcutArrow.bat` | 双击恢复（两个都还原） |
| `Verify-ShortcutArrow.bat` | 双击诊断（只读，不改任何东西） |

### 参数

| 参数 | 说明 |
|---|---|
| `-Action Remove` | 去掉小箭头（默认） |
| `-Action Restore` | 恢复小箭头**和**小盾牌 |
| `-Action Verify` | 只读诊断：当前装了什么、检查图标、并实测桌面 |
| `-IncludeShield` | 同时隐藏 UAC 盾牌覆盖层（槽位 `77`） |
| `-IconFormat Faint32bpp` | 默认，也是唯一安全的类别：32bpp + 一个 `alpha = 2/255` 的像素 |
| `-IconFormat Empty1bpp` | v1.3.0 的图标——全空；`-Action Remove` 会拒绝安装 |
| `-IconFormat Empty32bpp` | v1.2.0 的图标——同样全空，同样拒绝 |
| `-IconFormat Mask1bpp` / `Legacy32bpp` | 上面两个 `Empty*` 的兼容别名 |
| `-Force` | 即使图标已存在也强制重新生成 |
| `-UseSystemIcon` | **已弃用**——`shell32.dll,50` 本身就是全透明的（全空）图标 |
| `-NoRestart` | 不重启 explorer，下次重启后生效 |

> 两个 `Empty*` 格式保留下来，是为了让这个故障仍然可复现（测试套件就用它们），也让老命令行
> 仍能解析——但 `-Action Remove` 现在会**直接中止**，而不是安装一个已知会把所有快捷方式弄黑的
> 图标。确实想复现坏状态，用 `New-TransparentIco -Format Empty32bpp` 自己生成再手工写注册表。
>
> `shell32.dll,50` 与 `imageres.dll,195` 是全透明的，也就是**全空**，同属有风险的类别。
> `-UseSystemIcon` 仅为兼容旧用法保留，运行时会打印警告，不是推荐路径。图标索引还可能随
> Windows 版本变动，而自己生成的 `.ico` 不可能指向错误的图标。

### 测试

```powershell
pwsh -File tests/Test-ShortcutArrow.ps1           # PowerShell 7
powershell -File tests\Test-ShortcutArrow.ps1     # Windows PowerShell 5.1
```

测试套件钉住的正是这次被破坏的契约：生成的图标**不能全空**、墨迹必须保持极淡（不能有不透明
像素）、AND 掩码必须与墨迹一致、并且校验器必须拒绝两个旧的全空格式。

### 真机实测验证

Windows 11 25H2 build 26200，Intel 核显 + NVIDIA 独显笔记本，15 个桌面快捷方式。下表每一项都是
通过系统自带图标 API（`ExtractAssociatedIcon`）量出来的，统计每个快捷方式图标中纯黑像素的占比。

| 配置 | 墨迹 | 实测 |
|---|---|---|
| 不注册任何覆盖层 | 不适用 | ✅ 正常（最差 31.9%） |
| 32bpp，`alpha = 0`，10 尺寸（v1.2.0） | 0 | ❌ 100%——每个快捷方式都是黑方块 |
| 1bpp，AND 掩码全 1，10 尺寸（v1.3.0） | 0 | ❌ 100%——每个快捷方式都是黑方块 |
| 同一张全空图标放到 ASCII 路径 | 0 | ❌ 100%（所以路径**不是**原因） |
| 32bpp，一个 `alpha = 2/255` 的像素（v1.4.0） | 1 | ✅ 正常（最差 31.9%） |

做这件事的过程中踩到两个「测量陷阱」，v1.4.0 两个都处理了：

1. **做过改动的那个进程看不见结果。** 装上全空覆盖层后，脚本自己那个进程在 t+5s 到 t+60s
   一直报 38%（「正常」），而同一时刻新起的进程报 100%。所以端到端校验改成在**子进程**里做。
2. **shell 会短暂沿用旧的合成结果。** 改完注册表、清完缓存之后的一瞬间，shell 可能还在用之前
   的结果。所以校验会在一个短窗口内多次采样，**取最差值**判定。回归测试里第一次采样是 38%、
   第二次是 100%——正是第二次触发了自动回滚。

v1.3.0 的校验只看图标**文件格式**，什么毛病都没看出来，于是桌面已经全黑、它仍然打印
`no problems found`。新的端到端校验存在的意义就是防止这件事。

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
