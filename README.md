# AI 培训中台 - 能力复制手册

> 本仓库提取自企业级 AI 培训中台项目（Spring Boot + LangChain4j + JDK 21），包含完整的设计要素、Prompt 模板、数据库 Schema、API 设计和工程模式。
> 
> **目标**：拿到新机会时，基于本手册可在 1-2 周内搭建出同等水平的企业级 LLM Application。

## 项目定位

一个 **LLM-driven 的智能培训平台**，用 DAG 编排多步 Prompt 实现：
- AI 剧本自动生成（场景 → 角色 → 对话目标 → 评分维度）
- AI 陪练对话（角色扮演 + RAG 知识增强 + 实时反馈）
- 自动评分（LLM-as-Judge + 多维度 + 锚定校准）
- 评测中心（Dataset + Experiment + A/B Compare）

## 目录结构

```
├── README.md                    # 本文件
├── architecture/                # 整体架构设计
│   ├── system-overview.md       # 系统全景图
│   ├── module-design.md         # 模块划分与职责
│   ├── llm-integration.md      # LLM 集成层设计
│   └── dag-orchestration.md    # Prompt DAG 编排设计
├── prompts/                     # 核心 Prompt 模板（可直接复用）
│   ├── README.md               # Prompt 设计规范
│   ├── ai_practice_dialogue_open.md
│   ├── ai_practice_dialogue_process.md
│   ├── ai_practice_scoring.md
│   ├── ai_practice_goal_judge.md
│   ├── ai_practice_polish.md
│   ├── ai_practice_inspiration.md
│   └── ai_script_create_open.md
├── db-schema/                   # 数据库设计
│   ├── core-tables.sql         # 核心表结构
│   └── er-design.md            # ER 设计说明
├── api-design/                  # API 接口设计
│   ├── practice-api.md         # 陪练对话 API
│   ├── script-api.md           # 剧本管理 API
│   └── eval-api.md             # 评测中心 API
├── engineering-patterns/        # 工程模式（可迁移）
│   ├── llm-call-wrapper.md     # LLM 调用封装模式
│   ├── streaming-websocket.md  # 流式 + WebSocket 设计
│   ├── rag-integration.md      # RAG 集成模式
│   ├── observability.md        # LLM 可观测性
│   └── resilience.md           # 容错与重试
└── eval-system/                 # 评测系统设计
    ├── eval-architecture.md    # 评测中心架构
    └── llm-as-judge.md         # LLM-as-Judge 实现
```

## 技术栈

| 层面 | 技术选型 |
|------|---------|
| 语言/框架 | Java 21 + Spring Boot 2.7 |
| LLM 框架 | LangChain4j 1.12.2 |
| ORM | JOOQ 3.18.7（类型安全 SQL） |
| DB 迁移 | Flyway 9.22.3 |
| 数据库 | MySQL 8.0 + MongoDB + Redis + ElasticSearch |
| 消息队列 | Kafka |
| 语音 | Alibaba NLS SDK（ASR/TTS） |
| 实时通信 | STOMP WebSocket + Redis Pub/Sub |
| 模型支持 | GPT-5.x / DeepSeek-V3.x / Qwen3.x / Kimi-K2 |

## 快速复用路径

1. 先看 `architecture/system-overview.md` 理解全局
2. 复制 `db-schema/core-tables.sql` 建表
3. 实现 `engineering-patterns/llm-call-wrapper.md` 中的 LLM 调用层
4. 复制 `prompts/` 下的模板，按业务场景微调
5. 参照 `api-design/practice-api.md` 实现接口
6. 用 `eval-system/` 建设评测能力
