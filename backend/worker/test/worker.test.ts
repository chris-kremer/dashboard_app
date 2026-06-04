import { describe, expect, it } from "vitest";
import worker from "../src/index";

const env = {
  APP_API_TOKEN: "test-token",
  GOOGLE_SERVICE_ACCOUNT_JSON: "{}",
  SPREADSHEET_ID: "sheet",
  VERSION: "1.0.0"
};

describe("worker auth", () => {
  it("allows health without bearer token", async () => {
    const response = await worker.fetch(new Request("https://example.com/health"), env);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, version: "1.0.0" });
  });

  it("rejects protected endpoints without bearer token", async () => {
    const response = await worker.fetch(new Request("https://example.com/snapshot?date=2026-06-04"), env);
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unauthorized" });
  });
});
