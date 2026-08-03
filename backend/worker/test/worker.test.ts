import { describe, expect, it } from "vitest";
import worker from "../src/index";

const env = {
  APP_API_TOKEN: "test-token",
  ADDON_API_TOKEN: "addon-token",
  GOOGLE_SERVICE_ACCOUNT_JSON: "{}",
  SPREADSHEET_ID: "sheet",
  VERSION: "1.0.0",
  NUDGE_COORDINATOR: {
    idFromName: () => ({}) as DurableObjectId,
    get: () => ({
      fetch: async () => new Response(JSON.stringify({ ok: true }), {
        headers: { "Content-Type": "application/json" }
      })
    }) as unknown as DurableObjectStub
  } as unknown as DurableObjectNamespace
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

  it("accepts authenticated extension heartbeats with CORS", async () => {
    const response = await worker.fetch(new Request("https://example.com/media/heartbeat", {
      method: "POST",
      headers: {
        Authorization: "Bearer addon-token",
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ source: "youtube", active: true })
    }), env);
    expect(response.status).toBe(200);
    expect(response.headers.get("Access-Control-Allow-Origin")).toBe("*");
  });

  it("rejects extension heartbeats signed with the app token", async () => {
    const response = await worker.fetch(new Request("https://example.com/media/heartbeat", {
      method: "POST",
      headers: { Authorization: "Bearer test-token" }
    }), env);
    expect(response.status).toBe(401);
  });

  it("serves cloud media sessions to the authenticated app", async () => {
    const response = await worker.fetch(new Request("https://example.com/media/sessions", {
      headers: { Authorization: "Bearer test-token" }
    }), env);
    expect(response.status).toBe(200);
  });
});
