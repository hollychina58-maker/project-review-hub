# Codex 审核机设置指南

## 前置条件

1. GitHub CLI (`gh`) — 用于读写 Issues
2. `jq` — JSON 解析
3. Codex CLI（或等效的 AI 工具）— 执行审核

## 安装依赖

### macOS
```bash
brew install gh jq
```

### Linux (Debian/Ubuntu)
```bash
sudo apt install gh jq
```

### Windows
```bash
winget install GitHub.cli jqlang.jq
```

## 配置 gh CLI

```bash
gh auth login
# 选择 GitHub.com → HTTPS → Login with browser
# 使用同一 GitHub 账号 hollychina58-maker 登录
```

## 配置 Codex 审核接口

编辑 `codex-review-watchdog.sh` 中的 `do_review()` 函数，替换审核调用部分。

### 如果你的 Codex 有 CLI：
```bash
# 在 do_review() 中找到方式 1，取消注释：
codex chat --file "$review_prompt_file" > "$review_output_file" 2>&1
```

### 如果 Codex 是 Claude Code 的另一个实例：
```bash
claude --print --file "$review_prompt_file" > "$review_output_file" 2>&1
```

### 如果需要通过 prompt 文件手动操作：
保持默认的模式 3，脚本会将 prompt 写入文件，你手动完成审核后重新运行。

## 运行

### 一次性运行（适合 cron）
```bash
./codex-review-watchdog.sh --once
```

### 持续监控模式
```bash
./codex-review-watchdog.sh --interval 300
```

### 加入 crontab（推荐）
```bash
# 每 5 分钟检查一次
*/5 * * * * cd /path/to/project-review-hub && ./codex-review-watchdog.sh --once >> /tmp/codex-review.log 2>&1
```

## 验证

创建一个测试 Issue 确认流程正常：
```bash
gh issue create \
  --repo hollychina58-maker/project-review-hub \
  --title "TEST: 连通性测试" \
  --label "needs-review" \
  --body "这是一个测试方案，请审核。"
```

然后运行巡检脚本，确认它正确读取并回复了该 Issue。
