import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

import aitDevtools from "@apps-in-toss/devtools/unplugin";

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    // 패널은 진입점 하나(src/main.tsx)에만 넣는다. 기본 패턴은 index.ts 도 잡아서
    // src/api/index.ts · src/ui/index.ts 같은 모음 파일에까지 패널 import 가 들어간다.
    aitDevtools.vite({ entryPattern: /\/src\/main\.tsx$/ }),
    react(),
  ],
})
