-- Notiee 免费版后端建表脚本
-- 在 TencentDB MySQL 里先建库再执行：CREATE DATABASE notiee DEFAULT CHARSET utf8mb4;

-- 用户表：一个 Apple sub 一行
CREATE TABLE IF NOT EXISTS users (
  id             VARCHAR(64)  NOT NULL PRIMARY KEY,     -- Apple identityToken 里的 sub
  tier           VARCHAR(16)  NOT NULL DEFAULT 'free',  -- free / pro
  pro_expires_at DATETIME     NULL,                     -- Pro 到期时间（订阅用）
  email          VARCHAR(255) NULL,                     -- 仅 Apple 首次登录返回
  created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 月度用量账本：按 (用户, 年月) 一行，天然按月重置
CREATE TABLE IF NOT EXISTS usage_monthly (
  user_id      VARCHAR(64) NOT NULL,
  `year_month` CHAR(6)     NOT NULL,                    -- 如 202607（UTC）
  notes_count  INT         NOT NULL DEFAULT 0,          -- 已用「篇」数 = 额度口径
  real_tokens  BIGINT      NOT NULL DEFAULT 0,          -- 真实 token（成本对账，不展示）
  PRIMARY KEY (user_id, `year_month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 原始交易 → 用户 映射（App Store 通知按 original_transaction_id 回查用户）
CREATE TABLE IF NOT EXISTS subscriptions (
  original_transaction_id VARCHAR(64) NOT NULL PRIMARY KEY,
  user_id                 VARCHAR(64) NOT NULL,
  expires_at              DATETIME    NULL,
  updated_at              DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_sub_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
