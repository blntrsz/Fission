enum TerminalTabNaming {
    static func title(for number: Int) -> String {
        "Tab \(number)"
    }

    static func nextNumber(existingTitles: some Sequence<String>) -> Int {
        let usedNumbers = Set(existingTitles.compactMap(number(in:)))
        var candidate = 1
        while usedNumbers.contains(candidate) {
            candidate += 1
        }
        return candidate
    }

    static func number(in title: String) -> Int? {
        let prefix = "Tab "
        guard title.hasPrefix(prefix) else { return nil }
        let suffix = String(title.dropFirst(prefix.count))
        guard let number = Int(suffix), number > 0, String(number) == suffix else {
            return nil
        }
        return number
    }
}
