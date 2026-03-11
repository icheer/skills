#!/usr/bin/env python3
"""
Vue 3 + TDesign project scaffolding generator.

Usage:
    python scripts/scaffold.py --name my-project --platform desktop
    python scripts/scaffold.py --name my-project --platform mobile

Generates the standard directory structure with all boilerplate files
so the agent can start writing components immediately.

requires: python3 (no external dependencies)
"""

import argparse
import os
import sys

TDESIGN_CONFIG = {
    "desktop": {
        "package": "tdesign-vue-next",
        "css_import": "tdesign-vue-next/es/style/index.css",
        "import_name": "tdesign-vue-next",
    },
    "mobile": {
        "package": "tdesign-mobile-vue",
        "css_import": "tdesign-mobile-vue/es/style/index.css",
        "import_name": "tdesign-mobile-vue",
    },
}


def create_file(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"  ✅ {path}")


def scaffold(name, platform):
    cfg = TDESIGN_CONFIG[platform]
    root = name

    if os.path.exists(root):
        print(f"❌ Directory '{root}' already exists. Choose a different name or remove it first.")
        sys.exit(1)

    print(f"\n🚀 Scaffolding '{name}' ({platform})...\n")

    # package.json
    create_file(f"{root}/package.json", f"""\
{{
  "name": "{name}",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {{
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  }},
  "dependencies": {{
    "vue": "^3.4.0",
    "{cfg['package']}": "latest",
    "vue-router": "^4.3.0"
  }},
  "devDependencies": {{
    "@vitejs/plugin-vue": "^5.0.0",
    "less": "^4.2.0",
    "vite": "^5.4.0"
  }}
}}
""")

    # index.html
    create_file(f"{root}/index.html", f"""\
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>{name}</title>
</head>
<body>
  <div id="app"></div>
  <script type="module" src="/src/main.js"></script>
</body>
</html>
""")

    # vite.config.js
    create_file(f"{root}/vite.config.js", """\
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import path from 'path';

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  css: {
    preprocessorOptions: {
      less: {
        // Auto-inject variables.less into every component — no manual @import needed
        additionalData: `@import "@/assets/styles/variables.less";`,
      },
    },
  },
});
""")

    # main.js
    create_file(f"{root}/src/main.js", f"""\
import {{ createApp }} from 'vue';
import TDesign from '{cfg['import_name']}';
import '{cfg['css_import']}';
import App from './App.vue';
import router from './router';

const app = createApp(App);
app.use(TDesign);
app.use(router);
app.mount('#app');
""")

    # App.vue
    create_file(f"{root}/src/App.vue", """\
<template>
  <div id="app">
    <router-view />
  </div>
</template>

<script>
export default {
  name: 'App',
};
</script>

<style lang="less">
@import '@/assets/styles/global.less';
</style>
""")

    # router/index.js
    create_file(f"{root}/src/router/index.js", """\
import { createRouter, createWebHistory } from 'vue-router';

const routes = [
  {
    path: '/',
    name: 'Home',
    component: () => import('@/pages/HomeView.vue'),
  },
];

const router = createRouter({
  history: createWebHistory(),
  routes,
});

export default router;
""")

    # pages/HomeView.vue
    create_file(f"{root}/src/pages/HomeView.vue", """\
<template>
  <div class="home-view">
    <h1>Demo Home</h1>
    <p>Replace this with your first view.</p>
  </div>
</template>

<script>
export default {
  name: 'HomeView',
  data() {
    return {};
  },
};
</script>

<style lang="less" scoped>
.home-view {
  padding: @spacing-lg;
}
</style>
""")

    # assets/styles/variables.less
    create_file(f"{root}/src/assets/styles/variables.less", """\
// === Spacing (4px base unit) ===
@spacing-xs: 4px;
@spacing-sm: 8px;
@spacing-md: 16px;
@spacing-lg: 24px;
@spacing-xl: 32px;

// === Brand Colors (extend TDesign tokens as needed) ===
@brand-color: var(--td-brand-color, #0052d9);
@brand-color-light: var(--td-brand-color-light, #e8f3ff);

// === Text Colors ===
@text-primary: var(--td-text-color-primary, rgba(0, 0, 0, 0.9));
@text-secondary: var(--td-text-color-secondary, rgba(0, 0, 0, 0.6));
@text-placeholder: var(--td-text-color-placeholder, rgba(0, 0, 0, 0.35));

// === Background ===
@bg-color-page: var(--td-bg-color-page, #f3f3f3);
@bg-color-container: var(--td-bg-color-container, #ffffff);

// === Border Radius ===
@radius-sm: 4px;
@radius-md: 8px;
@radius-lg: 12px;
""")

    # assets/styles/mixins.less
    create_file(f"{root}/src/assets/styles/mixins.less", """\
// === Text truncation ===
.text-ellipsis() {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.text-ellipsis-multiline(@lines: 2) {
  display: -webkit-box;
  -webkit-line-clamp: @lines;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

// === Responsive breakpoints ===
@screen-sm: 768px;
@screen-md: 1024px;
@screen-lg: 1440px;

.respond-above(@breakpoint, @rules) {
  @media (min-width: @breakpoint) {
    @rules();
  }
}
""")

    # assets/styles/global.less
    create_file(f"{root}/src/assets/styles/global.less", """\
@import './mixins.less';

// === Global Reset ===
*,
*::before,
*::after {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

html, body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto,
    'Helvetica Neue', Arial, sans-serif;
  background-color: @bg-color-page;
  color: @text-primary;
}

// === TDesign Overrides (if needed) ===
// Add global TDesign style overrides here
""")

    # mock/data.js
    create_file(f"{root}/src/mock/data.js", """\
/**
 * Mock data for API and AI interaction simulation.
 *
 * Usage in components:
 *   import { mockUsers, simulateApiCall } from '@/mock/data';
 *
 * simulateApiCall wraps data in a Promise with configurable delay
 * to trigger loading states naturally.
 */

export const mockUsers = [
  { id: 1, name: '张三', role: '产品经理', avatar: '' },
  { id: 2, name: '李四', role: '前端工程师', avatar: '' },
  { id: 3, name: '王五', role: '设计师', avatar: '' },
];

/**
 * Simulate an async API call with realistic latency.
 * @param {*} data - The data to resolve with
 * @param {number} delay - Delay in ms (default: 800)
 * @returns {Promise}
 */
export function simulateApiCall(data, delay = 800) {
  return new Promise((resolve) => {
    setTimeout(() => resolve(data), delay);
  });
}

/**
 * Simulate an API call that may fail.
 * @param {*} data - The data to resolve with
 * @param {number} failRate - Probability of failure (0-1, default: 0)
 * @param {number} delay - Delay in ms
 * @returns {Promise}
 */
export function simulateApiCallWithError(data, failRate = 0, delay = 800) {
  return new Promise((resolve, reject) => {
    setTimeout(() => {
      if (Math.random() < failRate) {
        reject(new Error('模拟网络错误，请重试'));
      } else {
        resolve(data);
      }
    }, delay);
  });
}
""")

    # .gitignore
    create_file(f"{root}/.gitignore", """\
node_modules/
dist/
.DS_Store
*.local
""")

    print(f"\n✅ Project '{name}' scaffolded successfully!")
    print(f"\nNext steps:")
    print(f"  cd {name}")
    print(f"  npm install")
    print(f"  npm run dev")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Scaffold a Vue 3 + TDesign project")
    parser.add_argument("--name", required=True, help="Project directory name")
    parser.add_argument(
        "--platform",
        required=True,
        choices=["desktop", "mobile"],
        help="Target platform: 'desktop' (TDesign Vue Next) or 'mobile' (TDesign Mobile Vue)",
    )
    args = parser.parse_args()
    scaffold(args.name, args.platform)