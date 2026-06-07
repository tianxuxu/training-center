# LLM 调用封装模式

## 核心思想

将 LLM 调用的复杂性（模型选择、JSON 解析、重试、日志）封装为一个统一的 Service，业务层只需关心"传什么、期望得到什么"。

## 完整实现模板

### 1. ChatModelFactory（模型工厂）

```java
@Component
public class ChatModelFactory {
    // 缓存：scenario|modelCode|jsonMode → ChatModel 实例
    private final ConcurrentHashMap<String, ChatModel> modelCache = new ConcurrentHashMap<>();
    private volatile String configFingerprint = "";
    
    public ChatModel getModel(LlmModelType modelType, String scenario, boolean jsonMode) {
        // 1. 配置指纹检测（变更时清空缓存）
        String currentFp = computeFingerprint();
        if (!currentFp.equals(configFingerprint)) {
            modelCache.clear();
            configFingerprint = currentFp;
        }
        
        // 2. 缓存命中
        String key = scenario + "|" + modelType.getCode() + "|" + jsonMode;
        return modelCache.computeIfAbsent(key, k -> buildModel(modelType, scenario, jsonMode));
    }
    
    private ChatModel buildModel(LlmModelType model, String scenario, boolean jsonMode) {
        String apiUrl = LlmModelConfig.getLlmApiUrl(model, scenario);
        String apiKey = LlmModelConfig.getLlmApiKey(model, scenario);
        int timeout = LlmModelConfig.getLlmTimeoutSeconds();
        Integer maxTokens = LlmModelConfig.getLlmMaxTokens(scenario);
        Double temperature = LlmModelConfig.getLlmTemperature(scenario);
        
        if (isQwenCompatible(model)) {
            // Qwen/DeepSeek/Kimi 走 OpenAI 兼容接口
            return OpenAiChatModel.builder()
                .baseUrl(apiUrl + "/compatible-mode/v1")
                .apiKey(apiKey)
                .modelName(model.getCode())
                .maxTokens(maxTokens)
                .temperature(temperature)
                .timeout(Duration.ofSeconds(timeout))
                .responseFormat(jsonMode ? "json_object" : null)
                .build();
        } else {
            // GPT 走 Azure OpenAI
            return AzureOpenAiChatModel.builder()
                .endpoint(apiUrl)
                .apiKey(apiKey)
                .apiVersion(LlmModelConfig.getLlmApiVersion(model))
                .deploymentName(model.getCode())
                .maxCompletionTokens(maxTokens) // GPT-5 专用
                .timeout(Duration.ofSeconds(timeout))
                .responseFormat(jsonMode ? "json_object" : null)
                .build();
        }
    }
}
```

### 2. LangChainChatService（统一调用+解析）

```java
@Component
public class LangChainChatService {
    @Autowired private ChatModelFactory chatModelFactory;
    @Autowired private LlmCallLogRecordingService logService;
    
    // ========== 高阶 API ==========
    
    /** 调用 LLM 并反序列化 JSON 结果 */
    public <T> T chatForJsonObject(LlmModelType model, String systemPrompt, 
            String userMessage, String scenario, TypeReference<T> typeRef, String errorPrefix) {
        List<ChatMessage> messages = buildMessages(systemPrompt, userMessage);
        String rawText = doChat(model, messages, scenario, errorPrefix, true);
        if (rawText == null) return null;
        
        // 多策略 JSON 解析
        String json = stripMarkdownCodeBlock(rawText);
        T parsed = tryParseJson(json, typeRef);
        if (parsed != null) return parsed;
        
        // 格式纠错重试
        if (shouldRetry(rawText, messages)) {
            T retryResult = retryWithCorrection(model, messages, rawText, scenario, typeRef, errorPrefix);
            if (retryResult != null) return retryResult;
        }
        
        throw new TrainingException(LLM_PARSE_ERROR, errorPrefix + "JSON解析失败");
    }
    
    /** 调用 LLM 返回纯文本 */
    public String chatForText(LlmModelType model, String systemPrompt, 
            String userMessage, String scenario, String errorPrefix) {
        List<ChatMessage> messages = buildMessages(systemPrompt, userMessage);
        return doChat(model, messages, scenario, errorPrefix, false);
    }
    
    // ========== 内部实现 ==========
    
    private String doChat(LlmModelType model, List<ChatMessage> messages, 
            String scenario, String errorPrefix, boolean jsonMode) {
        long start = System.currentTimeMillis();
        try {
            ChatModel chatModel = chatModelFactory.getModel(model, scenario, jsonMode);
            ChatResponse response = chatModel.chat(messages);
            String text = response.aiMessage().text();
            
            // 内容过滤检测
            if (isContentFiltered(text)) {
                throw new TrainingException(CONTENT_FILTER, errorPrefix + "内容被过滤");
            }
            
            // 异步记录日志
            logService.recordAsync(model, scenario, messages, text, System.currentTimeMillis() - start);
            return StringUtils.isBlank(text) ? null : text;
            
        } catch (SocketTimeoutException | TimeoutException e) {
            logService.recordFailureAsync(model, scenario, "TIMEOUT", e.getMessage());
            throw new TrainingException(LLM_TIMEOUT, errorPrefix + "调用超时");
        } catch (Exception e) {
            if (Thread.currentThread().isInterrupted()) throw e; // 保留中断语义
            logService.recordFailureAsync(model, scenario, "ERROR", e.getMessage());
            throw new TrainingException(LLM_ERROR, errorPrefix + "调用失败: " + e.getMessage());
        }
    }
    
    /** Strip markdown ```json ... ``` 包裹 */
    private String stripMarkdownCodeBlock(String text) {
        Matcher m = Pattern.compile("```(?:json)?\\s*([\\s\\S]*?)```").matcher(text);
        return m.find() ? m.group(1).trim() : text.trim();
    }
    
    /** 格式纠错重试 */
    private <T> T retryWithCorrection(LlmModelType model, List<ChatMessage> original,
            String rawText, String scenario, TypeReference<T> typeRef, String errorPrefix) {
        List<ChatMessage> retryMessages = new ArrayList<>(original);
        retryMessages.add(AiMessage.from(rawText));
        retryMessages.add(UserMessage.from(
            "你的输出格式不正确。请严格按JSON格式重新输出，不要包含markdown标记。"));
        
        String retryRaw = doChat(model, retryMessages, scenario, errorPrefix, true);
        if (retryRaw != null) {
            return tryParseJson(stripMarkdownCodeBlock(retryRaw), typeRef);
        }
        return null;
    }
    
    private boolean shouldRetry(String rawText, List<ChatMessage> messages) {
        // 只有输出看起来像 JSON 且上下文不超长时才重试
        boolean looksLikeJson = rawText.contains("{") || rawText.contains("[");
        int contextSize = messages.stream().mapToInt(m -> m.text().length()).sum();
        return looksLikeJson && contextSize < 60000;
    }
}
```

