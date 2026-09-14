export type NavigationState = {
  selectedThreadID: string | null;
  requestedThreadID: string | null;
};

export function createNavigation(): NavigationState {
  return { selectedThreadID: null, requestedThreadID: null };
}

export function openThread(state: NavigationState, threadID: string): NavigationState {
  return { selectedThreadID: threadID, requestedThreadID: threadID };
}

export function selectThread(state: NavigationState, threadID: string | null): NavigationState {
  return { selectedThreadID: threadID, requestedThreadID: null };
}

export function didOpenThread(state: NavigationState, threadID: string): NavigationState {
  if (state.requestedThreadID === threadID) {
    return { ...state, requestedThreadID: null };
  }
  return state;
}

export function synchronizeNavigation(
  state: NavigationState,
  availableThreadIDs: string[]
): NavigationState {
  if (state.requestedThreadID) {
    if (!availableThreadIDs.includes(state.requestedThreadID)) {
      return state;
    }
    return { selectedThreadID: state.requestedThreadID, requestedThreadID: null };
  }
  if (state.selectedThreadID && availableThreadIDs.includes(state.selectedThreadID)) {
    return state;
  }
  return { selectedThreadID: availableThreadIDs[0] ?? null, requestedThreadID: null };
}
