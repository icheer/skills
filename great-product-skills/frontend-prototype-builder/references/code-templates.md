# Code Templates

## Full Project Scaffolding

Use `scripts/scaffold.py` to generate this structure automatically:

```
project-root/
├── index.html
├── vite.config.js          ← LESS + path aliases configured
├── package.json
└── src/
    ├── main.js             ← TDesign plugin + router registration
    ├── App.vue
    ├── router/
    │   └── index.js
    ├── pages/
    │   └── [ViewName].vue
    ├── components/
    │   └── [ComponentName].vue
    ├── assets/
    │   └── styles/
    │       ├── variables.less   ← Spacing, colors, radii
    │       ├── mixins.less      ← Text truncation, responsive
    │       └── global.less      ← Resets + TDesign overrides
    └── mock/
        └── data.js              ← Mock data + simulateApiCall helper
```

## Required `.vue` Component Template (Options API)

Every `.vue` file must follow this structure:

```vue
<template>
  <div class="feature-name">
    <!-- TDesign components + custom markup -->
  </div>
</template>

<script>
import { MessagePlugin } from 'tdesign-vue-next';
// Mobile: import { MessagePlugin } from 'tdesign-mobile-vue';

export default {
  name: 'FeatureName',

  components: {
    // Register TDesign components if not using global registration
  },

  props: {
    title: {
      type: String,
      default: '',
    },
  },

  data() {
    return {
      loading: false,
      formData: {},
    };
  },

  computed: {},

  watch: {},

  mounted() {},

  methods: {
    async handleSubmit() {
      this.loading = true;
      try {
        await new Promise(resolve => setTimeout(resolve, 800));
        MessagePlugin.success('操作成功');
      } catch (e) {
        MessagePlugin.error('操作失败，请重试');
      } finally {
        this.loading = false;
      }
    },
  },
};
</script>

<style lang="less" scoped>
/* @spacing-* variables available globally via vite.config.js additionalData */

.feature-name {
  padding: @spacing-lg;

  &__header {
    margin-bottom: @spacing-md;
  }

  &__content {
    // Component-specific styles
  }
}
</style>
```

**Key rules:**
- Use `MessagePlugin.success()` / `MessagePlugin.error()` directly — not `this.$message`.
  TDesign Vue Next exposes `MessagePlugin` as a standalone import that works reliably
  in Options API.
- Root `<div>` class should match BEM block name.
- `name` property must be set on every component for dev tools debugging.

## Single HTML File Template

For simple single-page demos without routing or complex state:

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Demo Title</title>
  <!-- TDesign CSS -->
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/tdesign-vue-next/es/style/index.css" />
  <style>
    /* === Use plain CSS only — no LESS in single files === */
    :root {
      --spacing-xs: 4px;
      --spacing-sm: 8px;
      --spacing-md: 16px;
      --spacing-lg: 24px;
      --spacing-xl: 32px;
    }

    .demo-container {
      max-width: 1200px;
      margin: 0 auto;
      padding: var(--spacing-lg);
    }
  </style>
</head>
<body>
  <div id="app">
    <div class="demo-container">
      <!-- Template here -->
    </div>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/vue@3/dist/vue.global.prod.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/tdesign-vue-next/dist/tdesign.min.js"></script>
  <script>
    const { createApp } = Vue;

    const app = createApp({
      data() {
        return {
          loading: false,
        };
      },
      methods: {},
    });

    app.use(TDesign);
    app.mount('#app');
  </script>
</body>
</html>
```

**Single HTML rules:**
- Use plain CSS with CSS custom properties (`var(--spacing-*)`) instead of LESS variables
- Load Vue 3 + TDesign from CDN
- Keep under ~300 lines; if growing beyond, switch to full project approach