# Notiee Privacy Policy

**Version: v1.0.7**
**Effective Date: August 6, 2026**

---

## 1. Introduction

We take your privacy very seriously. This Privacy Policy aims to transparently explain what information Notiee (hereinafter referred to as "the App") collects, how it uses that information, and how your data security is protected.

**Core Principle: Your data remains in your hands.** The App is a local-first tool application. All your records, notes, and conversations are stored on your own device.

---

## 2. Information Collection and Use

### 2.1 Information We Do NOT Collect

| Information Type | Description |
|----------|------|
| Personal Identity Information | No online account system; we do not collect names, email addresses, phone numbers, or other identity information |
| Location Information | No location permission requested; GPS coordinates are not collected |
| Device Identifiers | IDFA, IDFV, or other device identifiers are not collected |
| Usage Behavior Analytics | No analytics/statistics SDKs integrated; no event tracking |
| Advertising Identifiers | No advertising SDKs integrated; no ad tracking |
| Network Logs | User network request logs are not recorded |

### 2.2 Information Stored Locally on the Device

| Information Type | Storage Location | Purpose |
|----------|----------|------|
| Captured Photos | Device local file system | Record content display and review |
| OCR Text, AI Summaries, Key Points | Local JSON files | Search and knowledge review |
| Plain Text Records | Local JSON files | Manual text notes |
| To-Do Items | Local JSON files | Task management (including due dates and reminder markers) |
| Custom Folders, Tags, Schedule Tags | Local JSON files | Categorization and schedule color coding |
| Notti Conversation History | Local JSON files | AI conversation record storage and search |
| Notti Long-Term Memory and Vectors | AES-GCM encrypted local files; key stored separately in iOS Keychain | AI assistant personalized memory and local retrieval |
| Local Account Profile (Nickname, Avatar) | Local file system | Profile display |
| Semantic Vector Index (Search / Deep Connect) | Local file system | Semantic search of camera notes and related note recommendations (on-device vectors) |
| API Key (AI Key) | iOS Keychain (hardware-grade encryption) | AI service invocation |
| App Settings Preferences (Theme, Language, Model Config, etc.) | UserDefaults | Personalized experience |
| Calendar Event Information | Processed in memory; not stored long-term | Matching schedule context when capturing photos |

### 2.3 Information Sent to Third Parties

The following scenarios send data to the selected AI model. Notiee+ connects directly to the provider configured by the user; the free Notiee app uses Notiee's AI relay backend:

| Scenario | Content Sent | Recipient | User Control |
|------|----------|--------|----------|
| AI Camera Note Processing | Photo image data + text prompts | User-configured AI service provider | Automatically processed after user-initiated capture; AI functionality can be disabled |
| Notti Conversations | User messages + conversation history context | User-configured AI service provider | User-initiated conversations |
| Notti Memory Recall and Extraction | Current user message, confirmed tool results, and a small set of locally matched memory candidates (up to 5 for Free, up to 10 for Pro/Plus) | Selected AI model; routed through Notiee's stateless relay in the free app | Requires versioned Notti privacy consent; automatic memory and memory use can each be disabled |
| Notti Agent Actions | User instructions + related camera note/schedule/to-do data | User-configured AI service provider | User-initiated Agent mode usage |
| WebFetch Web Scraping | Target URL (provided by user) | Server hosting the target webpage | Triggered only by user instructions in Agent mode |
| Cloud Semantic Retrieval (Optional) | Camera note text summaries | User-configured AI service provider Embedding API | **Disabled by default**; must be manually enabled in Labs |
| iCloud Sync (If Enabled) | .tmn encrypted archive files | Apple iCloud Drive | User-initiated manual trigger |

> **Important Note**: Notiee+ uses API keys and providers configured by the user. The free Notiee app sends AI requests through Notiee's backend using server-managed credentials. The Notti memory extraction endpoint is stateless and does not persist or log request/response body text. **The "Deep Connect" related note recommendations on the detail page are, by default, computed entirely on-device, with no data sent to any server.**

---

## 3. Permission Usage

