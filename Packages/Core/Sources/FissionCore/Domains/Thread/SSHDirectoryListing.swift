import Foundation

/// Lists child directories on a Remote Machine over SSH (BatchMode, no password prompt).
public enum SSHDirectoryListing {
    public static func processArguments(
        machine: RemoteMachine,
        directory: String
    ) -> [String] {
        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=4",
            "-o", "LogLevel=ERROR"
        ]
        if let sshPort = machine.sshPort, sshPort != 22 {
            arguments.append(contentsOf: ["-p", String(sshPort)])
        }
        arguments.append(machine.target)
        arguments.append(remoteCommand(directory: directory))
        return arguments
    }

    public static func remoteCommand(directory: String) -> String {
        "sh -c \(MoshCommand.posixQuote(listingScript)) -- \(MoshCommand.posixQuote(directory))"
    }

    public static func parseOutput(_ output: String) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let name = String(line)
            guard !name.isEmpty, name != ".", name != "..", !name.hasPrefix(".") else { continue }
            guard seen.insert(name).inserted else { continue }
            names.append(name)
        }
        return names.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    public static func parseFixtureJSON(_ json: String) -> [String: [String]]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: [String]].self, from: data)
    }

    private static let listingScript = """
    path=$1
    case "$path" in
    ~) dir="$HOME" ;;
    ~/*) dir="$HOME/${path#~/}" ;;
    *) dir="$path" ;;
    esac
    [ -d "$dir" ] || exit 0
    find "$dir" -mindepth 1 -maxdepth 1 ! -name '.*' -print 2>/dev/null | while IFS= read -r p; do
      [ -d "$p" ] || continue
      printf '%s\\n' "${p##*/}"
    done
    """
}
