# 流式 + WebSocket 实时通信设计

## 一、整体架构

```
┌─────────┐    STOMP WS     ┌──────────────┐   Redis Pub/Sub   ┌──────────────┐
│  前端    │ ◄──────────────► │   Admin 实例1 │ ◄────────────────► │   Admin 实例2 │
│ (SockJS) │                 │  (WebSocket)  │                   │  (WebSocket)  │
└─────────┘                  └──────────────┘                   └──────────────┘
     │                              │
     │  Native WS                   │ LangChain4j Streaming
     │  (Voice)                     ▼
     │                       ┌──────────────┐
     └──────────────────────►│  NLS SDK     │
                             │  (ASR/TTS)   │
                             └──────────────┘
```

## 二、STOMP WebSocket 配置

```java
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig extends AbstractSecurityWebSocketMessageBrokerConfigurer {
    
    @Override
    public void configureMessageBroker(MessageBrokerRegistry config) {
        config.enableSimpleBroker("/topic", "/queue")
              .setHeartbeatValue(new long[]{10000, 10000});  // 10s 心跳
        config.setApplicationDestinationPrefixes("/app");
        config.setUserDestinationPrefix("/user");
    }
    
    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        registry.addEndpoint("/ws")
                .setAllowedOriginPatterns("*")
                .withSockJS()
                .setHeartbeatTime(25000)        // SockJS 25s 心跳
                .setDisconnectDelay(30000);      // 30s 断连延迟
    }
}
```

## 三、多实例消息广播（Redis Pub/Sub）

```java
@Component
public class WebSocketSendMessageService {
    @Autowired private SimpMessagingTemplate messagingTemplate;
    @Autowired private RedisTemplate<String, String> redisTemplate;
    
    /** 发送给指定用户 */
    public void sendToUser(String userId, String destination, Object payload) {
        // 先尝试本地发（如果用户连在本实例）
        messagingTemplate.convertAndSendToUser(userId, destination, payload);
        
        // 同时广播到其他实例（Redis Pub/Sub）
        WsMessage msg = new WsMessage(userId, destination, JsonUtils.toJson(payload));
        redisTemplate.convertAndSend("training-center.websocket.user", JsonUtils.toJson(msg));
    }
    
    /** 广播给所有连接 */
    public void broadcast(String destination, Object payload) {
        messagingTemplate.convertAndSend(destination, payload);
        redisTemplate.convertAndSend("training-center.websocket.broadcast", JsonUtils.toJson(payload));
    }
}

// Redis 监听端
@Component
public class RedisListenerHandle {
    @Autowired private TraWsHandlerRegistry handlerRegistry;
    
    public void onMessage(String channel, String body) {
        WsMessage msg = JsonUtils.fromJson(body, WsMessage.class);
        handlerRegistry.dispatch(msg);  // 分发给 @TraWsMapping 标注的 handler
    }
}
```

## 四、在线用户追踪

```java
@Component
public class WebSocketEventListener {
    @Autowired private RedisTemplate<String, String> redisTemplate;
    
    @EventListener
    public void handleConnect(SessionConnectEvent event) {
        String userId = extractUserId(event);
        redisTemplate.opsForSet().add(ONLINE_USERS_KEY, userId);
    }
    
    @EventListener
    public void handleDisconnect(SessionDisconnectEvent event) {
        String userId = extractUserId(event);
        redisTemplate.opsForSet().remove(ONLINE_USERS_KEY, userId);
    }
    
    public boolean isOnline(String userId) {
        return Boolean.TRUE.equals(redisTemplate.opsForSet().isMember(ONLINE_USERS_KEY, userId));
    }
}
```

## 五、语音 WebSocket（Native）

```java
@ServerEndpoint("/admin/training/practiceVoice")
public class PracticeVoiceWebSocket {
    private NlsTranscriber transcriber;
    
    @OnOpen
    public void onOpen(Session session) {
        // 等待 ESTABLISH 消息
    }
    
    @OnMessage
    public void onMessage(String message, Session session) {
        VoiceMessage msg = parse(message);
        switch (msg.getType()) {
            case ESTABLISH:
                // 初始化 NLS 语音识别
                transcriber = nlsService.createTranscriber(
                    result -> session.getBasicRemote().sendText(
                        new VoiceMessage(TRANSCRIPTION, result).toJson()));
                transcriber.start();
                session.getBasicRemote().sendText(
                    new VoiceMessage(ESTABLISH_ACK).toJson());
                break;
                
            case DATA:
                // base64 PCM 音频数据 → 送入 ASR
                byte[] pcm = Base64.decode(msg.getData());
                transcriber.send(pcm);
                break;
                
            case SEND:
                // 识别结束，获取最终文本
                transcriber.stop();
                break;
                
            case CLOSE:
                transcriber.close();
                break;
        }
    }
}
```

### 语音协议时序

```
Client                          Server
  │                               │
  │── ESTABLISH(sessionId) ──────►│  初始化 NLS Transcriber
  │◄── ESTABLISH_ACK ────────────│
  │                               │
  │── DATA(base64 PCM, 200ms) ──►│  transcriber.send(pcm)
  │── DATA ─────────────────────►│
  │── DATA ─────────────────────►│
  │◄── TRANSCRIPTION(partial) ──│  实时中间识别结果
  │── DATA ─────────────────────►│
  │                               │
  │── SEND ─────────────────────►│  transcriber.stop()
  │◄── TRANSCRIPTION(final) ────│  最终识别文本
  │                               │
  │  [前端用识别文本调HTTP sendMessage]
  │                               │
  │── CLOSE ────────────────────►│  释放资源
```

## 六、LLM Streaming 对话

```java
@Component
public class PracticeStreamingService {
    @Autowired private LangChainStreamingChatService streamingChatService;
    @Autowired private WebSocketSendMessageService wsService;
    
    public void sendMessageStreaming(Long sessionId, String userId, 
            String systemPrompt, List<ChatMessage> messages) {
        streamingChatService.chatForTextStream(
            LlmModelConfig.getDefaultLlmModel(),
            systemPrompt, messages, "practice", "练习失败：",
            partial -> {
                // 每收到一个 token 就推送给前端
                wsService.sendToUser(userId, "/queue/practice.stream",
                    new StreamToken(sessionId, partial));
            }
        );
        
        // 流结束，发送完成信号
        wsService.sendToUser(userId, "/queue/practice.stream",
            new StreamToken(sessionId, null, true)); // done=true
    }
}
```

### 前端接收

```javascript
stompClient.subscribe('/user/queue/practice.stream', (message) => {
    const token = JSON.parse(message.body);
    if (token.done) {
        // 流结束
        finishMessage();
    } else {
        // 追加文字（打字机效果）
        appendToMessage(token.content);
    }
});
```
