# block-adobe-network

> 在 Windows 上一键封禁 / 恢复 Adobe 全家桶联网的 Agent Skill（Photoshop、Illustrator、Lightroom、Premiere、After Effects、Acrobat、Creative Cloud 等）。

## 它解决什么问题

Adobe 软件联网校验授权后，会弹出 **"You no longer have access to this app"**（"您已失去对此应用的访问权限"）并拦截使用。本技能通过 **Windows 防火墙按程序路径精确拦截**，让 Adobe 全家桶无法联网，从根源上阻止授权校验、正版检测、自动更新。

特点：

- 不依赖写死的软件清单，**自动发现**这台机器上安装的所有 Adobe 程序
- 每个可执行文件同时配置 **出站 + 入站** 两条拦截规则
- 自动处理最常见的坑：**第三方安全软件把 Windows 防火墙整个关掉**（规则建了也不生效）
- 自动备份 Adobe 本地授权缓存，解决"断网了但弹窗还在"的问题
- 幂等：重复运行不会产生重复规则
- 一键还原：恢复联网 + 恢复授权缓存

## 系统要求

- Windows 10 / 11（Server 2012+）
- PowerShell 5.1+
- **管理员权限**（写入防火墙规则需要 UAC 提权）

## 安装

### 作为 Agent Skill 使用

1. 点击仓库右上角 `Code → Download ZIP`，解压
2. 把 `block-adobe-network` 文件夹放入你环境的 `.user_skills` 目录（技能目录）
3. 重启对话后，直接说"禁用 Adobe 联网"即可触发

### 手动使用脚本

```powershell
# 封禁（右键以管理员身份运行 PowerShell，或运行时会自动弹 UAC）
.\block-adobe-network.ps1

# 验证当前拦截状态（普通权限即可）
.\verify-adobe-network.ps1

# 恢复联网
.\unblock-adobe-network.ps1
```

## 脚本说明

| 脚本 | 作用 | 需要管理员 |
|---|---|---|
| `block-adobe-network.ps1` | 发现 Adobe 安装 → 为所有 .exe 建出站+入站拦截规则 → 必要时启用防火墙 → 备份授权缓存 → 停止后台辅助进程 | 是 |
| `verify-adobe-network.ps1` | 只读检查：防火墙状态、规则数量、未覆盖的程序、缓存备份、运行中的 Adobe 进程 | 否 |
| `unblock-adobe-network.ps1` | 删除全部 BlockAdobe_* 规则，恢复授权缓存 | 是 |

`block-adobe-network.ps1` 可选参数：

- `-SkipLicenseCacheBackup`：不备份授权缓存
- `-SkipFirewallEnable`：不自动启用防火墙
- `-SkipKillHelpers`：不停止后台辅助进程（绝不误杀 Photoshop/Illustrator/Lightroom 主程序）

## 工作流程

1. **发现**：读取注册表卸载项（任何名称含 "Adobe" 的产品）+ 扫描 `C:\Program Files\Adobe`、`Common Files\Adobe`、AppData 等常见目录
2. **建规则**：递归枚举所有 `.exe`，逐个创建 `BlockAdobe_OUT_*` / `BlockAdobe_IN_*` 防火墙规则
3. **开防火墙**：若三个配置文件（域/专用/公用）任一被关闭则自动启用
4. **清缓存**：把 `Adobe PCD\cache.db`、`pcd.db`、`SLStore\*` 重命名为 `.bak`，应用重新校验时连不上服务器即进入离线可用状态
5. **绕代理**：把 Adobe 域名加入系统代理绕过列表，防止应用借代理绕过防火墙规则
6. **验证**：确认防火墙 Enabled、规则生效、无遗漏程序

## 常见问题

**Q：规则建了，但 PS 还是弹"失去访问权限"？**
A：99% 是 Windows 防火墙被安全软件关了。先跑 `verify-adobe-network.ps1`，看防火墙三个配置文件是否 `Enabled=True`。

**Q：防火墙正常、规则也在，弹窗还是出现？**
A：检查是否走了**系统代理**（Clash/mihomo 等）。开了系统代理时，Adobe 应用经 `127.0.0.1:代理端口` 出网，真实连接由代理进程发出，按程序路径的防火墙规则拦不到。主脚本会自动把 Adobe 域名加入代理绕过列表，让应用直连后由防火墙拦截；改完需完全重启 Adobe 应用。

**Q：断网后弹窗依然在？**
A：之前联网时 Adobe 返回的"非正版"结论被缓存到了本地数据库。`block-adobe-network.ps1` 会自动把缓存数据库改名备份，应用重启后重新校验即可。

**Q：以后新装了 AE / PR 怎么办？**
A：重新运行一次 `block-adobe-network.ps1`，它会自动补全新增程序的规则（已有规则自动跳过）。

**Q：想恢复正常联网？**
A：运行 `unblock-adobe-network.ps1`。

## 注意事项

