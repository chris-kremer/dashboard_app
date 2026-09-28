import { appendTask, completeTask, patchTask, ensureTaskIdentityColumn, parseSchedule, sheetsBatchUpdate, getAccessToken, SHEET_RANGES } from "./sheets";
import type { Env, ScheduleItem } from "./types";

export interface Project { id: string; name: string; category: string; deadline?: string; closed: boolean }
export interface TaskGroup { id: string; projectId: string; parentId?: string; name: string }
export interface Membership { taskId: string; projectId?: string; groupId?: string; resolution?: "done" | "discarded"; checklist?: Array<{ id: string; title: string; done: boolean }> }
export interface ProjectDocument { revision: number; projects: Project[]; groups: TaskGroup[]; memberships: Membership[] }
const empty = (): ProjectDocument => ({ revision: 0, projects: [], groups: [], memberships: [] });

export function validateDocument(value: ProjectDocument): void {
  if (!value || !Number.isInteger(value.revision) || !Array.isArray(value.projects) || !Array.isArray(value.groups) || !Array.isArray(value.memberships)) throw new Error("Invalid project document");
  if (JSON.stringify(value).length > 750_000) throw new Error("Project document too large");
  const ids = new Set<string>();
  for (const item of [...value.projects, ...value.groups]) {
    if (typeof item.id !== "string" || !item.id || ids.has(item.id) || typeof item.name !== "string" || !item.name.trim() || item.name.length > 300) throw new Error("Project/group IDs and names must be unique and nonempty");
    ids.add(item.id);
  }
  const projects = new Set(value.projects.map(p => p.id));
  for (const p of value.projects) {
    if (typeof p.closed !== "boolean" || typeof p.category !== "string" || (p.deadline && !/^\d{4}-\d{2}-\d{2}$/.test(p.deadline))) throw new Error("Invalid project fields");
  }
  const groups = new Map(value.groups.map(g => [g.id, g]));
  for (const group of value.groups) {
    if (!projects.has(group.projectId)) throw new Error("Group project not found");
    const visited = new Set([group.id]);
    let parent = group.parentId;
    while (parent) {
      const candidate = groups.get(parent);
      if (!candidate || candidate.projectId !== group.projectId || visited.has(parent)) throw new Error("Groups must form a tree within one project");
      visited.add(parent); parent = candidate.parentId;
    }
  }
  const tasks = new Set<string>();
  for (const m of value.memberships) {
    if (typeof m.taskId !== "string" || !m.taskId || tasks.has(m.taskId) || (m.projectId && !projects.has(m.projectId)) || (m.groupId && (!m.projectId || groups.get(m.groupId)?.projectId !== m.projectId))) throw new Error("Invalid task membership");
    if (m.resolution && !["done", "discarded"].includes(m.resolution)) throw new Error("Invalid resolution");
    if (m.checklist && (!Array.isArray(m.checklist) || m.checklist.some(i => !i.id || typeof i.title !== "string" || !i.title.trim() || typeof i.done !== "boolean") || new Set(m.checklist.map(i => i.id)).size !== m.checklist.length)) throw new Error("Invalid checklist");
    tasks.add(m.taskId);
  }
}

export async function readProjectSchedule(env: Env): Promise<ScheduleItem[]> {
  const token = await getAccessToken(env);
  const response = await fetch(`https://sheets.googleapis.com/v4/spreadsheets/${env.SPREADSHEET_ID}/values/${encodeURIComponent(SHEET_RANGES.schedule)}?valueRenderOption=UNFORMATTED_VALUE&dateTimeRenderOption=SERIAL_NUMBER`, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`Project schedule read failed: ${response.status}`);
  return parseSchedule((await response.json<{ values?: unknown[][] }>()).values ?? []);
}

