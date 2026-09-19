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
5. **验证**：确认防火墙 Enabled、规则生效、无遗漏程序

## 常见问题

**Q：规则建了，但 PS 还是弹"失去访问权限"？**
A：99% 是 Windows 防火墙被安全软件关了。先跑 `verify-adobe-network.ps1`，看防火墙三个配置文件是否 `Enabled=True`。

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
