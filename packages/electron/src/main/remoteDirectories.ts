import { execFile } from "node:child_process";
import * as listing from "@shared/sshDirectoryListing";
import type { RemoteMachine } from "@shared/types";
import type { RemoteDirectoryListing } from "@shared/sshDirectoryListing";

export async function listRemoteDirectories(
  machine: RemoteMachine,
  directory: string,
  fixtureJSON?: string
): Promise<RemoteDirectoryListing> {
  if (fixtureJSON) {
    const directories = listing.parseFixtureJSON(fixtureJSON);
    if (directories) {
      const key = directory.replace(/\/+$/, "") || directory;
      const names = directories[key] ?? directories[directory];
      return names ? { kind: "contents", names } : { kind: "missing" };
    }
  }
  if (!listing.canList(machine)) {
    return { kind: "failed" };
  }
  return await new Promise((resolve) => {
    const child = execFile(
      "ssh",
      listing.processArguments(machine, directory),
      { timeout: 6000 },
      (error, stdout) => {
        const status = error && typeof error.code === "number" ? error.code : 0;
        resolve(listing.listingResult(status, stdout ?? ""));
      }
    );
    child.on("error", () => resolve({ kind: "failed" }));
  });
}
