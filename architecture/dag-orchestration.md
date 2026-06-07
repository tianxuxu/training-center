# Prompt DAG 编排设计

## 一、DAG 全景图

培训中台的 AI 链路由 15 个 Prompt 节点组成 DAG：

```
POLISHED_SCENARIO (场景润色)
    │
    ▼
QUESTION_CHECKLIST (问题清单)
    │
    ▼
ROLE_DEF (角色生成)
    │
    ├─────────────────────────────┐
    ▼                             ▼
SCRIPT_CREATE_OPEN (开放剧本)   SCRIPT_CREATE_PROCESS (流程剧本)
    │                             │
    ▼                             ▼
GOAL_OPEN (开放目标)            GOAL_PROCESS (流程目标)
    │                             │
    ▼                             ▼
SCORE_GENERATE_OPEN             SCORE_GENERATE_PROCESS
    │                             │
    ▼                             ▼
DIALOGUE_OPEN (开放对话)        DIALOGUE_PROCESS (流程对话)
    │         │                   │         │
    ├─────────┼───────────────────┼─────────┤
    │         │                   │         │
    ▼         ▼                   ▼         ▼
POLISH    INSPIRATION          POLISH    INSPIRATION
(润色)      (灵感)             (润色)      (灵感)
    │
    ▼
FINISH_CHECK (结束检查)
    │
    ▼
SCORING (评分)
```

## 二、DAG 节点枚举设计

```java
public enum PromptDagNode {
    POLISHED_SCENARIO("ai_training_polished_scenario"),
    QUESTION_CHECKLIST("ai_training_question_checklist", POLISHED_SCENARIO),
    ROLE_DEF("ai_training_role_def", QUESTION_CHECKLIST),
    SCRIPT_CREATE_OPEN("ai_script_create_open", ROLE_DEF),
    SCRIPT_CREATE_PROCESS("ai_script_create_process", ROLE_DEF),
    GOAL_OPEN("ai_script_goal_open", SCRIPT_CREATE_OPEN),
    GOAL_PROCESS("ai_script_goal_process", SCRIPT_CREATE_PROCESS),
    SCORE_GENERATE_OPEN("ai_score_generate_open", GOAL_OPEN),
    SCORE_GENERATE_PROCESS("ai_score_generate_process", GOAL_PROCESS),
    DIALOGUE_OPEN("ai_practice_dialogue_open", SCORE_GENERATE_OPEN),
    DIALOGUE_PROCESS("ai_practice_dialogue_process", SCORE_GENERATE_PROCESS),
    POLISH("ai_practice_polish", DIALOGUE_OPEN, DIALOGUE_PROCESS),
    INSPIRATION("ai_practice_inspiration", DIALOGUE_OPEN, DIALOGUE_PROCESS),
    FINISH_CHECK("ai_practice_finish_check", DIALOGUE_OPEN),
    SCORING("ai_practice_scoring", DIALOGUE_OPEN, DIALOGUE_PROCESS);

    private final String promptCode;
    private final List<PromptDagNode> dependencies;
}
```

## 三、拓扑排序执行器

支持从任意节点开始、到任意节点结束的子链路调试：

```java
/**
 * 从 start 到 end 的执行路径（拓扑序）。
 * 仅包含从 start 可达且能到达 end 的节点，按依赖顺序排列。
 */
public static List<PromptDagNode> getTopologicalOrder(String startCode, String endCode) {
    PromptDagNode start = fromCodeOrNull(startCode);
    // 1. 从 start 向前（后继方向）的可达集合
    Set<PromptDagNode> forward = forwardReachable(start);
    // 2. 从 end 向后（依赖方向）的可达集合
    Set<PromptDagNode> backward = backwardReachable(fromCodeOrNull(endCode));
    // 3. 取交集 = 路径上的节点
    Set<PromptDagNode> subset = forward.stream()
        .filter(backward::contains).collect(toSet());
    // 4. 拓扑排序
    return topologicalSort(subset);
}
```

## 四、DAG 调试能力

### 画布调试（后台功能）
- 运营在后台选择起始/结束节点
- 系统计算子链路并按拓扑序逐个执行
- 每个节点的输入/输出实时展示
- 支持修改中间节点的输出后继续执行（mock 输入）

### 配置键
```properties
# 跳过真实 LLM 调用（用于联调时打通流程）
training.center.prompt.debug.llm.mock.enabled=true
```

## 五、Prompt 模板管理

### 文件组织
```
resources/promot/
├── ai_training_polished_scenario.md    # ①场景润色
├── ai_training_question_checklist.md   # ②问题清单
├── ai_training_role_def.md             # ③角色生成
├── ai_training_role_refresh.md         # 角色刷新
├── ai_script_create_open.md            # ④开放剧本
├── ai_script_create_process.md         # ④流程剧本
├── ai_script_goal_open.md              # ⑤开放目标
├── ai_script_goal_process.md           # ⑤流程目标
├── ai_score_generate_open.md           # ⑥开放评分维度
├── ai_score_generate_process.md        # ⑥流程评分维度
├── ai_practice_dialogue_open.md        # ⑦开放对话
├── ai_practice_dialogue_process.md     # ⑦流程对话
├── ai_practice_polish.md               # ⑦a话术润色
├── ai_practice_inspiration.md          # ⑦b灵感提示
├── ai_practice_finish_check.md         # ⑦c结束判断
├── ai_practice_scoring.md              # ⑧评分（主）
├── ai_practice_scoring_dimension.md    # ⑧评分（维度）
├── ai_practice_scoring_reduce.md       # ⑧评分（汇总）
├── ai_practice_scoring_suggestion.md   # ⑧评分（建议）
├── ai_practice_goal_judge.md           # 目标判定
├── ai_knowledge_qa_parse.md            # 知识库问答
├── ai_qa_keyword_extract.md            # 关键词提取
├── ai_quality_qa_dedup.md              # QA去重
└── ai_prompt_revise_meta.md            # Prompt自修改
```

### 模板约定
- 占位符格式：`{{camelCaseVariable}}`
- 所有模板首行：`{{responseLanguageInstruction}}`（i18n）
- 输出格式在模板末尾严格定义（JSON Schema + 示例）
- Few-shot 示例直接嵌入模板

### Assembler 模式
```java
@Component
public class PracticePromptAssembler {
    @Autowired private PromptTemplateLoader templateLoader;
    
    public String getOpenDialoguePrompt(PracticeDialogueOpenInput input) {
        Map<String, Object> vars = new LinkedHashMap<>();
        vars.put("responseLanguageInstruction", input.getResponseLanguageInstruction());
        vars.put("roleName", nullToEmpty(input.getRoleName()));
        vars.put("roleGender", nullToEmpty(input.getRoleGender()));
        vars.put("roleAge", nullToEmpty(input.getRoleAge()));
        vars.put("aiIdentity", nullToEmpty(input.getAiIdentity()));
        // ... 20+ 个变量
        return templateLoader.loadAndFill("ai_practice_dialogue_open", vars);
    }
}
```
