# Advanced Sections — Steps 5–9

This file contains detailed generation instructions for the optional advanced spec sections.
Read this file only when the user has selected one or more advanced sections at the decision gate.

Each section follows the same execution pattern:
1. Generate the section content using the structure below
2. Append the section to the spec file
3. Update document status → save
4. Confirm with user before continuing

---

## Step 5 — Telemetry

Generate a telemetry event table:

| Funnel Stage | Event Name | Trigger | Metric / KPI | Purpose | Priority |
|--------------|------------|---------|--------------|---------|----------|

**Column rules:**
- **Funnel Stage**: One of Adoption / Usage / Retention / Monetization / Quality
- **Event Name**: lowercase snake_case, verb-first (e.g., `click_signup_button`)
- **Trigger**: Engineer-executable description of when the event fires
- **Priority**: P0 / P1 / P2

After generating the table, ask the user if they also want a **dashboard design subsection**. If yes, outline the key dashboard panels and their data sources.

Append as `## 5. Telemetry`. Update status. Save. Confirm.

---

## Step 6 — Experiment

Generate a complete A/B test plan covering:

- **Hypothesis & goal**: What you expect to prove and why
- **Eligibility / trigger logic**: Which users enter the experiment and when
- **Control vs. Treatment definition**: Exact differences between groups
- **Primary metric**: The single metric that determines success
- **Secondary metrics & guardrails**: Supporting metrics and safety boundaries
- **Expected duration & sample size**: Statistical rigor requirements
- **Success criteria**: Go/no-go rules, quantified (e.g., "Treatment shows ≥X% lift in primary metric with p < 0.05")

Append as `## 6. Experiment`. Update status. Save. Confirm.

---

## Step 7 — Evals

Generate an evaluation plan table:

| Eval Type | Objective | Method | Target |
|-----------|-----------|--------|--------|

Organize into three subsections:

### 7.1 Offline / Pre-launch
Evaluations that can be run before shipping (unit tests, model evals, internal QA, dogfooding).

### 7.2 Online Experiment
Metrics and methods for evaluating during the A/B test phase (ties back to Step 6 if present).

### 7.3 Post-Launch Monitoring
Ongoing metrics, alerting thresholds, and review cadence after full rollout.

Append as `## 7. Evals`. Update status. Save. Confirm.

---

## Step 8 — Roadmap

Generate a phased roadmap table:

| Phase | Timeline | Milestone | Deliverable | Status |
|-------|----------|-----------|-------------|--------|

Follow the table with a **Risks & Mitigations** section that identifies key risks for each phase and proposes mitigations. Use this format:

```
**Phase N Risks:**
- Risk: [description] → Mitigation: [action]
```

Append as `## 8. Roadmap`. Update status. Save. Confirm.

---

## Step 9 — GTM (Go-To-Market)

Generate three sub-tables:

### Target Audience & Positioning

| Segment | Need | Message | Expected Impact |
|---------|------|---------|-----------------|

### Launch Channels

| Channel | Action | Owner | Timing |
|---------|--------|-------|--------|

### GTM KPIs

| KPI | Target | Measurement |
|-----|--------|-------------|

Close with a **Messaging Consistency Checklist** — a short bullet list ensuring all channels use consistent terminology, value propositions, and CTAs.

Append as `## 9. GTM`. Update status. Save. Confirm.