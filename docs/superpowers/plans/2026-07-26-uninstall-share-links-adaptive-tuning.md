# RS Manager 卸载、分享链接与自适应调优实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成只移除 RS Manager 的安全卸载、Sing-box 数字协议菜单和自动分享 URI、编号配置详情，以及不会向受限 VPS 写入未知 sysctl 键的智能 BBR/TCP 调优。

**Architecture:** 保留现有 Bash 模块边界：安装/卸载所有权由独立部署模块负责，Sing-box 模块提供主机规范化、地址检测、详情和 URI 等可测试底层接口，`bin/rs` 仅负责中文数字交互。调优模块继续生成完整模板，再经过逐键能力过滤生成候选文件，事务层只应用已确认支持的键。

**Tech Stack:** Bash 4+、jq、iproute2、curl、sysctl、现有 RS Manager 事务/状态模块和 Shell 测试框架。

## Global Constraints

- 一键卸载只删除 RS Manager 包装器与库，不删除 Sing-box、Realm、服务、配置、证书、状态、备份或 sysctl 调优。
- 菜单协议必须用数字选择，并继续允许同协议多实例。
- 分享 URI 使用自动检测的本机可连接地址；IPv6 必须用方括号。
- 自动检测顺序为全局 IPv4、全局 IPv6、HTTPS 出口地址、手动输入。
- 分享 URI 失败不得回滚已成功创建的协议。
- 调优不得使用 `sysctl -e` 掩盖错误，不得持久化当前系统不支持的键。
- BBR 关键能力不可用时不得写入配置或显示成功。
- 不自动重启 VPS，不修改防火墙、SSH 或 DNS。
- 每项生产代码改动必须先有预期失败的回归测试。

---

### Task 1: 安装所有权标记与仅卸载管理器

**Files:**
- Create: `lib/modules/manager.sh`
- Modify: `install.sh`
- Modify: `bin/rs`
- Test: `tests/cli_test.sh`
- Test: `tests/release_test.sh`

**Interfaces:**
- Produces: `rs_manager_uninstall [prefix]`，成功返回 `0`，所有权无法确认或删除不完整时返回非零。
- Produces: `$PREFIX/lib/rs-manager/.rs-manager-install`，内容为固定标记 `RS_MANAGER_INSTALL_V1`。
- Consumes: `RS_PREFIX`，默认 `/usr/local`。

- [ ] **Step 1: 写卸载范围和所有权失败测试**

在 `tests/cli_test.sh` 安装测试后增加：创建需要保留的 Sing-box、Realm、状态、备份和 sysctl 哨兵文件；执行菜单卸载确认后断言只移除 `bin/rs`、`bin/sb` 和 `lib/rs-manager`。另建无标记前缀，断言卸载拒绝并保留全部文件。

```bash
touch "$prefix/lib/rs-manager/.rs-manager-install"
mkdir -p "$RS_ROOT/etc/sing-box" "$RS_ROOT/root/.realm" "$RS_ROOT/etc/rs-manager" "$RS_ROOT/backups"
printf keep >"$RS_ROOT/etc/sing-box/config.json"
printf keep >"$RS_SYSCTL_FILE"
printf '7\ny\n' | RS_PREFIX="$prefix" bash "$DIR/bin/rs" >/dev/null
assert_false test -e "$prefix/bin/rs"
assert_true test -e "$RS_ROOT/etc/sing-box/config.json"
assert_true test -e "$RS_SYSCTL_FILE"
```

- [ ] **Step 2: 运行 CLI 测试确认 RED**

Run: `bash tests/cli_test.sh`

Expected: FAIL，因为菜单没有卸载选项且安装目录没有所有权标记。

- [ ] **Step 3: 实现标记、卸载模块和菜单入口**

`install.sh` 在阶段库中写入固定标记。`lib/modules/manager.sh` 必须先验证 `prefix` 为绝对路径、标记文件内容完全匹配、两个包装器引用同一库路径，再删除三个安装目标。`bin/rs` 主菜单增加：

```text
7. 一键卸载 RS Manager
```

执行前显示删除/保留清单，只有输入 `y`/`Y` 才调用 `rs_manager_uninstall "${RS_PREFIX:-/usr/local}"`，成功后退出当前进程。

