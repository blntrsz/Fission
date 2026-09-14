import { describe, expect, it } from "vitest";
import {
  childProjects,
  completedInput,
  isPathQuery,
  listingTarget,
  normalizeRemoteQuery,
  pickerPaths,
  recentProjects,
  resolvedListingTarget
} from "@shared/projectPathQuery";
import { listingResult, parseFixtureJSON, parseOutput, processArguments } from "@shared/sshDirectoryListing";
import { loginShellCommand, posixQuote } from "@shared/moshCommand";
import { isValidMachine, machineTarget, moshCommandFor, projectNameFromPath } from "@shared/remoteMachine";
import { nextNumber, title } from "@shared/terminalTabNaming";
import { isValid, normalized } from "@shared/gitWorktreeBranch";
import { context, results } from "@shared/activeThreadSearch";
import {
  createNavigation,
  didOpenThread,
  openThread,
  synchronizeNavigation
} from "@shared/navigation";
import { createThreadInput, ThreadRepository } from "@shared/threadRepository";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

describe("ProjectPathQuery", () => {
  it("detects path-shaped queries", () => {
    expect(isPathQuery("~/src")).toBe(true);
    expect(isPathQuery("/work")).toBe(true);
    expect(isPathQuery("./lib")).toBe(true);
    expect(isPathQuery("fission")).toBe(false);
    expect(isPathQuery("~")).toBe(false);
  });

  it("splits listing targets", () => {
    expect(listingTarget("/work/fis", null)).toEqual({ directory: "/work", namePrefix: "fis" });
    expect(listingTarget("~/src/", null)).toEqual({ directory: "~/src", namePrefix: "" });
    expect(listingTarget("/", null)).toEqual({ directory: "/", namePrefix: "" });
  });

  it("normalizes remote queries under home", () => {
    expect(normalizeRemoteQuery("")).toBe("~/");
    expect(normalizeRemoteQuery("~")).toBe("~/");
    expect(normalizeRemoteQuery("src")).toBe("~/src");
    expect(normalizeRemoteQuery("/work/fission")).toBe("/work/fission");
  });

  it("browses into an exact directory name", () => {
    expect(
      resolvedListingTarget("/work/fission", null, (directory) =>
        directory === "/work" ? ["fission", "notes"] : null
      )
    ).toEqual({ directory: "/work/fission", namePrefix: "" });
  });

  it("lists current directory then children", () => {
    expect(
      pickerPaths("/work/fission", "", ["src", "Packages"], true)
    ).toEqual(["/work/fission", "/work/fission/Packages", "/work/fission/src"]);
    expect(pickerPaths("~", "", ["src", "work"], true)).toEqual(["~/src", "~/work"]);
    expect(pickerPaths("/missing", "", [], false)).toEqual([]);
  });

  it("expands relative queries", () => {
    expect(listingTarget("./fi", "/work")).toEqual({ directory: "/work", namePrefix: "fi" });
    expect(listingTarget("./", "/work/fission")).toEqual({
      directory: "/work/fission",
      namePrefix: ""
    });
  });

  it("filters child projects", () => {
    expect(childProjects("~/src", ["Fission", "notes", "other"], "fi")).toEqual(["~/src/Fission"]);
  });

  it("keeps query prefixes when completing", () => {
    expect(
      completedInput("/work/fi", "/work/fission", "/Users/ada", null)
    ).toBe("/work/fission/");
    expect(
      completedInput("~/src/fi", "/Users/ada/src/fission", "/Users/ada", null)
    ).toBe("~/src/fission/");
    expect(completedInput("./fi", "/work/fission", null, "/work")).toBe("./fission/");
    expect(completedInput("~/src/fi", "~/src/fission", null, null)).toBe("~/src/fission/");
  });

  it("dedupes recents", () => {
    expect(
      recentProjects(["/work/fission/", "/work/fission", "~/notes", "/tmp/other"], "fis")
    ).toEqual(["/work/fission"]);
  });
});

describe("SSH listing", () => {
  it("builds batch-mode arguments", () => {
    const arguments_ = processArguments(
      {
        id: "1",
        name: "Studio",
        username: "ada",
        host: "gpu.local",
        sshPort: 2222,
        projectPath: null
      },
      "~/src/fission"
    );
    expect(arguments_).toContain("BatchMode=yes");
    expect(arguments_).toContain("2222");
    expect(arguments_).toContain("ada@gpu.local");
    expect(arguments_.at(-1)?.includes("~/src/fission")).toBe(true);
    expect(arguments_.some((item) => item.includes("password"))).toBe(false);
  });

  it("parses find output", () => {
    expect(parseOutput("fission\nnotes\n.hidden\nfission\n\n")).toEqual(["fission", "notes"]);
  });

  it("parses fixture JSON", () => {
    const map = parseFixtureJSON('{"/work":["fission","notes"],"~/src":["app"]}');
    expect(map?.["/work"]).toEqual(["fission", "notes"]);
  });

  it("distinguishes missing and failed", () => {
    expect(listingResult(0, "src\nlib\n")).toEqual({ kind: "contents", names: ["lib", "src"] });
    expect(listingResult(2, "")).toEqual({ kind: "missing" });
    expect(listingResult(255, "")).toEqual({ kind: "failed" });
  });
});

