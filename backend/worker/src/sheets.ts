import type { CaffeineEntry, Env, FoodEntry, FreeTimeEntry, ScheduleItem, SleepEntry, TrackerSnapshot } from "./types";

const SHEETS_BASE = "https://sheets.googleapis.com/v4/spreadsheets";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/spreadsheets";

export const SHEET_RANGES = {
  schedule: "schedule!A2:T",
  caffeine: "caffein!A2:D",
  food: "foodtracker!A2:H",
  sleep: "sleep!A2:G",
  freeTime: "free_time!A2:F"
} as const;

let cachedToken: { token: string; expiresAt: number } | undefined;

interface ServiceAccount {
  client_email: string;
  private_key: string;
}

export async function getAccessToken(env: Env): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) {
    return cachedToken.token;
  }

  const account = JSON.parse(env.GOOGLE_SERVICE_ACCOUNT_JSON) as ServiceAccount;
  const now = Math.floor(Date.now() / 1000);
  const assertion = await signJWT(account.private_key, {
    iss: account.client_email,
    scope: SCOPE,
    aud: TOKEN_URL,
    exp: now + 3600,
    iat: now
  });

  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion
    })
  });

  if (!response.ok) {
    throw new Error(`Google token request failed: ${response.status} ${await response.text()}`);
  }

  const body = await response.json<{ access_token: string; expires_in: number }>();
  cachedToken = { token: body.access_token, expiresAt: Date.now() + body.expires_in * 1000 };
  return cachedToken.token;
}

export async function readSnapshot(env: Env, date: string): Promise<TrackerSnapshot> {
  const ranges = [SHEET_RANGES.schedule, SHEET_RANGES.caffeine, SHEET_RANGES.food, SHEET_RANGES.sleep, SHEET_RANGES.freeTime];
  const result = await sheetsGetBatch(env, ranges);
  const values = result.valueRanges ?? [];
  const allSchedule = parseSchedule(values[0]?.values ?? []);
  const schedule = allSchedule.filter(item => item.date === date);
  const openTasks = allSchedule.filter(isOpenTask).sort(sortByAdjustedPriority);
  const allCaffeine = parseCaffeine(values[1]?.values ?? []);
  const caffeine = allCaffeine.filter(item => item.date === date);
  const caffeineOptions = rankedLabels(allCaffeine.map(item => item.label));
  const food = parseFood(values[2]?.values ?? []).filter(item => item.date === date);
  const sleep = parseSleep(values[3]?.values ?? []).find(item => item.date === date) ?? null;
  const freeTime = parseFreeTime(values[4]?.values ?? []).filter(item => item.date === date);

  return { serverTime: new Date().toISOString(), date, schedule, openTasks, caffeine, caffeineOptions, food, sleep, freeTime };
}

export async function appendTask(env: Env, body: any): Promise<ScheduleItem> {
  const rowNumber = await nextRowNumber(env, "schedule");
  const values = [[
    body.date ?? "",
    body.task ?? "",
    body.category ?? "",
    body.comment ?? "",
    body.priority ?? "",
    body.estimateMinutes ?? "",
    `=IF(AND(E${rowNumber}<>"";F${rowNumber}<>"");INT(E${rowNumber}/(F${rowNumber}/60));"")`,
    "",
    `=IF(AND(J${rowNumber}<>"";K${rowNumber}<>"");ROUND(MOD(K${rowNumber}-J${rowNumber};1)*1440;0);"")`,
    "",
    "",
    "",
    "",
    ""
  ]];
  await sheetsAppend(env, "schedule!A:N", values);
  return await readScheduleRow(env, rowNumber);
}

export async function patchTask(env: Env, rowNumber: number, body: any): Promise<ScheduleItem> {
  const updates = buildTaskPatchValues(rowNumber, body);
  if (updates.length > 0) {
    await sheetsBatchUpdate(env, updates);
  }
  return await readScheduleRow(env, rowNumber);
}

export async function completeTask(env: Env, rowNumber: number, source: string): Promise<ScheduleItem> {
  await sheetsBatchUpdate(env, [
    { range: `schedule!L${rowNumber}:N${rowNumber}`, values: [["done", new Date().toISOString(), source || "ios"]] }
  ]);
  return await readScheduleRow(env, rowNumber);
}