/** One serialized metadata writer, independent from notification state. */
export class ProjectCoordinator {
  constructor(private state: DurableObjectState, private env: Env) {}
  async fetch(request: Request): Promise<Response> {
    return this.state.blockConcurrencyWhile(async () => {
      const document = await this.state.storage.get<ProjectDocument>("document") ?? empty();
      const path = new URL(request.url).pathname;
      const response = (body: unknown, status = 200) => Response.json(body, { status });
      try {
        // All app schedule writes use the same coordinator, preventing two creates
        // from calculating and overwriting the same next Sheet row.
        if (path === "/tasks" && request.method === "POST") {
          return response(await appendTask(this.env, await request.json()), 201);
        }
        const task = path.match(/^\/tasks\/(\d+)(\/complete)?$/);
        if (task) {
          const body: any = await request.json();
          if (request.method === "PATCH" && !task[2]) return response(await patchTask(this.env, Number(task[1]), body));
          if (request.method === "POST" && task[2]) return response(await completeTask(this.env, Number(task[1]), body.source ?? "ios", body.stop));
          return response({ error: "Method not allowed" }, 405);
        }
        if (request.method === "GET") return response({ ...document, schedule: await readProjectSchedule(this.env) });
        const body: any = await request.json();
        if (body.revision !== document.revision) return response({ error: "Projects changed elsewhere. Refresh and try again." }, 409);
        if (request.method === "PUT" && path === "/projects") {
          validateDocument(body);
          // A normal metadata save must not detach an existing task silently.
          const next: ProjectDocument = { revision: document.revision + 1, projects: body.projects, groups: body.groups, memberships: body.memberships };
          await this.state.storage.put("document", next);
          return response({ ...next, schedule: await readProjectSchedule(this.env) });
        }
        if (request.method === "POST" && path === "/projects/link") {
          if (!Array.isArray(body.rows) || body.rows.length < 1 || body.rows.length > 100) throw new Error("Select 1–100 tasks");
          const p = document.projects.find(p => p.id === body.projectId && !p.closed);
          if ((body.projectId && !p) || (body.groupId && !document.groups.some(g => g.id === body.groupId && g.projectId === p?.id))) throw new Error("Invalid destination");
          // Validate all row fingerprints before any write; never guess by title.
          const rows: ScheduleItem[] = [];
          const schedule = await readProjectSchedule(this.env);
          for (const ref of body.rows) {
            if (!Number.isInteger(ref.rowNumber) || ref.rowNumber < 2) throw new Error("Invalid row");
            const row = schedule.find(row => row.rowNumber === ref.rowNumber);
            if (!row || row.task !== ref.task || row.date !== ref.date || (ref.taskId && row.taskId !== ref.taskId)) return response({ error: "A Sheet row moved or changed. Refresh before assigning it." }, 409);
            rows.push(row);
          }
          const updates: Array<{ range: string; values: unknown[][] }> = [];
          for (const row of rows) {
            const taskId = row.taskId || crypto.randomUUID();
            if (!row.taskId) updates.push({ range: `schedule!U${row.rowNumber}`, values: [[taskId]] });
            const old = document.memberships.find(m => m.taskId === taskId);
            const m = { ...old, taskId, projectId: p?.id, groupId: body.groupId || undefined, resolution: undefined };
            document.memberships = document.memberships.filter(m => m.taskId !== taskId).concat(m);
          }
          if (updates.length) {
            await ensureTaskIdentityColumn(this.env);
            await sheetsBatchUpdate(this.env, updates);
          }
        } else if (request.method === "POST" && path === "/projects/resolve") {
          const m = document.memberships.find(m => m.taskId === body.taskId);
          if (!m || !["keep", "done", "discarded"].includes(body.action)) throw new Error("Invalid clarification");
          const today = new Intl.DateTimeFormat("en-CA", { timeZone: this.env.TIME_ZONE ?? "Europe/Berlin" }).format(new Date());
          const rows = (await readProjectSchedule(this.env)).filter(r => r.taskId === m.taskId).sort((a, b) => b.date.localeCompare(a.date) || b.rowNumber - a.rowNumber);
          const last = rows[0];
          if (!last || rows.some(r => r.date >= today) || !["open", "in_progress"].includes(last.status)) return response({ error: "This task is no longer missing. Refresh its project." }, 409);
          if (body.action === "keep") {
            await appendTask(this.env, { date: today, task: last.task, category: last.category, comment: last.comment, priority: last.priority, estimateMinutes: last.estimateMinutes, taskId: m.taskId });
            delete m.resolution;
          } else m.resolution = body.action;
        } else return response({ error: "Not found" }, 404);
        document.revision += 1;
        await this.state.storage.put("document", document);
        return response({ ...document, schedule: await readProjectSchedule(this.env) });
      } catch (error) {
        return response({ error: error instanceof Error ? error.message : "Project operation failed" }, 400);
      }
    });
  }
}