describe("mosh / machines", () => {
  it("builds a default-port login command", () => {
    const machine = {
      id: "1",
      name: "Studio",
      username: "ada",
      host: "gpu.local",
      sshPort: null,
      projectPath: null
    };
    expect(machineTarget(machine)).toBe("ada@gpu.local");
    expect(moshCommandFor(machine)).toBe("exec mosh ada@gpu.local");
    expect(isValidMachine(machine)).toBe(true);
  });

  it("quotes custom SSH ports", () => {
    expect(loginShellCommand("ada@host'box", 2222)).toBe(
      "exec mosh --ssh='ssh -p 2222' 'ada@host'\\''box'"
    );
  });

  it("cds into the remote project path", () => {
    const machine = {
      id: "1",
      name: "Studio",
      username: "ada",
      host: "gpu.local",
      sshPort: null,
      projectPath: "/work/fission/"
    };
    expect(projectNameFromPath("/work/fission/")).toBe("fission");
    expect(moshCommandFor({ ...machine, projectPath: "/work/fission" })).toBe(
      'exec mosh ada@gpu.local -- sh -lc \'cd -- "/work/fission" && exec "${SHELL:-/bin/sh}" -l\''
    );
  });

  it("expands tilde project paths", () => {
    expect(loginShellCommand("ada@gpu.local", null, "~/src/my project")).toBe(
      'exec mosh ada@gpu.local -- sh -lc \'cd -- "$HOME/src/my project" && exec "${SHELL:-/bin/sh}" -l\''
    );
  });

  it("rejects empty hosts", () => {
    expect(isValidMachine({ host: "  ", sshPort: null })).toBe(false);
    expect(isValidMachine({ host: "gpu", sshPort: 0 })).toBe(false);
  });

  it("quotes empty strings", () => {
    expect(posixQuote("")).toBe("''");
  });
});

describe("tabs and branches", () => {
  it("reuses the lowest tab number", () => {
    expect(nextNumber([])).toBe(1);
    expect(title(1)).toBe("Tab 1");
    expect(nextNumber(["Tab 2", "Tab 3"])).toBe(1);
    expect(nextNumber(["Tab 1", "Tab 3"])).toBe(2);
    expect(nextNumber(["Logs", "Tab 2"])).toBe(1);
    expect(nextNumber(["Tab 1 extra", "Tab 01"])).toBe(1);
  });

  it("validates isolate branch names", () => {
    expect(normalized("  feat  ")).toBe("feat");
    expect(isValid("feat/ok")).toBe(true);
    expect(isValid("")).toBe(false);
    expect(isValid("-no")).toBe(false);
    expect(isValid("has space")).toBe(false);
  });
});

describe("navigation and search", () => {
  it("selects a requested thread once it exists", () => {
    const requested = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
    const fallback = "11111111-2222-3333-4444-555555555555";
    let state = openThread(createNavigation(), requested);
    state = synchronizeNavigation(state, []);
    state = synchronizeNavigation(state, [fallback, requested]);
    expect(state.selectedThreadID).toBe(requested);
    expect(state.requestedThreadID).toBeNull();
  });

  it("clears a pending request after open", () => {
    const id = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
    const state = didOpenThread(openThread(createNavigation(), id), id);
    expect(state.selectedThreadID).toBe(id);
    expect(state.requestedThreadID).toBeNull();
  });

  it("selects the first available thread", () => {
    const first = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
    const state = synchronizeNavigation(createNavigation(), [first, "BBBB"]);
    expect(state.selectedThreadID).toBe(first);
  });

  it("filters active threads", () => {
    const threads = [
      createThreadInput({ title: "Alpha", projectName: "fission" }),
      createThreadInput({ title: "Beta", status: "settled", projectName: "notes" })
    ];
    expect(results("fis", threads).map((thread) => thread.title)).toEqual(["Alpha"]);
    expect(context(threads[0])).toBe("fission");
  });
});

describe("ThreadRepository", () => {
  it("performs CRUD and keeps newest first", async () => {
    const path = join(mkdtempSync(join(tmpdir(), "fission-")), "fission.sqlite");
    const repository = await ThreadRepository.open(path);
    const older = createThreadInput({
      title: "Older",
      createdAt: 1000,
      workingDirectory: "/tmp/worktrees/project/branch",
      projectName: "project",
      remoteMachineID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      remoteCommand: "exec mosh ada@gpu.local"
    });
    const newer = createThreadInput({ title: "Newer", createdAt: 2000 });
    repository.create(older);
    repository.create(newer);
    expect(repository.list().map((thread) => thread.title)).toEqual(["Newer", "Older"]);

    repository.reorder([older.id, newer.id]);
    expect(repository.list().map((thread) => thread.id)).toEqual([older.id, newer.id]);

    repository.update({ ...older, title: "Renamed", updatedAt: 3000 });
    expect(repository.thread(older.id)?.title).toBe("Renamed");
    expect(repository.list().map((thread) => thread.id)).toEqual([older.id, newer.id]);

    repository.delete(older.id);
    expect(repository.thread(older.id)).toBeNull();
    repository.close();
  });
});