| Permission | Purpose | Required | Revocable |
|------|------|----------|----------|
| Camera | Capture class notes, meeting minutes, whiteboard content | Core functionality; required | Can be disabled in System Settings |
| Microphone | Voice recording (if enabled) | Optional | Can be disabled in System Settings |
| Photo Library | Import existing images | Optional | Can be disabled in System Settings |
| Calendar | Read system calendar to match current schedule context | Optional (manual schedule selection available when disabled) | Can be disabled in System Settings |
| Speech Recognition | Voice-to-text transcription | Optional | Can be disabled in System Settings |
| Notifications | Schedule reminders, to-do reminders | Optional | Can be disabled in System Settings |

> The App does not request location permission, Bluetooth permission, Contacts permission, or any other system permissions not listed above.

---

## 4. Data Storage and Security

| Measure | Description |
|------|------|
| Local First | All records are stored locally on the device by default, without cloud dependency |
| Keychain Encryption | API Keys are stored in iOS Keychain and are not written to regular files. Depending on system behavior, Keychain items may remain after App uninstallation; use the in-app reset or key-removal controls before uninstalling when removal is required |
| HTTPS Transport | All AI service calls use HTTPS encrypted transport |
| No Cloud Retention | Notiee does not operate its own servers; it does not collect or store user content data |
| iCloud Security | If the user manually enables iCloud Sync, data is stored in the user's personal iCloud Drive, protected by Apple's security infrastructure |
| WebFetch Security | Uses ephemeral network sessions (no persistent cookies/cache), with built-in SSRF protection that blocks access to local and internal network addresses (localhost, 10.x, 172.16-31.x, 192.168.x, etc.) |
| Local Semantic Retrieval | Uses Apple NLEmbedding on-device vector engine by default; all vector computations are performed locally on the device and not uploaded to any server |
| No Unsolicited Network Requests | The App does not spontaneously send data to any server except for user-initiated AI processing, Notti conversations, WebFetch, or iCloud Sync |

---

## 5. Data Sharing and Disclosure

5.1 **User data is not sold, rented, or traded to third parties.**
5.2 User data may be disclosed only under the following circumstances:
   - As required by laws and regulations
   - To protect the legitimate rights and interests of the developer or others
   - With the user's explicit consent
5.3 AI service call data is sent to the AI service provider chosen by the user and is subject to that provider's own privacy policy, independent of this App.
5.4 Web content scraped via WebFetch is provided by the target website and is subject to that website's terms of use.

---

## 6. User Rights

| Right | Description |
|------|------|
| Right of Access | All data is directly viewable within the App, including camera notes, to-dos, Notti conversations, profile information, etc. |
| Right of Export | One-tap export of all records as a `.tmn` archive file is supported |
| Right of Deletion | Individual records, individual conversations, or all data can be deleted within the App |
| Right of Search | Full-text search and semantic search of camera notes and Notti conversations are supported |
| Right to Withdraw Consent | Any permission can be revoked in System Settings |
| Account Deactivation | Local files in the App container are normally removed when the App is uninstalled, but Keychain items may remain and iCloud-synced files must be deleted separately. Use the in-app deletion, reset, or clear controls before uninstalling when complete removal is required |

---

## 7. Protection of Minors

7.1 The App is designed for students and professionals and is not specifically targeted at children under the age of 14.
7.2 If a guardian discovers that a minor has used the App without consent, they may contact us through the contact information at the end of this policy to request data deletion.

---

## 8. Notti AI Assistant Privacy

Notti is the AI assistant built into the App and has the following privacy characteristics:

8.1 **Conversation Content**: Notti conversation messages (user input and AI responses) follow the transport path for the edition: the free Notiee app relays them through the Notiee backend to the selected AI model, while Notiee+ connects directly to the user-configured AI provider. Conversation history is stored locally on the device.
8.2 **Agent Mode**: When using Agent mode, Notti may read the user's camera notes, schedules, to-dos, and other local data as operational context; relevant data may be sent to the AI service provider with the request.
8.3 **WebFetch**: In Agent mode, web content may be fetched based on user instructions, using ephemeral secure sessions; no network data is persisted.
8.4 **Long-Term Memory**: Notti's memory database and vectors are encrypted locally with AES-GCM and are not synced to iCloud. To answer a request or extract a new memory, only the current message, confirmed tool results, and a small set of locally matched memory candidates are sent temporarily to the selected AI model. The full memory database is never uploaded.
8.5 **Sensitive Information**: Health, precise address, contact, financial, and identity information remains pending until the user explicitly asks Notti to remember it or confirms it. Passwords, one-time codes, API keys, tokens, bank card numbers, and private keys are never saved as memory.
8.6 **Privacy Consent and Controls**: The redesigned memory system requires separate versioned consent. Users can independently disable automatic memory writing or memory use without deleting existing memories, and can permanently delete memories from Settings.

