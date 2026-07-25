# RS Manager：Realm + Sing-box + BBR/TCP 一键管理

RS Manager 把 Realm 转发、Sing-box 多协议实例和可恢复的 BBR/TCP 调优整合为一个命令行工具，同时保留原 `realm.sh` 与 `sb` 使用习惯。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/zt1001zt/realm/v1.0.1/rs-manager.sh | sh
```

Alpine（默认自带 BusyBox `wget`）也可以使用：

```sh
wget -qO- https://raw.githubusercontent.com/zt1001zt/realm/v1.0.1/rs-manager.sh | sh
```

引导脚本只下载固定的 `v1.0.1` Release 包，并使用脚本内置的独立 SHA-256 摘要校验；摘要不匹配时会直接终止，不会覆盖现有安装。

脚本安装后会进入菜单。首次使用可选择 `Services` → `install/upgrade all`，或执行 `rs service install all`，安装经过固定 SHA-256 校验的 Sing-box 与 Realm 官方二进制及 systemd/OpenRC 服务。已有二进制、配置和服务文件在变更前会备份，启动或健康检查失败会回滚。

安装完成后：

```bash
rs                 # 统一管理菜单
sb                 # 直接进入 Sing-box 管理
rs --help          # 查看非交互命令
```

## 主要能力

- 首次没有选择的 SS、Hysteria2、TUIC、VLESS Reality、AnyTLS Reality，可在安装后继续添加。
- 同一种协议可创建多个独立实例，使用唯一 Tag、端口和凭据。
- 修改配置时保留已有 DNS、路由、出站和未知自定义字段。
- Realm 支持稳定 ID 的添加、编辑、启停、删除和连续端口段。
- 可安装、升级、启动、停止、重启并检查 Sing-box/Realm 服务。
- BBR/`fq` 提供低内存、标准、高带宽三档配置；只写入管理器自己的 sysctl 文件并可恢复。
- 支持 Debian/Ubuntu、CentOS/RHEL/Rocky/AlmaLinux 和 Alpine，兼容 systemd 与 OpenRC。
- 配置修改前自动备份，候选配置校验后原子替换。

## 常用命令

```bash
rs singbox list
rs service install all
rs service status all
rs singbox add hy2 hy-main 24443
rs singbox add vless reality-main 34443
rs singbox link rs-hy2-ab12 example.com
rs realm add edge-1 443 target.example.com:8443
rs realm range 10000 10010 target.example.com 20000
rs tune preview standard
rs tune apply standard
rs tune restore
rs diagnose
```

> BBR/TCP 调优不会自动换内核、重启 VPS、修改防火墙、SSH 或 DNS。修改内核前应确认服务商支持并准备控制台救援方式。

## 无损迁移

RS Manager 直接读取 `/etc/sing-box/config.json` 和 `/root/.realm/config.toml`。旧 Sing-box 的 `.protocols` 布尔标记不再决定哪些协议可以管理；实际入站配置才是数据源。已有 Sing-box 入站会登记为旧实例，已有 Realm endpoint 会添加稳定的 `legacy-*` 标记。DNS、路由、出站、其他 TOML 段和无法识别的自定义内容保持不变。

## 卸载

删除 RS Manager 默认不会删除 Sing-box、Realm、证书或原生配置。服务卸载仍可通过原 Realm 管理入口或发行版包管理器单独执行。

---

## 原 Realm 脚本说明
## Realm 一键转发脚本

参考自 https://www.nodeseek.com/post-183613-1 ，感谢原教程作者。

本脚本在原教程基础上增加了 Realm 安装、转发规则管理、服务重启、脚本更新和可视化面板管理功能。

## v3.2.5 更新重点

- 支持 Alpine Linux。
- Alpine 自动使用 OpenRC 管理 `realm` 和 `realm-panel` 服务。
- Alpine 自动选择官方 `unknown-linux-musl` 版 Realm 二进制。
- Debian / Ubuntu / CentOS 等 systemd 系统保留原有行为。
- 面板后端兼容 systemd 与 OpenRC 服务控制。
- Release 构建产物改为 GitHub Actions 自动生成，不再提交本地二进制。

## 脚本界面预览

```text
################################################
#        Realm 一键转发脚本 (v3.2.6)         #
################################################
 Realm 状态: 运行中
 面板 状态: 已安装但未启动
------------------------------------------------
  1. 安装 / 重置 Realm
  2. 卸载 Realm
------------------------------------------------
  3. 添加转发规则
  4. 添加端口段转发
  5. 删除转发规则
  6. 查看当前配置
------------------------------------------------
  7. 启动服务
  8. 停止服务
  9. 重启服务
------------------------------------------------
  10. 更新脚本
  11. 面板管理
  0. 退出脚本
################################################
```

## 一键安装

### Debian / Ubuntu / CentOS

```bash
curl -L https://github.com/wcwq98/realm/releases/download/v3.2.6/realm.sh -o realm.sh && chmod +x realm.sh && ./realm.sh
```

或使用主分支最新版：

```bash
curl -L https://raw.githubusercontent.com/wcwq98/realm/refs/heads/main/realm.sh -o realm.sh && chmod +x realm.sh && ./realm.sh
```

### Alpine Linux

Alpine 默认可能没有 Bash，先安装运行依赖：

```sh
apk add --no-cache bash curl
curl -L https://raw.githubusercontent.com/wcwq98/realm/refs/heads/main/realm.sh -o realm.sh
chmod +x realm.sh
bash ./realm.sh
```

## 系统支持

| 系统 | 包管理器 | 服务管理 | Realm 二进制 |
| --- | --- | --- | --- |
| Debian / Ubuntu | `apt-get` | systemd | `unknown-linux-gnu` |
| CentOS / RHEL | `yum` | systemd | `unknown-linux-gnu` |
| Alpine Linux | `apk` | OpenRC | `unknown-linux-musl` |

支持架构：

- `x86_64` / `amd64`
- `aarch64` / `arm64`

## 默认 Realm 配置

脚本首次部署环境时会自动创建 `/root/.realm/config.toml`：

```toml
[network]
no_tcp = false
use_udp = true

# 参考模板
# [[endpoints]]
# listen = "0.0.0.0:本地端口"
# remote = "落地机IP:目标端口"

[[endpoints]]
listen = "0.0.0.0:1234"
remote = "0.0.0.0:5678"
```

## 可视化面板配置

面板配置文件路径：

```text
/root/realm/web/config.toml
```

默认配置：

```toml
[auth]
password = "123456"

[server]
port = 8081
session_secret = ""

[https]
enabled = false
cert_file = "./certificate/cert.pem"
key_file = "./certificate/private.key"

[realm]
config_path = "/root/.realm/config.toml"
```

建议安装后立即修改默认密码。生产环境建议启用 HTTPS，并设置固定 `session_secret`。

## Release 自动构建

推送 `v*` tag 后，GitHub Actions 会自动构建面板后端并发布：

- `realm-panel-linux-amd64.zip`
- `realm-panel-linux-arm64.zip`

本仓库不再提交 `web/realm_web`、`dist/`、`*.zip`、`*.tar.gz` 等构建产物。

## 官方 Realm 文档

更多 Realm 配置请参考官方项目：

https://github.com/zhboner/realm
