# LLM-as-Judge 实现

## 一、核心思想

用一个 LLM（Judge）来评估另一个 LLM 的输出质量。相比人工评估：
- 成本低 100x（人工评估 1 条 ~5 分钟，LLM 评估 ~3 秒）
- 一致性高（同样输入同样标准，结果稳定）
- 可扩展（可跑 1000+ 条评测）

## 二、评分维度设计（Rubric）

```json
{
  "dimensions": [
    {
      "name": "relevance",
      "label": "相关性",
      "weight": 0.25,
      "description": "AI回复是否与当前对话场景和上下文相关",
      "scoring_guide": "1-3: 完全无关或答非所问; 4-6: 部分相关但有偏题; 7-9: 高度相关且切题; 10: 完美匹配场景需求"
    },
    {
      "name": "role_consistency",
      "label": "角色一致性",
      "weight": 0.25,
      "description": "是否保持设定的角色身份、性格、知识边界",
      "scoring_guide": "1-3: 完全跳出角色; 4-6: 偶尔不一致; 7-9: 基本保持; 10: 全程完美"
    },
    {
      "name": "naturalness",
      "label": "自然度",
      "weight": 0.20,
      "description": "回复是否自然流畅，像真人说话",
      "scoring_guide": "1-3: 明显机器味; 4-6: 略显生硬; 7-9: 自然流畅; 10: 无法分辨是AI"
    },
    {
      "name": "length_control",
      "label": "长度控制",
      "weight": 0.15,
      "description": "是否遵守字数限制（20-40字要求）",
      "scoring_guide": "1-3: 严重超长或过短; 4-6: 略微偏离; 7-9: 基本符合; 10: 精准控制"
    },
    {
      "name": "instruction_following",
      "label": "指令遵循",
      "weight": 0.15,
      "description": "是否遵循系统指令中的行为约束",
      "scoring_guide": "1-3: 明显违反多条; 4-6: 部分遵循; 7-9: 大部分遵循; 10: 完全遵循"
    }
  ],
  "pass_threshold": 6.0
}
```

## 三、Judge 实现

### 集成 Dokimos 框架

```java
@Service
public class EvalJudgeService {
    @Autowired private ChatModelFactory chatModelFactory;
    
    public Map<String, Double> judge(String llmOutput, EvalTestCase testCase, Rubric rubric) {
        Map<String, Double> scores = new LinkedHashMap<>();
        
        for (Dimension dim : rubric.getDimensions()) {
            // 跳过 consistency（用方差计算）
            if ("consistency".equals(dim.getName())) continue;
            
            // 每个维度独立评分
            double score = judgeSingleDimension(dim, llmOutput, testCase);
            // 归一化到 1-10
            double normalized = Math.max(1.0, Math.min(10.0, score * 10));
            scores.put(dim.getName(), normalized);
        }
        
        // 加权总分
        double total = scores.entrySet().stream()
            .mapToDouble(e -> e.getValue() * rubric.getWeight(e.getKey()))
            .sum();
        scores.put("total", total);
        
        return scores;
    }
    
    private double judgeSingleDimension(Dimension dim, String llmOutput, EvalTestCase testCase) {
        // 使用 Dokimos LLMJudgeEvaluator
        ChatModel judgeModel = chatModelFactory.getModel(
            LlmModelConfig.getScoringLlmModel(), "eval_judge", false);
        
        LLMJudgeEvaluator evaluator = LLMJudgeEvaluator.builder()
            .judge(LangChain4jSupport.asJudge(judgeModel))
            .criterion(dim.getDescription())
            .scoringGuide(dim.getScoringGuide())
            .build();
        
        return evaluator.evaluate(
            testCase.getInputAsString(),  // input context
            llmOutput                     // output to judge
        );
    }
}
```

### 自建 Judge Prompt（不用框架时）

```markdown
你是一个AI输出质量评估专家。请根据以下标准对AI的回复进行评分。

## 评分维度: {{dimensionName}}
## 维度说明: {{dimensionDescription}}
## 评分标准: {{scoringGuide}}

## 输入上下文
{{inputContext}}

## AI的回复（待评估）
{{llmOutput}}

## 评分要求
1. 严格按照评分标准打分（1-10分）
2. 必须给出 evidence（引用原文中的具体内容作为依据）
3. 评分要客观，避免偏高或偏低

## 输出格式
{"score": 7, "evidence": "...", "reasoning": "..."}
```

## 四、防偏差策略

### 策略 1: 独立维度评分
每个维度一次独立的 LLM 调用，避免维度间互相影响（"光环效应"）。

### 策略 2: 锚定校准
在 Judge Prompt 中提供标杆案例：
```
## 评分参考锚点
- 9分示例: "（高质量回复示例）"
- 5分示例: "（中等质量示例）"
- 2分示例: "（低质量示例）"
```

### 策略 3: 一致性度量
用 `repeat_count` 重复多次评测，计算方差：
```java
// 同一 case 的多次评分方差
double variance = calculateVariance(scoresForSameCase);
// 方差大 = LLM 输出不稳定 = consistency 维度得分低
double consistencyScore = Math.max(1, 10 - variance * 3);
```

### 策略 4: 多 Judge 投票（高级）
```java
// 3 个不同 Prompt 的 Judge 独立评分
double score1 = judge(prompt1, output, testCase);
double score2 = judge(prompt2, output, testCase);
double score3 = judge(prompt3, output, testCase);
// 取中位数
double finalScore = median(score1, score2, score3);
```

## 五、Consistency 维度特殊处理

consistency（一致性）不由 Judge LLM 评分，而是通过统计方法计算：

```java
/**
 * 一致性 = 同一输入多次运行结果的稳定程度
 * repeat_count=5 时，5次输出的分数方差越小 = 越一致
 */
public double calculateConsistency(List<EvalResult> sameInputResults) {
    List<Double> scores = sameInputResults.stream()
        .map(EvalResult::getTotalScore)
        .collect(toList());
    
    double variance = calculateVariance(scores);
    // 方差越小 → 分数越高
    // variance=0 → score=10, variance=3+ → score=1
    return Math.max(1.0, 10.0 - variance * 3);
}
```

## 六、评分结果归一化

```java
/**
 * Dokimos 返回 0-1 范围分数，需要归一化到 1-10
 * 并确保所有分数在 [1, 10] 范围内
 */
public double normalizeScore(double rawScore) {
    double scaled = rawScore * 10.0;
    return Math.max(1.0, Math.min(10.0, scaled));
}
```

## 七、评分结果聚合

```java
// 实验级别聚合
public ExperimentSummary aggregate(Long experimentId) {
    List<EvalResult> results = resultModel.listByExperiment(experimentId);
    
    // 过滤失败的
    List<EvalResult> successful = results.stream()
        .filter(r -> "SUCCESS".equals(r.getStatus()))
        .collect(toList());
    
    // 整体平均分
    double avgScore = successful.stream()
        .mapToDouble(EvalResult::getTotalScore)
        .average().orElse(0);
    
    // 方差（评估稳定性）
    double variance = calculateVariance(
        successful.stream().map(EvalResult::getTotalScore).collect(toList()));
    
    // 各维度平均（用于维度级别分析）
    Map<String, Double> dimensionAvgs = calculateDimensionAverages(successful);
    
    return new ExperimentSummary(avgScore, variance, dimensionAvgs, 
        successful.size(), results.size() - successful.size());
}
```
