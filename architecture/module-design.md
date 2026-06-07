# 模块设计与职责划分

## 一、DDD 四层架构

```
┌────────────────────────────────────────────────┐
│ Controller / Job / API 层                       │
│ 参数校验、权限、响应封装，禁止业务逻辑           │
├────────────────────────────────────────────────┤
│ 业务 Service 层                                 │
│ 组合 CommonService 完成业务流程编排              │
├────────────────────────────────────────────────┤
│ CommonService 层                                │
│ 可复用领域操作，不含业务编排                     │
├────────────────────────────────────────────────┤
│ Model 层                                        │
│ 一表一 Model，纯 CRUD 和基础查询                │
└────────────────────────────────────────────────┘
```

严格单向依赖，禁止反向引用和跨层调用。

## 二、核心模块职责

### training-center-admin（接入层）

| 包 | 职责 |
|---|------|
| controller/practice | 陪练对话 CRUD + 消息收发 |
| controller/script | 剧本管理 CRUD |
| controller/eval | 评测中心 CRUD + 执行 |
| controller/scenario | 培训场景管理 |
| controller/plan | 培训计划管理 |
| controller/knowledge | 知识库管理 |
| controller/llm | LLM 调试接口（dev） |
| websocket | STOMP WS + Voice WS |

### training-center-core（核心业务）

| 包 | 职责 |
|---|------|
| service/ai | LLM 调用封装（ChatService, Factory, LLMServices） |
| service/practice | 陪练对话、目标判定、评分、报告 |
| service/script | 剧本创建、编辑、复制、导入导出 |
| service/eval | 评测实验、数据集、Judge |
| service/rag | RAG 检索、路由、过滤 |
| service/prompt | Prompt 模板管理、Assembler |
| service/score | 评分维度管理 |
| service/hotword | 热词管理（NLS） |
| service/notify | 各渠道通知（企微/AI/OMS） |
| service/monitor | InfluxDB 监控打点 |
| model/sql | JOOQ DAO（一表一 Model） |
| model/generated | JOOQ 代码生成（Record/Table） |
| config | 配置类（DynamicProperties 封装） |
| enums | 枚举定义（50+ 枚举） |
| utils | 工具类 |
| dts | DTS binlog 处理 |

## 三、关键 Service 关系图

```
PracticeDialogueService（编排层）
    ├── PracticeLLMService（AI层） ──→ LangChainChatService ──→ ChatModelFactory
    ├── PracticeGoalJudgeService     ──→ PracticeLLMService
    ├── PracticePromptFormatService  ──→ PracticePromptAssembler
    ├── RagQueryCommonService        ──→ RAG Gateway (HTTP)
    ├── PracticeSessionService       ──→ TraPracticeSessionModel (DAO)
    ├── PracticeReportService        ──→ ScoreLLMService
    └── PracticeVoiceTtsService      ──→ NLS SDK (TTS)
```

## 四、跨模块通信

| 通信方式 | 场景 |
|---------|------|
| Kafka | DTS binlog → 知识库同步、权限同步 |
| Redis Pub/Sub | WebSocket 多实例消息广播 |
| Feign RPC | 其他业务系统调用培训中台 |
| HTTP | RAG Gateway、LLM Gateway |
| WebSocket | 实时对话推送、语音流 |

## 五、配置管理设计

所有配置通过 `DynamicProperties`（配置中心 SDK）管理，禁止 `@Value`：

```java
public class LlmModelConfig {
    // 五级优先级降级
    public static String getLlmApiUrl(LlmModelType modelType, String scenario) {
        // 1. scenario + model 级
        // 2. scenario 级
        // 3. model 级
        // 4. 全局级
        // 5. 代码内置
    }
    
    // 按场景读取推理参数
    public static Integer getLlmMaxTokens(String scenario) { ... }
    public static Double getLlmTemperature(String scenario) { ... }
}
```

配置命名规范：`training.center.{module}.{item}`
