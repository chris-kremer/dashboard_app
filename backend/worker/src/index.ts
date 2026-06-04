import { appendCaffeine, appendFood, appendTask, completeTask, patchTask, readSnapshot, upsertSleep } from "./sheets";
import type { Env } from "./types";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);

      if (request.method === "GET" && url.pathname === "/health") {
        return json({ ok: true, version: env.VERSION ?? "1.0.0" });
      }

      if (!authorized(request, env)) {
        return json({ error: "unauthorized" }, 401);
      }

      if (request.method === "GET" && url.pathname === "/snapshot") {
        const date = url.searchParams.get("date") ?? new Date().toISOString().slice(0, 10);
        return json(await readSnapshot(env, date));
      }

      if (request.method === "POST" && url.pathname === "/tasks") {
        return json(await appendTask(env, await request.json()), 201);
      }

      const taskMatch = url.pathname.match(/^\/tasks\/(\d+)(?:\/complete)?$/);
      if (taskMatch && request.method === "PATCH" && !url.pathname.endsWith("/complete")) {
        return json(await patchTask(env, Number(taskMatch[1]), await request.json()));
      }
      if (taskMatch && request.method === "POST" && url.pathname.endsWith("/complete")) {
        const body: { source?: string } = await request.json<{ source?: string }>().catch(() => ({}));
        return json(await completeTask(env, Number(taskMatch[1]), body.source ?? "ios"));
      }

      if (request.method === "POST" && url.pathname === "/caffeine") {
        return json(await appendCaffeine(env, await request.json()), 201);
      }

      if (request.method === "POST" && url.pathname === "/food") {
        return json(await appendFood(env, await request.json()), 201);
      }

      if (request.method === "POST" && url.pathname === "/sleep") {
        return json(await upsertSleep(env, await request.json()));
      }

      return json({ error: "not_found" }, 404);
    } catch (error) {
      return json({ error: error instanceof Error ? error.message : "unknown_error" }, 500);
    }
  }
};

function authorized(request: Request, env: Env): boolean {
  const header = request.headers.get("Authorization") ?? "";
  return header === `Bearer ${env.APP_API_TOKEN}`;
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" }
  });
}
