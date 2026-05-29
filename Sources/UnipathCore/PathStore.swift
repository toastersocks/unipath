import Foundation

public enum PathPosition: Sendable {
    case prepend
    case append
}

public enum PathChange: Equatable, Sendable {
    case added(String)
    case moved(String)
    case unchanged(String)
    case removed(String)
    case missing(String)
}

public struct ImportOptions: Sendable {
    public var homeRelative: Bool
    public var dedupe: Bool
    public var existingOnly: Bool
    public var merge: Bool
    public var position: PathPosition
    public var dryRun: Bool

    public init(
        homeRelative: Bool = false,
        dedupe: Bool = false,
        existingOnly: Bool = false,
        merge: Bool = false,
        position: PathPosition = .append,
        dryRun: Bool = false
    ) {
        self.homeRelative = homeRelative
        self.dedupe = dedupe
        self.existingOnly = existingOnly
        self.merge = merge
        self.position = position
        self.dryRun = dryRun
    }
}

public struct ImportResult: Equatable, Sendable {
    public let paths: [String]
    public let skippedMissing: [String]

    public init(paths: [String], skippedMissing: [String]) {
        self.paths = paths
        self.skippedMissing = skippedMissing
    }
}

enum PathFileLine: Equatable {
    case path(String)
    case passthrough(String)

    var text: String {
        switch self {
        case .path(let value), .passthrough(let value):
            value
        }
    }
}

public struct PathStore: Sendable {
    public let fileURL: URL
    public let currentDirectory: String
    public let homeDirectory: String

    public init(fileURL: URL, currentDirectory: String, homeDirectory: String) {
        self.fileURL = fileURL
        self.currentDirectory = currentDirectory
        self.homeDirectory = homeDirectory
    }

    public static func defaultStore(environment: [String: String] = ProcessInfo.processInfo.environment) -> PathStore {
        let home = environment["HOME"] ?? NSHomeDirectory()
        let configPath = environment["UNIPATH_CONFIG"] ?? "\(home)/.config/unipath/paths"
        return PathStore(
            fileURL: URL(fileURLWithPath: configPath),
            currentDirectory: FileManager.default.currentDirectoryPath,
            homeDirectory: home
        )
    }

    public func entries() throws -> [PathEntry] {
        try readLines().compactMap { line in
            switch line {
            case .path(let value):
                PathEntry(value, currentDirectory: currentDirectory, homeDirectory: homeDirectory, literal: true)
            case .passthrough:
                nil
            }
        }
    }

    public func add(_ input: String, position: PathPosition, moveExisting: Bool, force: Bool, literal: Bool) throws -> PathChange {
        let entry = PathEntry(input, currentDirectory: currentDirectory, homeDirectory: homeDirectory, literal: literal)
        guard !entry.stored.isEmpty else {
            throw UnipathError.message("path cannot be empty")
        }

        if !force && !FileManager.default.directoryExists(atPath: entry.expanded) {
            throw UnipathError.message("not a directory: \(entry.expanded)")
        }

        var lines = try readLines()
        let matchingIndices = indicesMatching(entry.comparison, in: lines)

        if !matchingIndices.isEmpty && !moveExisting {
            return .unchanged(entry.stored)
        }

        for index in matchingIndices.reversed() {
            lines.remove(at: index)
        }

        let insertIndex = insertionIndex(for: position, in: lines)
        lines.insert(.path(entry.stored), at: insertIndex)
        try write(lines)

        return matchingIndices.isEmpty ? .added(entry.stored) : .moved(entry.stored)
    }

    public func remove(_ input: String, literal: Bool) throws -> PathChange {
        let entry = PathEntry(input, currentDirectory: currentDirectory, homeDirectory: homeDirectory, literal: literal)
        var lines = try readLines()
        let matchingIndices = indicesMatching(entry.comparison, in: lines)

        guard !matchingIndices.isEmpty else {
            return .missing(entry.stored)
        }

        for index in matchingIndices.reversed() {
            lines.remove(at: index)
        }

        try write(lines)
        return .removed(entry.stored)
    }

