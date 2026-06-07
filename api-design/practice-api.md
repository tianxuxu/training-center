# 陪练对话 API 设计

## 基础信息
- Base Path: `/admin/training/practiceSession`
- 权限: `@PreAuthorize("hasAnyAuthorityWithBusinessCodePrefix('PRACTISE_MUTATE')")`
- Content-Type: `application/json`
- 时间字段: Unix 毫秒时间戳

## 核心接口

### 1. 创建会话

```
POST /createSession

Request:
{
  "scriptId": 123,           // 必填，剧本ID
  "planId": 456,             // 可选，培训计划ID
  "planScriptId": 789,       // 可选，计划-剧本关联ID
  "sessionType": "PRACTICE", // PRACTICE(练习) / EXAM(考试)
  "practiceLocale": "zh"     // 语言: zh / id
}

Response:
{
  "sessionId": 1001,
  "dialogueMode": "OPEN",   // OPEN / PROCESS
  "firstMessage": {          // AI开场白(如果dialogueInitiator=AI)
    "messageId": 5001,
    "role": "AI",
    "content": "喂，谁啊？",
    "roundNumber": 1
  },
  "totalGoals": 3,           // PROCESS模式下的总目标数
  "currentGoalIndex": 0
}
```

### 2. 发送消息（核心接口）

```
POST /sendMessage

Request:
{
  "sessionId": 1001,
  "content": "您好，我是XX公司的...",
  "messageType": "TEXT"      // TEXT / VOICE_TRANSCRIPTION
}

Response:
{
  "userMessage": {
    "messageId": 5002,
    "role": "STUDENT",
    "content": "您好，我是XX公司的...",
    "roundNumber": 2
  },
  "aiMessage": {
    "messageId": 5003,
    "role": "AI",
    "content": "啥事？我现在很忙。",
    "roundNumber": 2
  },
  "sessionStatus": "IN_PROGRESS",
  "currentGoalIndex": 0,
  "goalJudgeResult": null    // 异步判定，前端轮询
}
```

### 3. 目标判定（PROCESS模式）

```
POST /judgeGoal

Request:
{
  "sessionId": 1001
}

Response:
{
  "achieved": false,
  "failed": false,
  "reasoning": "学员尚未明确报出价格...",
  "summary": "对话继续",
  "sessionShouldEnd": false,
  "goalTransition": null     // 目标切换时有值
}
```

### 4. 话术润色

```
POST /polishMessage

Request:
{
  "sessionId": 1001,
  "messageId": 5002          // 要润色的消息ID
}

Response:
{
  "suggestion": "建议先确认对方身份再自报家门，语气可以更自信",
  "polishedExpression": "您好王先生，我是XX公司信贷部的小李，关于您上个月的账单想跟您确认一下"
}
```

### 5. 灵感提示

```
POST /getInspiration

Request:
{
  "sessionId": 1001
}

Response:
{
  "guidance": "引导确认还款意愿",
  "recommendedReply": "王先生，请问您这边什么时候方便处理一下这笔款项呢？"
}
```

### 6. 停止会话

```
POST /stopSession

Request:
{
  "sessionId": 1001,
  "endReason": "USER_STOP"   // USER_STOP / TIMEOUT
}

Response:
{
  "sessionStatus": "COMPLETED",
  "reportStatus": "SCORING"  // 评分中
}
```

### 7. 查询消息历史

```
GET /getMessages?sessionId=1001

Response:
{
  "messages": [
    {"messageId": 5001, "role": "AI", "content": "喂，谁啊？", "roundNumber": 1, "goalIndex": 0, "timeCreated": 1717000000000},
    {"messageId": 5002, "role": "STUDENT", "content": "...", "roundNumber": 2, "goalIndex": 0, "timeCreated": 1717000005000},
    ...
  ],
  "sessionStatus": "IN_PROGRESS",
  "currentGoalIndex": 1,
  "totalGoals": 3
}
```

### 8. 检查完成

```
POST /checkFinish

Request:
{
  "sessionId": 1001
}

Response:
{
  "finished": true,
  "endReason": "GOAL_COMPLETE",
  "summary": "所有目标已完成"
}
```

## 评分报告接口

Base Path: `/admin/training/practiceReport`

### 查询评分状态
```
GET /getReportStatus?sessionId=1001

Response:
{
  "reportStatus": "SCORED",  // PENDING / SCORING / SCORED / FAILED
  "reportId": 2001
}
```

### 获取报告详情
```
GET /getReportDetail?reportId=2001

Response:
{
  "totalScore": 72.5,
  "totalMaxScore": 100,
  "passed": true,
  "passScore": 60,
  "roundCount": 12,
  "duration": 180000,
  "overallComment": "学员整体表现良好...",
  "forbiddenWordDeduction": 5,
  "dimensions": [
    {
      "dimensionName": "话术专业度",
      "maxScore": 30,
      "actualScore": 24,
      "details": [
        {
          "assessmentPoint": "是否正确报出机构和身份",
          "maxScore": 10,
          "actualScore": 8,
          "comment": "...",
          "strength": "...",
          "improvement": "...",
          "deductionEvidenceQuote": "第3轮: '我是XX的'",
          "deductionReason": "未说明具体部门"
        }
      ]
    }
  ]
}
```

## 设计要点

### 并发控制
- 每个 session 有互斥锁，同一会话不能并发 sendMessage
- 10 秒内相同 content 视为重复请求，返回缓存结果

### 异步模式
- sendMessage 同步返回 AI 回复
- goalJudge 异步执行，前端轮询结果
- 评分在会话结束后异步进行

### WebSocket 推送（可选）
- 目标切换通知: `/user/queue/practice.goalTransition`
- 评分完成通知: `/user/queue/practice.reportReady`
- 实时点评推送: `/user/queue/practice.feedback`
