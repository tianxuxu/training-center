# 容错与重试设计

## 一、LLM 调用容错层次

```
Level 0: 正常返回
Level 1: JSON格式错误 → 格式纠错重试（自动）
Level 2: 内容过滤 → 检测+告警+抛业务异常
Level 3: 超时 → 切换备用模型（可配置）
Level 4: 网络错误 → 抛异常+告警
```

## 二、格式纠错重试

### 触发条件
```java
private boolean shouldRetryFormatCorrection(String rawText, List<ChatMessage> messages) {
    // 条件1: 输出看起来像 JSON（包含 { 或 [）
    boolean looksLikeJson = rawText.contains("{") || rawText.contains("[");
    // 条件2: 上下文不超长（避免超出 context window）
    int totalChars = messages.stream().mapToInt(m -> m.text().length()).sum();
    boolean contextNotTooLarge = totalChars < 60_000;
    return looksLikeJson && contextNotTooLarge;
}
```

### 纠错策略
```java
// 把错误输出放回消息列表，让 LLM 看到自己的错误并修正
List<ChatMessage> retryMessages = new ArrayList<>(originalMessages);
retryMessages.add(AiMessage.from(rawText));  // "你刚才输出了这个"
retryMessages.add(UserMessage.from(JSON_FORMAT_CORRECTION_PROMPT));  // "格式不对，重新来"
```

## 三、内容过滤统一检测

```java
private boolean isContentFiltered(String text) {
    if (text == null) return false;
    // 不同供应商的内容过滤标识
    return text.contains("content_filter")
        || text.contains("content management policy")
        || text.contains("responsible_ai_policy_violation")
        || text.contains("safety system")
        || text.contains("I cannot assist");
}
```

## 四、对话服务并发控制

### Session 级互斥
```java
// 每个 session 一个锁对象，防止同一会话并发 sendMessage
private final ConcurrentHashMap<Long, Object> sessionLocks = new ConcurrentHashMap<>();

public SendMessageResponse sendMessage(SendMessageRequest request) {
    Object lock = sessionLocks.computeIfAbsent(request.getSessionId(), k -> new Object());
    synchronized (lock) {
        return doSendMessage(request);
    }
}
```

### 幂等（内容去重）
```java
// 10秒内相同内容视为重复请求
private final Cache<String, SendMessageResponse> deduplicationCache = 
    Caffeine.newBuilder().expireAfterWrite(10, TimeUnit.SECONDS).build();

private SendMessageResponse doSendMessage(SendMessageRequest request) {
    String deduplicationKey = request.getSessionId() + "|" + request.getContent();
    SendMessageResponse cached = deduplicationCache.getIfPresent(deduplicationKey);
    if (cached != null) return cached; // 幂等返回
    
    SendMessageResponse response = actualSendMessage(request);
    deduplicationCache.put(deduplicationKey, response);
    return response;
}
```

## 五、异步操作失败处理

### 评分失败重试
```java
public void scoreSessionAsync(Long sessionId) {
    CompletableFuture.runAsync(() -> {
        try {
            doScoring(sessionId);
            updateReportStatus(sessionId, "SCORED");
        } catch (Exception e) {
            log.error("[Scoring] failed, sessionId={}", sessionId, e);
            updateReportStatus(sessionId, "FAILED");
            // 用户可手动重试
        }
    }, scoringExecutor);
}

// 手动重试接口
public void retryScoring(Long sessionId) {
    updateReportStatus(sessionId, "SCORING");
    scoreSessionAsync(sessionId);
}
```

### 异步任务线程池
```java
// 不同场景独立线程池，避免互相阻塞
private final ExecutorService polishExecutor = 
    new ThreadPoolExecutor(2, 4, 60, TimeUnit.SECONDS, new LinkedBlockingQueue<>(100));

private final ExecutorService ragComparisonExecutor = 
    new ThreadPoolExecutor(2, 4, 60, TimeUnit.SECONDS, new LinkedBlockingQueue<>(100));

private final ExecutorService scoringExecutor = 
    new ThreadPoolExecutor(2, 8, 60, TimeUnit.SECONDS, new LinkedBlockingQueue<>(50));

@PreDestroy
public void shutdown() {
    polishExecutor.shutdown();
    ragComparisonExecutor.shutdown();
    scoringExecutor.shutdown();
}
```

## 六、RAG 容错

```java
public RagCallOutcome queryByMode(RagCallType callType, String query, RagQueryContextVO context) {
    try {
        // RAG 查询...
        return RagCallOutcome.success(result, latency);
    } catch (Exception e) {
        // RAG 失败不阻断主流程！
        log.warn("[RAG] query failed, callType={}, error={}", callType, e.getMessage());
        return RagCallOutcome.failure(System.currentTimeMillis() - start);
        // 后续逻辑：ragContent 为空 → Prompt 中 {{ragReferenceContent}} = "（无）"
        // AI 对话仍可正常进行，只是缺少知识增强
    }
}
```

## 七、目标判定容错

### 轮次超限保护
```java
public GoalJudgeResult judgeGoal(Long sessionId) {
    int currentRounds = getCurrentGoalRounds(sessionId);
    int roundLimit = currentGoal.getDialogueRoundsSetting();
    
    if (currentRounds >= roundLimit) {
        // 给 LLM 最后一次机会判定
        GoalJudgeResultVO result = practiceLLMService.callGoalJudge(...);
        if (!result.isAchieved()) {
            // 超限强制失败
            return GoalJudgeResult.forceFailed("轮次超限");
        }
    }
    // 正常判定...
}
```

### 判定结果一致性保护
```java
// achieved 和 failed 不能同时为 true
if (result.isAchieved() && result.isFailed()) {
    log.warn("[GoalJudge] contradictory result, treating as not achieved");
    result.setAchieved(false);
    result.setFailed(false);
}
```

## 八、评测实验协作取消

```java
private final ConcurrentHashMap<Long, AtomicBoolean> cancelFlags = new ConcurrentHashMap<>();

public void executeExperiment(Long experimentId) {
    cancelFlags.put(experimentId, new AtomicBoolean(false));
    try {
        for (EvalTestCase testCase : testCases) {
            if (cancelFlags.get(experimentId).get()) {
                updateStatus(experimentId, "CANCELLED");
                return;
            }
            // 执行评测...
        }
    } finally {
        cancelFlags.remove(experimentId);
    }
}

public void cancelExperiment(Long experimentId) {
    AtomicBoolean flag = cancelFlags.get(experimentId);
    if (flag != null) flag.set(true);
}
```

## 九、TTS 语音容错

```java
// 语音合成失败时降级为纯文本
public DialogueResponse buildResponse(String aiText, boolean voiceEnabled) {
    DialogueResponse response = new DialogueResponse(aiText);
    if (voiceEnabled && ttsService != null) {
        try {
            byte[] audio = ttsService.synthesize(aiText);
            response.setAudioBase64(Base64.encode(audio));
        } catch (Exception e) {
            log.warn("[TTS] synthesis failed, fallback to text only", e);
            // 不抛异常，只是没有语音
        }
    }
    return response;
}
```
