# LLM 集成层设计

## 一、三层封装架构

```
┌─────────────────────────────────────────┐
│ 业务 LLM Service（场景化）               │
│ PracticeLLMService / ScriptLLMService    │
│ ScoreLLMService / KnowledgeLLMService    │
├─────────────────────────────────────────┤
│ 通用调用服务                              │
│ LangChainChatService（同步）             │
│ LangChainStreamingChatService（流式）    │
├─────────────────────────────────────────┤
│ 模型工厂                                  │
│ ChatModelFactory（实例创建+缓存+路由）    │
│ StreamingChatModelFactory                 │
└─────────────────────────────────────────┘
```

## 二、ChatModelFactory 设计

### 核心职责
- 根据 (scenario, modelType, jsonMode) 创建或复用 ChatModel 实例
- 配置变更时自动失效缓存（指纹比对）

### 缓存键
```java
String cacheKey = scenario + "|" + modelType.getCode() + "|" + jsonMode;
```

### 指纹机制
```java
// 每次 getModel() 时计算当前配置指纹
String currentFingerprint = computeFingerprint(allUrls, allKeys, allVersions, timeout, maxTokens, temperature);
if (!currentFingerprint.equals(lastFingerprint)) {
    modelCache.clear(); // 配置变了，全部失效
    lastFingerprint = currentFingerprint;
}
```

### 模型路由规则
```
模型类型判断：
├── QWEN_COMPATIBLE_MODELS (DeepSeek/Qwen/Kimi) → OpenAiChatModel + /compatible-mode/v1
└── GPT 系列 → AzureOpenAiChatModel

特殊处理：
├── GPT-5 系列 → 用 maxCompletionTokens 而非 max_tokens
├── GPT-5（非5.2/5.4）→ 不设 temperature
└── Qwen3-8B/14B/3.5-35B → 额外传 enable_thinking: false
```

### 配置优先级（5 级降级）
```
1. training.center.llm.scenario.{场景}.model.{模型}.api.url    ← 最高
2. training.center.llm.scenario.{场景}.url
3. training.center.llm.model.{模型}.api.url
4. training.center.llm.api.url
5. 代码内置默认值                                              ← 最低
```

## 三、LangChainChatService 设计

### 两个高阶 API

```java
// 调用 LLM 并反序列化 JSON 结果
<T> T chatForJsonObject(LlmModelType model, String systemPrompt, String userMessage,
    String scenario, TypeReference<T> typeRef, String errorPrefix, boolean jsonMode)

// 调用 LLM 返回原始文本
String chatForText(LlmModelType model, String systemPrompt, String userMessage,
    String scenario, String errorPrefix)
```

### 完整调用管道
```
1. 构建 messages (System + User/AI history)
2. ChatModelFactory.getModel() 获取模型实例
3. model.chat(messages) 执行调用
4. 失败检查（超时/网络/内容过滤）
5. Strip Markdown code block（```json ... ```）
6. JSON 反序列化（多策略）
7. 失败时自动纠错重试
8. 异步记录调用日志
```

### JSON 多策略解析
```java
// 策略 1: 直接解析
T parsed = objectMapper.readValue(json, typeRef);

// 策略 2: 检测到裸逗号分隔的多对象 → 包装为数组
if (json 以 { 开头但目标类型是 List) {
    parsed = objectMapper.readValue("[" + json + "]", typeRef);
}

// 策略 3: Streaming parser 检测重复 key → 拆分为数组
// 处理 LLM 输出 {key1:v, key1:v2} 这种非法JSON
```

### 格式自动纠错
```java
// 条件: rawText 包含 { 或 [，且上下文总长度 < 60K chars
if (shouldRetryFormatCorrection(rawText, messages)) {
    List<ChatMessage> retryMessages = new ArrayList<>(messages);
    retryMessages.add(AiMessage.from(rawText));           // 把错误输出放进去
    retryMessages.add(UserMessage.from(JSON_FORMAT_CORRECTION_PROMPT));  // 纠错指令
    String retryRaw = doChat(model, retryMessages, ...);  // 再调一次
}
```

