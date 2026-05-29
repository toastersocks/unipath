import Foundation

public struct PathEntry: Equatable, Sendable {
    public let stored: String
    public let comparison: String
    public let expanded: String

    public init(_ input: String, currentDirectory: String, homeDirectory: String, literal: Bool = false) {
        let stored = Self.storedForm(for: input, currentDirectory: currentDirectory, literal: literal)
        let expanded = Self.expandHome(in: stored, homeDirectory: homeDirectory)
        self.stored = stored
        self.expanded = (expanded as NSString).standardizingPath
        self.comparison = Self.comparisonForm(for: expanded)
    }

    public static func storedForm(for input: String, currentDirectory: String, literal: Bool = false) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard !literal else { return trimmed }

        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.hasPrefix("$HOME") || trimmed.hasPrefix("${HOME}") {
            return trimmed
        }

        return URL(fileURLWithPath: currentDirectory)
            .appendingPathComponent(trimmed)
            .standardizedFileURL
            .path
    }

    public static func expandHome(in value: String, homeDirectory: String) -> String {
        if value == "~" || value == "$HOME" || value == "${HOME}" {
            return homeDirectory
        }

        if value.hasPrefix("~/") {
            return homeDirectory + String(value.dropFirst())
        }

        if value.hasPrefix("$HOME/") {
            return homeDirectory + "/" + String(value.dropFirst("$HOME/".count))
        }

        if value.hasPrefix("${HOME}/") {
            return homeDirectory + "/" + String(value.dropFirst("${HOME}/".count))
        }

        return value
    }

    public static func comparisonForm(for expandedPath: String) -> String {
        (expandedPath as NSString).standardizingPath
    }
}

