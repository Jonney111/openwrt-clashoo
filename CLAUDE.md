# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

面向 OpenWrt 的双内核代理管理插件：**mihomo (Clash Meta)** + **sing-box**。内核切换无需重装，同一套 UCI 配置自动适配两端。

测试机：`192.168.3.252`（简称 **252**，OpenWrt LXC 容器），密码 `sony66..`，root 直连。

## 仓库结构

两个独立的 IPK 包：

```
clashoo/                              # 运行时包（OpenWrt IPK 源）
├── Makefile                          # clashoo 运行时包构建
├── files/etc/config/clashoo          # UCI 默认模板（conffile）
├── files/etc/init.d/clashoo          # 服务启停 (procd / USE_PROCD=1)
└── files/usr/share/clashoo/
    ├── net/                          # nftables 防火墙规则 + 连通性检测
    ├── runtime/                      # 订阅拉取、路由策略、YAML生成、DNS
    ├── lib/                          # sing-box JSON 工具 (ucode)
    ├── update/                       # 内核/面板/GeoIP 更新脚本
    └── ruleset/                      # .srs 规则集文件

luci-app-clashoo/                     # LuCI 前端 + RPC 后端
├── Makefile                          # PKG_VERSION 在此（注意：改实质代码需 bump）
├── root/usr/share/rpcd/ucode/luci.clashoo  # ubus RPC 后端（3100+ 行 ucode）
├── root/usr/share/rpcd/acl.d/        # ACL 权限文件
├── root/usr/share/luci/menu.d/       # LuCI 菜单注册
└── htdocs/luci-static/resources/
    ├── view/clashoo/                 # 前端页面（overview / config / system + CSS）
    └── tools/clashoo.js             # 共享 RPC 封装 + toast
```

## 部署与测试

```bash
# JS/CSS 前端改完直接 scp，刷新页面即生效
sshpass -p "sony66.." scp -O -o StrictHostKeyChecking=no \
  luci-app-clashoo/htdocs/luci-static/resources/view/clashoo/config.js \
  root@192.168.3.252:/www/luci-static/resources/view/clashoo/config.js

# luci.clashoo 后端改完需 reload rpcd
sshpass -p "sony66.." scp -O -o StrictHostKeyChecking=no \
  luci-app-clashoo/root/usr/share/rpcd/ucode/luci.clashoo \
  root@192.168.3.252:/usr/share/rpcd/ucode/luci.clashoo
sshpass -p "sony66.." ssh -o StrictHostKeyChecking=no root@192.168.3.252 \
  '/etc/init.d/rpcd reload'

# 验证 RPC 方法是否注册
sshpass -p "sony66.." ssh -o StrictHostKeyChecking=no root@192.168.3.252 \
  'ubus -v list luci.clashoo | grep <method>'

# 查看运行时状态
sshpass -p "sony66.." ssh -o StrictHostKeyChecking=no root@192.168.3.252 \
  'ubus call luci.clashoo status'
```

> 测试脚本（`scripts/test_*.sh`）只在本地工作目录使用，不提交到 GitHub 仓库（`.git/info/exclude` 已忽略）。

### clashoo 包完整恢复（conffile 丢失时）

当 `opkg install` 同版本 IPK 判定"已是最新"导致 conffile 不重建时，直接 scp 全部运行时文件：

```bash
# 补 UCI 配置（最关键，缺少时 RPC 报 uci/get failed: 未找到资源）
sshpass -p "sony66.." scp -O -o StrictHostKeyChecking=no \
  clashoo/files/etc/config/clashoo \
  root@192.168.3.252:/etc/config/clashoo

# 补 init.d + 运行时脚本
for d in init.d runtime net update lib ruleset; do
  sshpass -p "sony66.." scp -O -o StrictHostKeyChecking=no -r \
    clashoo/files/etc/$d root@192.168.3.252:/etc/ 2>/dev/null
done
# 注意：scp -r source/ dest/ 会连 source 目录名一起复制，需检查路径

# 最终 reload rpcd
sshpass -p "sony66.." ssh -o StrictHostKeyChecking=no root@192.168.3.252 \
  'chmod +x /usr/share/clashoo/*/*.sh && /etc/init.d/rpcd reload'
```

## 架构要点

### RPC 分层
- **`luci.clashoo`**（后端）：ucode 脚本，所有 UI 操作通过 `ubus call luci.clashoo <method>` 完成，不直接读写 UCI 缓存
- **`clashoo.js`**（共享层）：`baseclass.extend`，封装跨页面共用的 RPC 方法（status/start/stop 等）+ toast 通知
- **各页面 .js**：页面专属 RPC 用 `var callXxx = rpc.declare(...)` 在文件顶部声明，不通过 clashoo.js 转发

### 配置流
- mihomo：UCI → `yum_change.sh` → `/etc/clashoo/config.yaml`
- sing-box：UCI + 配置文件 → `normalize_singbox_config.uc` → `/etc/sing-box/config.json`
- 配置文件目录（按 type 区分）：`'1'`=`/usr/share/clashoo/config/sub`，`'2'`=`upload`，`'3'`=`custom`，singbox 专属 `/usr/share/clashoo/config/singbox`

