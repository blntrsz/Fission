import { resolve } from "node:path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["src/tests/**/*.test.ts"]
  },
  resolve: {
    alias: {
      "@shared": resolve("src/shared")
    }
  }
});
