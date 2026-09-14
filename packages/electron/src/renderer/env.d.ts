/// <reference types="vite/client" />

import type { FissionAPI } from "../preload";

declare global {
  interface Window {
    fission: FissionAPI;
  }
}

export {};