- [ ] **Step 4: 运行 CLI 与发布测试确认 GREEN**

Run: `bash tests/cli_test.sh && bash tests/release_test.sh`

Expected: PASS，保留哨兵文件存在，无标记目录未被删除。

- [ ] **Step 5: 提交**

```bash
git add -- install.sh bin/rs lib/modules/manager.sh tests/cli_test.sh tests/release_test.sh
git commit -m "feat: add safe manager-only uninstall"
```

### Task 2: 标准主机地址和可导入分享 URI

**Files:**
- Modify: `lib/modules/singbox.sh`
- Test: `tests/singbox_test.sh`

**Interfaces:**
- Produces: `rs_sb_validate_host <host>`，接受域名、IPv4、IPv6。
- Produces: `rs_sb_uri_host <host>`，IPv6 返回 `[2001:db8::1]`，其他原样返回。
- Produces: `rs_sb_detect_host`，按 IPv4、IPv6、HTTPS 顺序输出一个已验证地址。
- Produces: `rs_sb_detail <tag>`，输出稳定 TSV 字段供菜单消费。
- Updates: `rs_sb_link <tag> <host>`，对主机、标签、凭据和 IPv6 做标准编码。

- [ ] **Step 1: 写地址与五种 URI 的失败测试**

在 `tests/singbox_test.sh` 添加：

```bash
assert_eq "$(rs_sb_uri_host '2001:db8::1')" '[2001:db8::1]'
assert_true rs_sb_validate_host example.com
assert_false rs_sb_validate_host 'bad host'
link=$(rs_sb_link "$ss" '2001:db8::1')
assert_true grep -q '^ss://.*@\[2001:db8::1\]:' <<<"$link"
assert_false grep -q '[+/=]' <<<"${link#ss://}"
```

通过测试函数覆盖 `ip` 和 `curl`，分别验证全局 IPv4、全局 IPv6、出口 IPv4 回退和全部失败。为 SS、Hysteria2、TUIC、VLESS、AnyTLS 各断言 scheme、端口、关键查询参数和 URI 编码。

- [ ] **Step 2: 运行 Sing-box 测试确认 RED**

Run: `bash tests/singbox_test.sh`

Expected: FAIL，因为主机验证、IPv6 包装、地址检测和详情接口不存在。

- [ ] **Step 3: 实现地址检测、详情和 URI 规范化**

使用 `ip -o -4 addr show scope global` 和 `ip -o -6 addr show scope global` 读取网卡地址；排除 RFC1918、链路本地、环回和文档保留段后，私网场景进入 HTTPS 回退。HTTPS 依次使用固定纯文本端点并设置连接/总超时，不把错误页当地址。`rs_sb_link` 先调用 `rs_sb_validate_host` 和 `rs_sb_uri_host`；SS 用户信息使用无填充 URL-safe Base64：

```bash
printf '%s' "$method:$password" | base64 | tr '+/' '-_' | tr -d '=\r\n'
```

片段标签、密码、SNI 等通过 `rs_sb_urlencode` 编码。`rs_sb_detail` 从配置和状态文件输出名称、类型、Tag、监听、端口、SNI、Reality 公钥状态。

- [ ] **Step 4: 运行 Sing-box 测试确认 GREEN**

Run: `bash tests/singbox_test.sh`

Expected: PASS，五种 URI 均为单行、IPv6 已加方括号、无效主机被拒绝。

- [ ] **Step 5: 提交**

```bash
git add -- lib/modules/singbox.sh tests/singbox_test.sh
git commit -m "feat: generate importable sing-box links"
```

### Task 3: Sing-box 数字添加与编号配置详情菜单

**Files:**
- Modify: `bin/rs`
- Test: `tests/cli_test.sh`

**Interfaces:**
- Consumes: `rs_sb_add`, `rs_sb_list`, `rs_sb_detail`, `rs_sb_detect_host`, `rs_sb_link`。
- Produces: `menu_select_sb_type`，数字 `1..5` 映射 `ss|hy2|tuic|vless|anytls`，`0` 返回状态 `2`。
- Produces: `menu_resolve_sb_host`，自动检测失败时交互读取并验证用户输入。
- Produces: `singbox_view_menu`，编号映射到本次快照中的稳定 Tag。

