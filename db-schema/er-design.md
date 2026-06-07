# ER 设计说明

## 核心实体关系

```
Character (角色) 1──N Script (剧本)
    │
    └── 一个角色可用于多个剧本

Script (剧本) 1──N ScriptGoal (目标)
    │             │
    │             └── 流程式剧本有多个有序目标
    │
    ├── 1──N ScriptGoalStrategy (行为策略)
    │         └── 每个目标下定义AI对特定行为的应对
    │
    ├── 1──N ScriptFeedback (过程反馈)
    │         └── 对话过程中的实时反馈规则
    │
    ├── 1──N ScriptStandardReply (标准话术)
    │         └── 参考话术（注入Prompt但不直接输出）
    │
    ├── 1──N ScoreDimension (评分维度) 1──N ScoreDetail (考核点)
    │
    └── N──M Plan (培训计划) via PlanScript

Plan (培训计划)
    ├── 1──N PlanStage (阶段)
    ├── 1──N PlanScript (计划-剧本关联，含考试/练习配置)
    └── 1──N PlanUser (参训人员)

PracticeSession (练习会话)
    ├── 关联 Script + Plan + User
    ├── 1──N PracticeDialogue (对话消息)
    └── 1──1 PracticeReport (评分报告)
              └── 1──N PracticeReportDetail (逐项得分)

EvalDataset (评测数据集)
    ├── 1──N EvalTestCase (测试用例)
    └── 1──N EvalExperiment (评测实验)
              └── 1──N EvalResult (评测结果)
```

## 设计要点

### 1. 时间戳统一为毫秒 bigint
所有 `time_created`、`time_updated`、`start_time`、`end_time` 均为 `bigint(20)`，存储 Unix 毫秒时间戳。好处：跨时区无歧义、排序快。

### 2. 软删除
使用 `deleted tinyint(1) default 0`，不物理删除。

### 3. 状态机设计

**Script 状态**: DRAFT → PUBLISHED → ARCHIVED

**Session 状态**: IN_PROGRESS → COMPLETED → SCORING → SCORED

**Experiment 状态**: PENDING → RUNNING → COMPLETED / CANCELLED / FAILED

**Plan 状态**: DRAFT → PUBLISHED → IN_PROGRESS → COMPLETED

### 4. 多租户隔离
`business_id` 字段在所有核心表中都有，支持多业务线数据隔离。

### 5. 审计字段
统一包含 `creator_id`、`time_created`、`updater_id`、`time_updated`。

### 6. JSON 字段使用场景
- `tra_script.forbidden_words`: 违禁词数组
- `tra_script_goal.goal_achievement_condition`: 结构化达成条件
- `tra_practice_dialogue.extra_data`: 润色/灵感结果
- `tra_eval_test_case.input_data`: 测试输入
- `tra_eval_result.judge_scores`: 各维度得分