export async function appendCaffeine(env: Env, body: any): Promise<CaffeineEntry> {
  const rowNumber = await nextRowNumber(env, "caffein");
  await sheetsAppend(env, "caffein!A:D", [[body.date ?? "", body.label ?? "", body.time ?? "", `=A${rowNumber}+C${rowNumber}`]]);
  return { id: `caffein:${rowNumber}`, date: normalizeDate(body.date), label: body.label ?? "", time: normalizeTime(body.time) };
}

export async function appendFood(env: Env, body: any): Promise<FoodEntry> {
  const rowNumber = await nextRowNumber(env, "foodtracker");
  const row = [body.date ?? "", body.time ?? "", body.mealContext ?? "", body.item ?? "", body.amount ?? "", body.location ?? "", body.notes ?? "", body.confidence ?? ""];
  await sheetsAppend(env, "foodtracker!A:H", [row]);
  return parseFood([row], rowNumber)[0];
}

export async function upsertSleep(env: Env, body: any): Promise<SleepEntry> {
  const rows = await sheetsGet(env, "sleep!A2:G");
  const existingIndex = (rows.values ?? []).findIndex(row => normalizeDate(cell(row, 0)) === normalizeDate(body.date));
  const values = [[body.date ?? "", body.sleepHours ?? "", body.alarmTime ?? "", body.oversleptHours ?? "", body.sleepStart ?? "", body.plannedWake ?? "", body.actualWake ?? ""]];
  if (existingIndex >= 0) {
    const rowNumber = existingIndex + 2;
    await sheetsBatchUpdate(env, [{ range: `sleep!A${rowNumber}:G${rowNumber}`, values }]);
  } else {
    await sheetsAppend(env, "sleep!A:G", values);
  }
  return parseSleep(values)[0];
}

export function buildTaskPatchValues(rowNumber: number, body: any): Array<{ range: string; values: unknown[][] }> {
  const cells: Array<[string, unknown]> = [];
  if ("comment" in body) cells.push([`D${rowNumber}`, body.comment ?? ""]);
  if ("priority" in body) cells.push([`E${rowNumber}`, body.priority ?? ""]);
  if ("estimateMinutes" in body) cells.push([`F${rowNumber}`, body.estimateMinutes ?? ""]);
  if ("delay" in body) cells.push([`H${rowNumber}`, body.delay ?? ""]);
  if ("start" in body) cells.push([`J${rowNumber}`, body.start ?? ""]);
  if ("stop" in body) cells.push([`K${rowNumber}`, body.stop ?? ""]);
  if ("status" in body) cells.push([`L${rowNumber}`, body.status ?? ""]);
  if ("plannedStart" in body) cells.push([`O${rowNumber}`, body.plannedStart ?? ""]);
  if ("plannedStop" in body) cells.push([`P${rowNumber}`, body.plannedStop ?? ""]);
  if ("lane" in body) cells.push([`Q${rowNumber}`, body.lane ?? ""]);
  if ("source" in body) cells.push([`R${rowNumber}`, body.source ?? ""]);
  if ("sourceId" in body) cells.push([`S${rowNumber}`, body.sourceId ?? ""]);
  if ("importedAt" in body) cells.push([`T${rowNumber}`, body.importedAt ?? ""]);
  return cells.map(([cellRef, value]) => ({ range: `schedule!${cellRef}`, values: [[value]] }));
}

export function parseSchedule(rows: unknown[][], startRow = 2): ScheduleItem[] {
  return rows.map((row, index) => {
    const rowNumber = startRow + index;
    const rawStatus = String(cell(row, 11) || "").trim().toLowerCase();
    const status: ScheduleItem["status"] = rawStatus === "done" || rawStatus === "cancelled" || rawStatus === "in_progress" || rawStatus === "logged" ? rawStatus : "open";
    return {
      rowId: `schedule:${rowNumber}`,
      rowNumber,
      date: normalizeDate(cell(row, 0)),
      task: String(cell(row, 1) ?? ""),
      category: String(cell(row, 2) ?? ""),
      comment: optionalString(cell(row, 3)),
      priority: optionalNumber(cell(row, 4)),
      estimateMinutes: optionalNumber(cell(row, 5)),
      adjustedPriority: effectiveAdjustedPriority(optionalNumber(cell(row, 6)), optionalString(cell(row, 7))),
      delay: optionalString(cell(row, 7)),
      actualMinutes: optionalNumber(cell(row, 8)),
      start: optionalTime(cell(row, 9)),
      stop: optionalTime(cell(row, 10)),
      status,
      plannedStart: optionalTime(cell(row, 14)),
      plannedStop: optionalTime(cell(row, 15)),
      lane: optionalString(cell(row, 16)),
      source: optionalString(cell(row, 17)),
      sourceId: optionalString(cell(row, 18)),
      importedAt: optionalString(cell(row, 19))
    };
  }).filter(item => item.task.trim().length > 0);
}