---

## 9. Policy Updates

9.1 We reserve the right to update this Privacy Policy at any time.
9.2 Material changes will be notified to users via in-app pop-up.
9.3 Continued use of the App after an update constitutes your agreement to be bound by the updated policy.

---

## 10. Third-Party Privacy Policies

We recommend reading the privacy policies of the corresponding service providers when configuring AI services:

| Service Provider | Privacy Policy Link |
|--------|-------------|
| OpenAI | https://openai.com/policies/privacy-policy |
| Anthropic | https://www.anthropic.com/privacy |
| DeepSeek | https://www.deepseek.com/policies/privacy |
| Alibaba Cloud Bailian | https://help.aliyun.com/document_detail/ |
| Volcengine | https://www.volcengine.com/docs/ |
| MiniMax | https://platform.minimaxi.com/document |

---

## 11. Contact

For any privacy-related questions, please contact us through the following channels:

- **Email**: woxiantao@icloud.com
- **Developer Website**: https://tanqinghua.asia
- **Response Commitment**: We will respond to privacy-related inquiries within 15 business days

---

## Appendix A: Data Lifecycle

```
Capture → Local Storage → [User Triggers AI Processing] → Send to AI Service Provider → Return Results → Local Storage
                                ↓
                        [Notti Conversation] → Send to AI Service Provider → Return Results → Local Storage
                                ↓
                        [Notti Memory] → Local Retrieval → Small Matched Set Sent Temporarily → Encrypted Local Update
                                ↓
                        [Agent Action] → Read Local Data → Send to AI Service Provider → Execute Action
                                ↓
                        [WebFetch] → Temporary Web Scraping → Return Body Text → Not Persisted
                                ↓
                        [Cloud Semantic Retrieval (Optional)] → Send Text to Embedding API → Return Vectors → Local Storage
                                ↓
                        [iCloud Sync] → Send to iCloud Drive
                                ↓
                        [User Deletion] → Local File Removal + AI Service Provider Side Processed Per Its Policy
```

## Appendix B: Technical Implementation Privacy Highlights

| Implementation | Description |
|------|------|
| No Event Tracking | No analytics/statistics SDKs integrated |
| No Advertising | No advertising SDKs integrated |
| No Unsolicited Network Requests | No data is spontaneously sent to any server except for user-initiated actions |
| API Key Localization | Stored in Keychain; it may remain after App uninstallation depending on system behavior, so remove or reset it in the App first when required |
| Transport Encryption | All AI requests use HTTPS |
| WebFetch Ephemeral Sessions | Uses `URLSessionConfiguration.ephemeral`; no persistent cookies/cache |
| WebFetch SSRF Protection | Blocks localhost, internal network IPs, IPv6 local addresses |
| On-Device Vector Engine | Uses Apple NLEmbedding by default; semantic computation performed locally on device |
| Cloud Retrieval Optional | Cloud Embedding is disabled by default; requires manual user activation |

---

> **Version History**
> - v1.0.7 (2026-08-06): Renamed Spark to Notti; added encrypted local memory, bounded memory recall/extraction transmission, sensitive-memory confirmation, and independent memory controls
> - v1.0.6 (2026-07-02): Added encrypted notes (AES-GCM on-device encryption, key stored in the system Keychain) and biometric/passcode privacy lock (credentials never leave the device) description; encrypted notes are excluded from export, sync, search, and indexing; added data-flow description for custom AI models
> - v1.0.5 (2026-06-24): Added "Deep Connect" on-device semantic related notes (local vectors, independent local index, no external transmission) description; to-do item local persistence; added plain text record data description
> - v1.0.4 (2026-06-24, unreleased): Added Spark (now Notti) Agent WebFetch privacy disclosure, cloud semantic retrieval description, local account data description, WebFetch security measures, etc.
> - v1.0.3 (2026-06-04): Added Spark (now Notti) AI Assistant conversation data description
> - v1.0.1: Initial version
