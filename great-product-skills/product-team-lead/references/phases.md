# Phase Operational Guide

This document contains the full operational details for each phase of the product workflow, including dispatch specifics, quality gates, failure handling, and transition templates.

## Phase 1 — Product Discussion

**Goal**: Turn a fuzzy idea into a clear, confirmed product direction.

**Dispatch**: Call **PM Strategist** with the boss's idea and all stated context. Instruct PM Strategist to run the full discussion flow — challenge assumptions, enrich across multiple dimensions, and converge on a consensus summary when the boss signals readiness.

**Your role during this phase**:
- Supplement with full-stack perspective when relevant (tech feasibility, design implications, engineering cost trade-offs)
- Watch for convergence signals ("差不多了" / "收敛") and guide toward summary
- Intervene if discussion loops or drifts off target

**Quality Gate — must clear before Phase 2**:
- [ ] Clear product direction (articulable in one sentence)
- [ ] Target users identified with key pain points
- [ ] Core value proposition defined
- [ ] Key risks and open assumptions surfaced
- [ ] Boss has explicitly confirmed the direction

**If quality gate fails after one revision cycle**: Identify the specific gap ("方向在 [X] 这个点上还不够清楚"), ask one targeted question, give PM Strategist another pass. If still unclear after two cycles, flag it to the boss directly and propose a concrete resolution — don't keep looping.

**Transition → Phase 2**:

```
[Status Update]
- Done: Product discussion converged. Core direction: [one sentence].
- Output: Consensus summary — direction, users, value prop, open risks.
- Next: Structuring this into a formal spec. Recommend moving to Phase 2.
- Need your call: Green light?
```

---

## Phase 2 — Write Spec

**Goal**: Transform discussion consensus into a structured, testable PRD.

**Dispatch**: Call **Spec Engineer** with the full consensus summary from Phase 1 (or boss-provided context if entering directly). Explicitly instruct: "Reuse all upstream context. Do not re-ask things the boss already answered. Only clarify what is genuinely missing."

**Your role during this phase**:
- Ensure the member has enough context to avoid asking the boss to repeat
- Review spec sections for logical consistency with Phase 1 decisions
- Watch for spec-writing moments that reveal directional ambiguity (→ flag and consider returning to Phase 1)

**Quality Gate — must clear before Phase 3**:
- [ ] All core scenarios from Phase 1 are covered
- [ ] Functional requirements are implementable and testable
- [ ] User flows include exception handling
- [ ] Boss has reviewed and approved the spec
- [ ] Spec saved as `spec_[feature-name].md`

**If quality gate fails**: Identify the specific gap, give Spec Engineer targeted direction. If the gap reveals missing product-level decisions, surface it to the boss before continuing — do not spec around an unresolved direction. Maximum two revision rounds before escalating.

**Transition → Phase 3**:

```
[Status Update]
- Done: Spec complete. Saved to spec_[feature-name].md.
- Output: [N] core scenarios, [N] functional modules, user flow diagram.
- Next: Build an interactive prototype of the core flow. Which scenario should we demo first?
- Need your call: Demo scope.
```

---

## Phase 3 — Build Demo

**Goal**: Build a runnable, production-quality interactive prototype of the prioritized user flow.

**Dispatch**: Call **Frontend Engineer** with the spec document, boss-confirmed demo scope, and design direction.

Default aesthetic: Vercel/shadcn.ui minimalism — Zinc palette, clean 1px borders, Geist or Inter type, no AI-slop gradients.

Complexity guidance:
- Simple (single page, mostly display) → single HTML with Tailwind CDN
- Complex (multi-page, state-heavy) → full React + shadcn/ui project

If spec includes AI interactions (LLM responses, generative content), confirm mock data approach with boss before dispatch.

**Your role during this phase**:
- Help boss define demo scope if unspecified — default to the single most critical user journey
- Set expectation: "Demo targets core flow completeness, not production polish. But visual quality will be solid."
- Review demo before presenting: check spec alignment, interaction completeness, aesthetic standard

**Quality Gate — must clear before Phase 4**:
- [ ] Every key interaction in the scoped flow is clickable
- [ ] Visual quality is production-grade (no generic AI aesthetics)
- [ ] Demo matches spec requirements for the scoped scenario
- [ ] Boss has previewed and confirmed readiness to proceed

**If quality gate fails**: Give Frontend Engineer specific, targeted feedback (e.g., "the empty state in step 3 needs a real CTA, not a placeholder"). Maximum two revision rounds. If a blocker is technical (implementation infeasible as specced), surface to boss immediately with options: adjust spec, reduce scope, or change technical approach.

**Transition → Phase 4**:

```
[Status Update]
- Done: Demo ready. Core flow "[scenario]" fully interactive.
- Output: [Access path — local URL or file]
- Next: Expert UX walkthrough to catch experience issues before going further.
- Need your call: Any specific focus areas for the walkthrough?
```

---

## Phase 4 — UX Walkthrough

**Goal**: Systematically identify UX issues through expert review before the product moves forward.

**Dispatch**: Call **UX Reviewer** with demo access details, spec file for reference, the user scenarios to walk (from spec's scenario section), and any boss-specified focus areas.

**Your role during this phase**:
- Review walkthrough report for completeness and accurate severity classification before presenting to boss
- P0 issues (blocks core task completion): dispatch Frontend Engineer to fix immediately → dispatch UX Reviewer for targeted re-verification → report resolution to boss
- P1/P2 issues: present report to boss, ask which items to address now vs defer

**Quality Gate for completion**:
- [ ] All P0 issues resolved and re-verified
- [ ] Report saved as `walkthrough_[feature-name].md`
- [ ] Boss has reviewed and made decisions on remaining P1/P2 items

**Completion Report**:

```
[Status Update]
- Done: UX walkthrough complete. X issues found (P0: X / P1: X / P2: X).
  [All P0s resolved / X P0s need your decision].
- Output: walkthrough_[feature-name].md
- Next: [Recommendation — e.g., "address P1 items then ready for stakeholder review"]
- Need your call: [Pending P0 decisions or P1/P2 prioritization, if any]
```