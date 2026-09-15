import { resolve } from "node:path";
import { defineConfig, externalizeDepsPlugin } from "electron-vite";
import react from "@vitejs/plugin-react";

const sharedAlias = {
  "@shared": resolve("src/shared")
};

export default defineConfig({
  main: {
    plugins: [externalizeDepsPlugin()],
    resolve: { alias: sharedAlias },
    build: {
      rollupOptions: {
        input: {
          index: resolve("src/main/index.ts"),
          executionDaemon: resolve("src/main/executionDaemon.ts")
        }
      }
    }
  },
  preload: {
    plugins: [externalizeDepsPlugin()],
    resolve: { alias: sharedAlias }
  },
  renderer: {
    root: "src/renderer",
    resolve: { alias: sharedAlias },
    plugins: [react()]
  }
});