export function parseCaffeine(rows: unknown[][], startRow = 2): CaffeineEntry[] {
  return rows.map((row, index) => ({
    id: `caffein:${startRow + index}`,
    date: normalizeDate(cell(row, 0)),
    label: String(cell(row, 1) ?? ""),
    time: normalizeTime(cell(row, 2))
  })).filter(item => item.label.length > 0);
}

export function parseFood(rows: unknown[][], startRow = 2): FoodEntry[] {
  return rows.map((row, index) => ({
    id: `foodtracker:${startRow + index}`,
    date: normalizeDate(cell(row, 0)),
    time: normalizeTime(cell(row, 1)),
    mealContext: String(cell(row, 2) ?? ""),
    item: String(cell(row, 3) ?? ""),
    amount: optionalString(cell(row, 4)),
    location: optionalString(cell(row, 5)),
    notes: optionalString(cell(row, 6)),
    confidence: optionalString(cell(row, 7))
  })).filter(item => item.item.length > 0);
}

export function parseSleep(rows: unknown[][]): SleepEntry[] {
  return rows.map(row => ({
    date: normalizeDate(cell(row, 0)),
    sleepHours: optionalNumber(cell(row, 1)),
    alarmTime: optionalTime(cell(row, 2)),
    oversleptHours: optionalNumber(cell(row, 3)),
    sleepStart: optionalTime(cell(row, 4)),
    plannedWake: optionalTime(cell(row, 5)),
    actualWake: optionalTime(cell(row, 6))
  })).filter(item => item.date.length > 0);
}

export function parseFreeTime(rows: unknown[][], startRow = 2): FreeTimeEntry[] {
  return rows.map((row, index) => ({
    id: `free_time:${startRow + index}`,
    date: normalizeDate(cell(row, 0)),
    label: String(cell(row, 1) ?? ""),
    durationMinutes: optionalNumber(cell(row, 2)),
    time: optionalTime(cell(row, 3)),
    start: optionalTime(cell(row, 4)),
    end: optionalTime(cell(row, 5))
  })).filter(item => item.date.length > 0 && item.label.length > 0);
}

export function isOpenTask(item: ScheduleItem): boolean {
  return item.task.trim().length > 0 && item.status !== "done" && item.status !== "cancelled" && item.status !== "logged" && (!item.stop || item.status === "in_progress");
}

export function rankedLabels(labels: string[]): string[] {
  const counts = new Map<string, { label: string; count: number }>();
  for (const label of labels) {
    const normalized = label.trim().toLowerCase();
    if (!normalized) continue;
    const existing = counts.get(normalized);
    if (existing) {
      existing.count += 1;
    } else {
      counts.set(normalized, { label: label.trim(), count: 1 });
    }
  }
  return [...counts.values()]
    .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label))
    .map(item => item.label);
}

export function normalizeDate(value: unknown): string {
  if (value == null || value === "") return "";
  if (typeof value === "number") return serialDateToDate(value).toISOString().slice(0, 10);
  const stringValue = String(value);
  const direct = stringValue.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (direct) return direct[0].slice(0, 10);
  const german = stringValue.match(/^(\d{1,2})[./](\d{1,2})[./](\d{2,4})$/);
  if (german) {
    const year = german[3].length === 2 ? `20${german[3]}` : german[3];
    return `${year}-${german[2].padStart(2, "0")}-${german[1].padStart(2, "0")}`;
  }
  return stringValue;
}

