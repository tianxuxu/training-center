# LLM 可观测性设计

## 一、三层可观测

```
┌─────────────────────────────────────┐
│ Layer 1: 业务指标 (InfluxDB)         │
│ 对话延迟、评分分布、模型使用量        │
├─────────────────────────────────────┤
│ Layer 2: LLM 调用日志 (MySQL)        │
│ 每次调用的完整输入/输出/耗时/状态     │
├─────────────────────────────────────┤
│ Layer 3: 应用日志 (SLF4J)            │
│ 异常、告警、流程关键节点              │
└─────────────────────────────────────┘
```

## 二、LLM 调用日志详细设计

### 表结构
```sql
CREATE TABLE tra_llm_call_log (
    id, business_id, session_id, script_id, user_id,
    scene,           -- 调用场景（枚举）
    model_type,      -- 使用的模型
    scenario,        -- 场景参数（practice/score/script...）
    system_prompt,   -- 完整 System Prompt
    user_message,    -- 用户消息 / 最后一条消息
    ai_response,     -- LLM 完整输出
    status,          -- SUCCESS / FAILED / TIMEOUT / CONTENT_FILTER
    error_message,   -- 失败原因
    latency_ms,      -- 调用耗时
    input_tokens,    -- 输入 token 数
    output_tokens,   -- 输出 token 数
    temperature,     -- 使用的温度
    max_tokens,      -- max_tokens 设置
    time_created
);
```

### 调用场景枚举
```java
public enum LlmCallLogScene {
    PRACTICE_DIALOGUE,        // 陪练对话
    PRACTICE_GOAL_JUDGE,      // 目标判定
    PRACTICE_POLISH,          // 话术润色
    PRACTICE_INSPIRATION,     // 灵感提示
    PRACTICE_FINISH_CHECK,    // 结束检查
    PRACTICE_SCORING,         // 会话评分
    SCRIPT_CREATE_OPEN,       // 开放剧本生成
    SCRIPT_CREATE_PROCESS,    // 流程剧本生成
    SCORE_GENERATE,           // 评分维度生成
    KNOWLEDGE_QA,             // 知识库问答
    EVAL_EXPERIMENT,          // 评测实验
    EVAL_JUDGE,               // 评测评分
    SCENARIO_POLISH,          // 场景润色
    ROLE_GENERATE,            // 角色生成
    CHARACTER_REFRESH;        // 角色字段刷新
}
```

### ThreadLocal 上下文注入

```java
// 上下文定义
public class LlmCallLogContext {
    private Long sessionId;
    private Long scriptId;
    private String userId;
    private LlmCallLogScene scene;
    private Long businessId;
}

// Holder
public class LlmCallLogContextHolder {
    private static final ThreadLocal<LlmCallLogContext> CONTEXT = new ThreadLocal<>();
    
    public static void set(LlmCallLogContext ctx) { CONTEXT.set(ctx); }
    public static LlmCallLogContext get() { return CONTEXT.get(); }
    public static void clear() { CONTEXT.remove(); }
}

// 业务层使用
public String sendMessage(SendMessageRequest request) {
    try {
        LlmCallLogContextHolder.set(LlmCallLogContext.builder()
            .sessionId(request.getSessionId())
            .scriptId(session.getScriptId())
            .userId(operatorId)
            .scene(LlmCallLogScene.PRACTICE_DIALOGUE)
            .build());
        
        return practiceLLMService.callDialogue(...);
    } finally {
        LlmCallLogContextHolder.clear();
    }
}
```

## 三、InfluxDB 业务监控

```java
@Service
public class TrainingMonitorService extends BaseMonitorService {
    
    /** 记录 LLM 调用延迟 */
    public void recordLlmLatency(String scene, String model, long latencyMs, boolean success) {
        writePoint(MonitorMeasurementName.LLM_CALL)
            .tag("scene", scene)
            .tag("model", model)
            .tag("status", success ? "success" : "failed")
            .field("latency_ms", latencyMs)
            .build();
    }
    
    /** 记录对话轮次 */
    public void recordDialogueRound(Long sessionId, int roundNumber, long latencyMs) {
        writePoint(MonitorMeasurementName.PRACTICE_DIALOGUE)
            .tag("session_id", String.valueOf(sessionId))
            .field("round", roundNumber)
            .field("latency_ms", latencyMs)
            .build();
    }
    
    /** 记录评分结果分布 */
    public void recordScoringResult(Long scriptId, double score, boolean passed) {
        writePoint(MonitorMeasurementName.SCORING_RESULT)
            .tag("script_id", String.valueOf(scriptId))
            .tag("passed", String.valueOf(passed))
            .field("score", score)
            .build();
    }
}
```

### Grafana Dashboard 指标

| 面板 | 指标 | 告警阈值 |
|------|------|---------|
| LLM 调用延迟 P99 | 按 scene/model 分组 | >10s 告警 |
| LLM 调用成功率 | 按 scene 分组 | <95% 告警 |
| 每小时 Token 消耗 | 按 model 分组 | >500K 提醒 |
| 评分平均分趋势 | 按 script 分组 | 连续下降告警 |
| 对话平均轮次 | 全局 | >30 轮异常 |
| 会话完成率 | 完成数/创建数 | <50% 告警 |

## 四、日志规范

```java
// INFO: 业务流程关键节点
log.info("[Practice] sendMessage sessionId={}, round={}, latency={}ms", sessionId, round, latency);
log.info("[Scoring] completed sessionId={}, score={}, passed={}", sessionId, score, passed);

// WARN: 可恢复异常
log.warn("[LLM] JSON parse failed, retrying. scene={}, raw={}", scene, abbreviate(raw, 500));
log.warn("[RAG] retrieval timeout. sessionId={}, latency={}ms", sessionId, latency);

// ERROR: 不可恢复异常
log.error("[LLM] call failed after retry. scene={}, model={}, error={}", scene, model, e.getMessage());
log.error("[Scoring] scoring failed. sessionId={}", sessionId, e);
```

### 日志上下文
通过 MDC 注入 traceId、sessionId：
```java
MDC.put("traceId", UUID.randomUUID().toString().substring(0, 8));
MDC.put("sessionId", String.valueOf(sessionId));
```

## 五、异常通知

```java
@Service
public class AINotifyService {
    /** LLM 调用失败时发送企微告警 */
    public void notifyLlmFailure(String scene, String model, String errorMessage) {
        String msg = String.format("[培训中台] LLM调用失败\n场景: %s\n模型: %s\n错误: %s", 
            scene, model, abbreviate(errorMessage, 200));
        wechatService.sendGroupMessage(alertGroupId, msg);
    }
    
    /** 评分异常时通知 */
    public void notifyScoringFailure(Long sessionId, String reason) {
        // 记录+通知
    }
}
```
