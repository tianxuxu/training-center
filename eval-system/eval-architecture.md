# 评测中心架构

## 一、为什么需要评测中心

Prompt 优化面临的核心挑战：**如何量化"好不好"**。

没有评测系统的 Prompt 优化 = 盲调：
- 改了一个词，不知道是提升还是降级
- 换了模型，不知道效果差异有多大
- 不同人主观评价不一致

评测中心解决的问题：
1. **可量化**：每次 Prompt 变更产出一个数字（分数）
2. **可对比**：A/B 对比两个版本，维度级别的 diff
3. **可回归**：确保新版本不会在某些 case 上退化
4. **可复现**：相同输入 + 相同 Prompt + 相同模型 = 可复现结果

## 二、核心实体

```
Dataset (数据集)
│   "催收对话评测集 V2"
│   50 个测试用例
│
├── TestCase (测试用例)
│   ├── input_data: 对话历史 + 场景信息
│   ├── expected_output: 期望输出（可选）
│   └── metadata: 难度等级、场景类型
│
└── 被多个 Experiment 引用

Experiment (评测实验)
│   "V3 Prompt + DeepSeek-V3.2 @ temp=0.7"
│   ├── dataset_id → 引用数据集
│   ├── prompt_version_id → 测试哪个 Prompt
│   ├── model_name → 用什么模型
│   ├── temperature → 推理温度
│   ├── repeat_count → 重复次数（测量稳定性）
│   └── status → PENDING → RUNNING → COMPLETED
│
└── Result (评测结果)
    ├── test_case_id + run_index
    ├── llm_output → LLM 原始输出
    ├── judge_scores → 各维度得分
    ├── total_score → 加权总分
    └── latency_ms → 调用延迟
```

## 三、执行流程

```
创建实验
    │
    ▼
异步执行 (evalExecutor 线程池)
    │
    ├── for each TestCase in Dataset:
    │       ├── for i in range(repeatCount):
    │       │       ├── 构建 Prompt (注入 testCase.input_data)
    │       │       ├── 调用 LLM (指定 model + temperature)
    │       │       ├── 获取 llmOutput
    │       │       ├── 调用 Judge (独立 LLM 评分)
    │       │       └── 保存 Result
    │       │
    │       └── 更新 experiment.completed_cases++
    │
    ├── 汇总：计算 avgScore, variance
    └── 更新状态 → COMPLETED
```

## 四、A/B 对比逻辑

```java
public ExperimentCompareResponse compare(Long baseId, Long compareId) {
    // 1. 加载两个实验的所有结果
    List<EvalResult> baseResults = resultModel.listByExperiment(baseId);
    List<EvalResult> compareResults = resultModel.listByExperiment(compareId);
    
    // 2. 实验级别对比
    double baseTotalAvg = avg(baseResults, EvalResult::getTotalScore);
    double compareTotalAvg = avg(compareResults, EvalResult::getTotalScore);
    
    // 3. 维度级别对比（每个维度的平均分变化）
    List<DimensionCompare> dimensionComparisons = rubric.getDimensions().stream()
        .map(dim -> {
            double baseAvg = avgDimScore(baseResults, dim.getName());
            double compareAvg = avgDimScore(compareResults, dim.getName());
            return new DimensionCompare(dim.getLabel(), baseAvg, compareAvg, compareAvg - baseAvg);
        }).collect(toList());
    
    // 4. Case 级别对比（找出提升/退化最明显的 case）
    List<CaseCompare> caseComparisons = matchCaseResults(baseResults, compareResults)
        .stream()
        .sorted(comparingDouble(c -> Math.abs(c.getDelta())).reversed())
        .limit(20)  // Top 20 变化最大的 case
        .collect(toList());
    
    return new ExperimentCompareResponse(baseTotalAvg, compareTotalAvg, 
        dimensionComparisons, caseComparisons);
}
```

## 五、使用场景

### 场景 1: Prompt 版本对比
```
1. 准备 Dataset（50条典型对话输入）
2. 创建实验 A: V2 Prompt + GPT-5.4
3. 创建实验 B: V3 Prompt + GPT-5.4（仅改 Prompt）
4. 对比 A vs B → 看 Prompt 改动的效果
```

### 场景 2: 模型迁移评估
```
1. 使用同一 Dataset
2. 创建实验 A: 同一 Prompt + GPT-5.4
3. 创建实验 B: 同一 Prompt + DeepSeek-V3.2（仅改模型）
4. 对比 → 评估模型迁移是否可行（效果损失多少）
```

### 场景 3: 温度调参
```
1. 创建实验 A: temp=0.5, repeat=5
2. 创建实验 B: temp=0.8, repeat=5
3. 对比 avgScore（质量）+ variance（稳定性）
4. 选择质量和稳定性最佳平衡点
```

### 场景 4: 回归测试
```
每次 Prompt 变更前：
1. 在标准 Dataset 上跑一遍
2. 对比历史最高分实验
3. 确认无退化后才发布
```

## 六、Dev 模式兜底

本地开发环境没有 Judge LLM 时：

```java
private Map<String, Double> judgeFallbackDev(String llmOutput) {
    // 生成确定性伪分数（基于输出长度、JSON合法性等规则）
    Map<String, Double> scores = new LinkedHashMap<>();
    scores.put("relevance", llmOutput.length() > 50 ? 7.0 : 5.0);
    scores.put("naturalness", isValidJson(llmOutput) ? 8.0 : 4.0);
    scores.put("total", 6.5);
    return scores;
}
```

## 七、未来演进

| 当前 | 演进方向 |
|------|---------|
| 手动触发 | CI/CD 集成（Prompt 变更自动跑评测） |
| 离线评测 | 在线评测（线上采样+实时打分） |
| 单 Judge | 多 Judge 投票（减少偏差） |
| 手动建 Dataset | 数据飞轮（线上优质样本自动入库） |