export function normalizeTime(value: unknown): string {
  if (value == null || value === "") return "";
  if (typeof value === "number") {
    const minutes = Math.round((value % 1) * 24 * 60);
    return `${Math.floor(minutes / 60).toString().padStart(2, "0")}:${(minutes % 60).toString().padStart(2, "0")}`;
  }
  const stringValue = String(value);
  const match = stringValue.match(/(\d{1,2}):(\d{2})/);
  if (match) return `${match[1].padStart(2, "0")}:${match[2]}`;
  return stringValue;
}

function optionalTime(value: unknown): string | undefined {
  const time = normalizeTime(value);
  return time ? time : undefined;
}

function optionalString(value: unknown): string | undefined {
  if (value == null || value === "") return undefined;
  return String(value);
}

function optionalNumber(value: unknown): number | undefined {
  if (value == null || value === "") return undefined;
  const number = Number(value);
  return Number.isFinite(number) ? number : undefined;
}

function serialDateToDate(serial: number): Date {
  return new Date(Date.UTC(1899, 11, 30) + serial * 24 * 60 * 60 * 1000);
}

function sortByAdjustedPriority(a: ScheduleItem, b: ScheduleItem): number {
  return (b.adjustedPriority ?? -1) - (a.adjustedPriority ?? -1) || (b.priority ?? -1) - (a.priority ?? -1);
}

function effectiveAdjustedPriority(adjustedPriority: number | undefined, delay: string | undefined): number | undefined {
  if (delay && Date.parse(delay) > Date.now()) return 0;
  return adjustedPriority;
}

function cell(row: unknown[], index: number): unknown {
  return row[index] ?? "";
}

async function readScheduleRow(env: Env, rowNumber: number): Promise<ScheduleItem> {
  const result = await sheetsGet(env, `schedule!A${rowNumber}:T${rowNumber}`);
  return parseSchedule(result.values ?? [], rowNumber)[0];
}

async function nextRowNumber(env: Env, sheetName: string): Promise<number> {
  const result = await sheetsGet(env, `${sheetName}!A:A`);
  return (result.values?.length ?? 1) + 1;
}

async function sheetsGet(env: Env, range: string): Promise<{ values?: unknown[][] }> {
  const token = await getAccessToken(env);
  const url = `${SHEETS_BASE}/${env.SPREADSHEET_ID}/values/${encodeURIComponent(range)}?valueRenderOption=UNFORMATTED_VALUE&dateTimeRenderOption=SERIAL_NUMBER`;
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`Sheets get failed: ${response.status} ${await response.text()}`);
  return await response.json();
}

async function sheetsGetBatch(env: Env, ranges: string[]): Promise<{ valueRanges?: Array<{ values?: unknown[][] }> }> {
  const token = await getAccessToken(env);
  const params = new URLSearchParams({ valueRenderOption: "UNFORMATTED_VALUE", dateTimeRenderOption: "SERIAL_NUMBER" });
  for (const range of ranges) params.append("ranges", range);
  const response = await fetch(`${SHEETS_BASE}/${env.SPREADSHEET_ID}/values:batchGet?${params}`, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`Sheets batchGet failed: ${response.status} ${await response.text()}`);
  return await response.json();
}

async function sheetsAppend(env: Env, range: string, values: unknown[][]): Promise<void> {
  const token = await getAccessToken(env);
  const url = `${SHEETS_BASE}/${env.SPREADSHEET_ID}/values/${encodeURIComponent(range)}:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS`;
  const response = await fetch(url, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ values })
  });
  if (!response.ok) throw new Error(`Sheets append failed: ${response.status} ${await response.text()}`);
}

async function sheetsBatchUpdate(env: Env, data: Array<{ range: string; values: unknown[][] }>): Promise<void> {
  const token = await getAccessToken(env);
  const response = await fetch(`${SHEETS_BASE}/${env.SPREADSHEET_ID}/values:batchUpdate`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ valueInputOption: "USER_ENTERED", data })
  });
  if (!response.ok) throw new Error(`Sheets batchUpdate failed: ${response.status} ${await response.text()}`);
}

async function signJWT(privateKeyPem: string, payload: Record<string, unknown>): Promise<string> {
  const unsigned = `${base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${base64url(JSON.stringify(payload))}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${base64url(signature)}`;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const normalized = pem.replace(/\\n/g, "\n").replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes.buffer;
}

function base64url(value: string | ArrayBuffer): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : new Uint8Array(value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
