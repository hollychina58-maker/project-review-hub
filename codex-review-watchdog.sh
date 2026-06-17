#!/bin/bash
# =============================================================================
# codex-review-watchdog.sh
# Codex 审核巡检脚本 — 在远端 Codex 机器上运行
#
# 功能:
#   1. 定时扫描 project-review-hub 中 needs-review 标签的 Issue
#   2. 检查是否已有 Codex 评论（避免重复审核）
#   3. 调用 Codex CLI 进行多维度审计
#   4. 将审核结果作为 Issue 评论发布
#   5. 更新 Issue 标签（in-discussion / approved / rejected）
#
# 用法:
#   一次性:   ./codex-review-watchdog.sh --once
#   持续监控: ./codex-review-watchdog.sh --interval 300
#   cron:     */5 * * * * /path/to/codex-review-watchdog.sh --once
#
# 依赖: gh (GitHub CLI), jq, codex CLI (或兼容的 AI CLI 工具)
# =============================================================================

set -euo pipefail

# ======================== 配置区 ========================
REPO="hollychina58-maker/project-review-hub"
REVIEWER_NAME="Codex"
MAX_ROUNDS=5
WORK_DIR="/tmp/codex-review"

# Codex 调用方式: "cli" | "claude" | "http" | "placeholder"
# 根据你的 Codex 实际接口选择，详见 do_review() 函数
CODEX_MODE="cli"

# 如果 CODEX_MODE="http"，配置以下参数:
CODEX_HTTP_URL="http://localhost:8080/api/review"

mkdir -p "$WORK_DIR"

# ======================== 辅助函数 ========================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# 检查 gh CLI 是否可用
check_deps() {
    for cmd in gh jq; do
        if ! command -v "$cmd" &>/dev/null; then
            log "ERROR: $cmd 未安装，请先安装 $cmd"
            exit 1
        fi
    done
}

# 获取 Issue 中 Codex 的评论数量（用于判断是否已审核和当前轮次）
get_codex_comment_count() {
    local issue_number="$1"
    gh issue view "$issue_number" \
        --repo "$REPO" \
        --json comments \
        --jq '[.comments[] | select(.author.login == "hollychina58-maker")] | length' 2>/dev/null || echo "0"
}

# 获取所有评论内容
get_all_comments() {
    local issue_number="$1"
    gh issue view "$issue_number" \
        --repo "$REPO" \
        --comments 2>/dev/null || echo ""
}

# 获取 Issue 作者
get_issue_author() {
    local issue_number="$1"
    gh issue view "$issue_number" \
        --repo "$REPO" \
        --json author \
        --jq '.author.login' 2>/dev/null || echo "unknown"
}

# 获取当前标签
get_current_labels() {
    local issue_number="$1"
    gh issue view "$issue_number" \
        --repo "$REPO" \
        --json labels \
        --jq '[.labels[].name] | join(",")' 2>/dev/null || echo ""
}

# 更新标签
update_label() {
    local issue_number="$1"
    local remove_label="$2"
    local add_label="$3"
    gh issue edit "$issue_number" \
        --repo "$REPO" \
        --remove-label "$remove_label" \
        --add-label "$add_label" 2>/dev/null
    log "  Issue #$issue_number 标签: $remove_label → $add_label"
}

# ======================== 核心审核函数 ========================
#
# 这是需要适配 Codex CLI 的核心函数。
# 接收: Issue 正文 + 所有历史评论
# 输出: 审核报告 (Markdown)
#
# 根据 Codex 的实际 CLI 接口修改此函数。
# 如果 Codex 不支持 CLI，也可以用文件管道 + 手动操作替代。
# ==============================================================

do_review() {
    local issue_body="$1"
    local round="$2"
    local review_prompt_file="$WORK_DIR/review-prompt-round-${round}.md"
    local review_output_file="$WORK_DIR/review-output-round-${round}.md"
    local review_header="## 第 ${round} 轮审核 (Codex)"

    # 构建 prompt：先写指令头，再拼接待审内容文件
    cat > "$review_prompt_file" << PROMPT_EOF
你是一名资深技术审核员（Codex）。请对以下技术方案进行严格的多维度审计。

审核要求：
1. 逐点审计方案，每点使用以下标签之一：PASS / CONCERN / REJECT / SUGGEST / QUESTION
   （注意：标签前不要加方括号，直接用大写单词后跟冒号，如 "PASS: xxx"）
2. 覆盖维度：正确性、简洁性、安全性、性能、可维护性、一致性、完整性、可测试性
3. 每个质疑必须包含：具体问题 + 改进建议 + 风险等级
4. 最后给出总评：本轮整体意见 + 整体风险等级（低/中/高）
5. 如果方案完全通过，回复末尾写：FINAL_VERDICT: APPROVED
6. 如果要否决方案，回复末尾写：FINAL_VERDICT: REJECTED，并说明原因

回复格式：以 "## 第 ${round} 轮审核 (Codex)" 开头。

---
PROMPT_EOF

    # 将待审内容追加到 prompt 文件（printf 比 sed 安全，保留原文字符）
    printf '%s\n' "$issue_body" >> "$review_prompt_file"

    # ============================================
    # 根据 CODEX_MODE 选择调用方式
    # ============================================

    log "  调用 Codex 审核 (mode: $CODEX_MODE)..."

    case "$CODEX_MODE" in
        cli)
            # 方式 1: Codex exec — 非交互模式，stdin 传入 prompt，输出到文件
            codex exec \
                --ephemeral \
                --skip-git-repo-check \
                --dangerously-bypass-approvals-and-sandbox \
                --output-last-message "$review_output_file" \
                - < "$review_prompt_file" 2>&1
            ;;
        claude)
            # 方式 2: Codex 是 Claude Code 实例
            claude --print "$(cat "$review_prompt_file")" > "$review_output_file" 2>&1
            ;;
        http)
            # 方式 3: HTTP API
            curl -s -X POST "$CODEX_HTTP_URL" \
                -H "Content-Type: application/json" \
                -d "$(cat "$review_prompt_file" | jq -Rs '{prompt: .}')" \
                > "$review_output_file" 2>&1
            ;;
        placeholder|*)
            # 方式 0: 占位模式
            echo "$review_header" > "$review_output_file"
            echo "" >> "$review_output_file"
            echo "⚠️  CODEX_NOT_CONFIGURED: 审核接口未配置 (CODEX_MODE=$CODEX_MODE)。" >> "$review_output_file"
            echo "请将 script 中 CODEX_MODE 设为 cli/claude/http，或手动审核：" >> "$review_output_file"
            echo "  输入: $review_prompt_file" >> "$review_output_file"
            echo "  输出: $review_output_file" >> "$review_output_file"
            echo "" >> "$review_output_file"
            echo "FINAL_VERDICT: PENDING" >> "$review_output_file"
            ;;
    esac

    # 返回审核结果
    cat "$review_output_file"
}

