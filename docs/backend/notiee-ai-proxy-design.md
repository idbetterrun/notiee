# Notiee AI 代理后端 · MVP 设计文档

> 状态：草案 v0.1 · 2026-07-01
> 作者：Notiee 团队
> 范围：为 **Notiee（免费/Pro）** 客户端提供托管 AI 能力的后端代理。**Notiee+（买断 BYOK）不依赖本后端**。
> 🔲 = 待你拍板的参数/决策。

---

## 1. 背景与目标

Notiee 免费/Pro 版内置 AI（拍记总结、Spark 对话、语义搜索），由官方替用户调用第三方大模型（DeepSeek / 智谱 GLM / 豆包 / MiniMax）。因此**不能把 provider API Key 打进客户端**，所有 AI 调用必须经过官方后端代理。

本后端要解决四件靠"发版"解决不了的事：

1. **持密钥代理**：后端持有各 provider 的 Key，客户端永远拿不到。
2. **远程可控**：模型开关、额度、熔断随时改，不发版。
3. **鉴权与限额**：区分免费/Pro 用户，按成本计量、按月限额，防白嫖与滥用。
4. **成本护栏**：全局与单用户花费上限，防 bug/攻击把账单打爆。

### 非目标（MVP 明确不做）
- ❌ 自建账号/密码体系（用苹果原生身份，见 §5）。
- ❌ 用户笔记数据的云端存储/同步（同步是客户端 iCloud 的事，与本后端无关）。
- ❌ 训练/托管任何自有模型。
- ❌ 全球多区域部署（先国内单区；新加坡阶段见 §14）。

---

## 2. 部署范围与阶段策略

- **首发**：Notiee+（买断 BYOK）先送审上架，**不依赖本后端**，后端不阻塞首发。
- **本后端服务对象**：仅 Notiee 免费/Pro。就绪并稳定后，Notiee 免费/Pro 再上架。
- **地域**：先**国内 Serverless**；作者赴新加坡后再做全球版（§14）。

---

## 3. 架构总览

```
┌─────────────┐        ①启动拉配置          ┌──────────────────────────┐
│  Notiee App │ ───────────────────────────▶ │  GET /config              │
│ (免费/Pro)  │                              │   (模型池/额度/公告/熔断) │
│             │        ②AI 请求(带凭证)      ├──────────────────────────┤
│             │ ───────────────────────────▶ │  POST /ai/chat            │
│             │                              │  POST /ai/embed           │
│             │ ◀───── SSE 流式返回 ──────── │                          │
└─────────────┘                              │                          │
                                             │  鉴权 → 限额 → 转发 → 计量 │
                                             └────────────┬─────────────┘
                                                          │
                          ┌───────────────────────────────┼───────────────────────────┐
                          ▼                ▼               ▼               ▼            ▼
                     DeepSeek        智谱 GLM         豆包(Ark)        MiniMax     (Redis/KV
                    api.deepseek     open.bigmodel   ark...volces     minimaxi      额度+配置)
```

请求生命周期（`/ai/chat`）：
```
验凭证(App Attest 免费 / StoreKit JWS Pro) → 解析 userId + tier
  → 读远程配置：该 tier 允许此模型？额度？是否熔断？
  → 查 Redis：本月成本是否超限 → 超则 402
  → 选 provider 适配器，转发（透传 SSE 流）
  → 流结束：usage.tokens × 单价 → 原子累加进 Redis
```

---

## 4. 技术选型（国内阶段）

| 组件 | 选型 | 说明 |
|---|---|---|
| 计算 | 🔲 阿里云函数计算 FC **或** 腾讯云云函数 SCF | 二选一。单人运维选 Serverless，别开 VPS。需支持**流式响应/SSE**（两者都支持，FC 用 "HTTP 触发器 + 响应流"，SCF 用 "Response Streaming"）。 |
| 状态存储 | 🔲 阿里云 Redis **或** Upstash（国内可用性存疑，倾向阿里云 Redis） | 存额度计数、App Attest 公钥、会话 token。要求**原子自增**。 |
| 远程配置 | Redis 里一个 JSON key，或对象存储 OSS 上一个 JSON | `/config` 直接读它。改配置=改这个 JSON。 |
| 密钥管理 | 🔲 阿里云 KMS / 凭据管家（或 SCF 环境变量加密） | provider Key 绝不硬编码、不进代码仓库。 |
| 语言 | 🔲 Node/TypeScript（推荐，生态最全、SSE 好写） 或 Go | 看你熟悉度。 |
| 域名 | 自有域名 + HTTPS | 需 **ICP 备案**（见 §12）。 |

> **为什么 Serverless**：AI 请求是突发、IO 密集、长连接（流式）。Serverless 按量付费、免运维、天然弹性。唯一要确认的坑是"函数超时时长要够长（流式对话可能几十秒）"和"支持响应流"。

