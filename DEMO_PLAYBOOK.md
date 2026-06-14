# MedicoScope — Demo Playbook (AI Agents & Autonomous Systems)

The architecture is only worth points if judges *see* it. This is the path that
makes the autonomous + governed story undeniable. Practice it once end-to-end.

## T-15 min: go/no-go (do this EVERY time before presenting)
```bash
cd server
MONGODB_URI="<your-uri>" node aegis/demo-check.js --services
```
- Must print **✅ GO**. If it says KB not seeded → `node aegis/seed-kb.js` then re-check.
- Leave the pre-warmer running so services don't cold-start mid-demo:
  `node aegis/prewarm.js`

## The 90-second core story (lead with this)
1. **Frame it (10s):** "Most health AI confidently guesses. Ours is an
   *autonomous agent with a safety gate* — it plans, uses tools, fuses
   evidence, and **knows when to stop and call a human**. Every decision is
   logged in a tamper-evident ledger."
2. **Run a consult (30s):** trigger the agentic consult → show it
   **plan → call multiple tools → fuse** into a cross-modality concordance.
   Narrate: "no single signal — it's corroborating independent modalities."
3. **THE MONEY SHOT (30s):** submit a critical input (mental-health check-in
   with crisis language, or a screening with a red-flag value). Show the agent
   **refuse to act autonomously** → a **RED ClinicianCase** opens in the doctor
   console. "It didn't diagnose. It escalated to a human. That's governed
   autonomy."
4. **Prove it (20s):** open the **audit ledger** for that patient → show the
   **hash-chained, tamper-evident** decision trail + "chain INTACT". "Every
   autonomous decision is provable and auditable."

## Hard questions — have these answers ready
- **"Is it really an agent or just rules + an LLM?"**
  → "The agentic loop plans and orchestrates tools toward a goal and carries
  memory across encounters. The *gate* is deterministic **on purpose** —
  autonomy without a brake is a liability, not a feature. We separated the
  reasoning (adaptive) from the safety envelope (provable)."
- **"How do I trust an AI medical reading?"**
  → "You don't have to trust it blindly — that's the point. It carries
  calibrated confidence, refuses to score noisy signals, labels everything
  screening-grade, and routes anything serious to a clinician. The ledger
  proves what it did."
- **"What's actually ML vs heuristic?"**
  → Be honest: heart-sound is a real TFLite model; lab/vitals/symptom are
  deterministic over published clinical thresholds; PPG/voice/respiratory are
  real signal-processing with honest confidence. "Our edge is breadth +
  governance + fusion, not one black-box model."

## Backup if a live service is down
- The on-device analyzers (PPG, voice, respiratory, lab) run **offline** — demo
  those locally; they don't need the network.
- `DemoModeService` seeds realistic 3-disease data so dashboards/concordance
  are never empty in front of judges.

## Don't forget to show
- Cross-modality **concordance panel** (unified risk dashboard) — the
  single-modality-app-can't-do-this moment.
- The **honesty**: a roadmap modality returning "unavailable" instead of faking.
