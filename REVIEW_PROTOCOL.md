# 方案评审协议 (Review Protocol)

本仓库是 **Claude Code**（提案方）与 **Codex**（审核方）之间的异步评审通道。
所有非平凡修改必须在此经过多轮博弈，收敛后方可执行。

---

## 一、角色定义

| 角色 | 实体 | 职责 |
|------|------|------|
| **提案方** | Claude Code (本机) | 生成技术方案，回应质疑，修改方案直到通过 |
| **审核方** | Codex (远端) | 审计方案，提出反驳和改进建议，最终给出 PASS/REJECT |

**硬性规则：审核方只负责讨论和审核，绝不编写代码。**

---

## 二、Issue 标签状态机

```
needs-review  →  in-discussion  →  approved  →  implemented
                    ↑                  │
                    └──────────────────┘ (多轮迭代)
                    
rejected (方案被否决，需重新设计)
```

| 标签 | 含义 | 谁来贴 |
|------|------|--------|
| `needs-review` | 等待 Codex 审核 | Claude Code |
| `in-discussion` | 审核中，多轮博弈 | Codex |
| `approved` | 审核通过，可以执行 | Codex |
| `implemented` | 方案已执行完毕 | Claude Code |
| `rejected` | 方案被否决 | Codex |

---

## 三、提案格式 (Claude Code → Codex)

每个 Issue 必须遵循以下结构：

```markdown
---
type: proposal
status: v1
author: Claude Code
date: YYYY-MM-DD
---

## 背景与目标
- 为什么需要这个变更
- 要解决什么问题
- 成功标准是什么

## 技术方案
### 方案 A（推荐）
- 详细描述
- 关键代码路径
- 涉及的文件/模块

### 方案 B（备选）
- 详细描述
- 与方案 A 的对比

## 关键决策与权衡
- 为什么选 A 而不是 B
- 技术债务风险

## 风险点与缓解
| 风险 | 严重度 | 概率 | 缓解措施 |
|------|--------|------|----------|
| ... | 高/中/低 | 高/中/低 | ... |

## 预估工作量
- 预计修改文件数
- 预计耗时
```

---

## 四、评审回复格式 (Codex → Claude Code)

每条评论必须以标签开头：

| 标签 | 含义 |
|------|------|
| `[PASS]` | 该点无问题，通过 |
| `[CONCERN]` | 有疑虑，需要解释或修改 |
| `[REJECT]` | 严重问题，必须否决或大改 |
| `[SUGGEST]` | 改进建议，非强制 |
| `[QUESTION]` | 需要提案方澄清 |

每轮审核评论必须包含：
1. **逐点审计**：对方案的每个部分给出标签
2. **总评**：本轮整体意见（继续/接近通过/否决）
3. **风险等级**：该方案的整体风险（🟢低 / 🟡中 / 🔴高）

---

## 五、收敛规则

### 通过条件
Codex 在 Issue 评论中发出：
```
[PASS] LGTM — 方案审核通过，可以开始执行。
```
然后由 Codex 将 `needs-review` 标签替换为 `approved`。

### 否决条件
Codex 发出：
```
[REJECT] 方案否决 — <具体原因>
```
然后将标签替换为 `rejected`，Claude Code 必须重新设计方案。

### 多轮上限
- 最多进行 **5 轮** 博弈
- 第 5 轮仍未收敛 → 升级为人工决策
- 人工介入方式：在 Issue 中 @ 项目负责人

### 轮次追踪
每轮审核评论标题格式：`## 第 N 轮审核 (Codex)`，N 从 1 开始。

---

## 六、自动化流程

### Claude Code 侧
1. `/proposal <描述>` — 生成方案
2. `/send-review` — 以 Issue 形式提交到本仓库，贴 `needs-review`
3. 提交后进入 **锁定状态**：禁止编辑代码，直到审核通过
4. `/check-review` — 拉取 Codex 审核意见
5. 根据意见修改方案，在 Issue 中回复，回到步骤 2
6. 收到 `[PASS] LGTM` 后，`/approve` 解除锁定，开始执行

### Codex 侧
1. 定时（每 5 分钟）扫描 `needs-review` 标签的 Issue
2. 读取提案内容，进行多维度审计
3. 以标准格式发布审核评论
4. 更新 Issue 标签
5. 收到 Claude Code 回复后进入下一轮审核

---

## 七、审核维度（Codex 检查清单）

Codex 在审核时必须覆盖以下维度：

- [ ] **正确性** — 方案能否达到宣称的效果
- [ ] **简洁性** — 是否过度工程，有无更简单方案
- [ ] **安全性** — 是否引入安全隐患
- [ ] **性能** — 是否引入性能退化
- [ ] **可维护性** — 是否增加不必要的复杂度
- [ ] **一致性** — 是否与项目现有模式一致
- [ ] **完整性** — 是否遗漏边界情况、错误处理
- [ ] **可测试性** — 方案是否便于测试

---

## 八、示例流程

```
Round 1:
  Claude Code: 创建 Issue "认证系统重构方案"
  Codex:      [CONCERN] 方案 A 中 JWT 存储方式不安全
              [SUGGEST] 考虑 HttpOnly Cookie
              → 标签改为 in-discussion

Round 2:
  Claude Code: 回应 CONCERN，更新方案改用 HttpOnly Cookie
  Codex:      [PASS] 安全问题已解决
              [CONCERN] Refresh Token 轮换策略需要明确
              → 标签保持 in-discussion

Round 3:
  Claude Code: 明确 Refresh Token 轮换策略
  Codex:      [PASS] LGTM — 方案审核通过，可以开始执行。
              → 标签改为 approved

Claude Code: 开始代码实现
Claude Code: 实现完成后标签改为 implemented
```
