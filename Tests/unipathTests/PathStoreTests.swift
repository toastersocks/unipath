import Foundation
import Testing
@testable import UnipathCore

@Test func addPreservesEnteredHomePath() throws {
    let fixture = try Fixture()
    try fixture.makeDirectory(".cargo/bin")

    let change = try fixture.store.add("~/.cargo/bin", position: .prepend, moveExisting: false, force: false, literal: false)

    #expect(change == .added("~/.cargo/bin"))
    #expect(try fixture.fileText() == "~/.cargo/bin\n")
}

@Test func addDetectsHomeDuplicatesWithoutMovingByDefault() throws {
    let fixture = try Fixture()
    try fixture.makeDirectory(".cargo/bin")

    _ = try fixture.store.add("~/.cargo/bin", position: .prepend, moveExisting: false, force: false, literal: false)
    let change = try fixture.store.add("$HOME/.cargo/bin", position: .prepend, moveExisting: false, force: false, literal: false)

    #expect(change == .unchanged("$HOME/.cargo/bin"))
    #expect(try fixture.store.entries().map(\.stored) == ["~/.cargo/bin"])
}

@Test func moveExistingRepositionsPath() throws {
    let fixture = try Fixture()
    try fixture.makeDirectory(".cargo/bin")
    try fixture.makeDirectory(".local/bin")

    _ = try fixture.store.add("~/.cargo/bin", position: .append, moveExisting: false, force: false, literal: false)
    _ = try fixture.store.add("~/.local/bin", position: .append, moveExisting: false, force: false, literal: false)
    let change = try fixture.store.add("$HOME/.local/bin", position: .prepend, moveExisting: true, force: false, literal: false)

    #expect(change == .moved("$HOME/.local/bin"))
    #expect(try fixture.store.entries().map(\.stored) == ["$HOME/.local/bin", "~/.cargo/bin"])
}

@Test func relativePathBecomesAbsoluteUnlessLiteral() throws {
    let fixture = try Fixture()
    try FileManager.default.createDirectory(at: fixture.cwd.appendingPathComponent("bin"), withIntermediateDirectories: true)

    _ = try fixture.store.add("bin", position: .prepend, moveExisting: false, force: false, literal: false)

    #expect(try fixture.store.entries().map(\.stored) == [fixture.cwd.appendingPathComponent("bin").path])
}

@Test func shellEmitterIncludesLoadTimeHomeExpansion() {
    let output = ShellEmitter().emit(kind: .fish, storedPaths: ["~/.cargo/bin", "$HOME/.local/bin"])

    #expect(output.contains("string replace -r '^~(?=/|$)'"))
    #expect(output.contains("\\$HOME/.local/bin"))
}

@Test func importPreservesPathTextByDefault() throws {
    let fixture = try Fixture()
    let path = "\(fixture.home.path)/.cargo/bin:/opt/homebrew/bin:\(fixture.home.path)/bin"

    _ = try fixture.store.importPath(path, options: ImportOptions())

    #expect(try fixture.store.entries().map(\.stored) == [
        "\(fixture.home.path)/.cargo/bin",
        "/opt/homebrew/bin",
        "\(fixture.home.path)/bin",
    ])
}

@Test func importCanStoreHomeRelativePaths() throws {
    let fixture = try Fixture()
    let path = "\(fixture.home.path)/.cargo/bin:/opt/homebrew/bin:\(fixture.home.path)"

    _ = try fixture.store.importPath(path, options: ImportOptions(homeRelative: true))

    #expect(try fixture.store.entries().map(\.stored) == [
        "~/.cargo/bin",
        "/opt/homebrew/bin",
        "~",
    ])
}

@Test func importCanDedupeEquivalentHomePaths() throws {
    let fixture = try Fixture()
    let path = "\(fixture.home.path)/.cargo/bin:~/.cargo/bin:$HOME/.cargo/bin"

    _ = try fixture.store.importPath(path, options: ImportOptions(homeRelative: true, dedupe: true))

    #expect(try fixture.store.entries().map(\.stored) == ["~/.cargo/bin"])
}

@Test func dryRunImportDoesNotWriteFile() throws {
    let fixture = try Fixture()
    let result = try fixture.store.importPath("/opt/homebrew/bin", options: ImportOptions(dryRun: true))

    #expect(result.paths == ["/opt/homebrew/bin"])
    #expect(!FileManager.default.fileExists(atPath: fixture.store.fileURL.path))
}

private struct Fixture {
    let root: URL
    let home: URL
    let cwd: URL
    let store: PathStore

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("unipath-tests-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        cwd = root.appendingPathComponent("cwd", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        store = PathStore(
            fileURL: home.appendingPathComponent(".config/unipath/paths"),
            currentDirectory: cwd.path,
            homeDirectory: home.path
        )
    }

    func makeDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(path), withIntermediateDirectories: true)
    }

    func fileText() throws -> String {
        try String(contentsOf: store.fileURL, encoding: .utf8)
    }
}