### sing-box 配置文件的 sidecar 文件约定
每个 `.json` 配置文件旁边可能有：
- `.info`：`Subscription-Userinfo` HTTP 响应头内容（流量/到期信息），由下载时写入
- `.url`：原始订阅链接，仅 `fetch_singbox_native` 拉取的配置才有，用于"更新"按钮重新拉取

`extract_meta()` 优先读 `.info`，再回退解析 JSON outbound tag。`delete_singbox_profile` 同步删除两个 sidecar。

### init.d 启动逻辑（关键）
- `boot()` 在 `rcS S boot` 阶段调用，会把 `sing-box.main.enabled` 强制设为 `0`，防止 sing-box init.d 在 clashoo 管理它之前自动启动
- `stop_singbox_service()` 停止时同样重置 `sing-box.main.enabled='0'`，防止重启后自启
- `prepare_singbox_runtime()` 是唯一允许设置 `sing-box.main.enabled='1'` 的地方
- `health_status` 运行时状态存在 `/tmp/clashoo_runtime` 下，值：`stopped` / `pass` / `fail` / `degraded`

### 前端健康检查与轮询
- `_pollUntilOpDone`（overview.js）：进程启动后即视为"完成"（`st.running === true || st.health_status === 'fail'`），健康检查继续在后台跑并更新徽标，不阻塞 UI
- LuCI change indicator：执行 `uci.save()` 后若不想触发"未保存的设置"提示，需调用 `clearClashooDirty()`，它执行 `L.uci.callApply(0, false)` 并清空 LuCI staging

### 日志系统（system.js）
三个 tab，key 对应关系：
| tab id | 数据来源 | 能否清空 |
|--------|---------|---------|
| `plugin` | `/usr/share/clashoo/clashoo.txt` | ✓ |
| `core` | `logread -e 'sing-box\|mihomo'` | ✗（syslog） |
| `update` | `/tmp/clash_update.txt` + `/tmp/geoip_update.txt` 合并 | ✓ |

### CSS 按钮样式规范
蓝色轮廓按钮（和「切换」「删除」同色）需要加 `cl-btn-edit` / `cl-btn-switch` / `cl-btn-delete` 类，这些类在 `clashoo.css` 里统一受 `background: rgba(var(--primary-rgb), 0.1)` 控制。新增按钮类时同步在 CSS 两处（normal + hover）加入选择器。

## 关键开发约定

- **修改/修复源码先验证，后提交**：所有代码修改必须先在 252 上部署验证通过，commit/push 前需得到吴白确认。严禁未经验证或未获批准就推送 GitHub。
- **标准化 bump 版本**：每次 commit 涉及较多代码修改或新增功能时，需同时 bump 版本号。`luci-app-clashoo/Makefile` 的 `PKG_VERSION`（patch bump）和 `clashoo/Makefile` 的 `PKG_RELEASE` 都要评估是否需要更新。
- **版本 bump**：改动 `luci-app-clashoo` 任何有实质功能变化的文件，需同步 bump `luci-app-clashoo/Makefile` 中的 `PKG_VERSION`
- **Conffile 陷阱**：`opkg install` 同版本 IPK 会判定"已是最新"，不解包也不重建 conffile。改实质代码后务必 bump 版本号，否则 252 上 `opkg install` 不会更新任何文件。对应地，`clashoo` 包的 `Makefile` PKG_SOURCE_VERSION 改 commit 后也要升 `PKG_VERSION`
- **勿手动改 `clashoo/Makefile` 的 mihomo 版本字段**：`auto-bump-mihomo.yml` 每天 UTC 2:18 自动更新并推 main，手动改会被覆盖
- **nftables 命名空间**：`fw4.sh` 操作 `clashoo_*` 表/链，与 openclash 的 `clash_*` 不冲突
- **UCI 操作**：后端用 `uci_get(pkg, sec, opt)` 辅助函数（每次新建 cursor），避免缓存过期；`sync_legacy_core_fields(c)` 在切换内核时同步旧字段
- **shell 安全**：所有传入 `system()` / `popen()` 的外部变量必须经过 `shell_quote()`
- **异步操作**：耗时操作（restart/download）通过 `rpc_async.sh` 后台执行，前端通过轮询 `status` 感知结果
- **发布**：打 `v*` tag 自动触发 GitHub Actions 构建 9 个架构的 IPK（SDK 24.10）和 APK（25.12），发布到 Release 并同步 B2 feed

## 近期开发记录

- 2026-05 月初：APNs push notification proxy module 功能尝试后因兼容性问题全部 revert（共 5 个 revert commits）
- 当前 `PKG_VERSION`：`1.19.39`（luci-app-clashoo），`clashoo` 包版本 `2026.05.02~2d94970-r1`
- `~/.claude/commands/` 相关 skill：`playwright-cli`（浏览器自动化优先）、`superpowers:systematic-debugging`（调试）
