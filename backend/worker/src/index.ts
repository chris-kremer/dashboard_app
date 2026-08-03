import { appendCaffeine, appendFood, appendTask, completeTask, patchTask, readSnapshot, upsertSleep } from "./sheets";
import type { Env } from "./types";
export { NudgeCoordinator } from "./nudges";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);

      if (request.method === "OPTIONS") {
        return new Response(null, {
          status: 204,
          headers: corsHeaders()
        });
      }

      if (request.method === "GET" && url.pathname === "/health") {
        return json({ ok: true, version: env.VERSION ?? "1.0.0" });
      }

      if (url.pathname === "/media/heartbeat") {
        if (!authorizedWith(request, env.ADDON_API_TOKEN)) {
          return corsJSON({ error: "unauthorized" }, 401);
        }
        if (request.method !== "POST") {
          return corsJSON({ error: "method_not_allowed" }, 405);
        }
        return withCORS(await coordinator(env).fetch(new Request("https://nudge/heartbeat", request)));
      }

      if (!authorized(request, env)) {
        return json({ error: "unauthorized" }, 401);
      }

      if (request.method === "GET" && url.pathname === "/media/sessions") {
        return coordinator(env).fetch(new Request("https://nudge/sessions"));
      }

      if (url.pathname.startsWith("/nudge/")) {
        const targetPath = url.pathname.slice("/nudge".length);
        const target = new URL(`https://nudge${targetPath}`);
        target.search = url.search;
        return coordinator(env).fetch(new Request(target, request));
      }

      if (request.method === "GET" && url.pathname === "/snapshot") {
        const date = url.searchParams.get("date") ?? new Date().toISOString().slice(0, 10);
        return json(await readSnapshot(env, date));
      }

      if (request.method === "POST" && url.pathname === "/tasks") {
        const task = await appendTask(env, await request.json());
        await notifyTaskStateChanged(env);
        return json(task, 201);
      }

      const taskMatch = url.pathname.match(/^\/tasks\/(\d+)(?:\/complete)?$/);
      if (taskMatch && request.method === "PATCH" && !url.pathname.endsWith("/complete")) {
        const task = await patchTask(env, Number(taskMatch[1]), await request.json());
        await notifyTaskStateChanged(env);
        return json(task);
      }
      if (taskMatch && request.method === "POST" && url.pathname.endsWith("/complete")) {
        const body: { source?: string; stop?: string } = await request.json<{ source?: string; stop?: string }>().catch(() => ({}));
        const task = await completeTask(env, Number(taskMatch[1]), body.source ?? "ios", body.stop);
        await notifyTaskStateChanged(env);
        return json(task);
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
  return authorizedWith(request, env.APP_API_TOKEN);
}

function authorizedWith(request: Request, token: string | undefined): boolean {
  const header = request.headers.get("Authorization") ?? "";
  return Boolean(token) && header === `Bearer ${token}`;
}

function coordinator(env: Env): DurableObjectStub {
  const id = env.NUDGE_COORDINATOR.idFromName("primary");
  return env.NUDGE_COORDINATOR.get(id);
}

async function notifyTaskStateChanged(env: Env): Promise<void> {
  try {
    await coordinator(env).fetch(new Request("https://nudge/tasks-changed", { method: "POST" }));
  } catch {
    // Task writes must remain successful even if the optional nudge wake-up fails.
  }
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" }
  });
}

function corsJSON(value: unknown, status = 200): Response {
  return withCORS(json(value, status));
}

function withCORS(response: Response): Response {
  const next = new Response(response.body, response);
  for (const [key, value] of Object.entries(corsHeaders())) {
    next.headers.set(key, value);
  }
  return next;
}

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
    "Access-Control-Max-Age": "86400"
  };
}
