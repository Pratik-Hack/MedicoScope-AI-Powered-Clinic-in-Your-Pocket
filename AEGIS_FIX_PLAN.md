# MedicoScope Aegis — Permanent-Fix Plan

Source: adversarial bug/persistence audit (34 of 37 findings confirmed against live code, 2026-06-14).
Legend: **[QUICK]** code-only · **[COLLECTION]** new/extended Mongo model · **[ATOMIC]** concurrency fix.

Decision: implement ALL tiers. Code only — new data persists going forward; user runs any live-DB migration themselves.

---

## TIER 0 — RED-action execution paths + persistence gaps

- **0.1 [QUICK] CRITICAL** `server/src/routes/mental-health.js:12` — POST /notifications has no auth; any caller can drive the Aegis gate / open RED cases. Add `auth`, bind identity (patient may only file for self), thread chatbot bearer token. *(regression from earlier Gap-1 wiring)*
- **0.2 [QUICK] CRITICAL** `server/src/routes/aegis.js:113-129` — approve/modify calls EXECUTORS directly, bypassing gate. Route back through `aegisService.submit({...clinicianApproved:true})`; add `clinicianApproved` branch in gate that still classifies + ledgers + is idempotent.
- **0.3 [RE-EVALUATED → KEPT ?? 1]** `server/aegis/gate.js:42` — Audit claimed missing confidence dodges escalation. On inspection this is NOT exploitable: omitting confidence defaults to 1 (same as the classifier), and you cannot LOWER a class by omitting it — only an EXPLICIT confidence <0.45 escalates, which classifier.js already enforces. Forcing `?? 0.4` broke the documented `high→AMBER` contract + 2 gate tests. Resolution (user-approved): keep `?? 1`, documented; LLM/agent callers must pass real confidence.
- **0.4 [ATOMIC] CRITICAL** `server/aegis/ledger.js:77-96` — non-atomic seq alloc → dup seqs / broken hash chain. Add `LedgerCounter` model, allocate seq via `$inc` upsert in a transaction; fix `DecisionAudit` unique index to cover patient-wide (episodeId:null) chains.
- **0.5 [QUICK] CRITICAL** `chatbot/main.py:54,178-200,209-245` — `session_histories` in-memory. POST to existing `/api/chat/message` (best-effort), hydrate from backend on cold start.
- **0.6 [COLLECTION] CRITICAL** `chatbot/main.py:57-58,540,564-580` — vitals sessions/alerts in-memory. Add `VitalsAlert` + `VitalsSession` models, `routes/vitals-alerts.js`, POST from main.py, read from Mongo.
- **0.7 [COLLECTION] CRITICAL** `lib/services/disease_risk_store.dart:14-20` — risk results only on device. Add `DiseaseRiskResult` model + `POST/GET /api/detections/risk-result(s)`; Flutter persists + hydrates newest-wins.
- **0.8 [COLLECTION] HIGH** `lib/services/appointment_service.dart:92-119` — no canonical appointment record. Add `Appointment` model + `routes/appointments.js`; Flutter POSTs + reads /mine with offline retry.
- **0.9 [QUICK] HIGH** `lib/services/appointment_response_service.dart:182-233` — read/ack local-only. Add `patientAcknowledged` to `MentalHealthNotification`, `PUT /:id/ack`, wire Flutter.
- **0.10 [QUICK] MEDIUM** `lib/services/disease_alert_service.dart:85-206` — alert read-state local-only. Add `source` to notification schema, wire `markAllRead` to backend, hydrate on startup.
- **0.11 [ATOMIC] HIGH** `lib/core/providers/coins_provider.dart:58-243` — fire-and-forget sync, divergence. Server `Rewards` authoritative; `$inc` earns, versioned `$set` spends; await + durable retry on client.

## TIER 1 — IDOR / authorization (build `middleware/patientAccess.js` first)

- **1.1 [QUICK] CRITICAL** mental-health.js:56-62,97-102 — notifications by doctorId IDOR.
- **1.2 [QUICK] CRITICAL** vitals.js:69-75 — vitals by patientId IDOR.
- **1.3 [QUICK] CRITICAL** detections.js:39-51 — detection records by patientId IDOR.
- **1.4 [QUICK] CRITICAL** episodes.js:43-57 — episode context/fact by patientId IDOR.
- **1.5 [QUICK] CRITICAL** aegis.js:143-151 — audit ledger by patientId IDOR.
- **1.6 [QUICK] CRITICAL** aegis.js:49-59 — case detail no owner check.
- **1.7 [QUICK] MEDIUM** aegis.js:36-47 — GET /cases exposes all to non-doctors.
- **1.8 [QUICK] HIGH** mindspace.js:45-62 — doctor sessions need role + linkage check.
- **1.9 [QUICK] HIGH** auth.js:16,33 — remove 'admin' from self-registration roles.

## TIER 2 — Aegis correctness & concurrency

