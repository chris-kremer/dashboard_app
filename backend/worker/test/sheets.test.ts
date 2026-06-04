import { describe, expect, it } from "vitest";
import {
  buildTaskPatchValues,
  isOpenTask,
  normalizeDate,
  normalizeTime,
  parseCaffeine,
  parseFood,
  parseFreeTime,
  parseSchedule,
  parseSleep
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
      status: "open"
    });
    expect(isOpenTask(task)).toBe(true);
  });

  it("keeps paused tasks open but excludes completed and finished schedule rows", () => {
    const [done, stopped, paused] = parseSchedule([
      ["2026-06-04", "Task", "", "", "", "", "", "", "", "", "", "done"],
      ["2026-06-04", "Lecture", "Public Economics", "", 5, 90, 3, "", 90, "08:30", "10:00", ""],
      ["2026-06-04", "Paused todo", "Admin", "", 4, 30, 8, "", "", "08:30", "08:45", "in_progress"]
    ]);

    expect(isOpenTask(done)).toBe(false);
    expect(isOpenTask(stopped)).toBe(false);
    expect(isOpenTask(paused)).toBe(true);
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
});

describe("request mapping", () => {
  it("builds sparse task patch values", () => {
    expect(buildTaskPatchValues(12, {
      priority: 5,
      estimateMinutes: 30,
      comment: "updated from iOS",
      start: "14:15"
    })).toEqual([
      { range: "schedule!D12", values: [["updated from iOS"]] },
      { range: "schedule!E12", values: [[5]] },
      { range: "schedule!F12", values: [[30]] },
      { range: "schedule!J12", values: [["14:15"]] }
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