# ======================== 主流程 ========================

process_single_issue() {
    local issue_number="$1"
    log "=== 处理 Issue #$issue_number ==="

    # 获取 Issue 详情
    local title
    title=$(gh issue view "$issue_number" --repo "$REPO" --json title --jq '.title' 2>/dev/null)
    local body
    body=$(gh issue view "$issue_number" --repo "$REPO" --json body --jq '.body' 2>/dev/null)
    local author
    author=$(get_issue_author "$issue_number")

    log "  标题: $title"
    log "  作者: $author"

    # 判断当前轮次（Codex 已评论次数 + 1）
    local codex_comments
    codex_comments=$(get_codex_comment_count "$issue_number")
    local current_round=$((codex_comments + 1))

    if [ "$current_round" -gt "$MAX_ROUNDS" ]; then
        log "  ⚠️  已达到最大轮次 ($MAX_ROUNDS)，需要人工介入"
        gh issue comment "$issue_number" --repo "$REPO" \
            --body "## 已达最大审核轮次

已进行 $MAX_ROUNDS 轮审核仍未收敛。

**建议**: @hollychina58-maker 请人工介入决策。"
        update_label "$issue_number" "in-discussion" "rejected"
        return
    fi

    # 检查是否是 Claude Code 回复了新一轮（自上次 Codex 评论后有新回复）
    local all_comments
    all_comments=$(get_all_comments "$issue_number")

    # 获取完整上下文：原始提案 + 所有讨论
    local full_context="## Issue 标题: $title

## 原始提案
$body

## 讨论历史
$all_comments"

    # 执行审核
    local review_result
    review_result=$(do_review "$full_context" "$current_round")

    # 发布审核评论
    log "  发布第 $current_round 轮审核评论..."
    echo "$review_result" | gh issue comment "$issue_number" --repo "$REPO" --body-file -

    # 根据审核结果更新标签
    if echo "$review_result" | grep -q "FINAL_VERDICT: APPROVED"; then
        log "  ✅ 审核通过！"
        update_label "$issue_number" "needs-review" "approved"
    elif echo "$review_result" | grep -q "FINAL_VERDICT: REJECTED"; then
        log "  ❌ 方案被否决"
        update_label "$issue_number" "needs-review" "rejected"
    elif echo "$review_result" | grep -q "CODEX_NOT_CONFIGURED\|FINAL_VERDICT: PENDING"; then
        log "  ⚠️  Codex 接口未配置或审核待处理，跳过此 Issue"
        # 保持 needs-review 标签，等待 Codex 配置完成
        return
    else
        log "  🔄 审核中，等待下一轮"
        local current_labels
        current_labels=$(get_current_labels "$issue_number")
        if echo "$current_labels" | grep -q "needs-review"; then
            update_label "$issue_number" "needs-review" "in-discussion"
        fi
    fi
}

process_all() {
    log "=== 开始巡检 ==="

    # 获取所有 needs-review 标签的 Issue
    local issues
    issues=$(gh issue list \
        --repo "$REPO" \
        --label "needs-review" \
        --state open \
        --json number \
        --jq '.[].number' 2>/dev/null)

    if [ -z "$issues" ]; then
        log "没有待审核的 Issue"
        return
    fi

    # 逐条处理
    for num in $issues; do
        process_single_issue "$num" || log "  ERROR: Issue #$num 处理失败"
    done

    log "=== 巡检完成 ==="
}

# ======================== 入口 ========================

main() {
    check_deps

    local mode="daemon"
    local interval=300  # 默认 5 分钟

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --once)
                mode="once"
                shift
                ;;
            --interval)
                interval="$2"
                shift 2
                ;;
            *)
                log "未知参数: $1"
                echo "用法: $0 [--once] [--interval SECONDS]"
                exit 1
                ;;
        esac
    done

    if [ "$mode" = "once" ]; then
        process_all
    else
        log "Codex 审核巡检已启动，间隔 ${interval}s"
        while true; do
            process_all
            log "下次巡检: $(date -d "+${interval} seconds" '+%Y-%m-%d %H:%M:%S')"
            sleep "$interval"
        done
    fi
}

main "$@"
