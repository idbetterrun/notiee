# Spark Citation Full-Text Continuation Design

| Field | Value |
|---|---|
| Date | 2026-07-23 |
| Scope | Shared Spark plain-chat flow: Notiee and Notiee+ |
| Status | Approved design, pending implementation-plan review |

## Problem

Spark ordinary chat uses a layered record prompt. Recent anchor records expose only title and short summary; `detailedContent` is withheld to control token cost. This is appropriate for broad recall, but fails when a user identifies a cited record and immediately asks to continue work that requires its body, such as translating an English article.

The existing short-followup pinning mechanism does not solve this reliably:

1. `SparkViewModel.processQuestion` appends the current turn's empty assistant placeholder before it asks `computePinnedRecordIDs` for the previous assistant message. The helper therefore selects the new placeholder, whose citations are always empty.
2. It additionally requires a narrow keyword list. A natural confirmation such as `对，就是这条` does not match, despite the surrounding conversation making its meaning clear.

Spark already receives recent conversation history. The missing context is the source record's full text, not natural-language understanding.

## Goals

- After a Spark reply cites one or more live, unencrypted records, make their full text available as candidate context for the immediately following ordinary-chat turn.
- Let the existing main model use its conversation history to decide whether that material is relevant. No user keyword, special command, or extra intent-classification request is required.
- Keep the original anchor/semantic recall policy unchanged for the first turn.
- Preserve citation identity through `Citation.recordID`; never identify a record by title matching during continuation selection.
- Keep prompt growth bounded and prevent encrypted or deleted content from entering the prompt.

## Non-Goals

- Do not change Spark Agent behavior, tools, trust levels, backend contracts, or model selection.
- Do not introduce a second LLM request to classify follow-up intent.
- Do not persist an indefinite selected-record state across turns or conversations.
- Do not expand the record-recall cap, alter semantic ranking, or change the 4,000-character rendering cap per record.

## Design

### Conversation-Scoped Candidate Context

For every ordinary-chat request, obtain the immediately preceding completed assistant message before appending the new empty assistant placeholder. If that message has citations, map their `recordID`s to the current in-memory record set and retain only records that are not deleted and not encrypted.

Pass those IDs as `pinnedRecordIDs` to the existing `SparkAIServing.ask` call. `SparkAIService.buildSystemPrompt` already renders the corresponding `detailedContent` in a `## 完整内容（用户正在追问的拍记全文）` block. The model also sees the preceding conversation round, so it can understand a terse continuation such as `对，就是这条`; it may ignore the candidate body for an unrelated reply such as `谢谢`.

The candidate context is deliberately single-turn: only the assistant response immediately before the current user request can contribute pin IDs. Once Spark produces the next response, later turns use its citations instead. This prevents old selections from silently carrying forward.

### Total Prompt Budget

The existing 4,000-character limit applies per pinned record. Continuation pinning can contain several citations, so `buildPinnedFullTextBlock` must also enforce a total 4,000-character budget across the whole block, preserving citation order. The first record receives as much content as fits; later records may receive the remaining portion or be omitted. A visible truncation suffix is appended when an included body is cut. Empty bodies remain omitted, and the header is emitted only when at least one body is included.

This maintains a known maximum incremental prompt cost for every follow-up turn.

### Citation Robustness

The continuation mechanism consumes only persisted `ChatMessage.citations`. Those citations are created from model `[来源N]` markers, with the existing title fallback as compatibility support. The prompt continues to require `[来源N]`; internal `[记录N]` labels are not a supported user-facing citation format and must not become a continuation-selection parser.

## Data Flow

```text
previous assistant reply
  -> ChatMessage.citations (record IDs)
  -> next user sends ordinary-chat message
  -> resolve valid cited record IDs before placeholder insertion
  -> ask(... pinnedRecordIDs: valid IDs)
  -> bounded full-text block in system prompt
  -> main model uses current + prior conversation context to respond
```

## Error Handling And Privacy

- No prior assistant reply, no citations, missing records, deleted records, encrypted records, and blank `detailedContent` produce no full-text block and retain current behavior.
- The resolver must not throw or block a chat request when a cited record is absent.
- The candidate set is derived from IDs owned by the local `ChatMessage`; no model-provided title or arbitrary ID is trusted.
- Deleted and encrypted records are excluded before prompt construction, preserving existing privacy guarantees.

## Tests And Acceptance Criteria

`SparkViewModelTests` gains an integration test using its mock AI service. The test must complete a first assistant response that yields a citation, send an arbitrary natural confirmation (`对，就是这条`), and assert that the second `ask` call receives that cited record ID even after the new assistant placeholder exists.

`SparkPromptRecallTests` gains prompt-rendering tests that prove:

- Multiple pinned records share a 4,000-character total budget.
- The first citation order is preserved.
- No header is emitted when every eligible body is blank.

Existing tests must still cover missing IDs and encrypted/deleted exclusion through ViewModel-level input. Both Notiee and Notiee+ schemes must build after the shared source change.

## Files Expected To Change

- `Notiee/Features/Spark/SparkViewModel.swift` — resolve immediate prior citations before placeholder insertion; remove keyword gating from continuation selection.
- `Notiee/Features/Spark/SparkAIService.swift` — enforce the whole pinned-full-text block's total character budget.
- `NotieeTests/SparkViewModelTests.swift` — mock capture of requested pinned IDs and end-to-end continuation regression tests.
- `NotieeTests/SparkPromptRecallTests.swift` — total-budget prompt tests.

No target-specific source file, localization string, Xcode project file, backend file, or UI file should change.
