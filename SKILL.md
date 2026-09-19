---
name: block-adobe-network
description: 在 Windows 上封禁或恢复 Adobe 系列软件（Photoshop、Illustrator、Lightroom、Premiere、After Effects、Acrobat、Creative Cloud 组件等）的联网权限。当用户要求"禁用/封禁/切断 Adobe 软件的联网"、"屏蔽 Adobe 正版校验/许可验证弹窗"（如 "You no longer have access to this app" / "您已失去对此应用的访问权限"）、"阻止 Adobe 更新与授权检测"、需要查询/移除 BlockAdobe 防火墙规则、或清理 Adobe 授权缓存（Adobe PCD / SLStore）时使用。通过 PowerShell + Windows 防火墙实现，按程序路径精确拦截，需管理员权限。
---

# Block Adobe Network (Windows)

把本机所有 Adobe 可执行文件（主程序 + 组件 + 授权/更新辅助进程）通过 Windows 防火墙按程序路径精确拦截出站与入站，并处理防火墙被第三方安全软件关闭、以及本地授权缓存导致弹窗仍在等常见坑。

## 工作流

### 1. 前置只读检查（无需提权）

- 运行 `scripts/verify-adobe-network.ps1`（普通权限即可）查看：
  - 防火墙配置文件是否 Enabled（**关键**：第三方安全软件常把 Windows 防火墙整个关掉，规则建了也不生效）
  - 现有 `BlockAdobe_*` 规则数量与启用的出站/入站拦截数
  - 哪些已发现的 Adobe exe 尚未被规则覆盖
  - 正在运行的 Adobe 进程

### 2. 执行封禁（需管理员提权）

以提权方式运行主脚本（会弹出 UAC，提示用户点"是"）：

```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','<skill目录>\scripts\block-adobe-network.ps1' -Wait
```

脚本自动完成：
1. 从注册表卸载项（`HKLM/HKCU Uninstall` 的 DisplayName 含 Adobe）和常见目录（`C:\Program Files\Adobe`、`(x86)`、`Common Files\Adobe`、`%LOCALAPPDATA%/%APPDATA%\Adobe`）发现全部安装位置；
2. 递归枚举所有 `.exe`，为每个创建 `BlockAdobe_OUT_xxx_名称.exe`（出站拦截）与 `BlockAdobe_IN_xxx_名称.exe`（入站拦截）规则；
3. 若防火墙配置文件被关闭则自动启用（`Set-NetFirewallProfile -Enabled $true`）；
4. 备份授权判定缓存（`Adobe PCD\cache\cache.db`、`pcd.db`、`SLStore\*` 重命名为 `.bak`）——清除本地缓存的"非正版"判定；
5. 停止 Adobe 后台辅助进程（CCXProcess/CCLibrary/AdobeIPCBroker/CoreSync 等；**绝不杀** Photoshop.exe / Illustrator.exe / Lightroom.exe 等主程序）。

幂等设计：已存在的规则会自动跳过，重复运行安全。日志写入 `$env:TEMP\block-adobe-network-<时间戳>.log`。

可选参数：`-SkipLicenseCacheBackup`、`-SkipFirewallEnable`、`-SkipKillHelpers`。

### 3. 验证

再次运行 `scripts/verify-adobe-network.ps1`，确认：防火墙 Enabled、出站/入站拦截数符合预期、无未覆盖 exe。

### 4. 弹窗仍在时的处理

若用户重开 Photoshop 后仍弹"失去访问权限"：
1. 先确认防火墙没有被第三方软件再次关闭（重跑 verify 脚本看 Enabled）；
2. 确认所有 Adobe 进程已退出后完全重启应用（后台进程被杀后会自动重启，不影响）；
3. 确认脚本日志里授权缓存已成功备份（`.bak` 存在）；
4. 若仍无效，检查是否有 Adobe 程序安装在其他未发现的位置（如 D:\AI 等安装包目录），补建规则后重跑主脚本。

### 5. 恢复联网（需管理员提权）

```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','<skill目录>\scripts\unblock-adobe-network.ps1' -Wait
```

移除全部 `BlockAdobe_*` 规则（含历史遗留规则）并把 `.bak` 授权缓存还原。

## 关键经验

- **防火墙关闭是最常见的"规则无效"原因**：规则存在 ≠ 生效。任何一次排查都先看 `Get-NetFirewallProfile` 的 Enabled。
- **规则按程序路径生效**：Adobe 程序换了安装位置或装了新版本后，需要重跑主脚本补规则。
- **本地授权缓存会断网也弹窗**：Adobe 服务器曾返回的"非正版"结论被缓存在 `Adobe PCD\cache.db / pcd.db / SLStore`，断网后应用读缓存照样弹窗；备份（重命名）这些缓存数据库后应用会重新校验，连不上服务器即进入离线可用。
- **Block 规则优先于 Allow 规则**：即使存在放行规则，Block 也生效，无需清理放行规则。
- **只拦 Adobe 程序本身**：浏览器等非 Adobe 进程访问 adobe.com 不受影响；如用户要求连域名一起拦，可额外改 hosts（本技能默认不做）。
- **UAC 提权**：所有写防火墙/改 Program Files 的操作都必须在提权进程中执行；用 `Start-Process -Verb RunAs` 触发，并提醒用户点击 UAC 确认框。
- 主程序（Photoshop.exe 等）进程**绝不自动结束**，避免用户未保存的工作丢失。

## 环境要求

- Windows（10/11/Server 2012+），PowerShell 5.1+
- 写入操作需管理员权限（UAC）