---

## 5. 鉴权设计（核心 · 不自建账号）

两类用户打后端，用两套**苹果原生机制**，都不需要密码/注册。

### 5.1 Pro 订阅用户 → StoreKit 2 已签名交易（JWS）
- 客户端用 StoreKit 2 拿到当前订阅的 `Transaction`（JWS 字符串，Apple 用 ES256 签名，头部 `x5c` 是到 Apple Root CA 的证书链）。
- 客户端把该 JWS 放进请求头 `X-Notiee-Subscription: <JWS>`。
- 后端验证：
  1. 解析 JWS header 的 `x5c` 证书链，**验签到 Apple Root CA**（Apple 公开根证书，离线可验）。
  2. 校验 payload：`bundleId` 匹配、`productId` ∈ 你的订阅产品、`expiresDate > now`、环境（Sandbox/Production）匹配。
  3. 取 `originalTransactionId` 作为**稳定用户 id**（同一 Apple ID 续订也不变）。
     - 可选：购买时设置 `appAccountToken`(UUID)，用它当 userId，跨设备更干净。🔲
- **性能优化**：首次验签后，签发一个**短时 session token**（JWT，30 min，含 `userId`/`tier`），客户端后续请求带 session token，避免每次都验 JWS + 打 App Store Server API。

> 说明：JWS 本地验签即可确认"这是苹果签发的有效订阅"。是否额外调 **App Store Server API** 做实时状态查询（如已退款/已取消）视需要，MVP 可先只本地验签 + 依赖 `expiresDate`，退款滥用后续再补。

### 5.2 免费用户 → App Attest（防白嫖）
免费用户**没有订阅可证明身份**，但仍要用你的后端跑 DeepSeek-flash。若不设防，`/ai/chat` 就是一个公开免费 AI API，会被脚本刷干。

- 客户端用 `DCAppAttestService`：
  1. 首次生成一对密钥 + attestation，后端**验证 attestation**（验到 Apple App Attest Root CA），存下该设备公钥 + 一个 `deviceId`。
  2. 之后每个请求带一个用该私钥签名的 **assertion**，后端用存的公钥验签 + 校验 challenge/counter 防重放。
- 后端按 `deviceId` 做**每日免费额度**限流。
- ⚠️ **免费额度越诱人，越必须有 App Attest 兜底。** 这条不做，成本不可控。

### 5.3 身份汇总
| 用户类型 | 凭证 | 后端 userId | 限额口径 |
|---|---|---|---|
| 免费 | App Attest assertion | `deviceId` | 每日次数（§7） |
| Pro | StoreKit JWS → session token | `originalTransactionId`（或 appAccountToken） | 每月成本额度（§7） |

---

## 6. 端点契约

所有响应统一错误结构：
```json
{ "error": { "code": "QUOTA_EXCEEDED", "message": "本月 AI 额度已用完", "upgrade": true } }
```
错误码：`UNAUTHORIZED` `ATTEST_FAILED` `MODEL_NOT_ALLOWED` `QUOTA_EXCEEDED` `RATE_LIMITED` `KILL_SWITCH` `UPSTREAM_ERROR`。

### 6.1 `GET /config`
客户端启动 & 每 N 小时拉一次。**远程控制的抓手。**
```json
{
  "version": 7,
  "killSwitch": false,
  "announcement": null,
  "models": {
    "text": [
      { "id": "deepseek-v4-flash", "display": "DeepSeek V4 Flash", "tiers": ["free","pro"] },
      { "id": "deepseek-v4-pro",   "display": "DeepSeek V4 Pro",   "tiers": ["pro"] },
      { "id": "minimax-m3",        "display": "MiniMax M3",        "tiers": ["pro"] },
      { "id": "glm-5",             "display": "GLM-5",             "tiers": ["pro"] }
    ],
    "vision": [
      { "id": "glm-4.6v",          "display": "GLM-4.6V",          "tiers": ["pro"] },
      { "id": "doubao-2.0-lite",   "display": "Doubao 2.0 Lite",   "tiers": ["pro"] },
      { "id": "minimax-vl",        "display": "MiniMax VL",        "tiers": ["pro"] }
    ]
  },
  "quota": {
    "free":  { "dailyChat": 5, "dailyAIProcess": 3, "allowedModels": ["deepseek-v4-flash"], "semanticSearch": "localOnly" },
    "pro":   { "monthlyCostBudgetCents": 500, "visionSubBudgetCents": 200 }
  }
}
```
> 🔲 免费视觉是否允许？当前假设**免费视觉走端侧 OCR、不调云端视觉模型**（省钱）。若要给免费云端视觉，加进 `free.allowedModels`。

