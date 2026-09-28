import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../src/types";
import { ProjectCoordinator } from "../src/projects";

const fixture = vi.hoisted(() => ({ rows: [] as unknown[][], writes: 0 }));
vi.mock("../src/sheets", async importOriginal => {
  const actual = await importOriginal<typeof import("../src/sheets")>();
  return { ...actual, getAccessToken: async () => "fixture-token", ensureTaskIdentityColumn: async () => {},
    sheetsBatchUpdate: async (env: unknown, updates: Array<{ range: string; values: unknown[][] }>) => {
      for (const update of updates) {
        const row = Number(update.range.match(/U(\d+)/)![1]);
        fixture.rows[row - 2][20] = update.values[0][0]; fixture.writes++;
      }
    },
    appendTask: async (env: unknown, body: any) => {
      const row = Array(21).fill(""); row[0] = body.date; row[1] = body.task; row[2] = body.category; row[20] = body.taskId;
      fixture.rows.push(row); fixture.writes++;
      return actual.parseSchedule([row], fixture.rows.length + 1)[0];
    }
  };
});

function coordinator() {
  const storage = new Map<string, unknown>();
  return new ProjectCoordinator({
    storage: { get: async (k: string) => structuredClone(storage.get(k)), put: async (k: string, v: unknown) => { storage.set(k, structuredClone(v)); } },
    blockConcurrencyWhile: async (f: () => Promise<Response>) => f()
  } as unknown as DurableObjectState, { SPREADSHEET_ID: "fixture", TIME_ZONE: "Europe/Berlin" } as Env);
}
const request = (path: string, method = "GET", body?: unknown) => new Request("https://fixture" + path, { method, ...(body ? { body: JSON.stringify(body) } : {}) });
const document = () => ({ revision: 0, projects: [{ id: "p", name: "Paper", category: "Work", closed: false }], groups: [], memberships: [] });

describe("project coordinator persistence and safe mutations", () => {
  beforeEach(() => {
    fixture.rows = []; fixture.writes = 0;
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({ values: fixture.rows })));
  });
  it("rejects stale metadata without losing saved projects", async () => {
    const c = coordinator();
    expect((await c.fetch(request("/projects", "PUT", document()))).status).toBe(200);
    expect((await c.fetch(request("/projects", "PUT", document()))).status).toBe(409);
    const saved: any = await (await c.fetch(request("/projects"))).json();
    expect(saved.projects[0].name).toBe("Paper"); expect(saved.revision).toBe(1);
  });
  it("verifies row fingerprints before stamping IDs", async () => {
    const row = Array(21).fill(""); row[0] = "2026-09-28"; row[1] = "Original"; fixture.rows = [row];
    const c = coordinator(); await c.fetch(request("/projects", "PUT", document()));
    const bad = { revision: 1, projectId: "p", rows: [{ rowNumber: 2, task: "Different", date: "2026-09-28" }] };
    expect((await c.fetch(request("/projects/link", "POST", bad))).status).toBe(409);
    expect(fixture.writes).toBe(0);
    bad.rows[0].task = "Original";
    const good: any = await (await c.fetch(request("/projects/link", "POST", bad))).json();
    expect(good.memberships[0].taskId).toBe(fixture.rows[0][20]);
    expect(good.revision).toBe(2);
  });
  it("keep is not replayed and does not rewrite historical status", async () => {
    const row = Array(21).fill(""); row[0] = "2000-01-01"; row[1] = "Missing"; row[20] = "logical"; fixture.rows = [row];
    const c = coordinator(); const doc: any = document(); doc.memberships = [{ projectId: "p", taskId: "logical" }];
    await c.fetch(request("/projects", "PUT", doc));
    const resolve = { revision: 1, taskId: "logical", action: "keep" };
    expect((await c.fetch(request("/projects/resolve", "POST", resolve))).status).toBe(200);
    expect((await c.fetch(request("/projects/resolve", "POST", resolve))).status).toBe(409);
    expect(fixture.rows).toHaveLength(2); expect(fixture.rows[0][11]).toBe("");
    expect(fixture.rows[1][20]).toBe("logical");
  });
  it("done and discarded resolutions do not modify Sheet history", async () => {
    const row = Array(21).fill(""); row[0] = "2000-01-01"; row[1] = "Missing"; row[20] = "logical"; fixture.rows = [row];
    const c = coordinator(); const doc: any = document(); doc.memberships = [{ projectId: "p", taskId: "logical" }];
    await c.fetch(request("/projects", "PUT", doc));
    const result: any = await (await c.fetch(request("/projects/resolve", "POST", { revision: 1, taskId: "logical", action: "done" }))).json();
    expect(result.memberships[0].resolution).toBe("done"); expect(fixture.writes).toBe(0);
  });
});