- [ ] **Step 1: 写数字选择、添加后链接和详情菜单失败测试**

更新旧的文本协议输入测试为：

```bash
output=$(printf '2\n1\nmenu-test\n23456\n0\n' |
  RS_SB_HOST_OVERRIDE=198.51.100.20 bash "$DIR/bin/rs" singbox menu)
assert_true grep -q 'ss://.*198.51.100.20:23456' <<<"$output"
```

增加无效数字后重新选择、`0` 返回、不读取名称端口、两个 SS 实例均存在的断言。查看配置输入 `1\n1\n0\n0\n`，断言输出名称、Tag、端口和 URI；自动检测失败时输入手工域名，断言 URI 使用该域名。

- [ ] **Step 2: 运行 CLI 测试确认 RED**

Run: `bash tests/cli_test.sh`

Expected: FAIL，因为菜单仍读取协议文本，查看配置只输出 TSV。

- [ ] **Step 3: 实现纯数字菜单和添加后自动 URI**

将交互拆成短函数而不是继续扩展单行 `singbox_menu`。添加成功时用命令替换捕获 Tag：

```bash
if tag=$(rs_sb_add "$type" "$name" "$port"); then
  printf '添加成功，实例 Tag: %s\n' "$tag"
  if host=$(menu_resolve_sb_host) && uri=$(rs_sb_link "$tag" "$host"); then
    printf '分享链接：\n%s\n' "$uri"
  else
    rs_warn "协议已创建，但分享链接生成失败；实例 Tag: $tag"
  fi
fi
```

查看配置先把 `rs_sb_list` 快照读入 Bash 数组，显示编号后按编号取 Tag，调用详情与链接函数。空列表、无效编号和 Reality 公钥缺失均给中文提示。

- [ ] **Step 4: 运行 CLI 测试确认 GREEN**

Run: `bash tests/cli_test.sh`

Expected: PASS，数字添加、重复协议、添加后 URI 和编号详情全部工作。

- [ ] **Step 5: 提交**

```bash
git add -- bin/rs tests/cli_test.sh
git commit -m "feat: improve sing-box interactive menus"
```

### Task 4: 自适应 sysctl 候选配置与可靠恢复

**Files:**
- Modify: `lib/modules/tuning.sh`
- Test: `tests/tuning_test.sh`
- Test: `tests/cli_test.sh`

**Interfaces:**
- Produces: `rs_tune_key_supported <key>`，只读探测存在性。
- Produces: `rs_tune_filter_supported <template> <candidate> <skipped>`。
- Produces: `rs_tune_candidate <profile> <candidate> <skipped>`。
- Updates: `rs_tune_preview`, `rs_tune_smart_preview`, `_rs_tune_apply`, `_rs_tune_realm`, `rs_tune_restore_runtime`。

- [ ] **Step 1: 写 unknown-key 回归和关键键失败测试**

在 `tests/tuning_test.sh` 提供可配置的 `sysctl` 测试替身：三个 `net.core.*` 读取返回失败，其他读取成功；写入未知键时记录并失败。断言：

```bash
rs_tune_candidate standard "$candidate" "$skipped"
assert_false grep -q '^net.core.default_qdisc' "$candidate"
assert_true grep -q '^net.core.default_qdisc$' "$skipped"
assert_true rs_tune_apply standard
assert_false test -s "$RS_ROOT/unknown-writes"
```

另让 `net.ipv4.tcp_congestion_control` 不存在，断言 apply 失败且原持久化文件不变。恢复测试让一个捕获键消失，断言其余键仍尝试恢复、函数返回非零且状态备份保留以便重试。

- [ ] **Step 2: 运行调优测试确认 RED**

Run: `bash tests/tuning_test.sh`

Expected: FAIL，当前候选文件仍包含三个未知键并由 `sysctl -p` 整体应用。

- [ ] **Step 3: 实现逐键过滤与应用**

