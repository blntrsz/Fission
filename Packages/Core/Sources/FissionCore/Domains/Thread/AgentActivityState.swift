/// The transient attention state of an agent working in a Thread.
///
/// Activity is reported by agent integrations and is intentionally not persisted with the
/// Thread lifecycle. A Thread with no report is idle.
public enum AgentActivityState: String, CaseIterable, Codable, Hashable, Sendable {
    case idle
    case running
    case blocked
    case finished
}
