# 系统全景架构

## 一、业务全流程（7 步 AI 链路）

```
① 场景润色 → ② 问题清单 → ③ 角色生成 → ④ 剧本生成 → ⑤ 目标生成 → ⑥ 评分细则生成 → ⑦ 陪练对话 → ⑧ 练习评分
```

每一步都是一次或多次 LLM 调用，步与步之间形成 DAG 依赖关系。

## 二、系统分层架构

```
┌─────────────────────────────────────────────────────────────┐
│                    接入层 (Admin / API / WS)                  │
│  HTTP REST + STOMP WebSocket + Native WebSocket(Voice)       │
├─────────────────────────────────────────────────────────────┤
│                    业务编排层 (Service)                        │
│  PracticeDialogueService / ScriptCreateService / EvalService │
├─────────────────────────────────────────────────────────────┤
│                    AI 调用层                                   │
│  LangChainChatService ← ChatModelFactory                     │
│  PracticeLLMService / ScriptLLMService / ScoreLLMService     │
│  LangChainStreamingChatService                               │
├─────────────────────────────────────────────────────────────┤
│                    Prompt 工程层                               │
│  PromptAssembler (模板加载+变量注入)                           │
│  PromptDagNode (DAG 拓扑排序执行)                             │
│  34 个 .md Prompt 模板文件                                    │
├─────────────────────────────────────────────────────────────┤
│                    数据与外部服务层                             │
│  JOOQ DAO / MongoDB / Redis / ES / RAG Gateway / Kafka       │
├─────────────────────────────────────────────────────────────┤
│                    基础设施层                                  │
│  配置中心(DynamicProperties) / 监控(InfluxDB) / 日志(LlmCallLog) │
└─────────────────────────────────────────────────────────────┘
```

## 三、多模块划分

```
training-center-admin     → HTTP REST 控制器（主应用）
training-center-api       → 内部 RPC 接口
training-center-scheduler → 定时任务（批量刷新、统计）
training-center-consumer  → Kafka 消息消费（DTS binlog、事件处理）
training-center-core      → 核心业务逻辑（AI 服务、DAO、Prompt 模板）
training-center-common    → 通用工具（异常码、枚举、工具类）
training-center-client    → Feign RPC 客户端
```

## 四、AI 调用流转图（以陪练对话为例）

```
用户发送消息
    │
    ▼
PracticeDialogueService.sendMessage()
    │
    ├─── [并行] RAG 检索 (RagQueryCommonService)
    │         └── RAG Gateway HTTP → 返回 top-K 知识片段
    │
    ├─── PracticePromptAssembler 组装 Prompt
    │         └── 加载 .md 模板 + 注入变量(角色/对话历史/RAG结果)
    │
    ├─── PracticeLLMService.callOpenDialogue()
    │         └── LangChainChatService.chatForText()
    │               └── ChatModelFactory.getModel() → 选择模型实例
    │               └── ChatModel.chat(messages) → 调用 LLM
    │               └── 记录日志 (LlmCallLogRecordingService)
    │
    ├─── [异步] 目标判定 (PracticeGoalJudgeService)
    │         └── 独立 LLM 调用判断 achieved/failed
    │
    ├─── [异步] 话术润色 (auto-polish)
    │
    └─── 返回 AI 回复给用户
```

## 五、关键设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| LLM 框架 | LangChain4j（仅用 ChatModel 层） | 只需轻量消息抽象，不用 Agent/Chain 模块 |
| Prompt 管理 | 文件模板 + Assembler | 迭代快、支持 DAG 编排 |
| 对话 vs 判定 | 分离为两个独立 LLM 调用 | 避免 AI 自评偏差 |
| 多模型支持 | ChatModelFactory 统一管理 | 按场景路由不同模型 |
| 配置热加载 | 指纹对比 + 缓存失效 | 配置中心改参数即时生效 |
| 可观测性 | 每次 LLM 调用异步记录 | 全量日志用于回放和调试 |
| JSON 解析 | 多策略 + 格式自动纠错 | 对抗 LLM 输出不稳定 |
| RAG | 按场景分路由 | 对话/灵感/润色各有不同检索策略 |
