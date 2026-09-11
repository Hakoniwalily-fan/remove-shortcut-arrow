# 去掉 Windows 桌面快捷方式小箭头

用**遮挡层图标替换法**去掉 Windows 10 / 11 桌面快捷方式左下角那个丑丑的小箭头。

**不碰 `IsShortcut`**，所以「固定到任务栏」「固定到开始屏幕」、拖放等快捷方式功能全部保持正常。

---

## 为什么不用网上那个「删除 IsShortcut」的方法

搜「去掉快捷方式箭头」，排在前面的几乎都是让你删掉注册表里
`HKEY_CLASSES_ROOT\lnkfile` 下的 `IsShortcut` 值。这个方法确实能让箭头消失，
但代价是系统不再把 `.lnk` 当成「快捷方式」，典型后果：

| 症状 | 说明 |
|---|---|
| 「固定到任务栏」/「固定到开始屏幕」消失 | 右键菜单里这两项直接没了，或点了没反应 |
| 双击快捷方式报错 | 「该文件没有与之关联的应用来执行该操作。请安装应用……」 |
| 拖放到任务栏失效 | 无法把程序拖到任务栏固定 |
| 开始菜单搜索异常 | 快捷方式索引行为改变 |

想恢复还得把 `IsShortcut` 加回去、重建图标缓存、有时还得动组策略，很折腾。

**本项目只改「画在图标上的那个覆盖层」，不动文件类型关联**，所以没有上述副作用。

---

## 原理

Windows 的快捷方式箭头是一个**图标覆盖层（icon overlay）**，由注册表指定：

```
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons
    值名: 29        (REG_SZ)
    值数据: <图标文件路径>
```

`29` 就是「快捷方式覆盖层」的编号。把它指向一个**全透明的 .ico**，
箭头照画，只是画出来什么都没有 —— 视觉上箭头就消失了。

本项目用脚本**即时生成**这个透明图标（16 / 32 / 48 三种尺寸，
纯手工拼 ICO 二进制，逐像素 Alpha = 0），不依赖任何预置文件。

图标存放在固定位置：

```
%LOCALAPPDATA%\ShortcutArrow\blank.ico
```

放在这里而不是脚本旁边，是因为**脚本目录可以被随意移动/重命名，
而注册表里记的是绝对路径**——放在稳定位置就不会因为挪动文件夹而失效。

---

## 环境要求

- Windows 10 或 Windows 11
- Windows PowerShell 5.1（系统自带）或 PowerShell 7+
- 需要**管理员权限**（写 `HKEY_LOCAL_MACHINE`）

---

## 使用方法

### 一键（推荐）

1. 下载本仓库（`Code` → `Download ZIP`，或 `git clone`）
2. 双击 **`Remove-ShortcutArrow.bat`**
3. UAC 弹窗点「是」
4. 任务栏会闪一下（explorer 重启），完成

### 恢复箭头

双击 **`Restore-ShortcutArrow.bat`**，同样点「是」。

### 手动调用

```powershell
# 去掉箭头
powershell -NoProfile -ExecutionPolicy Bypass -File .\ShortcutArrow.ps1 -Action Remove

# 恢复箭头
powershell -NoProfile -ExecutionPolicy Bypass -File .\ShortcutArrow.ps1 -Action Restore
```

### 参数

| 参数 | 说明 |
|---|---|
| `-Action Remove` | 去掉箭头（默认） |
| `-Action Restore` | 恢复箭头 |
| `-UseSystemIcon` | 改用系统自带的空白图标 `imageres.dll,195`，不生成 .ico 文件 |
| `-NoRestart` | 不重启 explorer，改动在下次重启后生效 |

> `-UseSystemIcon` 在 Windows 11 build 26200 上实测该索引为完全透明（Alpha=0）。
> 但**图标索引可能随 Windows 版本变动**，所以默认走「自己生成 .ico」这条更确定的路。

---

## 脚本做了什么

**`-Action Remove`**

1. 在 `%LOCALAPPDATA%\ShortcutArrow\` 生成全透明的 `blank.ico`（已存在则跳过）
2. 写注册表 `Shell Icons` 值 `29` → 该图标
   - 管理员运行：写 `HKLM`（官方文档位置，全机器生效）
   - 非管理员运行：退回写 `HKCU`
3. 清理图标缓存（`IconCache.db`、`iconcache_*.db`、`thumbcache_*.db`）
4. 重启 `explorer.exe` 让改动立即生效

**`-Action Restore`**

1. 删除 `HKLM` / `HKCU` 下的值 `29`
2. 清理图标缓存
3. 重启 `explorer.exe`

每次运行都会在同目录写 `ShortcutArrow.log`，排查问题看它。

---

## 常见问题

**Q：跑完了箭头还在？**

大概率是注册表没写进去。看 `ShortcutArrow.log` 里有没有
`FAIL ... not writable`。确认是用**管理员**运行的。

**Q：重启电脑后箭头又回来了？**

说明注册表里的图标路径失效了（比如你把 `blank.ico` 删了）。
重新运行一次 `Remove-ShortcutArrow.bat` 即可。

**Q：Windows 大版本更新后箭头回来了？**

系统更新有时会重置这个注册表项，重新运行脚本。

**Q：去掉箭头后分不清哪个是快捷方式了？**

这是必然的 —— 箭头没了就和真实文件长得一样。
如果你想要的是「更好看」而不是「完全消失」，可以把注册表值 `29`
指向一个你自己设计的浅色小箭头图标，做法的其余部分完全一样。

**Q：杀毒软件报警？**

脚本会「改注册表 + 重启 explorer」，行为上像恶意软件。
代码全部可读（就一个 `.ps1`），放行即可。

---

## 手动恢复（脚本跑不了时）

按 `Win+R` 输入 `regedit`，定位到：

```
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons
```

删掉右侧名为 `29` 的字符串值，并检查 `HKEY_CURRENT_USER` 下的同一路径。
然后重启电脑（或注销再登录）。

---

## English

**Remove the shortcut arrow overlay on Windows 10 / 11 — the safe way.**

Most guides tell you to delete the `IsShortcut` value under
`HKEY_CLASSES_ROOT\lnkfile`. That does hide the arrow, but it makes Windows stop
treating `.lnk` as a shortcut, which breaks **Pin to taskbar**, **Pin to Start**,
taskbar drag & drop, and can make shortcuts fail to launch with
*"This file does not have an app associated with it"*.

This project instead **overrides the shortcut overlay icon**
(`Shell Icons` value `29`) with a fully transparent `.ico` that the script
generates on the fly. `IsShortcut` is never touched, so all shortcut behaviour
stays intact.

**Usage**

```powershell
# remove the arrow (run as Administrator)
powershell -NoProfile -ExecutionPolicy Bypass -File .\ShortcutArrow.ps1 -Action Remove

# put it back
powershell -NoProfile -ExecutionPolicy Bypass -File .\ShortcutArrow.ps1 -Action Restore
```

Or just double-click `Remove-ShortcutArrow.bat` / `Restore-ShortcutArrow.bat`.

The transparent icon is written to `%LOCALAPPDATA%\ShortcutArrow\blank.ico`
(not next to the script) so that moving the script folder does not break the
absolute path stored in the registry.

Requires Administrator. Tested on Windows 11 build 26200.

---

## License

MIT —— 见 [LICENSE](LICENSE)。
