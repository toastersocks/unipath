import Foundation

public struct InitResult: Equatable, Sendable {
    public let file: String
    public let changed: Bool
}

public struct ShellInitializer: Sendable {
    public let homeDirectory: String
    public let emitter: ShellEmitter

    public init(homeDirectory: String, emitter: ShellEmitter = ShellEmitter()) {
        self.homeDirectory = homeDirectory
        self.emitter = emitter
    }

    public func initialize(kind: ShellKind, dryRun: Bool, binaryName: String = "unipath") throws -> [InitResult] {
        let files = startupFiles(for: kind)
        return try files.map { file in
            let url = URL(fileURLWithPath: file)
            let snippet = emitter.loaderSnippet(kind: kind == .zsh || kind == .bash ? .sh : kind, binaryName: binaryName)
            let changed = try update(fileURL: url, snippet: snippet, dryRun: dryRun)
            return InitResult(file: file, changed: changed)
        }
    }

    public func startupFiles(for kind: ShellKind) -> [String] {
        switch kind {
        case .fish:
            ["\(homeDirectory)/.config/fish/config.fish"]
        case .zsh:
            ["\(homeDirectory)/.zshrc", "\(homeDirectory)/.zprofile"]
        case .bash:
            ["\(homeDirectory)/.bashrc", "\(homeDirectory)/.bash_profile"]
        case .sh:
            ["\(homeDirectory)/.profile"]
        }
    }

    private func update(fileURL: URL, snippet: String, dryRun: Bool) throws -> Bool {
        let start = "# >>> unipath initialize >>>"
        let end = "# <<< unipath initialize <<<"
        let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let replacement = snippet + "\n"

        let updated: String
        if let startRange = existing.range(of: start), let endRange = existing.range(of: end, range: startRange.upperBound..<existing.endIndex) {
            let afterEnd = existing.index(endRange.upperBound, offsetBy: 0)
            updated = String(existing[..<startRange.lowerBound]) + replacement + String(existing[afterEnd...]).trimmingPrefixNewline()
        } else {
            updated = existing + (existing.hasSuffix("\n") || existing.isEmpty ? "" : "\n") + replacement
        }

        guard updated != existing else {
            return false
        }

        if !dryRun {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try updated.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        return true
    }
}

private extension String {
    func trimmingPrefixNewline() -> String {
        var result = self
        while result.hasPrefix("\n") {
            result.removeFirst()
        }
        return result
    }
}

