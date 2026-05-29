import ArgumentParser
import Foundation
import UnipathCore

@main
struct Unipath: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unipath",
        abstract: "Manage one PATH list across fish, zsh, and bash.",
        subcommands: [
            Add.self,
            Remove.self,
            List.self,
            Doctor.self,
            Import.self,
            Env.self,
            Init.self,
        ]
    )
}

struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add directories to the managed PATH list."
    )

    @Flag(name: [.customLong("append"), .customShort("a")], help: "Add paths to the end instead of the front.")
    var append = false

    @Flag(name: [.customLong("prepend"), .customShort("p")], help: "Add paths to the front. This is the default.")
    var prepend = false

    @Flag(name: [.customLong("move"), .customShort("m")], help: "Move existing paths to the chosen position.")
    var move = false

    @Flag(name: [.customLong("force"), .customShort("f")], help: "Allow paths that do not currently exist.")
    var force = false

    @Flag(help: "Store relative paths literally instead of making them absolute.")
    var literal = false

    @Argument(help: "Directories to add.")
    var paths: [String]

    func run() throws {
        let position: PathPosition = append ? .append : .prepend
        let store = PathStore.defaultStore()

        for path in paths {
            let change = try store.add(path, position: position, moveExisting: move, force: force, literal: literal)
            printChange(change)
        }
    }
}

struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove directories from the managed PATH list.",
        aliases: ["rm"]
    )

    @Flag(help: "Match the path text literally instead of normalizing it first.")
    var literal = false

    @Argument(help: "Directories to remove.")
    var paths: [String]

    func run() throws {
        let store = PathStore.defaultStore()

        for path in paths {
            let change = try store.remove(path, literal: literal)
            printChange(change)
        }
    }
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Print managed PATH entries.",
        aliases: ["ls"]
    )

    @Flag(help: "Show the expanded comparison path for each entry.")
    var expanded = false

    func run() throws {
        let entries = try PathStore.defaultStore().entries()

        for (index, entry) in entries.enumerated() {
            let number = String(format: "%2d", index + 1)
            if expanded {
                print("\(number)  \(entry.stored) -> \(entry.expanded)")
            } else {
                print("\(number)  \(entry.stored)")
            }
        }
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check the managed PATH list for problems."
    )

    func run() throws {
        let diagnostics = try PathStore.defaultStore().diagnostics()
        if diagnostics.isEmpty {
            print("No problems found.")
        } else {
            diagnostics.forEach { print($0) }
        }
    }
}

struct Import: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import entries from the current PATH."
    )

    @Flag(name: [.customLong("home-relative")], help: "Store paths under your home directory using ~.")
    var homeRelative = false

    @Flag(name: [.customLong("normalize-home")], help: "Alias for --home-relative.")
    var normalizeHome = false

    @Flag(help: "Remove duplicate entries after normalization.")
    var dedupe = false

    @Flag(help: "Skip paths that do not currently exist.")
    var existingOnly = false

    @Flag(help: "Merge imported entries with the existing managed list.")
    var merge = false

    @Flag(name: [.customLong("append"), .customShort("a")], help: "When merging, place imported entries after existing entries.")
    var append = false

    @Flag(name: [.customLong("prepend"), .customShort("p")], help: "When merging, place imported entries before existing entries.")
    var prepend = false

    @Flag(name: [.customLong("dry-run"), .customShort("n")], help: "Print the imported list without writing it.")
    var dryRun = false

    func run() throws {
        let options = ImportOptions(
            homeRelative: homeRelative || normalizeHome,
            dedupe: dedupe,
            existingOnly: existingOnly,
            merge: merge,
            position: prepend ? .prepend : .append,
            dryRun: dryRun
        )
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let store = PathStore.defaultStore()
        let result = try store.importPath(path, options: options)

        if options.dryRun {
            result.paths.forEach { print($0) }
        } else {
            print("imported \(result.paths.count) paths into \(store.fileURL.path)")
        }

        for skipped in result.skippedMissing {
            print("skipped missing: \(skipped)")
        }
    }
}

struct Env: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print shell code that applies the managed PATH list."
    )

    @Argument(help: "The shell syntax to emit: fish, sh, bash, or zsh.")
    var shell: ShellKindArgument

    func run() throws {
        let paths = try PathStore.defaultStore().entries().map(\.stored)
        print(ShellEmitter().emit(kind: shell.kind, storedPaths: paths))
    }
}

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Install shell startup snippets."
    )

    @Flag(name: [.customLong("dry-run"), .customShort("n")], help: "Show which files would change without writing them.")
    var dryRun = false

    @Argument(help: "Shells to initialize: fish, zsh, bash, sh, or all. Defaults to fish, zsh, and bash.")
    var shells: [InitShell] = []

    func run() throws {
        let selectedShells = resolvedShells()
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let initializer = ShellInitializer(homeDirectory: home)

        for shell in selectedShells {
            let results = try initializer.initialize(kind: shell, dryRun: dryRun)
            for result in results {
                let verb = dryRun ? (result.changed ? "would update" : "unchanged") : (result.changed ? "updated" : "unchanged")
                print("\(verb): \(result.file)")
            }
        }
    }

    private func resolvedShells() -> [ShellKind] {
        if shells.isEmpty {
            return [.fish, .zsh, .bash]
        }

        var result: [ShellKind] = []
        for shell in shells {
            switch shell {
            case .all:
                result.append(contentsOf: [.fish, .zsh, .bash])
            case .shell(let kind):
                result.append(kind)
            }
        }
        return result
    }
}

enum ShellKindArgument: String, ExpressibleByArgument {
    case fish
    case sh
    case bash
    case zsh

    var kind: ShellKind {
        switch self {
        case .fish: .fish
        case .sh: .sh
        case .bash: .bash
        case .zsh: .zsh
        }
    }
}

enum InitShell: ExpressibleByArgument {
    case all
    case shell(ShellKind)

    init?(argument: String) {
        if argument == "all" {
            self = .all
            return
        }

        guard let shell = ShellKindArgument(rawValue: argument) else {
            return nil
        }
        self = .shell(shell.kind)
    }
}

func printChange(_ change: PathChange) {
    switch change {
    case .added(let path):
        print("added: \(path)")
    case .moved(let path):
        print("moved: \(path)")
    case .unchanged(let path):
        print("unchanged: \(path)")
    case .removed(let path):
        print("removed: \(path)")
    case .missing(let path):
        print("not present: \(path)")
    }
}
