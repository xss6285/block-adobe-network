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
5. 把 Adobe 域名（`adobe.com`、`adobe.io`、`adobe.net`、`adobecreativecloud.com`、`adobessm.com` 等及子域）加入系统代理绕过列表——防止应用走代理绕过防火墙；
6. 若检测到 Clash Verge（`verge.yaml`），把 Adobe 域名写入它**自己的**代理绕过配置（`use_default_bypass: false` + `system_proxy_bypass`），防止代理软件重启时冲掉手动添加的绕过项。**注意：若 Clash Verge 正在运行，脚本改的配置文件会在它退出时被旧内存配置覆盖——运行前先让用户完全退出 Clash Verge（托盘退出），或运行后让用户重启一次 Clash Verge，此后每次重启都会自动带上 Adobe 绕过。**
7. 在 hosts 文件中把 Adobe 授权/正版校验域名（`lmlicenses.wip4.adobe.com`、`prod.adobegenuine.com`、`cc-api.adobe.io` 等 23 个）解析到 `0.0.0.0`——即使应用不走系统代理，DNS 解析也直接失败；
8. 停止 Adobe 后台辅助进程（CCXProcess/CCLibrary/AdobeIPCBroker/CoreSync 等；**绝不杀** Photoshop.exe / Illustrator.exe / Lightroom.exe 等主程序）。

幂等设计：已存在的规则会自动跳过，重复运行安全。日志写入 `$env:TEMP\block-adobe-network-<时间戳>.log`。

可选参数：`-SkipLicenseCacheBackup`、`-SkipFirewallEnable`、`-SkipKillHelpers`。

### 3. 验证

再次运行 `scripts/verify-adobe-network.ps1`，确认：防火墙 Enabled、出站/入站拦截数符合预期、无未覆盖 exe。

### 4. 弹窗仍在时的处理

若用户重开 Photoshop 后仍弹"失去访问权限"：
1. 先确认防火墙没有被第三方软件再次关闭（重跑 verify 脚本看 Enabled）；
2. **检查是否走了系统代理**：若用户装了 Clash/mihomo 等代理且系统代理开启，Adobe 应用会通过代理联网，绕过按程序路径的防火墙规则（真正的出站连接由代理进程发出）。此时查看 Windows 防火墙连接日志（`C:\Windows\System32\LogFiles\Firewall\pfirewall.log`，需管理员读取）确认 Adobe PID 是否在连 `127.0.0.1:<代理端口>`；修复方式就是重跑主脚本（会自动把 Adobe 域名加入代理绕过列表，逼应用直连后由防火墙拦截）；
   - **特别注意：Clash Verge 会在启动/重配时重写系统代理并冲掉手动加入的绕过项**。若绕过列表又变回默认（只剩 `localhost;127.*;<local>` 等），说明被重置了——重跑主脚本即可（它会同时写 Clash 自己的 `verge.yaml`，之后重启 Clash 也不再丢）；
3. 确认所有 Adobe 进程已退出后完全重启应用（后台进程被杀后会自动重启，不影响）；
4. 确认脚本日志里授权缓存已成功备份（`.bak` 存在）；
5. 若仍无效，检查是否有 Adobe 程序安装在其他未发现的位置（如 D:\AI 等安装包目录），补建规则后重跑主脚本。

### 5. 恢复联网（需管理员提权）

```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','<skill目录>\scripts\unblock-adobe-network.ps1' -Wait
```

移除全部 `BlockAdobe_*` 规则（含历史遗留规则）并把 `.bak` 授权缓存还原。

## 关键经验

- **防火墙关闭是最常见的"规则无效"原因**：规则存在 ≠ 生效。任何一次排查都先看 `Get-NetFirewallProfile` 的 Enabled。
- **规则按程序路径生效**：Adobe 程序换了安装位置或装了新版本后，需要重跑主脚本补规则。
- **本地授权缓存会断网也弹窗**：Adobe 服务器曾返回的"非正版"结论被缓存在 `Adobe PCD\cache.db / pcd.db / SLStore`，断网后应用读缓存照样弹窗；备份（重命名）这些缓存数据库后应用会重新校验，连不上服务器即进入离线可用。
- **系统代理会绕过按程序路径的规则**：装了 Clash/mihomo 等代理并开启系统代理时，Adobe 应用经 `127.0.0.1:<端口>` 出网，真实连接由代理进程发起，防火墙按程序拦截失效。必须把 Adobe 域名加入代理绕过列表（主脚本自动处理），让应用直连后被规则拦截。
- **Clash Verge 会重置系统代理绕过列表**：代理软件启动/重配时会把 ProxyOverride 写回默认值，手动加的 Adobe 域名会被冲掉。主脚本同时修改 Clash 自己的 `verge.yaml`（`system_proxy_bypass`），从源头持久化。**关键坑：必须在 Clash 停止时修改配置文件**——它运行时改的文件会在退出时被旧内存配置覆盖（曾因此反复复发）；改完后重启一次 Clash Verge 即可永久生效。
- **hosts 兜底**：主脚本还把 23 个 Adobe 授权/正版校验域名写进 hosts（`0.0.0.0`），即使应用绕过系统代理，DNS 解析也直接失败。hosts 改动会全局生效（浏览器访问这些域名同样被拦），恢复联网时 unblock 脚本会一并清理。
- **Block 规则优先于 Allow 规则**：即使存在放行规则，Block 也生效，无需清理放行规则。
- **只拦 Adobe 程序本身**：浏览器等非 Adobe 进程访问 adobe.com 不受影响；hosts 兜底仅拦授权相关域名（不影响 adobe.com 主页）。
- **UAC 提权**：所有写防火墙/改 Program Files 的操作都必须在提权进程中执行；用 `Start-Process -Verb RunAs` 触发，并提醒用户点击 UAC 确认框。
- 主程序（Photoshop.exe 等）进程**绝不自动结束**，避免用户未保存的工作丢失。

## 环境要求

- Windows（10/11/Server 2012+），PowerShell 5.1+
- 写入操作需管理员权限（UAC）
