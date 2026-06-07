-- ============================================================
-- AI 培训中台 核心表结构
-- MySQL 8.0 | 字符集 utf8mb4 | 时间戳为毫秒级 bigint(20)
-- ============================================================

-- ----------------------------------------------------------
-- 1. 角色（AI 扮演的虚拟人物）
-- ----------------------------------------------------------
CREATE TABLE tra_character (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL COMMENT '业务线ID',
    name            VARCHAR(100) NOT NULL COMMENT '角色名称',
    avatar_id       VARCHAR(200) COMMENT '头像资源ID',
    voice_id        VARCHAR(100) COMMENT '语音合成音色ID',
    gender          VARCHAR(10) COMMENT '性别: MALE/FEMALE',
    voice_speed     DOUBLE COMMENT '语速倍率',
    age             INT COMMENT '年龄',
    personality_traits VARCHAR(500) COMMENT '性格特征',
    social_identity VARCHAR(200) COMMENT '社会身份',
    role_summary    VARCHAR(1000) COMMENT '角色简介',
    detailed_background TEXT COMMENT '详细背景故事',
    creator_id      VARCHAR(50) NOT NULL,
    time_created    BIGINT(20) NOT NULL,
    updater_id      VARCHAR(50),
    time_updated    BIGINT(20),
    deleted         TINYINT(1) DEFAULT 0,
    status          VARCHAR(20) DEFAULT 'ACTIVE',
    PRIMARY KEY (id),
    KEY idx_business (business_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 2. 剧本（AI 陪练的脚本配置）
-- ----------------------------------------------------------
CREATE TABLE tra_script (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    question_id     BIGINT(20) COMMENT '关联的培训场景ID',
    script_mode     VARCHAR(20) NOT NULL COMMENT 'AI_GENERATED / MANUAL',
    script_name     VARCHAR(200) NOT NULL,
    department_id   VARCHAR(50),
    department_name VARCHAR(100),
    dialogue_mode   VARCHAR(20) NOT NULL COMMENT 'OPEN / PROCESS',
    dialogue_type   VARCHAR(20) COMMENT 'TEXT / VOICE / BOTH',
    original_scene  TEXT COMMENT '原始场景描述',
    scene           TEXT COMMENT '润色后的场景描述',
    ai_identity     VARCHAR(200) COMMENT 'AI扮演的身份',
    trainee_identity VARCHAR(200) COMMENT '学员扮演的身份',
    is_voice_input  TINYINT(1) DEFAULT 0,
    is_text_input   TINYINT(1) DEFAULT 1,
    character_id    BIGINT(20) COMMENT '关联角色ID',
    dialogue_goal   TEXT COMMENT 'AI的对话目标',
    dialogue_idea   TEXT COMMENT 'AI的对话思路',
    trainee_achievement_condition TEXT COMMENT '学员达成条件',
    dialogue_initiator VARCHAR(20) DEFAULT 'AI' COMMENT '对话发起方',
    narration       TEXT COMMENT '旁白/开场白',
    forbidden_words TEXT COMMENT '违禁词列表(JSON数组)',
    deduct_score    INT DEFAULT 5 COMMENT '每个违禁词扣分',
    deduct_score_max INT DEFAULT 20 COMMENT '违禁词最大扣分',
    creator_id      VARCHAR(50) NOT NULL,
    time_created    BIGINT(20) NOT NULL,
    updater_id      VARCHAR(50),
    time_updated    BIGINT(20),
    deleted         TINYINT(1) DEFAULT 0,
    status          VARCHAR(20) DEFAULT 'DRAFT',
    PRIMARY KEY (id),
    KEY idx_business (business_id),
    KEY idx_character (character_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 3. 剧本目标（流程式剧本的分步目标）
-- ----------------------------------------------------------
CREATE TABLE tra_script_goal (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    script_id       BIGINT(20) NOT NULL,
    sort_order      INT DEFAULT 0 COMMENT '目标排序',
    ai_goal         TEXT COMMENT 'AI在此阶段的目标',
    trainee_goal    TEXT COMMENT '学员在此阶段的目标',
    dialogue_rounds_setting INT DEFAULT 10 COMMENT '本目标最大轮次',
    dialogue_idea   TEXT COMMENT '对话策略',
    ai_requirement_setting TEXT COMMENT 'AI行为约束',
    goal_achievement_condition TEXT COMMENT '达成条件(JSON)',
    achievement_reward_copy TEXT COMMENT '达成后的过渡话术',
    failure_feedback_copy TEXT COMMENT '失败后的反馈话术',
    post_failure_flow_mode VARCHAR(30) DEFAULT 'END_DIALOGUE' COMMENT 'END_DIALOGUE/CONTINUE',
    creator_id      VARCHAR(50) NOT NULL,
    time_created    BIGINT(20) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_script (script_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 4. 剧本行为策略（对学员特定行为的AI应对策略）
-- ----------------------------------------------------------
CREATE TABLE tra_script_goal_strategy (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    script_id       BIGINT(20) NOT NULL,
    goal_id         BIGINT(20) NOT NULL,
    trigger_behavior TEXT COMMENT '触发行为描述',
    ai_strategy     TEXT COMMENT 'AI应对策略',
    creator_id      VARCHAR(50) NOT NULL,
    time_created    BIGINT(20) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_goal (goal_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 5. 剧本反馈（过程中的实时反馈规则）
-- ----------------------------------------------------------
CREATE TABLE tra_script_feedback (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    script_id       BIGINT(20) NOT NULL,
    trigger_behavior TEXT COMMENT '触发行为',
    prompt_copy     TEXT COMMENT '反馈话术',
    feedback_type   VARCHAR(30) COMMENT 'POSITIVE/NEGATIVE/NEUTRAL',
    creator_id      VARCHAR(50) NOT NULL,
    time_created    BIGINT(20) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_script (script_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 6. 标准话术参考
-- ----------------------------------------------------------
CREATE TABLE tra_script_standard_reply (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    script_id       BIGINT(20) NOT NULL,
    ai_behavior     TEXT COMMENT '客户行为/场景',
    standard_reply  TEXT COMMENT '标准回复话术',
    creator_id      VARCHAR(50) NOT NULL,
    time_created    BIGINT(20) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_script (script_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 7. 评分维度
-- ----------------------------------------------------------
CREATE TABLE tra_score_dimension (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    script_id       BIGINT(20) NOT NULL,
    goal_id         BIGINT(20) COMMENT '关联目标(PROCESS模式)',
    score_dimension VARCHAR(200) NOT NULL COMMENT '维度名称',
    score           INT NOT NULL COMMENT '维度分值',
    is_system_preset TINYINT(1) DEFAULT 0 COMMENT '系统预设维度',
    sort_order      INT DEFAULT 0,
    operator_id     VARCHAR(50),
    time_created    BIGINT(20) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_script (script_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 8. 评分明细（每个维度下的具体考核点）
-- ----------------------------------------------------------
CREATE TABLE tra_score_detail (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    script_id       BIGINT(20) NOT NULL,
    score_id        BIGINT(20) NOT NULL COMMENT '维度ID',
    assessment_point VARCHAR(500) NOT NULL COMMENT '考核点',
    scoring_standard TEXT COMMENT '评分标准描述',
    score           INT NOT NULL COMMENT '该考核点分值',
    operator_id     VARCHAR(50),
    time_created    BIGINT(20) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_dimension (score_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 9. 练习会话
-- ----------------------------------------------------------
CREATE TABLE tra_practice_session (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    plan_id         BIGINT(20) COMMENT '培训计划ID',
    script_id       BIGINT(20) NOT NULL,
    plan_script_id  BIGINT(20),
    user_id         BIGINT(20) NOT NULL,
    work_number     VARCHAR(50),
    session_type    VARCHAR(20) NOT NULL COMMENT 'PRACTICE/EXAM',
    session_status  VARCHAR(20) NOT NULL COMMENT 'IN_PROGRESS/COMPLETED/SCORING/SCORED',
    dialogue_mode   VARCHAR(20) NOT NULL COMMENT 'OPEN/PROCESS',
    current_goal_index INT DEFAULT 0,
    total_goals     INT DEFAULT 0,
    completed_goals INT DEFAULT 0,
    total_rounds    INT DEFAULT 0,
    start_time      BIGINT(20),
    end_time        BIGINT(20),
    duration        BIGINT(20) COMMENT '时长(毫秒)',
    end_reason      VARCHAR(50) COMMENT 'USER_STOP/GOAL_COMPLETE/ROUND_LIMIT/...',
    report_status   VARCHAR(20) DEFAULT 'PENDING',
    creator_id      VARCHAR(50) NOT NULL,
    time_created    BIGINT(20) NOT NULL,
    updater_id      VARCHAR(50),
    time_updated    BIGINT(20),
    PRIMARY KEY (id),
    KEY idx_user (user_id),
    KEY idx_script (script_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 10. 对话消息
-- ----------------------------------------------------------
CREATE TABLE tra_practice_dialogue (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    session_id      BIGINT(20) NOT NULL,
    message_type    VARCHAR(20) NOT NULL COMMENT 'USER/AI/SYSTEM/TRANSITION',
    role            VARCHAR(20) NOT NULL COMMENT 'STUDENT/AI/SYSTEM',
    content         TEXT NOT NULL,
    round_number    INT NOT NULL,
    goal_index      INT DEFAULT 0,
    ref_message_id  BIGINT(20) COMMENT '引用消息ID(润色/灵感)',
    extra_data      JSON COMMENT '扩展数据(polish/inspiration结果)',
    creator_id      VARCHAR(50),
    time_created    BIGINT(20) NOT NULL,
    updater_id      VARCHAR(50),
    time_updated    BIGINT(20),
    PRIMARY KEY (id),
    KEY idx_session (session_id),
    KEY idx_round (session_id, round_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 11. 练习报告
-- ----------------------------------------------------------
CREATE TABLE tra_practice_report (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    session_id      BIGINT(20) NOT NULL,
    plan_id         BIGINT(20),
    script_id       BIGINT(20) NOT NULL,
    user_id         BIGINT(20) NOT NULL,
    script_name     VARCHAR(200),
    session_type    VARCHAR(20),
    total_score     DECIMAL(10,2),
    total_max_score DECIMAL(10,2),
    passed          TINYINT(1),
    pass_score      DECIMAL(10,2),
    round_count     INT,
    duration        BIGINT(20),
    end_reason      VARCHAR(50),
    overall_comment TEXT,
    forbidden_word_deduction DECIMAL(10,2) DEFAULT 0,
    report_status   VARCHAR(20) DEFAULT 'PENDING',
    creator_id      VARCHAR(50),
    time_created    BIGINT(20) NOT NULL,
    updater_id      VARCHAR(50),
    time_updated    BIGINT(20),
    PRIMARY KEY (id),
    KEY idx_session (session_id),
    KEY idx_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 12. 报告明细（逐项评分）
-- ----------------------------------------------------------
CREATE TABLE tra_practice_report_detail (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    report_id       BIGINT(20) NOT NULL,
    session_id      BIGINT(20) NOT NULL,
    dimension_id    BIGINT(20),
    dimension_name  VARCHAR(200),
    dimension_max_score DECIMAL(10,2),
    detail_id       BIGINT(20),
    assessment_point VARCHAR(500),
    scoring_standard TEXT,
    max_score       DECIMAL(10,2),
    actual_score    DECIMAL(10,2),
    comment         TEXT COMMENT 'LLM生成的评语',
    strength        TEXT COMMENT '亮点',
    improvement     TEXT COMMENT '改进建议',
    deduction_evidence_quote TEXT COMMENT '扣分依据原文',
    deduction_reason TEXT COMMENT '扣分理由',
    goal_id         BIGINT(20),
    creator_id      VARCHAR(50),
    time_created    BIGINT(20) NOT NULL,
    updater_id      VARCHAR(50),
    time_updated    BIGINT(20),
    PRIMARY KEY (id),
    KEY idx_report (report_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 13. 评测数据集
-- ----------------------------------------------------------
CREATE TABLE tra_eval_dataset (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    name            VARCHAR(200) NOT NULL,
    description     TEXT,
    test_case_count INT DEFAULT 0,
    creator_id      VARCHAR(50) NOT NULL,
    time_created    BIGINT(20) NOT NULL,
    updater_id      VARCHAR(50),
    time_updated    BIGINT(20),
    deleted         TINYINT(1) DEFAULT 0,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 14. 评测用例
-- ----------------------------------------------------------
CREATE TABLE tra_eval_test_case (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    dataset_id      BIGINT(20) NOT NULL,
    input_data      JSON NOT NULL COMMENT '输入数据(对话历史等)',
    expected_output JSON COMMENT '期望输出(可选)',
    metadata        JSON COMMENT '元信息(场景类型等)',
    creator_id      VARCHAR(50) NOT NULL,
    time_created    BIGINT(20) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_dataset (dataset_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 15. 评测实验
-- ----------------------------------------------------------
CREATE TABLE tra_eval_experiment (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    name            VARCHAR(200) NOT NULL,
    dataset_id      BIGINT(20) NOT NULL,
    prompt_version_id BIGINT(20) COMMENT '测试的Prompt版本',
    model_name      VARCHAR(100) COMMENT '使用的模型',
    temperature     DOUBLE,
    repeat_count    INT DEFAULT 1 COMMENT '每个case重复次数',
    status          VARCHAR(20) NOT NULL COMMENT 'PENDING/RUNNING/COMPLETED/CANCELLED/FAILED',
    total_cases     INT DEFAULT 0,
    completed_cases INT DEFAULT 0,
    avg_score       DECIMAL(10,4),
    variance        DECIMAL(10,4),
    creator_id      VARCHAR(50) NOT NULL,
    time_created    BIGINT(20) NOT NULL,
    updater_id      VARCHAR(50),
    time_updated    BIGINT(20),
    PRIMARY KEY (id),
    KEY idx_dataset (dataset_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 16. 评测结果
-- ----------------------------------------------------------
CREATE TABLE tra_eval_result (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    experiment_id   BIGINT(20) NOT NULL,
    test_case_id    BIGINT(20) NOT NULL,
    run_index       INT DEFAULT 0 COMMENT '第几次运行(repeat)',
    llm_output      TEXT COMMENT 'LLM原始输出',
    judge_scores    JSON COMMENT '各维度得分(JSON)',
    total_score     DECIMAL(10,4),
    latency_ms      BIGINT(20),
    token_count     INT,
    status          VARCHAR(20) COMMENT 'SUCCESS/FAILED/TIMEOUT',
    error_message   TEXT,
    time_created    BIGINT(20) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_experiment (experiment_id),
    KEY idx_case (test_case_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 17. LLM 调用日志（可观测性）
-- ----------------------------------------------------------
CREATE TABLE tra_llm_call_log (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20),
    session_id      BIGINT(20) COMMENT '练习会话ID',
    script_id       BIGINT(20),
    user_id         VARCHAR(50),
    scene           VARCHAR(50) NOT NULL COMMENT '调用场景枚举',
    model_type      VARCHAR(50) NOT NULL,
    scenario        VARCHAR(50) COMMENT '场景参数',
    system_prompt   MEDIUMTEXT,
    user_message    MEDIUMTEXT,
    ai_response     MEDIUMTEXT,
    status          VARCHAR(20) NOT NULL COMMENT 'SUCCESS/FAILED/TIMEOUT/CONTENT_FILTER',
    error_message   TEXT,
    latency_ms      BIGINT(20),
    input_tokens    INT,
    output_tokens   INT,
    temperature     DOUBLE,
    max_tokens      INT,
    time_created    BIGINT(20) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_session (session_id),
    KEY idx_scene (scene),
    KEY idx_time (time_created)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 18. 培训计划
-- ----------------------------------------------------------
CREATE TABLE tra_plan (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    plan_name       VARCHAR(200) NOT NULL,
    department_id   VARCHAR(50),
    department_name VARCHAR(100),
    plan_mode       VARCHAR(20) COMMENT 'NORMAL/STAGE',
    valid_days      INT COMMENT '有效天数',
    start_time      BIGINT(20),
    end_time        BIGINT(20),
    is_time_limit   TINYINT(1) DEFAULT 0,
    is_stage_mode   TINYINT(1) DEFAULT 0,
    creator_id      VARCHAR(50) NOT NULL,
    time_created    BIGINT(20) NOT NULL,
    updater_id      VARCHAR(50),
    time_updated    BIGINT(20),
    deleted         TINYINT(1) DEFAULT 0,
    status          VARCHAR(20) DEFAULT 'DRAFT',
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 19. 培训计划-剧本关联
-- ----------------------------------------------------------
CREATE TABLE tra_plan_script (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    plan_id         BIGINT(20) NOT NULL,
    script_id       BIGINT(20) NOT NULL,
    stage_id        BIGINT(20),
    sort_order      INT DEFAULT 0,
    is_required     TINYINT(1) DEFAULT 1,
    practice_mode   VARCHAR(20) COMMENT 'PRACTICE_ONLY/EXAM_ONLY/BOTH',
    exam_count_limit INT DEFAULT 3,
    pass_score      DECIMAL(10,2) DEFAULT 60,
    inspiration_hint TINYINT(1) DEFAULT 1 COMMENT '是否开启灵感提示',
    realtime_comment TINYINT(1) DEFAULT 1 COMMENT '是否开启实时点评',
    creator_id      VARCHAR(50) NOT NULL,
    time_created    BIGINT(20) NOT NULL,
    updater_id      VARCHAR(50),
    time_updated    BIGINT(20),
    PRIMARY KEY (id),
    KEY idx_plan (plan_id),
    KEY idx_script (script_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 20. RAG 检索历史
-- ----------------------------------------------------------
CREATE TABLE tra_rag_history (
    id              BIGINT(20) NOT NULL AUTO_INCREMENT,
    business_id     BIGINT(20) NOT NULL,
    session_id      BIGINT(20) NOT NULL,
    round_number    INT,
    call_type       VARCHAR(30) COMMENT 'DIALOGUE/INSPIRATION/POLISH',
    query           TEXT COMMENT '检索query',
    rag_response    MEDIUMTEXT COMMENT 'RAG返回结果',
    latency_ms      BIGINT(20),
    time_created    BIGINT(20) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_session (session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