### 纠错 Prompt
```
你的输出格式不正确，程序无法解析。请严格按以下规则重新输出：
1. 如果要求输出多条数据，必须使用 JSON 数组（以 [ 开头、] 结尾）
2. 不要将多条数据的字段平铺在同一个 JSON 对象中
3. 只输出纯 JSON，不要包含解释文字或 markdown 代码块标记
```

### 内容过滤检测
```java
// 统一识别不同供应商的内容过滤标识
boolean isContentFilter(String text) {
    return text.contains("content_filter") 
        || text.contains("content management policy")
        || text.contains("responsible_ai_policy_violation")
        || text.contains("safety system");
}
```

## 四、流式服务设计

```java
public void chatForTextStream(LlmModelType model, String systemPrompt, String userMessage,
    String scenario, String errorPrefix, Consumer<String> partialConsumer) {
    
    CountDownLatch latch = new CountDownLatch(1);
    AtomicReference<Throwable> error = new AtomicReference<>();
    
    streamingModel.chat(messages, new StreamingChatResponseHandler() {
        void onPartialResponse(String partial) {
            partialConsumer.accept(partial);  // 实时推给调用方
        }
        void onComplete() { latch.countDown(); }
        void onError(Throwable t) { error.set(t); latch.countDown(); }
    });
    
    latch.await(timeout + 5, TimeUnit.SECONDS);  // 超时保护
}
```

## 五、模型类型枚举设计

```java
public enum LlmModelType implements ICodeDescEnum<String> {
    GPT_5_4("gpt-5.4", "GPT 5.4", "gpt54"),
    GPT_5_2("gpt-5.2", "GPT 5.2", "gpt52"),
    GPT_5("gpt-5", "GPT 5", "gpt5"),
    DEEPSEEK_V3("deepseek-v3", "DeepSeek V3", "deepseekv3"),
    DEEPSEEK_V3_1("deepseek-v3-1", "DeepSeek V3.1", "deepseekv3_1"),
    DEEPSEEK_V3_2("deepseek-v3-2", "DeepSeek V3.2", "deepseekv3_2"),
    QWEN3_NEXT_80B("qwen3-next-80b", "Qwen3 Next 80B", "qwen3next80b"),
    QWEN3_5_35B("qwen3.5-35b", "Qwen3.5 35B", "qwen35_35b"),
    QWEN3_MAX("qwen-max", "Qwen Max", "qwenmax"),
    QWEN3_8B("qwen3-8b", "Qwen3 8B", "qwen3_8b"),
    QWEN3_14B("qwen3-14b", "Qwen3 14B", "qwen3_14b"),
    QWEN2_5_72B("qwen2.5-72b-instruct", "Qwen2.5 72B", "qwen25_72b"),
    KIMI_K2("kimi-k2.5-0711", "Kimi K2.5", "kimik2");
    
    private final String code;      // API 调用时的 model 字段
    private final String desc;      // 显示名
    private final String configKey; // 配置中心 key 前缀
}
```

## 六、场景化 LLM Service 设计模式

每个业务场景一个 LLMService，职责：
1. 构建 Input VO（收集业务数据）
2. 调用 PromptAssembler（模板 + 变量注入）
3. 调用 LangChainChatService（执行 LLM 调用）
4. 解析结果为业务 VO

```java
@Component
public class PracticeLLMService {
    @Autowired private LangChainChatService langChainChatService;
    @Autowired private PracticePromptAssembler promptAssembler;
    
    public String callOpenDialogue(TraScriptRecord script, TraCharacterRecord character,
            List<TraPracticeDialogueRecord> dialogues, String studentMessage, String ragContent) {
        // 1. 组装 Prompt
        PracticeDialogueOpenInput input = buildInput(script, character, dialogues, studentMessage, ragContent);
        String systemPrompt = promptAssembler.getOpenDialoguePrompt(input);
        
        // 2. 构建 messages (system + 历史对话 + 当前消息)
        List<ChatMessage> messages = buildChatMessages(systemPrompt, dialogues, studentMessage);
        
        // 3. 调用 LLM
        return langChainChatService.chatForText(
            LlmModelConfig.getDefaultLlmModel(), messages, "practice", "练习失败：");
    }
}
```
