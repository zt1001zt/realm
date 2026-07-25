# 中文菜单与按需依赖安装 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提供中文数字菜单、操作前的组件安装确认，并修复未安装 Sing-box 时添加 Reality 协议的错误路径。

**Architecture:** 保持现有 CLI 可脚本化；交互依赖检测集中在 `bin/rs`，底层 Sing-box 模块只报告明确的前置条件错误。智能调优复用已有 BBR 检测、预览、应用、运行态备份与还原逻辑，在菜单层编排“检测→预览→确认→应用”。

**Tech Stack:** Bash、jq、sysctl、systemd/OpenRC、现有 Shell 测试框架。

## Global Constraints

- 不实现或展示 Web 面板。
- 不在用户确认前下载或安装组件。
- 不自动重启 VPS，且不修改 SSH、DNS 或防火墙。
- CLI `rs singbox add` 不得隐式下载安装 Sing-box。
- 菜单安装复用 `rs_component_install` 的 SHA-256 校验与事务回滚。
- BBR 不受内核支持时必须明确失败。

---

### Task 1: 明确缺失 Sing-box 的 Reality 前置条件

**Files:**
- Modify: `tests/singbox_test.sh`
- Modify: `lib/modules/singbox.sh:8-15`

**Interfaces:**
- Produces: `rs_sb_reality_keypair()` 在无二进制时返回 1，并向 stderr 输出 `sing-box is not installed; run: rs service install sing-box`。

- [ ] **Step 1: 写失败测试**

在 `tests/singbox_test.sh` 的 mock 二进制加入 `PATH` 前，以 `/usr/bin:/bin` 运行子 Shell，调用 `rs_sb_reality_keypair`，并断言 exit code 为 `1`、输出包含手动安装命令。

- [ ] **Step 2: 验证失败**

Run: `bash tests/singbox_test.sh`

Expected: 新断言失败，旧输出为 `sing-box is required to generate Reality keys`。

- [ ] **Step 3: 最小实现**

在 `lib/modules/singbox.sh` 中将缺失二进制分支替换为：

```bash
command -v sing-box >/dev/null 2>&1 || {
  rs_die 'sing-box is not installed; run: rs service install sing-box'
  return 1
}
```

- [ ] **Step 4: 验证通过**

Run: `bash tests/singbox_test.sh`

Expected: exit 0，新增断言通过。

- [ ] **Step 5: 提交**

```bash
git add tests/singbox_test.sh lib/modules/singbox.sh
git commit -m "fix: clarify missing Sing-box prerequisite"
```

### Task 2: 菜单中按需安装组件

**Files:**
- Modify: `tests/cli_test.sh`
- Modify: `bin/rs:20-28`

**Interfaces:**
- Consumes: `rs_component_install COMPONENT`。
- Produces: `menu_ensure_component COMPONENT LABEL`。成功返回 0；拒绝返回 1 并显示 `请先安装：rs service install COMPONENT`；确认时调用已有安装器。

- [ ] **Step 1: 写失败测试**

在 `tests/cli_test.sh` 添加临时安装 hook：

```bash
cat >"$RS_ROOT/menu-install-hook" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >"$RS_ROOT/menu-install.log"
EOF
chmod +x "$RS_ROOT/menu-install-hook"
sb_prompt=$(printf '2\n\n0\n' | RS_MENU_INSTALL_HOOK="$RS_ROOT/menu-install-hook" PATH="$RS_ROOT/test-bin:/usr/bin:/bin" bash "$DIR/bin/rs" singbox menu 2>&1 || true)
assert_true grep -Fq '未安装 Sing-box，是否立即安装？ [Y/n]' <<<"$sb_prompt"
assert_eq "$(cat "$RS_ROOT/menu-install.log")" sing-box
```

- [ ] **Step 2: 验证失败**

Run: `bash tests/cli_test.sh`

Expected: 断言失败，因为当前菜单没有安装提示也不会调用 hook。

- [ ] **Step 3: 最小实现**

在 `bin/rs` 新增：

```bash
menu_ensure_component(){
  local component=$1 label=$2 answer
  command -v "$component" >/dev/null 2>&1 && return 0
  read -r -p "未安装 ${label}，是否立即安装？ [Y/n] " answer
  case ${answer:-Y} in Y|y|yes|YES) ;; *) rs_warn "请先安装：rs service install $component"; return 1;; esac
  if [[ -n ${RS_MENU_INSTALL_HOOK:-} ]]; then "$RS_MENU_INSTALL_HOOK" "$component"; else rs_component_install "$component"; fi || {
    rs_warn "${label} 安装失败，已取消当前操作"; return 1;
  }
}
```