### 6.2 `POST /ai/chat`
```json
// 请求
{
  "model": "deepseek-v4-flash",
  "messages": [ { "role": "user", "content": "..." } ],
  "stream": true,
  "purpose": "spark" // spark | summary | ...（用于分类计量/审计）
}
// 请求头： X-Notiee-Session: <jwt>  或  X-Notiee-Attest: <assertion>
```
- 成功：**SSE 流**（OpenAI 兼容的 `data: {...}` 分片），末尾带一条包含 `usage` 的事件，供客户端展示 & 后端计量。
- 失败：非 2xx + 上面的错误结构。

### 6.3 `POST /ai/embed`
语义搜索用（仅 Pro 走云端；免费走端侧）。
```json
{ "model": "embedding-v1", "input": ["文本1","文本2"] }
→ { "vectors": [[...],[...]], "usage": { "tokens": 123 } }
```

---

## 7. 计量与限额

### 7.1 原则：内部按"钱"计量，对用户展示成"额度条"
不同模型价差数倍，按次数会被贵模型吃穿。**统一算 `Σ(tokens × 单价)` 累计成本（分）**，达到预算即限流。

### 7.2 Redis 数据结构
```
# Pro：按月成本（分）
usage:pro:<userId>:<YYYYMM>            → 累计成本(分)，INCRBY 原子累加，key 设 35 天 TTL
usage:pro:<userId>:<YYYYMM>:vision     → 视觉子预算单独计（防刷贵模型）

# 免费：按日次数
usage:free:<deviceId>:<YYYYMMDD>:chat    → 次数，INCR，24h TTL
usage:free:<deviceId>:<YYYYMMDD>:process → 次数，INCR，24h TTL

# App Attest 公钥 & 防重放
attest:<deviceId>  → { publicKey, signCount }
```

### 7.3 扣费时序（先转发后计量）
1. 请求进来 → 读当前用量，**若已超预算直接 402**（先拦一道）。
2. 未超 → 转发 provider，流式返回。
3. 流结束拿到 `usage.tokens` → `INCRBY` 累加成本。
4. 允许**轻微超支**（最后一次请求可能略超预算）——可接受，避免复杂的预扣/回滚。

### 7.4 额度数值（🔲 待定，先给公式和示意）
```
每用户月 AI 成本上限 = 订阅价 × (1 − 苹果抽成) − 分摊基建 − 目标毛利
```
示意：Pro ¥18/月，抽成 15% → 到手 ¥15.3，留 65% 毛利 → **AI 预算 ≈ ¥5/月/用户**（= `monthlyCostBudgetCents: 500`）。
- 🔲 订阅价、🔲 目标毛利、🔲 各 provider 真实单价 → 填进公式即得预算。
- 贵模型（GLM-5 / 视觉）再设**子预算**（`visionSubBudgetCents`），防有人专挑贵的刷。
- 免费：🔲 `dailyChat=5` / `dailyAIProcess=3`，仅 `deepseek-v4-flash`。

---

## 8. 远程配置 Schema

即 §6.1 的 `/config` 响应体，存在 Redis/OSS 的一个 JSON，改它即生效。可控项：
- `killSwitch`：全局熔断（AI 全部返回 `KILL_SWITCH`，客户端提示"AI 维护中"）。
- `models`：增删模型、调整每个模型对哪些 tier 开放——**上新模型不用发版**。
- `quota`：免费/Pro 的额度参数随时调。
- `announcement`：公告条（如"今日 DeepSeek 波动，已切备用"）。
- 🔲 是否加 `providerRouting`（同一逻辑模型 id 后端可切不同 provider 做灾备）——建议 v0.2 再加。

---

## 9. 成本护栏与安全

- **全局每日花费上限**（circuit breaker）：所有用户累计成本达 🔲 `¥X/日` → 触发 `killSwitch`，报警。防 bug/攻击跑飞。
- **单用户/单设备速率限制**：除额度外，加"每分钟 N 次"防并发刷。
- **provider Key 管理**：只存 KMS/加密环境变量，代码仓库零明文。
- **输入大小限制**：`messages` 总长、`input` 条数上限，防超大请求 OOM/高费。
- **防重放**：App Attest assertion 带 challenge + counter 单调递增校验。
- **日志脱敏**：见 §10。

---

## 10. 数据与隐私

- **不落用户内容**：`messages` / 笔记正文**不写日志、不入库**。只记元数据：`userId`(hash)、`model`、`purpose`、`tokens`、`cost`、`latency`、`status`。
- provider 侧：审计各 provider 的数据留存政策，隐私政策里如实披露"AI 请求经官方服务器转发至第三方模型提供商"。
- 与客户端隐私政策一致：官方托管 AI **会经过服务器**（不同于 BYOK 直连）——这点必须在 Notiee 隐私政策明确写清（Notiee+ 是直连、Notiee 是代理）。

---