- 拦截后，Adobe 的云同步、Stock 素材、在线字体、AI 生成功能将不可用，属预期行为
- 本脚本只拦截 Adobe 程序本身，不影响浏览器访问 adobe.com
- 换了 Adobe 安装位置或重装系统后，需重新运行
- 仅供学习研究和个人使用，请遵守你所在地的软件授权条款

## 许可证

MIT

---

# English Version

> One-click block / restore of network access for the entire Adobe suite on Windows (Photoshop, Illustrator, Lightroom, Premiere, After Effects, Acrobat, Creative Cloud, etc.)

## What it solves

After Adobe validates your license online, it may show **"You no longer have access to this app"** and lock the app. This skill uses the **Windows Firewall to block each executable by path**, so the Adobe suite cannot reach the internet and license validation, genuine-software checks, and auto-updates never run.

Highlights:

- **Auto-discovers** every Adobe install on the machine (no hardcoded app list)
- Creates **outbound + inbound** block rules for every executable
- Handles the #1 gotcha: **third-party security software silently disables Windows Firewall**, which makes all rules useless
- **Defeats system proxies**: adds Adobe domains to the proxy bypass list so apps cannot tunnel around the firewall rules via Clash/mihomo
- Backs up the local Adobe license cache, fixing the "popup still appears even offline" problem
- Idempotent: safe to re-run, no duplicate rules
- One-command undo

## Requirements

- Windows 10 / 11 (Server 2012+)
- PowerShell 5.1+
- **Administrator privileges** (UAC elevation)

## Installation

### As an agent skill

1. Click `Code → Download ZIP` on the repository page and unzip
2. Drop the `block-adobe-network` folder into your environment's `.user_skills` directory
3. Restart the session and say "disable Adobe network access" to trigger it

### Run scripts manually

```powershell
# Block everything (run PowerShell as administrator)
.\block-adobe-network.ps1

# Verify current blocking state (no admin needed)
.\verify-adobe-network.ps1

# Restore network access
.\unblock-adobe-network.ps1
```

## Scripts

| Script | Purpose | Admin needed |
|---|---|---|
| `block-adobe-network.ps1` | Discover Adobe installs → create out+in block rules for every .exe → enable firewall if needed → back up license cache → stop background helpers | Yes |
| `verify-adobe-network.ps1` | Read-only report: firewall state, rule counts, uncovered executables, cache backups, running Adobe processes | No |
| `unblock-adobe-network.ps1` | Remove all BlockAdobe_* rules and restore license caches | Yes |

Optional flags for `block-adobe-network.ps1`:

- `-SkipLicenseCacheBackup`
- `-SkipFirewallEnable`
- `-SkipKillHelpers` (never kills the main apps: Photoshop/Illustrator/Lightroom)

## How it works

1. **Discover** reads the uninstall registry (any product whose name contains "Adobe") and scans `C:\Program Files\Adobe`, `Common Files\Adobe`, AppData, and other common paths.
2. **Rule creation** enumerates every `.exe` recursively and creates `BlockAdobe_OUT_*` / `BlockAdobe_IN_*` firewall rules.
3. **Firewall on**: enables any of the three profiles (Domain / Private / Public) that are disabled.
4. **Cache cleanup**: renames `Adobe PCD\cache.db`, `pcd.db`, `SLStore\*` to `.bak`; on next launch the app re-validates, fails to reach the server, and runs offline.
5. **Proxy bypass**: adds Adobe domains to the system proxy bypass list so apps connect directly and get caught by the firewall rules.
6. **Verify**: confirms the firewall is on, rules are active, and nothing is missed.

## FAQ

**Q: Rules exist but Photoshop still shows the "no access" popup?**
A: 99% of the time Windows Firewall is disabled by security software. Run `verify-adobe-network.ps1` and check that all three profiles show `Enabled=True`.

**Q: Firewall is on, rules are in place, but the popup still appears?**
A: Check for a **system proxy** (Clash/mihomo etc.). With a system proxy enabled, Adobe apps connect via `127.0.0.1:<proxy-port>` and the real outbound connection is made by the proxy process, which per-program firewall rules cannot catch. The main script automatically adds Adobe domains to the proxy bypass list so apps connect directly and are blocked by the firewall; fully restart the Adobe app afterwards.

**Q: The popup still appears even offline?**
A: Adobe cached the "non-genuine" verdict locally. The script renames the cache databases to `.bak`; restart the app so it re-validates.

**Q: I install AE / Premiere later — what now?**
A: Just re-run `block-adobe-network.ps1`; it adds rules for the new apps automatically (existing rules are skipped).

**Q: I want normal network access back.**
A: Run `unblock-adobe-network.ps1`.

## Notes

- Cloud sync, Stock assets, online fonts, and AI generation features of Adobe will be unavailable — this is expected.
- Only Adobe processes are blocked; your browser can still reach adobe.com.
- Re-run the script after moving Adobe installs or reinstalling Windows.
- For personal / research use only. Follow the software license terms applicable in your jurisdiction.

## License

MIT
