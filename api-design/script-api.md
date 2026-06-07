# 剧本管理 API 设计

## 核心流程

```
用户输入原始场景描述
    │
    ▼ (AI一键生成)
场景润色 → 问题清单 → 角色生成 → 剧本生成 → 目标生成 → 评分维度生成
    │
    ▼
剧本进入 DRAFT 状态 → 人工审核/编辑 → 发布
```

## API 接口

### 1. AI 一键生成剧本

```
POST /admin/training/script/aiGenerate

Request:
{
  "rawInput": "催收首通电话，客户逾期30天，金额5000元，客户是外卖骑手",
  "dialogueMode": "OPEN",        // OPEN / PROCESS
  "characterId": 101,            // 使用哪个角色
  "businessId": 1
}

Response:
{
  "scriptId": 201,
  "scriptName": "催收首通-外卖骑手逾期30天",
  "scene": "（润色后的场景描述）...",
  "aiIdentity": "逾期30天的外卖骑手，小额借款5000元",
  "traineeIdentity": "催收坐席",
  "dialogueGoal": "...",
  "dialogueIdea": "...",
  "traineeAchievementCondition": "...",
  "goals": [...],               // PROCESS 模式下的分步目标
  "feedbacks": [...],           // 过程反馈规则
  "scoreDimensions": [...],     // 评分维度
  "status": "DRAFT"
}
```

### 2. 剧本 CRUD

```
POST   /admin/training/script/create       手动创建
POST   /admin/training/script/update       更新
POST   /admin/training/script/delete       删除
POST   /admin/training/script/list         分页列表
GET    /admin/training/script/detail       详情
POST   /admin/training/script/publish      发布（DRAFT→PUBLISHED）
POST   /admin/training/script/archive      归档
POST   /admin/training/script/copy         复制
POST   /admin/training/script/export       导出
POST   /admin/training/script/import       导入
```

### 3. 目标管理（PROCESS模式）

```
POST   /admin/training/scriptGoal/create   创建目标
POST   /admin/training/scriptGoal/update   更新目标
POST   /admin/training/scriptGoal/delete   删除目标
POST   /admin/training/scriptGoal/reorder  调整顺序
POST   /admin/training/scriptGoal/aiAppend AI追加目标
```

### 4. 评分维度管理

```
POST   /admin/training/score/generate      AI生成评分维度
POST   /admin/training/score/update        更新维度/考核点
POST   /admin/training/score/list          查询维度列表
```

### 5. 角色管理

```
POST   /admin/training/character/create    创建角色
POST   /admin/training/character/update    更新角色
POST   /admin/training/character/list      角色列表
POST   /admin/training/character/aiRefresh AI刷新角色字段
```

## 剧本数据结构

```json
{
  "scriptId": 201,
  "scriptName": "催收首通-外卖骑手逾期30天",
  "dialogueMode": "PROCESS",
  "character": {
    "name": "张三",
    "gender": "MALE",
    "age": 28,
    "personalityTraits": "脾气急躁，但本质不坏",
    "socialIdentity": "外卖骑手",
    "roleSummary": "...",
    "detailedBackground": "..."
  },
  "scene": "催收首次电话联系...",
  "aiIdentity": "逾期30天的借款人张三",
  "traineeIdentity": "催收坐席",
  "dialogueGoal": "通过电话确认身份，了解还款意愿...",
  "traineeAchievementCondition": "1.成功确认身份 2.了解逾期原因 3.达成还款意向",
  "goals": [
    {
      "goalId": 1,
      "sortOrder": 0,
      "traineeGoal": "确认对方身份",
      "aiGoal": "防备但最终配合确认",
      "roundLimit": 5,
      "achievementCondition": ["学员说出机构名称", "确认对方姓名"],
      "strategies": [
        {"triggerBehavior": "学员直接问身份证号", "aiStrategy": "表现警觉，质问为何需要"}
      ]
    },
    {
      "goalId": 2,
      "sortOrder": 1,
      "traineeGoal": "了解逾期原因并共情",
      "roundLimit": 8
    }
  ],
  "feedbacks": [
    {"triggerBehavior": "学员使用威胁性语言", "promptCopy": "注意话术合规", "feedbackType": "NEGATIVE"},
    {"triggerBehavior": "学员展现同理心", "promptCopy": "沟通方式良好", "feedbackType": "POSITIVE"}
  ],
  "standardReplies": [
    {"aiBehavior": "客户说没钱", "standardReply": "理解您的困难，我们可以协商分期方案..."}
  ],
  "forbiddenWords": ["威胁", "恐吓", "不还就..."],
  "scoreDimensions": [
    {
      "dimensionName": "开场白规范",
      "score": 20,
      "details": [
        {"assessmentPoint": "是否自报家门", "score": 10, "scoringStandard": "明确说出机构名称和个人身份"},
        {"assessmentPoint": "是否说明来电目的", "score": 10}
      ]
    }
  ]
}
```

## Prompt DAG 调试接口

```
POST /admin/training/promptDebug/run

Request:
{
  "startNode": "ai_training_polished_scenario",
  "endNode": "ai_script_create_open",    // null=跑到链路末端
  "inputData": {
    "rawInput": "催收首通...",
    "characterId": 101
  },
  "mockOutputs": {
    "ai_training_polished_scenario": "（手动指定某节点的输出，跳过LLM调用）"
  }
}

Response:
{
  "executionPath": ["ai_training_polished_scenario", "ai_training_question_checklist", "ai_training_role_def", "ai_script_create_open"],
  "nodeResults": [
    {"node": "ai_training_polished_scenario", "output": "...", "latencyMs": 2300},
    {"node": "ai_training_question_checklist", "output": "...", "latencyMs": 1800},
    ...
  ],
  "totalLatencyMs": 8500
}
```
