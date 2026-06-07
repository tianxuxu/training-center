# 评测中心 API 设计

## 核心概念

```
Dataset (数据集)
  └── TestCase (测试用例) × N

Experiment (评测实验)
  ├── 关联 Dataset
  ├── 指定 Prompt版本 + Model + Temperature
  ├── repeat_count (重复次数，测量稳定性)
  └── Result (评测结果) = TestCase × RepeatCount
```

## API 接口

### 数据集管理

```
POST   /eval/dataset/create     创建数据集
POST   /eval/dataset/list       分页查询数据集列表
POST   /eval/dataset/update     更新数据集信息
POST   /eval/dataset/delete     删除数据集

POST   /eval/testCase/create    创建测试用例
POST   /eval/testCase/list      分页查询用例列表
POST   /eval/testCase/update    更新用例
POST   /eval/testCase/delete    删除用例
```

### 实验管理

```
POST   /eval/experiment/create   创建并运行实验
POST   /eval/experiment/list     分页查询实验列表
GET    /eval/experiment/detail   查询实验详情(含逐case结果)
POST   /eval/experiment/cancel   取消运行中的实验
POST   /eval/experiment/compare  A/B 对比两个实验
```

### 创建实验

```
POST /eval/experiment/create

Request:
{
  "name": "对话Prompt V3 vs V2",
  "datasetId": 101,
  "promptVersionId": 203,       // 测试的Prompt版本
  "modelName": "deepseek-v3-2", // 使用的模型
  "temperature": 0.7,
  "repeatCount": 3              // 每个case跑3次
}

Response:
{
  "experimentId": 301,
  "status": "RUNNING",
  "totalCases": 50,
  "estimatedDurationMinutes": 15
}
```

### A/B 对比

```
POST /eval/experiment/compare

Request:
{
  "baseExperimentId": 301,      // 基准实验
  "compareExperimentId": 302    // 对比实验
}

Response:
{
  "base": {
    "name": "V2 + GPT-5.4",
    "avgScore": 7.2,
    "variance": 0.8
  },
  "compare": {
    "name": "V3 + DeepSeek-V3.2",
    "avgScore": 7.8,
    "variance": 0.5
  },
  "delta": +0.6,
  "deltaPercent": "+8.3%",
  "dimensionComparison": [
    {
      "dimension": "角色一致性",
      "baseAvg": 7.5,
      "compareAvg": 8.2,
      "delta": +0.7
    },
    {
      "dimension": "回复长度",
      "baseAvg": 8.0,
      "compareAvg": 7.3,
      "delta": -0.7
    }
  ],
  "caseComparison": [
    {
      "caseId": 1001,
      "baseScore": 6.5,
      "compareScore": 8.0,
      "delta": +1.5,
      "significantImprovement": true
    }
  ]
}
```

## 评测执行流程

```java
public void executeExperiment(Long experimentId) {
    EvalExperiment experiment = getExperiment(experimentId);
    List<EvalTestCase> testCases = getTestCases(experiment.getDatasetId());
    
    for (EvalTestCase testCase : testCases) {
        // 检查是否被取消
        if (isCancelled(experimentId)) break;
        
        for (int run = 0; run < experiment.getRepeatCount(); run++) {
            // 1. 用测试的 Prompt + Model 调用 LLM
            String llmOutput = callLlm(experiment, testCase);
            
            // 2. 用 Judge LLM 评分（独立的评分模型）
            Map<String, Double> scores = judgeService.judge(llmOutput, testCase);
            
            // 3. 记录结果
            saveResult(experimentId, testCase.getId(), run, llmOutput, scores);
        }
        
        // 更新进度
        updateProgress(experimentId);
    }
    
    // 汇总计算平均分
    aggregateScores(experimentId);
}
```

## LLM-as-Judge 评分

### 评分维度（Rubric）
```json
{
  "dimensions": [
    {
      "name": "relevance",
      "label": "相关性",
      "weight": 0.3,
      "description": "回复是否与场景相关",
      "scoring_guide": "1-3分：完全无关；4-6分：部分相关；7-9分：高度相关；10分：完美匹配"
    },
    {
      "name": "role_consistency",
      "label": "角色一致性",
      "weight": 0.3,
      "description": "是否保持角色设定"
    },
    {
      "name": "naturalness",
      "label": "自然度",
      "weight": 0.2,
      "description": "回复是否自然流畅"
    },
    {
      "name": "length_control",
      "label": "长度控制",
      "weight": 0.2,
      "description": "是否遵守字数要求"
    }
  ],
  "pass_threshold": 6.0
}
```

### Judge 实现
```java
public Map<String, Double> judge(String llmOutput, EvalTestCase testCase) {
    // 每个维度独立评分（避免维度间互相影响）
    Map<String, Double> scores = new LinkedHashMap<>();
    for (Dimension dim : rubric.getDimensions()) {
        if ("consistency".equals(dim.getName())) continue; // consistency 用方差计算
        
        double rawScore = evaluator.evaluate(dim, llmOutput, testCase.getInput());
        double normalized = Math.clamp(rawScore * 10, 1.0, 10.0); // 归一化到 1-10
        scores.put(dim.getName(), normalized);
    }
    
    // 加权总分
    double total = scores.entrySet().stream()
        .mapToDouble(e -> e.getValue() * getWeight(e.getKey()))
        .sum();
    scores.put("total", total);
    return scores;
}
```

## 协作取消机制

```java
// 共享取消标记
private final ConcurrentHashMap<Long, AtomicBoolean> cancelFlags = new ConcurrentHashMap<>();

public void cancelExperiment(Long experimentId) {
    cancelFlags.computeIfAbsent(experimentId, k -> new AtomicBoolean())
        .set(true);
}

private boolean isCancelled(Long experimentId) {
    AtomicBoolean flag = cancelFlags.get(experimentId);
    return flag != null && flag.get();
}
```
