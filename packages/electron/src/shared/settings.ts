export type AppSettings = {
  createThreadsInNewIsolate: boolean;
  newThreadLocation: "local" | "remote";
  notifyWhenAgentFinishes: boolean;
};

export const defaultSettings: AppSettings = {
  createThreadsInNewIsolate: true,
  newThreadLocation: "local",
  notifyWhenAgentFinishes: false
};