    public func importPath(_ pathString: String, options: ImportOptions) throws -> ImportResult {
        let imported = preparedImportEntries(from: pathString, options: options)
        var skippedMissing: [String] = []
        var importedLines: [PathFileLine] = []
        var seen: Set<String> = []

        for stored in imported {
            let entry = PathEntry(stored, currentDirectory: currentDirectory, homeDirectory: homeDirectory, literal: true)

            if options.existingOnly && !FileManager.default.directoryExists(atPath: entry.expanded) {
                skippedMissing.append(stored)
                continue
            }

            if options.dedupe {
                guard !seen.contains(entry.comparison) else { continue }
                seen.insert(entry.comparison)
            }

            importedLines.append(.path(stored))
        }

        let finalLines: [PathFileLine]
        if options.merge {
            finalLines = mergedLines(importedLines, position: options.position)
        } else {
            finalLines = importedLines
        }

        if !options.dryRun {
            try write(finalLines)
        }

        let finalPaths = finalLines.compactMap { line -> String? in
            guard case .path(let value) = line else { return nil }
            return value
        }
        return ImportResult(paths: finalPaths, skippedMissing: skippedMissing)
    }

    public func diagnostics() throws -> [String] {
        let entries = try entries()
        var seen: [String: String] = [:]
        var messages: [String] = []

        for entry in entries {
            if !FileManager.default.directoryExists(atPath: entry.expanded) {
                messages.append("missing: \(entry.stored) -> \(entry.expanded)")
            }

            if let first = seen[entry.comparison] {
                messages.append("duplicate: \(entry.stored) matches \(first)")
            } else {
                seen[entry.comparison] = entry.stored
            }
        }

        return messages
    }

    func readLines() throws -> [PathFileLine] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                return .passthrough(line)
            }

            return .path(line)
        }
    }

    func write(_ lines: [PathFileLine]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = lines.map(\.text).joined(separator: "\n") + "\n"
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func indicesMatching(_ comparison: String, in lines: [PathFileLine]) -> [Int] {
        lines.indices.filter { index in
            guard case .path(let stored) = lines[index] else { return false }
            let existing = PathEntry(stored, currentDirectory: currentDirectory, homeDirectory: homeDirectory, literal: true)
            return existing.comparison == comparison
        }
    }

    private func insertionIndex(for position: PathPosition, in lines: [PathFileLine]) -> Int {
        switch position {
        case .prepend:
            return lines.firstIndex { line in
                if case .path = line { return true }
                return false
            } ?? lines.count
        case .append:
            return lines.count
        }
    }

    private func preparedImportEntries(from pathString: String, options: ImportOptions) -> [String] {
        pathString.split(separator: ":", omittingEmptySubsequences: false).compactMap { component in
            guard !component.isEmpty else { return nil }

            let raw = String(component)
            if options.homeRelative {
                return homeRelativePath(raw)
            }

            return raw
        }
    }

    private func homeRelativePath(_ path: String) -> String {
        let normalizedHome = (homeDirectory as NSString).standardizingPath
        let expanded = PathEntry.expandHome(in: path, homeDirectory: homeDirectory)
        let standardized = (expanded as NSString).standardizingPath

        if standardized == normalizedHome {
            return "~"
        }

        if standardized.hasPrefix(normalizedHome + "/") {
            return "~/" + standardized.dropFirst(normalizedHome.count + 1)
        }

        return path
    }

    private func mergedLines(_ importedLines: [PathFileLine], position: PathPosition) -> [PathFileLine] {
        let existingLines = (try? readLines()) ?? []
        let importedComparisons = Set(importedLines.compactMap { line -> String? in
            guard case .path(let stored) = line else { return nil }
            return PathEntry(stored, currentDirectory: currentDirectory, homeDirectory: homeDirectory, literal: true).comparison
        })

        let existingWithoutImported = existingLines.filter { line in
            guard case .path(let stored) = line else { return true }
            let comparison = PathEntry(stored, currentDirectory: currentDirectory, homeDirectory: homeDirectory, literal: true).comparison
            return !importedComparisons.contains(comparison)
        }

        switch position {
        case .prepend:
            return importedLines + existingWithoutImported
        case .append:
            return existingWithoutImported + importedLines
        }
    }
}

public enum UnipathError: LocalizedError, Equatable {
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .message(let message):
            message
        }
    }
}

extension FileManager {
    func directoryExists(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
