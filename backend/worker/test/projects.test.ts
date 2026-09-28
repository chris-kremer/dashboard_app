import { describe, expect, it } from "vitest";
import { validateDocument, type ProjectDocument } from "../src/projects";
import { parseSchedule, buildExactTaskRowWrite } from "../src/sheets";

const fixture = (): ProjectDocument => ({ revision: 0,
  projects: [{ id: "p", name: "Paper", category: "Work", closed: false }],
  groups: [{ id: "g", projectId: "p", name: "Introduction" }, { id: "child", projectId: "p", parentId: "g", name: "Sources" }],
  memberships: [{ taskId: "stable", projectId: "p", groupId: "child" }]
});

describe("project data invariants", () => {
  it("accepts a nested project with a checklist", () => {
    const doc = fixture(); doc.memberships[0].checklist = [{ id: "step", title: "Read sources", done: false }];
    expect(() => validateDocument(doc)).not.toThrow();
  });
  it("rejects cyclic folders", () => {
    const doc = fixture(); doc.groups[0].parentId = "child";
    expect(() => validateDocument(doc)).toThrow("tree");
  });
  it("rejects groups from a different project", () => {
    const doc = fixture(); doc.projects.push({ id: "p2", name: "Chores", category: "Personal", closed: false });
    doc.groups[1].projectId = "p2";
    expect(() => validateDocument(doc)).toThrow("tree");
  });
  it("rejects duplicate logical task memberships", () => {
    const doc = fixture(); doc.memberships.push({ ...doc.memberships[0] });
    expect(() => validateDocument(doc)).toThrow("membership");
  });
  it("rejects invalid checklist IDs and duplicate projects", () => {
    const doc = fixture(); doc.memberships[0].checklist = [{ id: "", title: "Step", done: true }];
    expect(() => validateDocument(doc)).toThrow("checklist");
    const duplicate = fixture(); duplicate.projects.push({ ...duplicate.projects[0] });
    expect(() => validateDocument(duplicate)).toThrow("unique");
  });
  it("reads stable IDs without replacing interval row IDs", () => {
    const row = Array(21).fill(""); row[0] = "2026-09-28"; row[1] = "Write"; row[20] = "same-task";
    const copy = [...row]; copy[0] = "2026-09-29";
    const parsed = parseSchedule([row, copy]);
    expect(parsed[0].taskId).toBe(parsed[1].taskId);
    expect(parsed[0].rowId).not.toBe(parsed[1].rowId);
    expect(buildExactTaskRowWrite(10, [row]).range).toBe("schedule!A10:U10");
  });
  it("keeps old 20-column rows readable", () => {
    const row = Array(20).fill(""); row[0] = "2026-09-28"; row[1] = "Legacy";
    expect(parseSchedule([row])[0].taskId).toBeUndefined();
    expect(buildExactTaskRowWrite(10, [row]).range).toBe("schedule!A10:T10");
  });
});