在 Sing-box 的添加和克隆分支读取任何参数前调用 `menu_ensure_component sing-box Sing-box || continue`。

- [ ] **Step 4: 验证通过**

Run: `bash tests/cli_test.sh`

Expected: exit 0；提示显示且 hook 文件记录 `sing-box`。

- [ ] **Step 5: 提交**

```bash
git add tests/cli_test.sh bin/rs
git commit -m "fix: prompt to install Sing-box before protocol changes"
```

### Task 3: 中文菜单与智能 BBR 调优入口

**Files:**
- Modify: `tests/cli_test.sh`
- Modify: `tests/tuning_test.sh`
- Modify: `bin/rs:24-28`
- Modify: `lib/modules/tuning.sh:105-106`

**Interfaces:**
- Consumes: `rs_tune_status`、`rs_tune_preview standard`、`rs_tune_apply standard`、`rs_tune_check_support`。
- Produces: `rs_tune_smart_preview()`；输出检测、内存、nofile 限制及 BBR 配置预览，失败时返回非零。

- [ ] **Step 1: 写失败测试**

在 `tests/tuning_test.sh` 增加：

```bash
smart_preview=$(rs_tune_smart_preview)
assert_true grep -q '^kernel=' <<<"$smart_preview"
assert_true grep -q 'tcp_congestion_control = bbr' <<<"$smart_preview"
```

在 `tests/cli_test.sh` 增加：

```bash
cn_menu=$(printf '0\n' | bash "$DIR/bin/rs")
assert_true grep -Fq 'RS Manager 一键管理脚本' <<<"$cn_menu"
assert_true grep -Fq 'BBR/TCP 智能调优' <<<"$cn_menu"
```

- [ ] **Step 2: 验证失败**

Run: `bash tests/tuning_test.sh && bash tests/cli_test.sh`

Expected: `rs_tune_smart_preview: command not found`，且中文标题断言失败。

- [ ] **Step 3: 最小实现**

在 `lib/modules/tuning.sh` 增加：

```bash
rs_tune_smart_preview(){
  printf '%s\n' '智能检测结果：'
  rs_tune_status
  printf 'memory_kb=%s\n' "$(awk '/MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || true)"
  printf 'nofile=%s\n' "$(ulimit -n)"
  rs_tune_check_support || return 1
  printf '%s\n' '将应用以下 BBR/TCP 参数：'
  rs_tune_preview standard
}
```

把主菜单、Sing-box、Realm 和服务子菜单替换为中文数字文本，不改变数字绑定的现有底层函数。调优菜单的“智能一键调优”先调用 `rs_tune_smart_preview`，然后读 `确认应用智能调优？ [y/N]`；仅 `Y/y` 调用 `rs_tune_apply standard`。

- [ ] **Step 4: 验证通过**

Run: `bash tests/tuning_test.sh && bash tests/cli_test.sh`

Expected: exit 0；智能预览含 kernel 与 BBR 配置，主菜单含中文标题和调优项。

- [ ] **Step 5: 提交**

```bash
git add tests/cli_test.sh tests/tuning_test.sh bin/rs lib/modules/tuning.sh
git commit -m "feat: add Chinese menu and smart BBR tuning"
```

### Task 4: 文档、完整验证与发布

**Files:**
- Modify: `README.md`
- Modify: `rs-manager.sh`
- Modify: `checksums.txt`

- [ ] **Step 1: 更新 README**

说明菜单会确认安装 Sing-box，智能调优先检测和预览再确认应用，且还原会恢复 RS Manager 修改前的调优状态。

- [ ] **Step 2: 完整验证**

Run:

```bash
find install.sh realm.sh rs-manager.sh bin lib scripts tests -type f -name '*.sh' -exec bash -n {} +
bash tests/run.sh
sha256sum -c checksums.txt
```

Expected: 全部 exit 0。

- [ ] **Step 3: 发布 v1.0.3**

将 bootstrap 的 `VERSION` 升级为 `1.0.3` 后先推送 main，由 Linux CI 输出 `bundle_sha256`；以该值更新 `EXPECTED_SHA256` 并推送。CI 成功后：

```bash
git tag -a v1.0.3 -m "RS Manager v1.0.3"
git push user v1.0.3
```

Expected: Release 使用相同 SHA-256 创建 `v1.0.3`。