`rs_tune_filter_supported` 保留注释/空行，对赋值行提取等号左侧键并用 `sysctl -n "$key"` 探测；支持项写入 candidate，不支持项只写 key 到 skipped。`rs_tune_check_support` 把 `tcp_congestion_control` 视为关键可写项，并验证可用算法含 `bbr`。应用流程在事务前重新生成 candidate，candidate 校验通过后才替换文件，`rs_tune_post_apply` 只对 candidate 中每个键执行：

```bash
sysctl -w "$key=$value"
```

任一已探测键写入失败则事务失败并恢复，不调用 `sysctl -p`。预览清楚打印“将应用的参数”和“系统不支持，已跳过”。恢复逐项继续，累计失败状态且不删除恢复数据。

- [ ] **Step 4: 运行调优和 CLI 测试确认 GREEN**

Run: `bash tests/tuning_test.sh && bash tests/cli_test.sh`

Expected: PASS，没有 unknown-key 写入；关键键缺失不修改持久化文件；可选键缺失只提示跳过。

- [ ] **Step 5: 提交**

```bash
git add -- lib/modules/tuning.sh tests/tuning_test.sh tests/cli_test.sh
git commit -m "fix: adapt TCP tuning to supported sysctls"
```

### Task 5: 文档、完整审查、发布与固定一键安装

**Files:**
- Modify: `README.md`
- Modify: `rs-manager.sh`
- Modify: `checksums.txt`
- Modify: release metadata files discovered by `rg '1\.0\.3|VERSION='`
- Test: all `tests/*.sh`

**Interfaces:**
- Produces: 下一补丁版本 `v1.0.4` 的可重复构建 Release bundle 和固定 SHA-256 bootstrap。

- [ ] **Step 1: 写/更新发布断言**

在 `tests/release_test.sh` 断言 bundle 包含 `manager.sh` 和安装所有权标记逻辑；在 `tests/cli_test.sh` 断言帮助和中文主菜单包含安全卸载、数字协议和分享链接说明。

- [ ] **Step 2: 运行发布测试确认 RED**

Run: `bash tests/release_test.sh && bash tests/cli_test.sh`

Expected: FAIL，因为 README、bootstrap 版本和 release 断言仍指向 `v1.0.3`。

- [ ] **Step 3: 更新 README 和 `v1.0.4` 发布元数据**

README 写明：

- 直接运行 `rs` 的中文数字菜单；
- 添加协议后自动输出 URI；
- 查看配置可显示 URI；
- 一键卸载仅删除 RS Manager；
- 容器不支持的 sysctl 会显示并跳过；
- 固定 tag 的一键命令。

先把 bootstrap 更新为 `VERSION=1.0.4` 和摘要占位，提交并推送主分支，通过 Ubuntu CI 日志取得 `bundle_sha256`，再只更新 `EXPECTED_SHA256`。

- [ ] **Step 4: 执行本地完整验证和代码审查**

Run:

```bash
find install.sh realm.sh rs-manager.sh bin lib scripts tests -type f -name '*.sh' -exec bash -n {} +
bash tests/run.sh
sha256sum -c checksums.txt
git diff --check
```

Expected: 所有命令退出 `0`；测试输出零失败；无空白错误。

逐条对照设计规格检查卸载保留范围、五种 URI、IPv4/IPv6/手工回退、Reality 公钥错误、未知 sysctl 跳过、关键 BBR 失败和恢复部分失败。

- [ ] **Step 5: 提交、推送、校准摘要并发布**

```bash
git add -- README.md rs-manager.sh checksums.txt tests/release_test.sh tests/cli_test.sh
git commit -m "docs: document safer interactive management"
git push user HEAD:main
# 从 Ubuntu CI 获取 v1.0.4 bundle_sha256 后更新 EXPECTED_SHA256
git add -- rs-manager.sh
git commit -m "chore: pin v1.0.4 release bundle"
git push user HEAD:main
git tag -a v1.0.4 -m "RS Manager v1.0.4"
git push user v1.0.4
```

等待主分支 CI 和 Release workflow 成功；下载 Release asset，校验其 SHA-256 等于 bootstrap 固定摘要，并验证：

```bash
curl -fsSL https://raw.githubusercontent.com/zt1001zt/realm/v1.0.4/rs-manager.sh | sh
```
