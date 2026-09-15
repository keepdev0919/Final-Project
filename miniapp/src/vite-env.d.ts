/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** 서버 주소 (https). 비우면 Railway 운영 서버. */
  readonly VITE_API_BASE?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
