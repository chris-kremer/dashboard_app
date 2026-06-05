import { describe, expect, it } from "vitest";
import {
  SHEET_RANGES,
  buildTaskPatchValues,
  isOpenTask,
  normalizeDate,
  normalizeTime,
  parseCaffeine,
  parseFood,
  parseFreeTime,
  parseSchedule,
  parseSleep,
  rankedLabels
} from "../src/sheets";

describe("sheet parsers", () => {
  it("maps schedule rows into app task models", () => {
    const rows = [[
      45447,
      "Send email",
      "Home/Admin",
      "Todoist",
      4,
      15,
      16,
      "",
      "",
      "",
      "",
      "",
      "",
      ""
    ]];

    const task = parseSchedule(rows)[0];

    expect(task).toEqual({
      rowId: "schedule:2",
      rowNumber: 2,
      date: "2024-06-04",
      task: "Send email",
      category: "Home/Admin",
      comment: "Todoist",
      priority: 4,
      estimateMinutes: 15,
      adjustedPriority: 16,
      delay: undefined,
      actualMinutes: undefined,
      start: undefined,
      stop: undefined,
      status: "open",
      plannedStart: undefined,
      plannedStop: undefined,
      lane: undefined,
      source: undefined,
      sourceId: undefined,
      importedAt: undefined
    });
    expect(isOpenTask(task)).toBe(true);
  });

  it("keeps planned schedule metadata in columns O through T separate from actual start/stop/status", () => {
    const [task] = parseSchedule([[
      "2026-06-05",
      "Scholar pitch",
      "Research",
      "planned via morning import",
      5,
      90,
      3,
      "",
      "",
      "08:30",
      "09:00",
      "logged",
      "",
      "",
      "10:15",
      "11:45",
      "Deep work",
      "google-calendar",
      "calendar-event-123",
      "2026-06-05T06:00:00.000Z"
    ]]);

    expect(task.start).toBe("08:30");
    expect(task.stop).toBe("09:00");
    expect(task.status).toBe("logged");
    expect(task.plannedStart).toBe("10:15");
    expect(task.plannedStop).toBe("11:45");
    expect(task.lane).toBe("Deep work");
    expect(task.source).toBe("google-calendar");
    expect(task.sourceId).toBe("calendar-event-123");
    expect(task.importedAt).toBe("2026-06-05T06:00:00.000Z");
  });

  it("reads schedule rows through column T so planned metadata is available", () => {
    expect(SHEET_RANGES.schedule).toBe("schedule!A2:T");
  });

  it("keeps paused tasks open but excludes completed, logged, and finished schedule rows", () => {
    const [done, stopped, paused, logged] = parseSchedule([
      ["2026-06-04", "Task", "", "", "", "", "", "", "", "", "", "done"],
      ["2026-06-04", "Lecture", "Public Economics", "", 5, 90, 3, "", 90, "08:30", "10:00", ""],
      ["2026-06-04", "Paused todo", "Admin", "", 4, 30, 8, "", "", "08:30", "08:45", "in_progress"],
      ["2026-06-04", "Logged interval", "Admin", "", 4, 30, 8, "", "", "08:30", "08:45", "logged"]
    ]);

    expect(isOpenTask(done)).toBe(false);
    expect(isOpenTask(stopped)).toBe(false);
    expect(isOpenTask(paused)).toBe(true);
    expect(isOpenTask(logged)).toBe(false);
  });

  it("treats future delay as adjusted priority zero", () => {
    const future = new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString();
    const [task] = parseSchedule([
      ["2026-06-04", "Snoozed", "Admin", "", 4, 15, 16, future]
    ]);

    expect(task.adjustedPriority).toBe(0);
    expect(task.delay).toBe(future);
  });

  it("parses caffeine, food, and sleep rows", () => {
    expect(parseCaffeine([["2026-06-04", "big coffee", "09:00"]])[0]).toMatchObject({
      id: "caffein:2",
      date: "2026-06-04",
      label: "big coffee",
      time: "09:00"
    });

    expect(parseFood([["2026-06-04", "09:30", "breakfast", "sandwich", "1", "", "notes", "reported"]])[0]).toMatchObject({
      id: "foodtracker:2",
      mealContext: "breakfast",
      item: "sandwich",
      confidence: "reported"
    });

    expect(parseSleep([["2026-06-04", 7.5, "07:00", 0.5, "00:00", "07:00", "07:30"]])[0]).toEqual({
      date: "2026-06-04",
      sleepHours: 7.5,
      alarmTime: "07:00",
      oversleptHours: 0.5,
      sleepStart: "00:00",
      plannedWake: "07:00",
      actualWake: "07:30"
    });

    expect(parseFreeTime([["2026-06-04", "Walk", 45, "18:00", "18:05", "18:50"]])[0]).toEqual({
      id: "free_time:2",
      date: "2026-06-04",
      label: "Walk",
      durationMinutes: 45,
      time: "18:00",
      start: "18:05",
      end: "18:50"
    });
  });

  it("ranks caffeine labels by count", () => {
    expect(rankedLabels(["coffee", "tea", "Coffee", "espresso", "tea", "coffee"])).toEqual(["coffee", "tea", "espresso"]);
  });
});

describe("request mapping", () => {
  it("builds sparse task patch values", () => {
    expect(buildTaskPatchValues(12, {
      priority: 5,
      estimateMinutes: 30,
      comment: "updated from iOS",
      delay: "2026-06-04T12:00:00.000Z",
      start: "14:15",
      plannedStart: "15:00",
      plannedStop: "16:30",
      lane: "Deep work",
      source: "manual",
      sourceId: "todoist-42",
      importedAt: "2026-06-05T06:00:00.000Z"
    })).toEqual([
      { range: "schedule!D12", values: [["updated from iOS"]] },
      { range: "schedule!E12", values: [[5]] },
      { range: "schedule!F12", values: [[30]] },
      { range: "schedule!H12", values: [["2026-06-04T12:00:00.000Z"]] },
      { range: "schedule!J12", values: [["14:15"]] },
      { range: "schedule!O12", values: [["15:00"]] },
      { range: "schedule!P12", values: [["16:30"]] },
      { range: "schedule!Q12", values: [["Deep work"]] },
      { range: "schedule!R12", values: [["manual"]] },
      { range: "schedule!S12", values: [["todoist-42"]] },
      { range: "schedule!T12", values: [["2026-06-05T06:00:00.000Z"]] }
    ]);
  });

  it("normalizes German dates, ISO dates, serial dates, and serial times", () => {
    expect(normalizeDate("04.06.2026")).toBe("2026-06-04");
    expect(normalizeDate("2026-06-04T10:45:00+02:00")).toBe("2026-06-04");
    expect(normalizeDate(45447)).toBe("2024-06-04");
    expect(normalizeTime(0.5)).toBe("12:00");
    expect(normalizeTime("8:05")).toBe("08:05");
  });
});
