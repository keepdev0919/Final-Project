import { defineConfig } from 'vitest/config'

// 테스트는 순수 로직(저장·판정)만 본다 — SDK mock·React 플러그인 없이 node 에서 돈다.
// (vite.config.ts 를 쓰지 않도록 따로 둔다. 그쪽은 devtools 가 SDK 를 바꿔치기한다.)
export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
  },
})
