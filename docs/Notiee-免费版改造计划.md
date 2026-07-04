# Notiee 免费版改造计划

> 目标：在现有代码（本质是 Notiee+ 的 BYOK 形态）之上，为 **Notiee 免费版**新增「后端代付 AI + Apple 登录鉴权 + 订阅 Pro」这条线，与 Notiee+ 共享同一份源码、靠 target 与编译标志隔离。

---

## 1. 两个版本的定位

| | Notiee+（现状，别动） | Notiee 免费版（本计划） |
|---|---|---|
| 商业模式 | 一次买断（BYOK 壳） | 免费下载 + 订阅 Pro ¥18/月 |
| AI 来源 | 用户填 endpoint+key，直连模型厂商 | 走**自建后端**代付，客户端只送 model ID |
| Key 位置 | 用户设备 | **后端**（客户端永远拿不到） |
| 调用链路 | 客户端 → 模型厂商 | 客户端 → 后端 → 模型厂商 |
| 登录 | 可选、轻量 | **必须 Apple 登录**（鉴权命门） |

隔离机制：
- 免费版**独有**的新文件 → **只勾 Notiee target**（Notiee+ 里根本不存在）。
- 两版都要编译、只是走不同分支 → **`#if NOTIEE_PLUS`**。
- 共享文件**严禁**写 `if 免费版 {}` 之类散落判断。
- 已有中心化 `AppBranding`（`#if NOTIEE_PLUS`）是范式，沿用。

---

## 2. 免费版模型目录

客户端只选 model ID，key 在后端。

### 文本模型（价格高 → 低）
| 显示名 | model ID | 档位 |
|---|---|---|
| MiniMax M3 | `MiniMax-M3` | Pro |
| MiniMax M2.7-highspeed | `MiniMax-M2.7-highspeed` | Pro |
| MiniMax M2.7 | `MiniMax-M2.7` | Pro |
| DeepSeek v4-pro | `deepseek-v4-pro` | Pro |
| **DeepSeek v4-flash** | `deepseek-v4-flash` | **免费试用** |

### 视觉模型（仅豆包）
| 显示名 | model ID | 档位 |
|---|---|---|
| Doubao-Seed-2.0-mini | `doubao-seed-2-0-mini` | 免费 |
| Doubao-Seed-2.0-lite | `doubao-seed-2-0-lite` | Pro |
| Doubao-Seed-2.1-Pro | `doubao-seed-2-1-pro` | Pro |

### Spark 档位差异（已定）
| | 免费档 | Pro |
|---|---|---|
| 可用模型 | 仅 `deepseek-v4-flash` | 全部文本模型 |
| 记忆上限 | 5 条 | 不限 |
| 单会话轮数 | 20 轮 | 不限 |
| Agent 模式 | ❌ | ✅ |

### 厂商接入格式（后端配置，客户端不碰）
- **MiniMax**：Anthropic 兼容 `https://api.minimaxi.com/anthropic/v1/messages`，`Authorization: Bearer <key>`。
- **DeepSeek**：OpenAI 兼容 `https://api.deepseek.com`，模型 `deepseek-v4-flash` / `deepseek-v4-pro`。
- **豆包**：火山引擎 ark，切模型只改 `model` 字段。

---

## 3. 额度方案

**原则**：客户端「不判断，只显示后端给的数字」。额度真值、扣减、防刷全在后端。

- 展示口径：**「本月 X / N 篇」绝对数字 + 进度环装饰**。不用纯百分比——Notiee 有天然可数单位「篇」，比百分比更透明。
- 计费口径：**扁平计费**，一篇扣一篇，不分模型。成本差异由「免费档锁死便宜模型 + 后端真实 token 记账」消化，留日后切积分制的口子。
- 兜底：免费额度用尽 → **自动降级本地 OCR**（复用已有 `LocalOCRService` / 低消耗模式），而非硬堵。
- **Spark 不占「篇」额度**（已定）：「篇」只计拍照记笔记。免费档 Spark 靠结构限制兜底（仅 flash、单会话 20 轮、记忆 5 条、无 Agent，见 §2），后端对 Spark 接口按用户做频控防刷。

### Spark 公平频控（已定方向，数字可调）

目的是防脚本和共享账号，不是计费——数字定在「正常重度用户碰不到，脚本一天撞墙」的位置。**计量单位 = 模型调用次数**（普通对话一轮 1 次；Agent 一轮含工具循环，可能 2–5 次），后端按请求记账，天然覆盖 Agent。