## 11. 可观测性

MVP 最小指标（够你看健康度和成本）：
- **成本**：按天/按模型/按 tier 的累计 `cost`。
- **错误率**：`UPSTREAM_ERROR` 占比、各 provider 分开看。
- **延迟**：首字节时间（流式体验关键）、P95。
- **额度**：触发 `QUOTA_EXCEEDED` 的用户数（转化信号）。
- 报警：全局日成本超阈值、错误率突增、killSwitch 触发。
- 工具：🔲 云厂商自带监控（FC/SCF 日志+指标）起步即可，别一上来上 Grafana。

---

## 12. 合规（国内特有 · 必须重视）

- **ICP 备案**：面向大陆、用国内云 + 自有域名 → 需 ICP 备案（一次性流程，有周期，尽早启动）。
- ⚠️ **生成式 AI 服务合规**：对外提供生成式 AI 能力受《生成式人工智能服务管理暂行办法》约束，可能需要**大模型服务备案/算法备案**，并落实**内容安全审核**（输入输出过滤）。
  - 缓解：优先依赖各 provider 内置的内容安全能力，并确认其**允许你转售/代调用**给 C 端；但作为服务运营方你仍有主体责任。
  - 🔲 **这是法律事项，建议上线前咨询专业意见**——本文档不构成法律建议。
- provider 商务条款：确认 DeepSeek/GLM/豆包/MiniMax 的 API 是否允许"代 C 端用户调用"的商用形态、是否需要企业实名/资质。

---

## 13. 里程碑（分期，避免一口吃成胖子）

**M0 · 打通闭环（最小）**
- `/config` + `/ai/chat`，只接 **DeepSeek-flash 一个模型**。
- Pro 用 StoreKit JWS 验签 + session token；免费用 App Attest。
- Redis 成本计量 + 月度/日度限额。
- 全局日成本护栏 + killSwitch。

**M1 · 模型池 & 视觉**
- 接入 GLM-5 / MiniMax M3 / DeepSeek-Pro（文本）+ GLM-4.6V / 豆包 / MiniMax VL（视觉）。
- 视觉子预算。`/ai/embed`（Pro 云端语义搜索）。

**M2 · 韧性 & 运营**
- provider 灾备路由、退款/取消状态核查（App Store Server API + 通知）、更完善的监控报警。

---

## 14. 未来：全球化（新加坡阶段）

赴新加坡后做全球版时的预留考虑（现在不实现，但设计上别堵死）：
- 计算迁 **Cloudflare Workers / Fly.io**（国内那套 SSE 透传、鉴权、计量逻辑基本可平移）。
- 数据合规切到 GDPR/PDPA 口径。
- 模型池可能补国际模型（Claude / GPT / Gemini），`/config` 的 `models` 结构已支持无痛扩展。
- 鉴权（StoreKit JWS / App Attest）**全球通用，无需改**。
- 抽象要点：把"provider 适配器"和"托管区域/合规策略"做成可插拔，避免与国内实现耦合。

---

## 15. 待你拍板的决策清单（🔲 汇总）

1. 计算平台：阿里云 FC vs 腾讯云 SCF？
2. 后端语言：Node/TS vs Go？
3. Pro 订阅定价 & 目标毛利 → 定 `monthlyCostBudgetCents`。
4. 免费日额度：chat=5 / process=3 是否合适？
5. 免费是否允许云端视觉（默认否，走端侧 OCR）。
6. userId 用 `originalTransactionId` 还是购买时写入的 `appAccountToken`。
7. 全局日成本熔断阈值 `¥X/日`。
8. 合规：ICP 备案 + 生成式 AI 备案 谁来推进、何时启动（**关键路径，越早越好**）。
9. 各 provider 真实单价 & 商用条款确认。

---

## 附录 A · 关键流程伪代码（/ai/chat）

```pseudo
handler(req):
    cfg = loadConfig()
    if cfg.killSwitch: return 503 KILL_SWITCH

    (userId, tier, quotaKind) = authenticate(req)      # JWS→session 或 App Attest
    if not authorized: return 401

    model = req.model
    if model not in cfg.allowedModelsFor(tier): return 403 MODEL_NOT_ALLOWED

    if quotaExceeded(userId, tier, model, cfg): return 402 QUOTA_EXCEEDED
    if rateLimited(userId): return 429 RATE_LIMITED

    provider = adapterFor(model)                        # OpenAI 兼容优先，特殊的单独适配
    stream = provider.chat(req.messages, stream=true)   # 持后端 Key

    usage = pipeThrough(stream → client as SSE)          # 透传，边转边发
    cost  = usage.tokens * priceOf(model)
    redisIncrCost(userId, tier, model, cost)             # 原子累加
    logMetrics(userId_hash, model, req.purpose, usage, cost, latency)  # 不记内容
```
