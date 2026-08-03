import { describe, expect, it } from "vitest";
import {
  followUpAlert,
  hasProductiveTaskInProgress,
  initialAlert,
  parsePersonalizedAlerts,
  personalizedAlertsSchema,
  personalizedNudgeSystemPrompt,
  randomFollowUpDelayMs,
  rewardAlert
} from "../src/nudges";
import type { ScheduleItem, TrackerSnapshot } from "../src/types";

function task(overrides: Partial<ScheduleItem> = {}): ScheduleItem {
  return {
    rowId: "schedule:2",
    rowNumber: 2,
    date: "2026-08-03",
    task: "Write project brief",
    category: "Work",
    status: "in_progress",
    start: "09:15",
    ...overrides
  };
}

function snapshot(tasks: ScheduleItem[]): TrackerSnapshot {
  return {
    serverTime: "2026-08-03T08:00:00.000Z",
    date: "2026-08-03",
    schedule: tasks,
    openTasks: tasks,
    caffeine: [],
    caffeineOptions: [],
    food: [],
    sleep: null,
    freeTime: []
  };
}

describe("watch nudge variation", () => {
  it("suppresses nudges while a productive task is actively running", () => {
    expect(hasProductiveTaskInProgress(snapshot([task()]))).toBe(true);
  });

  it("does not treat completed or merely open tasks as actively running", () => {
    expect(hasProductiveTaskInProgress(snapshot([
      task({ rowNumber: 2, status: "done", stop: "09:45" }),
      task({ rowNumber: 3, status: "open", start: undefined })
    ]))).toBe(false);
  });

  it("does not let a free-time task suppress free-time nudges", () => {
    expect(hasProductiveTaskInProgress(snapshot([
      task({ rowNumber: 2, category: "Free Time" }),
      task({ rowNumber: 3, category: "Social_Media" }),
      task({ rowNumber: 4, category: "YouTube" })
    ]))).toBe(false);
  });

  it("randomizes follow-up delays from one to three minutes, averaging two", () => {
    expect(randomFollowUpDelayMs(() => 0)).toBe(60_000);
    expect(randomFollowUpDelayMs(() => 0.5)).toBe(120_000);
    expect(randomFollowUpDelayMs(() => 0.999999)).toBeLessThan(180_000);
  });

  it("selects different follow-up messages", () => {
    const first = followUpAlert("YouTube", 4, () => 0);
    const last = followUpAlert("YouTube", 4, () => 0.999999);

    expect(first).not.toEqual(last);
    expect(first.body).toContain("4 minutes");
    expect(last.body).toContain("YouTube");
  });

  it("keeps the first session message focused on leaving immediately", () => {
    const alert = initialAlert("YouTube", 0, 0, () => 0);

    expect(alert.title).toBe("Caught you on YouTube");
    expect(alert.body).not.toContain("already spent");
  });

  it("includes cumulative daily time in repeat-session messages", () => {
    const first = initialAlert("YouTube", 2, 25, () => 0);
    const last = initialAlert("X", 3, 41, () => 0.999999);

    expect(first.title).toBe("You're on YouTube again");
    expect(first.body).toContain("25 minutes");
    expect(last.body).toContain("41 minutes");
  });

  it("can include cumulative daily time in follow-up messages", () => {
    const alert = followUpAlert("X", 6, () => 0.999999, 29);

    expect(alert.body).toContain("29 minutes");
  });

  it("parses and bounds Cloudflare-generated alert bundles", () => {
    const alerts = parsePersonalizedAlerts({
      response: JSON.stringify({
        alerts: Array.from({ length: 7 }, (_, index) => ({
          title: index === 0 ? "T".repeat(80) : `Alert ${index}`,
          body: index === 0 ? "B".repeat(220) : `Body ${index}`
        }))
      })
    });

    expect(alerts).toHaveLength(6);
    expect(alerts[0]?.title.length).toBeLessThanOrEqual(45);
    expect(alerts[0]?.body.length).toBeLessThanOrEqual(150);
  });

  it("rejects malformed personalized output and constrains the prompt", () => {
    expect(parsePersonalizedAlerts({ response: "not json" })).toEqual([]);
    expect(personalizedNudgeSystemPrompt()).toContain("Never invent");
    expect(personalizedNudgeSystemPrompt()).toContain("never time remaining");
    expect(personalizedAlertsSchema()).toMatchObject({ type: "object", additionalProperties: false });
  });

  it("rejects invented countdown wording based on task estimates", () => {
    const alerts = parsePersonalizedAlerts({
      response: {
        alerts: [
          { title: "15 min left", body: "Get moving." },
          { title: "Do the task", body: "Only 10 minutes to go." },
          { title: "Start small", body: "Close X and start the estimated 15-minute task." }
        ]
      }
    });

    expect(alerts).toEqual([
      { title: "Start small", body: "Close X and start the estimated 15-minute task.", angle: "generic" }
    ]);
  });

  it("selects different positive reinforcement messages", () => {
    const first = rewardAlert("X", 3, () => 0);
    const last = rewardAlert("X", 3, () => 0.999999);

    expect(first).not.toEqual(last);
    expect(first.body).toContain("X");
    expect(last.title).toBe("Loop interrupted");
  });
});
