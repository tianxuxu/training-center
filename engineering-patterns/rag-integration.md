# RAG 集成模式

## 一、三场景 RAG 设计

培训中台在 3 个不同场景使用 RAG，各场景的检索策略和使用方式不同：

| 场景 | 目的 | Query 构建 | 结果用途 |
|------|------|-----------|---------|
| DIALOGUE（对话） | AI 扮演角色时参考知识 | 学员最新消息 + 剧本前缀 | 注入 System Prompt 的 `ragReferenceContent` |
| INSPIRATION（灵感） | 给学员推荐话术 | 当前对话上下文摘要 | 作为推荐回复的素材 |
| POLISH（润色） | 优化学员话术 | 学员原始话术 + 目标信息 | 润色时的参考标准 |

## 二、RAG 架构

```
┌──────────────────────────────────────────────────┐
│              RagQueryCommonService                 │
│  (统一入口：路由 + 查询重写 + 结果过滤)            │
├──────────────────────────────────────────────────┤
│ RagServiceRouter    │ RagQueryRewriter  │ RagChunkFilter │
│ (选择 RAG 服务)     │ (改写 query)     │ (过滤/重排)     │
├──────────────────────────────────────────────────┤
│              RAG Gateway (HTTP)                    │
│  /generate (检索+生成) / /retrieval (仅检索)       │
└──────────────────────────────────────────────────┘
```

## 三、核心实现

### RagQueryCommonService

```java
@Service
public class RagQueryCommonService {
    @Autowired private RagServiceRouter router;
    @Autowired private RagQueryRewriter rewriter;
    @Autowired private RagChunkFilter filter;
    @Autowired private TraAiRagGatewayConfig gatewayConfig;
    
    /**
     * 统一 RAG 查询入口
     * @param callType  调用场景 (DIALOGUE / INSPIRATION / POLISH)
     * @param userContent 用户查询内容
     * @param context   上下文（含 scriptId, businessType, interactionMode 等）
     */
    public RagCallOutcome queryByMode(RagCallType callType, String userContent, RagQueryContextVO context) {
        long start = System.currentTimeMillis();
        try {
            // 1. 路由：选择 RAG 服务 ID
            String serviceId = router.route(context.getBusinessType(), context.getInteractionMode());
            
            // 2. 查询重写：添加剧本前缀
            String rewrittenQuery = rewriter.rewrite(userContent, context.getScriptName());
            
            // 3. 调用 RAG Gateway
            RagResponse response = callGateway(serviceId, rewrittenQuery, context);
            
            // 4. 结果过滤/重排
            List<RagChunk> chunks = filter.filter(response.getChunks(), context);
            
            // 5. 组装为纯文本（注入 Prompt）
            String plainText = chunks.stream()
                .map(RagChunk::getContent)
                .collect(Collectors.joining("\n\n"));
            
            return RagCallOutcome.success(plainText, System.currentTimeMillis() - start);
        } catch (Exception e) {
            log.warn("RAG query failed, callType={}, error={}", callType, e.getMessage());
            return RagCallOutcome.failure(System.currentTimeMillis() - start);
        }
    }
}
```

### 路由策略

```java
@Component
public class RagServiceRouter {
    /**
     * 根据业务类型和交互模式选择 RAG 服务
     * - AI_ASK_AGENT_REPLY: AI扮演客户，需要"客户视角"的知识
     * - AGENT_ASK_AI_REPLY: 学员提问，需要"业务员视角"的知识
     */
    public String route(TraBusinessType businessType, QaItemInteractionMode interactionMode) {
        // 不同业务线有不同的知识库
        return String.format("training_%s_%s", 
            businessType.getCode(), 
            interactionMode.getCode());
    }
}
```

### 查询重写

```java
@Component
public class RagQueryRewriter {
    /**
     * 在用户 query 前加上剧本名称作为上下文
     * 例: "怎么还款" → "[催收-首通] 怎么还款"
     */
    public String rewrite(String query, String scriptName) {
        if (StringUtils.isNotBlank(scriptName)) {
            return "[" + scriptName + "] " + query;
        }
        return query;
    }
}
```

## 四、RAG 结果注入 Prompt

在 Prompt 模板中使用 `{{ragReferenceContent}}` 占位符：

```markdown
## RAG 知识参考（可选）
{{ragReferenceContent}}
```

Assembler 中注入：

```java
public String getOpenDialoguePrompt(PracticeDialogueOpenInput input) {
    Map<String, Object> vars = new LinkedHashMap<>();
    // ... 其他变量
    vars.put("ragReferenceContent", 
        StringUtils.defaultIfBlank(input.getRagReferenceContent(), "（无）"));
    return templateLoader.loadAndFill("ai_practice_dialogue_open", vars);
}
```

## 五、RAG 历史记录

每次 RAG 调用都记录到 `tra_rag_history` 表，用于：
1. 调试：看到每轮对话实际检索了什么
2. 质量评估：检索结果相关性分析
3. 数据飞轮：优质检索结果反馈给知识库

```java
// 异步记录
ragComparisonExecutor.submit(() -> {
    TraRagHistoryRecord record = new TraRagHistoryRecord();
    record.setSessionId(sessionId);
    record.setRoundNumber(roundNumber);
    record.setCallType(callType.name());
    record.setQuery(query);
    record.setRagResponse(ragResult);
    record.setLatencyMs(latency);
    ragHistoryModel.insert(record);
});
```

## 六、容错设计

- RAG 查询失败不阻断主流程（对话仍可继续，只是没有知识增强）
- 超时设置独立于 LLM 超时（通常 3-5 秒）
- 空结果时 Prompt 中显示"（无）"，不影响 LLM 输出质量
- 检索结果为空时，后续的灵感/润色使用标准话术兜底

## 七、FAQ 标签增强

```java
@Component
public class RagFaqQuestionTagSupport {
    /**
     * 对 FAQ 类知识，自动将问题标签加入检索 query
     * 提升精确匹配率
     */
    public String enhanceWithTags(String query, List<String> faqTags) {
        if (CollectionUtils.isEmpty(faqTags)) return query;
        return query + " [标签:" + String.join(",", faqTags) + "]";
    }
}
```
