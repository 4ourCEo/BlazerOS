import BlazerCore
import Foundation

/// Explicitly read-only export. Requires a frozen cutoff and an existing desk archive.
@main
struct EdgeReportCommand {
    static func main() async {
        do {
            var root: URL?
            var asOf: Date?
            var splitAt: Date?
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count.isMultiple(of: 2) else { throw ScanError.failed("Use --root PATH --as-of UNIX_SECONDS [--split-at UNIX_SECONDS]") }
            for index in stride(from: 0, to: arguments.count, by: 2) {
                let key = arguments[index], value = arguments[index + 1]
                if key == "--root" { root = URL(fileURLWithPath: value, isDirectory: true); continue }
                guard ["--as-of", "--split-at"].contains(key), let seconds = Double(value),
                      seconds.isFinite, seconds >= 0, seconds < 253_402_300_800 else { throw ScanError.failed("Invalid report argument") }
                if key == "--as-of" { asOf = Date(timeIntervalSince1970: seconds) }
                else { splitAt = Date(timeIntervalSince1970: seconds) }
            }
            guard let root, let asOf, FileManager.default.fileExists(atPath: root.path) else {
                throw ScanError.failed("An existing --root desk archive and --as-of Unix cutoff are required")
            }
            let report = try await ExecutionIntelligence.loadReport(root: root, asOf: asOf, splitAt: splitAt)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
        } catch {
            FileHandle.standardError.write(Data("Edge report failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