- **2.1 [QUICK] HIGH** gate.js:121-123 — notifyDoctor rejection swallowed; log + ledger `notify_failed`.
- **2.2 [ATOMIC] HIGH** service.js:68-77 — ClinicianCase dedupe upsert race; transaction or check-then-act.
- **2.3 [ATOMIC] HIGH** memory.js:97-116 — touchTimeline/upsertFact RMW race; use `$push $slice`/positional ops + validation.
- **2.4 [ATOMIC] MEDIUM** ledger.js:105-122 — recordOverride two-step not atomic; wrap in transaction.
- **2.5 [QUICK] HIGH** seed-kb.js:107-150 — KB cache never invalidated; call `kb.invalidate()` at end + admin `POST /kb/reload`.
- **2.6 [QUICK] MEDIUM** tools/index.js:179 — roadmap tool kind always 'evidence'; fix ternary.
- **2.7 [QUICK] HIGH** aegis_consult.py:92-103,149 — empty token fails silently; validate + fail fast.
- **2.8 [QUICK] MEDIUM** main.py:326-341 — also POST MindSpace session at source.
- **2.9 [QUICK] LOW** gate.js:23-26, ledger.js:26-28 — prefer explicit idempotencyKey, digest fallback.

## TIER 3 — Hardening

- **3.1 [QUICK] MEDIUM** nearby-doctors.js:34-36 — escape regex (ReDoS).
- **3.2 [QUICK] MEDIUM** index.js:32 — replace open CORS with allow-list.
- **3.3 [COLLECTION] MEDIUM** auth_provider.dart — secure token storage + `Session` model + revocation.
- **3.4 [QUICK] LOW** theme/locale providers — `User.preferences` subdoc + PATCH.

## New collections
`LedgerCounter` (0.4) · `VitalsAlert`,`VitalsSession` (0.6) · `DiseaseRiskResult` (0.7) · `Appointment` (0.8) · `Session` (3.3)
Extensions: `MentalHealthNotification` (+source,+patientAcknowledged) · `User` (+preferences) · `DecisionAudit` index fix · `Rewards` (+version)

## Order
1. 0.1, 0.2, 0.3 (RED-execution) → 2. patientAccess + 1.1–1.9 (IDOR) → 3. 0.4 + 2.4 + LedgerCounter (ledger) →
4. 0.5–0.8 (persistence collections) → 5. 0.9–0.11 (read-state/rewards) → 6. 2.1–2.7 (correctness) → 7. Tier 3.

---

## IMPLEMENTATION STATUS (2026-06-14) — all verified: 57/57 server tests pass, flutter analyze clean on touched files

DONE:
- Tier 0: 0.1 (mental-health auth+identity, token threaded Node→chatbot→Flutter), 0.2 (clinician approve/modify re-routed through gate via clinicianApproved), 0.4+2.4 (LedgerCounter atomic seq, unique patient-wide index, self-bootstrap, override fail-loud).
- 0.3 RE-EVALUATED → kept `?? 1` (not exploitable; blanket 0.4 broke documented high→AMBER + 2 tests). User-approved.
- Tier 1 IDOR: patientAccess middleware + 1.1–1.9 all applied (detections, vitals, episodes, ledger, cases, mental-health, mindspace, no-admin-self-register).
- Persistence (0.5–0.8): chat (already via Flutter; +bottom-sheet now persists), VitalsAlert+VitalsSession models+routes+chatbot+Flutter, DiseaseRiskResult model+route+pipeline funnel, Appointment model+routes+Flutter book/getAll.
- 0.9 (MentalHealthNotification +patientAcknowledged + /ack route + Flutter markRead), 0.10 (+source field, disease-alert POST now auth'd), 0.11 (rewards loss-proof $max sync).
- Tier 2: 2.1 (notify fail logged+ledgered), 2.2 (dedupe documented—pattern already atomic), 2.3 (memory touchTimeline/upsertFact now atomic $push/$slice/arrayFilters), 2.5 (KB invalidate in seed + admin POST /kb/reload), 2.6 (roadmap kind action/evidence), 2.7 (consult empty-token fail-fast).
- Tier 3: 3.1 (ReDoS escape), 3.2 (CORS allow-list via CORS_ORIGINS), 3.3 backend (Session model + opt-in SESSION_ENFORCEMENT revocation + login/register session record + /logout), 3.4 (User.preferences + PATCH /users/preferences).

DEFERRED (documented, not silently skipped):
- 2.8 chatbot-source MindSpace persist — redundant (Flutter client already persists); MEDIUM, low value.
- 3.3 Flutter half (flutter_secure_storage migration) — needs new package download + native keychain config; risky on a near-full C: disk. Backend revocation is ready; enable with SESSION_ENFORCEMENT=true once client migrates.

ENV TO SET (new): CORS_ORIGINS (prod web origins), SERVICE_KEY (Node + chatbot, for vitals ingest), optionally SESSION_ENFORCEMENT=true.

VERIFICATION LIMITS: server verified via 57-test suite + load checks. Flutter/chatbot verified via flutter analyze (clean) + py_compile + node require — NOT exercised end-to-end against live MongoDB (credentials never shared). Final round-trip confirmation requires running the app once against the DB. C: disk was 100% full — freed ~1GB of safe caches to let `flutter pub get` succeed; large reclaim needs user action.
