# RS Manager 卸载、分享链接与自适应调优设计

## 目标

完善 RS Manager 中文交互菜单：

- 增加只移除 RS Manager 程序的一键卸载。
- Sing-box 添加协议时使用数字选择。
- 创建协议后立即输出可直接导入代理客户端的分享 URI。
- 查看 Sing-box 配置时可按编号选择实例并查看详情及分享 URI。
- BBR/TCP 调优只写入当前系统实际支持的 sysctl 键，兼容受限的 LXC、OpenVZ 和其他容器型 VPS。

## 一键卸载

主菜单增加“一键卸载 RS Manager”。

卸载前显示将删除和保留的范围，并要求二次确认。卸载只删除当前安装前缀下由 RS Manager 安装的程序：

- `/usr/local/bin/rs`
- `/usr/local/bin/sb`
- `/usr/local/lib/rs-manager`

安装前缀由 `RS_PREFIX` 决定，测试或自定义安装时不得写死 `/usr/local`。

卸载必须保留：

- Sing-box 和 Realm 二进制及服务
- `/etc/sing-box/config.json`
- `/root/.realm/config.toml`
- Sing-box 证书
- `/etc/rs-manager` 状态
- `/var/lib/rs-manager/backups`
- RS Manager 已写入的 sysctl 配置和当前运行时调优

卸载器只删除带有 RS Manager 安装标记的包装器和库目录；无法确认所有权时拒绝删除并显示原因。卸载完成后当前菜单进程退出。

## Sing-box 数字协议选择

“添加入站”不再要求输入协议缩写，改为：

1. Shadowsocks
2. Hysteria2
3. TUIC
4. VLESS Reality
5. AnyTLS Reality
0. 返回

数字映射到底层现有协议键 `ss`、`hy2`、`tuic`、`vless`、`anytls`。无效选项不读取名称或端口，直接提示后重新选择。

## 本机地址检测与 URI

新增统一的服务器地址检测函数，按以下顺序选择：

1. 从本机网卡获取非环回、全局作用域的 IPv4。
2. 没有可用 IPv4 时获取全局作用域 IPv6。
3. 本机只有私网地址或无法识别时，通过 HTTPS 查询本机出口公网地址。
4. 自动检测仍失败时提示用户输入域名或 IP。

检测结果必须通过主机名、IPv4 或 IPv6 格式校验。IPv6 写入 URI 时自动添加方括号；标签和凭据按 URI 规则编码。

创建协议成功后，菜单捕获新实例 Tag，并立即调用现有分享链接生成能力，输出标准 URI：

- `ss://`
- `hy2://`
- `tuic://`
- `vless://`
- `anytls://`

分享链接生成失败不回滚已经成功创建的协议；菜单明确说明“协议已创建，但分享链接生成失败”，并给出实例 Tag。

## 查看配置与分享链接

“查看配置”显示编号、名称、协议、端口和 Tag。用户选择编号后显示：

- 名称
- 协议
- Tag
- 监听地址与端口
- SNI/Reality 等该协议适用的关键字段
- 可直接导入的分享 URI

编号只在本次列表中使用，实际操作仍以稳定 Tag 为准。旧 VLESS/AnyTLS 实例若缺少 Reality 公钥，显示明确错误，不输出不完整 URI。

## 自适应 BBR/TCP 调优

当前错误的根因是调优模板固定包含：

- `net.core.default_qdisc`
- `net.core.rmem_max`
- `net.core.wmem_max`

部分容器 VPS 不向来宾暴露这些宿主级 sysctl，因此 `sysctl -p` 返回 unknown key。

修复采用逐项能力探测：

1. 先检测 `net.ipv4.tcp_available_congestion_control` 和 `net.ipv4.tcp_congestion_control`。
2. 必要时尝试加载 `tcp_bbr`，随后重新检测。
3. BBR 不可用或拥塞控制键不可写时停止，不显示成功。
4. 对模板中的每个非关键键调用只读探测；只把系统支持的键写入候选配置。
5. 预览时分别显示“将应用的参数”和“当前系统不支持、已跳过的参数”。
6. 应用前再次生成候选配置，避免预览与应用之间能力状态变化。
7. 持久化文件中不得保留不支持的键，不使用 `sysctl -e` 掩盖错误。

`rs_tune_render` 继续负责生成完整逻辑模板；新增能力过滤层负责生成当前主机候选配置，使模板定义和系统探测可以分别测试。

恢复流程只恢复此前成功捕获的运行时键。某个键在恢复时已经不可用时，记录警告并继续恢复其余键，最终返回部分失败状态。

## 错误处理与安全

- 不自动重启 VPS。
- 不修改防火墙、SSH 或 DNS。
- 不因分享链接失败删除已创建协议。
- 不因某个可选 sysctl 不可用而中止全部调优。
- 关键 BBR 能力不可用时不写入配置。
- 卸载操作必须二次确认并限制在已验证的安装路径。

## 测试

- 菜单数字协议映射、无效选择和返回行为。
- 添加成功后输出对应协议 URI。
- IPv4、IPv6、出口地址回退和手动地址回退。
- 配置编号选择、详情显示和分享 URI。
- 卸载只删除管理器程序并保留服务、配置、状态、备份和 sysctl 文件。
- 模拟缺失 `default_qdisc`、`rmem_max`、`wmem_max` 时，预览显示跳过项，候选配置不含这些键，应用无 unknown key 错误。
- 关键 BBR 键缺失、BBR 不可用以及恢复部分失败。
- 完整 Shell 测试、ShellCheck、Alpine、Rocky 和 Ubuntu CI。