### 3. LlmCallLogRecordingService（异步日志）

```java
@Component
public class LlmCallLogRecordingService {
    private final ExecutorService logExecutor = Executors.newFixedThreadPool(2, 
        r -> { Thread t = new Thread(r, "llm-log"); t.setDaemon(true); return t; });
    
    @Autowired private TraLlmCallLogModel logModel;
    
    public void recordAsync(LlmModelType model, String scenario, 
            List<ChatMessage> messages, String response, long latencyMs) {
        logExecutor.submit(() -> {
            TraLlmCallLogRecord record = new TraLlmCallLogRecord();
            record.setModelType(model.getCode());
            record.setScenario(scenario);
            record.setSystemPrompt(extractSystemPrompt(messages));
            record.setUserMessage(extractUserMessage(messages));
            record.setAiResponse(StringUtils.abbreviate(response, 10000));
            record.setStatus("SUCCESS");
            record.setLatencyMs(latencyMs);
            record.setTimeCreated(System.currentTimeMillis());
            // 注入业务上下文
            LlmCallLogContext ctx = LlmCallLogContextHolder.get();
            if (ctx != null) {
                record.setSessionId(ctx.getSessionId());
                record.setScriptId(ctx.getScriptId());
                record.setUserId(ctx.getUserId());
                record.setScene(ctx.getScene().getCode());
            }
            logModel.insert(record);
        });
    }
}
```

### 4. 业务 LLM Service 示例

```java
@Component
public class PracticeLLMService {
    @Autowired private LangChainChatService chatService;
    @Autowired private PracticePromptAssembler assembler;
    
    /** 开放式对话 */
    public String callOpenDialogue(TraScriptRecord script, TraCharacterRecord character,
            List<TraPracticeDialogueRecord> dialogues, String studentMessage, String ragContent) {
        // 1. 组装 SystemPrompt
        String systemPrompt = assembler.getOpenDialoguePrompt(
            PracticeDialogueOpenInput.builder()
                .roleName(character.getName())
                .roleAge(String.valueOf(character.getAge()))
                .personalityTraits(character.getPersonalityTraits())
                .aiIdentity(script.getAiIdentity())
                .sceneDescription(script.getScene())
                .ragReferenceContent(ragContent)
                // ... 20+ 变量
                .build());
        
        // 2. 构建多轮消息（System + 历史对话交替 + 当前消息）
        List<ChatMessage> messages = new ArrayList<>();
        messages.add(SystemMessage.from(systemPrompt));
        for (TraPracticeDialogueRecord d : dialogues) {
            if ("STUDENT".equals(d.getRole())) {
                messages.add(UserMessage.from(d.getContent()));
            } else {
                messages.add(AiMessage.from(d.getContent()));
            }
        }
        messages.add(UserMessage.from(studentMessage));
        
        // 3. 调用
        return chatService.chatForText(
            LlmModelConfig.getDefaultLlmModel(), messages, "practice", "练习失败：");
    }
    
    /** 目标判定（返回结构化结果） */
    public GoalJudgeResultVO callGoalJudge(String goalDetail, String recentDialogue) {
        String systemPrompt = assembler.getGoalJudgePrompt(goalDetail, recentDialogue);
        return chatService.chatForJsonObject(
            LlmModelConfig.getDefaultLlmModel(),
            systemPrompt, null, "practice",
            new TypeReference<GoalJudgeResultVO>() {},
            "目标判定失败：");
    }
}
```

## 关键设计点总结

| 模式 | 解决的问题 |
|------|-----------|
| 配置指纹缓存失效 | 配置热更新生效而不重启 |
| 多策略 JSON 解析 | 对抗 LLM 输出不稳定 |
| 格式纠错重试 | 格式错误自动修复（减少人工介入） |
| 异步日志 | 不阻塞主请求路径 |
| ThreadLocal 上下文 | 业务信息透传到日志层 |
| 内容过滤统一检测 | 多供应商兼容 |
| 场景化配置 | 不同场景用不同参数（温度/token数/模型） |
