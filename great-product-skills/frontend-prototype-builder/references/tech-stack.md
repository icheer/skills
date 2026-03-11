# Tech Stack — Complete Constraints

> Every line of code must comply with this document.
> Violations are bugs, not style choices.

## Framework

**Vue 3, Options API only.**

- Do NOT use Composition API.
- Do NOT use `<script setup>` syntax.
- All components use `export default { data(), methods, computed, watch, mounted, ... }`.

## TypeScript Policy

TypeScript is **allowed sparingly**:

- ✅ Allowed: interface definitions for props and data shapes, function parameter/return types
- ❌ Forbidden: complex generics, conditional types, mapped types, template literal types,
  utility type chains (`Partial<Pick<Omit<...>>>`), or anything called "type gymnastics"

When in doubt: use plain JavaScript. TypeScript should reduce confusion, not add it.

## Styling

| Context | Preprocessor | Notes |
|---|---|---|
| Full Vue 3 project | **LESS** | Compiled by Vite; use `lang="less"` in `<style>` |
| Single HTML file | **Plain CSS** | Do NOT use `lang="less"` or `less.js` CDN — use plain CSS with CSS custom properties for theming |

LESS rules (full project only):
- Use LESS variables for theming: `@brand-color`, `@spacing-sm`, `@spacing-md`, `@spacing-lg`
- Use LESS mixins for reusable patterns: responsive breakpoints, text truncation
- Follow BEM naming for custom classes: `.block__element--modifier`

## Component Libraries

| Platform scope | Library | Package |
|---|---|---|
| PC / Desktop | TDesign Vue Next | `tdesign-vue-next` |
| Mobile | TDesign Mobile Vue | `tdesign-mobile-vue` |

Platform selection:
- Spec says "Desktop" → `tdesign-vue-next`
- Spec says "Mobile" → `tdesign-mobile-vue`
- Spec says "Cross-platform" → two separate entry points, one per platform

**TDesign MCP tool** (`tdesign-mcp-server`): When available, use it to query component
API docs and DOM structures before implementing any TDesign component.

Docs:
- Desktop: https://tdesign.tencent.com/vue-next/overview
- Mobile: https://tdesign.tencent.com/mobile-vue/overview

## Absolute Prohibitions

| Forbidden | Reason |
|---|---|
| Tailwind CSS | Explicitly banned by project constraints |
| shadcn/ui | React-only; incompatible with Vue |
| Any React library or hook | Project is Vue 3 |
| Composition API / `<script setup>` | Project mandates Options API |
| `lang="less"` in single HTML files | LESS requires a build step — use plain CSS |
| SCSS / Sass | Project uses LESS |
| CSS-in-JS (styled-components, emotion) | Project uses LESS |
| Heavy animation libraries (GSAP, Framer Motion) | Use CSS `transition` / `@keyframes` |

## Design Approach

**Follow TDesign's design language as the foundation.** Do not invent a new aesthetic
on top of a component library that already has an established visual system.

- **Color**: Use TDesign's CSS design tokens (`--td-brand-color`, `--td-text-color-primary`,
  `--td-bg-color-container`, etc.). Override via LESS variables that reference these tokens.
  Avoid arbitrary hex values.
- **Typography**: Use TDesign's default font stack. Override only when the product identity
  explicitly requires a different typeface.
- **Layout**: Use TDesign's `t-layout` / `t-row` / `t-col` components for page structure.
  Avoid deeply nested absolute positioning.
- **Spacing**: Follow the 4px base unit:
  `@spacing-xs: 4px; @spacing-sm: 8px; @spacing-md: 16px; @spacing-lg: 24px; @spacing-xl: 32px;`
- **Motion**: CSS `transition` for hover/focus micro-interactions. `@keyframes` for loading
  indicators and entrance animations only.

## Quality Bar

Every visible element must feel intentional — aligned, spaced, colored with purpose.

- Mock data must look realistic: `"张三"` beats `"用户1"`; `"2024-03-15"` beats `"2000-01-01"`
- Empty states: use `t-skeleton` or meaningful empty illustrations
- Loading states: use `t-loading` or `t-skeleton` during async operations
- Error states: use `t-alert` or `MessagePlugin.error()` for the core flow