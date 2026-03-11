# Walkthrough Checklist — Six Dimensions

Use this checklist as a systematic sweep during Step 3 of the walkthrough. Apply every item to every page/flow in scope. Do not skip items.

---

## Dimension 1: Page Load Experience

- [ ] Clear loading state present (skeleton, spinner, or progressive rendering)?
- [ ] Load failure shows user-friendly message with recovery action?
- [ ] TDesign loading components (`t-loading`, `t-skeleton`) used and configured correctly?
- [ ] Heavy operations deferred or lazy-loaded?

## Dimension 2: Visual Consistency

- [ ] Color usage consistent across pages and aligned with TDesign design tokens?
- [ ] Typography hierarchy clear and uniform (headings, body, captions, labels)?
- [ ] Spacing and alignment consistent? Grid system applied systematically?
- [ ] Icon style cohesive (line vs. filled, size, color)?
- [ ] TDesign component styling not overridden in ways that break design language?
- [ ] LESS variables used for shared values rather than repeated magic numbers?

## Dimension 3: Interaction Experience

- [ ] Button states all present and distinct (default / hover / active / disabled / loading)?
- [ ] TDesign `disabled` and `loading` props used correctly instead of custom CSS hacks?
- [ ] Form inputs provide real-time validation feedback?
- [ ] Click/tap targets meet minimum size (44×44px mobile, 32×32px desktop)?
- [ ] Every user action produces visible feedback (toast, state change, animation)?
- [ ] `t-message`, `t-toast`, or `t-notification` used appropriately for feedback?

## Dimension 4: Flow Continuity

- [ ] Users can recover from mid-flow interruptions (accidental back, accidental close)?
- [ ] Transitions between steps feel natural and guided?
- [ ] Users always know: where they are, what they just did, what comes next?
- [ ] No unnecessary steps that could be eliminated or merged?
- [ ] Breadcrumbs, step indicators, or progress bars present where flow warrants them?

## Dimension 5: Error Handling

- [ ] Error messages specific and human-readable — no raw error codes exposed?
- [ ] Every error state offers a recovery path (retry, go back, contact support)?
- [ ] Network failures trigger retry with appropriate feedback?
- [ ] Preventive design present: disable invalid actions, confirm destructive operations?
- [ ] `t-dialog` (confirmations) and `t-message` / `t-notification` (feedback) used in right contexts?

## Dimension 6: Edge Cases

- [ ] Empty states have guidance (illustration + CTA, not blank screens)?
- [ ] Data overflow handled (pagination, virtual scroll, truncation with tooltip)?
- [ ] Extreme content renders correctly: long strings, special characters, zero values, missing images?
- [ ] First-time vs returning user experience differs appropriately?
- [ ] Platform-specific edge cases addressed (mobile keyboard overlap, desktop viewport resize)?