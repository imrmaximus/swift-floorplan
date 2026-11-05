import FloorplanScanner
import Foundation

/// Sends the prompt to `claude -p` on stdin and returns what it prints.
func askClaude(_ prompt: String) throws -> String {
    let process = Process(), input = Pipe(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["claude", "-p"]
    process.standardInput = input
    process.standardOutput = output
    try process.run()
    input.fileHandleForWriting.write(Data(prompt.utf8))
    try input.fileHandleForWriting.close()
    let reply = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw ScanError.modelReplyUnreadable("claude exited with \(process.terminationStatus)") }
    return String(decoding: reply, as: UTF8.self)
}

guard let options = parseOptions(Array(CommandLine.arguments.dropFirst())) else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(64)
}
do {
    if let json = try runCommand(options, ask: askClaude) {
        FileHandle.standardOutput.write(json + Data("\n".utf8))
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
