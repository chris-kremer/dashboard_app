import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["test/**/*.test.ts"],
    pool: "forks",
    reporters: ["default"],
    testTimeout: 5000
  }
});