| | 免费档 | Pro |
|---|---|---|
| 脚本防线（用户无感知） | 10 次/分钟 | 15 次/分钟、150 次/小时 |
| 日/月上限 | 30 次/天 | **3000 次/月**（≈ 普通对话 100 轮/天连续一个月） |
| 高价模型子上限 | —（只有 flash） | 后端可配单模型上限（如 M3 600 次/月），超出自动切下一档模型 |
| 触顶行为 | 当日到点，次日恢复 | **降级 flash + 关 Agent**，下月恢复——不硬堵，和「篇用尽降级本地 OCR」同哲学 |
| 展示 | 不展示 | 平时不展示，用到 80% 在 Spark 内提示一次（真值在后端） |

**待拍板数字**：免费档 30 篇/月（建议）、Pro 300 篇/月（公平上限，建议）。

---

## 4. 文件级工作清单

图例：🆕 新建 · ✏️ 改 · **[N]** 只勾 Notiee · **[both+#if]** `#if NOTIEE_PLUS` 分叉 · **[共享]** 不动

### Phase 0 · AI 服务分叉（对接真后端 `notiee-ping-stream`）

> **现状更新（2026-07-04）**：后端骨架已建在 `notiee-ping-stream/`（Express，SCF 部署，非流式），接口契约已定——Phase 0 不再是「假后端 stub」，直接按真契约开发。本地联调：`ALLOW_FAKE_APPLE=1 node index.js`，客户端 DEBUG 构建用 `fake-` 开头的假 identityToken 走 `POST /auth/apple` 换**真 JWT**，不用等 Phase 1 就能端到端跑通。

**后端接口契约**（`error.code` 统一为 `{ error: { code, message } }`）：
| 端点 | 请求 | 响应 |
|---|---|---|
| `POST /auth/apple` | `{identityToken, rawNonce?}` | `{token, userId, email?}`（JWT 30 天） |
| `GET /me/quota` | Bearer | `{tier, used, limit, remaining}` |
| `POST /ai/chat` | `{messages, model, system?}` | `{text, tokensUsed}` |
| `POST /ai/process` | `{images: base64[], visionModel, textModel, visionPrompt?, textPrompt?, systemVision?, systemText?}` | `{ocrText, content, tokensUsed, quota}` |

| 文件 | 动作 | 机制 |
|---|---|---|
| `Features/Spark/SparkAIService.swift` | ✏️ **先拆协议**：`SparkAIServing` 目前混着网络调用（`ask`/`agentChat`/标题生成）与纯本地解析（`extractMemory`/`extractCitations` 等）。把本地解析拆出去（或让 Backend 版组合复用现有实现），Backend 版只重写网络部分 | [共享重构] |
| `Services/BackendAPIClient.swift` | 🆕 baseURL + Bearer 注入 + 错误解码成 typed enum（`UNAUTHORIZED` / `UPGRADE_REQUIRED` / `QUOTA_EXCEEDED` / `BAD_MODEL` / `UPSTREAM_ERROR`）+ 长超时：`/ai/process` 串行两次上游（各 60s），客户端 timeout 给 ≥150s | [N] |
| DEBUG 假登录 bootstrap | 🆕 DEBUG-only：`POST /auth/apple` 传 `fake-<稳定设备串>` 换 JWT，Phase 1 换成真 AuthService，同一个存取口子 | [N] |
| `Services/BackendAIProcessingService.swift` | 🆕 复用现有 resize/compress → base64（**无 `data:` 前缀**）→ `POST /ai/process`，vision/text 提示沿用现有拼装；`content` 沿用 `extractJSONObject` 解析；**body 预算 <10MB**（API 网关上限），多图降质/限张数 | [N] |
| `Features/Spark/BackendSparkAIService.swift` | 🆕 `ask` → `POST /ai/chat`；`agentChat` 先 throw「暂不支持」——后端还没有 tools 透传（见下方缺口） | [N] |
| `Services/NotieeStore.swift` `:90` `:489` | ✏️ 注入点 `RealAIProcessingService()` → `#if` 二选一 | [both+#if] |
| `Features/Spark/SparkViewModel.swift` `:76` | ✏️ `SparkAIService()` → `#if` 分叉 | [both+#if] |

> 完成后免费版能编译，验证未被 BYOK 代码污染。
>
> **Phase 0 注意事项**：
> - `402 QUOTA_EXCEEDED` → 本地 OCR 降级的触发点在这里埋好（UI 在 Phase 3 接）。
> - `/ai/process` 响应捎带 `quota` → 直接喂 EntitlementStore 展示态，省一次 `/me/quota` 拉取。
> - 模型 ID 字符串必须与后端 `MODEL_CATALOG` 完全一致（如 `MiniMax-M2.7` 带点）。
> - SCF 执行超时要配 ≥150s（两次上游串行，各 60s）。
>
> **后端已知缺口（对应 §7）**：① `/ai/chat` 不支持 `tools`/`tool_calls` 透传——**Pro 档 Agent 模式（Phase 2.5）前必须补**，且 OpenAI/Anthropic 两种格式都要适配；② 建议加 `/auth/refresh`——JWT 30 天到期后 Apple 登录无法静默重签（必须用户手点），应允许旧 token 未过期时换新续期；③ system prompt 注入/校验、Spark 频控还是 TODO；④ 数据层是内存 Map，上线前换 TDSQL。

### Phase 1 · Apple 登录换后端 token

> **现状更新（2026-07）**：客户端 Apple 登录已在 `db56341` 完成——两个 target 都是真 Sign in with Apple（官方按钮 + entitlements + `AccountStore.appleLogin`）。但回调只存了 `appleUserID`，**没有取 `identityToken` / `authorizationCode`**；它们是短时效凭证，换后端 token 必须在登录回调当场做。本 Phase 的剩余工作如下。

| 文件 | 动作 | 机制 |
|---|---|---|
| `Services/AuthService.swift` | 🆕 登录回调内用 `identityToken` 换后端 session（**`POST /auth/apple` 已就绪**）；带 **rawNonce 防重放**：客户端生成 rawNonce，`request.nonce = sha256(rawNonce)`，rawNonce 随请求发后端比对；token 存 **Keychain**（不进 UserDefaults）；续期走 `/auth/refresh`（后端待加，见 Phase 0 缺口②） | [N] |
| `Features/Settings/LoginView.swift` | ✏️ ASAuthorization 回调把 credential 交给 AuthService（免费版分支） | [both+#if] |
| `Services/AccountStore.swift` | ✏️ 免费版 profile 关联后端账户 | [both+#if] |
| Phase 0 两个 Backend service | ✏️ 请求头带后端 token | [N] |
| 账号注销 | 🆕 设置内删除账户：后端删数 + Apple token revoke——**审核 5.1.1(v) 硬要求**，有登录+订阅必须有注销 | [N] |

### Phase 2 · 模型目录 + 选模型界面
| 文件 | 动作 | 机制 |
|---|---|---|
| `Models/CuratedModelCatalog.swift` | 🆕 ID + 名 + 档位，不带 key/endpoint。**内置目录只作 fallback，运行时以后端下发为准**；model ID 用字符串透传、容忍未知值——模型下线/换名不用发版 | [N] |
| `Features/Settings/ModelPickerView.swift` | 🆕 选模型页，Pro 模型加锁标 | [N] |
| `Features/Settings/SettingsMainView.swift` `:68` `:164` | ✏️ + 显示 BYOK 配置；免费显示 ModelPicker | [both+#if] |
| `Features/Settings/SparkSettingsView.swift` | ✏️ 免费版走精选目录 | [both+#if] |

> `AIConfigurationView` / `CustomModelsListView` / `AIModelConfiguration` / `AIProvider` 保持 [共享]，免费版不给入口。

### Phase 2.5 · Spark 档位限制

> 注意：**免费档 vs Pro 是运行时概念（看 EntitlementStore），不是编译标志**。为了不违反「共享文件严禁散落 if 判断」原则，所有限额收敛到一个中心出口，沿用 `AppBranding` 范式。

| 文件 | 动作 | 机制 |
|---|---|---|
| `Features/Spark/SparkTierLimits.swift` | 🆕 中心化限额出口（模型白名单 / 单会话轮数 / 记忆条数 / Agent 开关）：Notiee+ 分支恒为「不限」，免费版读 `EntitlementStore` 档位 | [both+#if]（仅此一处分叉） |
| `Features/Spark/SparkModelPreferences.swift` | ✏️ 读 SparkTierLimits：免费档锁 `deepseek-v4-flash` | [共享，只读中心出口] |
| `Features/Spark/SparkViewModel.swift` | ✏️ 单会话 20 轮上限，触顶提示新开会话 / 升级 Pro | [共享，只读中心出口] |
| `Features/Spark/SparkMemoryStore.swift` | ✏️ 记忆上限 5 条 | [共享，只读中心出口] |
| `Features/Settings/AgentSettingsView.swift` | ✏️ Agent 模式仅 Pro：免费档加锁标 → 付费墙 | [共享，只读中心出口] |

> `EntitlementStore` 到 Phase 4 才有真值——此前免费版分支可先硬编码「免费档」，Phase 4 接上即可。客户端限制只是 UX；**后端要按档位再校验一遍**模型 / Agent 请求，否则改包即可绕过。

### Phase 3 · 额度展示（「我」tab + 回顾重做）
| 文件 | 动作 | 机制 |
|---|---|---|
| `Features/Settings/QuotaCard.swift` | 🆕 额度环 + 「本月 X/N 篇」+ Pro 入口 | [N] |
| `Features/Settings/MeView.swift` | ✏️ 账户区下插 QuotaCard（仅免费版） | [both+#if] |
| `Features/Settings/UsageReviewView.swift` | 🆕 篇数版回顾（额度环 + 按日程篇数占比） | [N] |
| `Features/Settings/MeView.swift` `:96` 回顾入口 | ✏️ `#if` 决定 push ReviewView(+) 还是 UsageReviewView(免费) | [both+#if] |
| QuotaCard / AI 入口 | ✏️ 断网、后端不可用、token 失效三种状态的展示与重试（额度用尽降级 OCR 之外的兜底） | [N] |

> `ReviewView`（token 版回顾）保持 [共享]，只给 Notiee+。篇数 = 时间范围内 `NoteRecord` 计数，数据层不重做。

### Phase 4 · 订阅/内购
| 文件 | 动作 | 机制 |
|---|---|---|
| `Services/EntitlementStore.swift` | 🆕 缓存档位+剩余额度展示态，真值来自后端；需能表达**宽限期（Billing Grace Period）/ 已过期**中间态 | [N] |
| `Services/StoreKitService.swift` | 🆕 StoreKit 2 购买/恢复，凭证上报后端 | [N] |
| `Features/Settings/PaywallView.swift` | 🆕 付费墙 ¥18/月：**审核 3.1.2 要求**写明价格、周期、自动续订条款，附 EULA + 隐私政策链接；带「恢复购买」入口 | [N] |
| `QuotaCard` / `ModelPickerView` / Spark 锁点 | ✏️ 挂付费墙触发 | [N] |
| StoreKit Configuration 文件 | ⚙️ 本地沙盒测试订阅流程，不依赖 App Store Connect 联调 | 配置 |
| App Store Connect | ⚙️ 配订阅产品 | 配置 |

> 额度扣减、收据校验不进客户端。

### 完全不动
笔记/存储/拍摄/OCR/日历/加密/同步/导入导出/所有笔记浏览 UI/Widget。

---

## 5. 建议动手顺序
Phase 0 → 1 → 2 → 3 → 4。地基（0）立起来后每步都能编译验证；前 3 步完成即「能用后端 AI 的可用 App」，Phase 4 才锁上商业闭环。

---

## 6. App Store Connect 配置（见 §7 详解）
- App 内购买项目：自动续期订阅（Auto-Renewable Subscription），¥18/月。
- 订阅群组（Subscription Group）：Notiee Pro。
- Sign in with Apple 能力（已在 Xcode 侧配好 entitlements）。
- App Store Server Notifications V2 回调后端。
- **App Privacy 标签按免费版数据流重填**（见 §8）。

## 7. 后端建设（骨架已建：`notiee-ping-stream/`，Express + SCF）
五个能力（✅ 已有 / ⬜ 待做）：
1. Apple 身份校验：✅ 验签（apple-signin-auth，支持 nonce）+ 自有 JWT；⬜ `/auth/refresh` 续期、⬜ Apple revoke 通知处理、⬜ 账号注销删数。
2. AI 代理：✅ `/ai/chat` + `/ai/process`（模型白名单、档位校验、断连 abort 上游）；⬜ system prompt 注入/校验、⬜ **tools 透传（Pro Agent 前必须）**。
3. 额度账本：✅ 篇数扣减（成功后扣）+ 402 拦截；⬜ 真实 token 记账入库、⬜ 数据层换 TDSQL（现为内存 Map，重启即丢）。
4. 订阅校验：⬜ 全部（`/subscription/verify` 与 `/apple/notifications` 只有骨架，Phase 4 做）。
5. 防刷：⬜ 全部——DeviceCheck/App Attest + 按用户频控；Spark 按「模型调用次数」单独记账（数值见 §3），不走篇数账本。
另：⬜ `JWT_SECRET` 等生产环境变量落 SCF 配置（当前有 dev 默认值，生产必须换）。

## 8. 合规清单与待拍板

**合规（免费版数据流与 BYOK 完全不同，不能沿用现有文案）**
- 账号注销：应用内删除账户 + Apple token revoke（审核 5.1.1(v)，已列入 Phase 1）。
- 隐私政策 & App Privacy 标签重写：免费版会把笔记图片、Spark 上下文（最多 150 条笔记全文 + 日程）发到自建后端。
- 后端若部署境内：ICP 备案。
- 付费墙 3.1.2 文案 + 恢复购买（已列入 Phase 4）。

**待拍板**
- 免费 30 篇 / Pro 300 篇的具体数字。
- ~~老用户方案~~ **已确认无此问题（2026-07-04）**：Notiee（`com.idbetterrun.notiee`）与 Notiee+（`com.idbetterrun.notieeplus`）两个独立 App 分别上架，且目前**均未上架**——没有历史买断用户，EntitlementStore 与后端账户模型不需要 grandfathering 逻辑。
