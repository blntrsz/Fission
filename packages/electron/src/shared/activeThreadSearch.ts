import { isSettled, type AgentThread } from "./types";
import { lastPathComponent } from "./types";

export function results(matching: string, threads: AgentThread[]): AgentThread[] {
  const activeThreads = threads.filter((thread) => !isSettled(thread));
  const terms = matching.split(/\s+/).filter((term) => term.length > 0);
  if (terms.length === 0) {
    return activeThreads;
  }
  return activeThreads.filter((thread) => {
    const searchableText = [
      thread.title,
      thread.projectName,
      thread.workingDirectory,
      thread.remoteCommand
    ]
      .filter((value): value is string => value != null)
      .join(" ");
    return terms.every((term) => searchableText.toLowerCase().includes(term.toLowerCase()));
  });
}

export function context(thread: AgentThread): string | null {
  if (thread.projectName && thread.projectName.length > 0) {
    return thread.projectName;
  }
  if (!thread.workingDirectory) {
    return null;
  }
  const directoryName = lastPathComponent(thread.workingDirectory);
  return directoryName.length === 0 ? thread.workingDirectory : directoryName;
}
