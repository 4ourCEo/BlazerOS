import BlazerCore
import Foundation

enum GBPJPYLondonArchiveReplayCommand {
    static func run(arguments: [String]) throws {
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard ["--archive", "--configuration", "--session", "--provenance"].contains(key),
                  index + 1 < arguments.count else {
                throw ScanError.failed("London archive replay requires --archive DIR --configuration JSON --session JSON --provenance JSON")
            }
            values[key] = arguments[index + 1]
            index += 2
        }
        guard let archivePath = values["--archive"], let configurationPath = values["--configuration"],
              let sessionPath = values["--session"], let provenancePath = values["--provenance"] else {
            throw ScanError.failed("London archive replay requires explicit archive, configuration, session, and provenance files")
        }
        // Archive batches and Codable session inputs use JSONEncoder's default Date
        // representation (seconds since the 2001 reference date). Do not decode them
        // as Unix seconds: that would shift valid 2026 archive data back to 1995.
        let decoder = JSONDecoder()
        func read<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
            try decoder.decode(type, from: Data(contentsOf: URL(fileURLWithPath: path)))
        }
        let configuration = try read(GBPJPYLondonBreakRetestConfiguration.self, configurationPath)
        let session = try read(GBPJPYLondonBreakRetestSession.self, sessionPath)
        let provenance = try read(GBPJPYLondonBreakRetestProvenance.self, provenancePath)
        let directory = URL(fileURLWithPath: archivePath, isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let sources = try files.map { url in
            ORBArchiveBatchSource(filename: url.lastPathComponent,
                batch: try read(OandaHistoricalBidAskBatch.self, url.path))
        }
        let report = try GBPJPYLondonBreakRetestArchiveReplay.replay(sources: sources,
            configuration: configuration, session: session, provenance: provenance)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        FileHandle.standardOutput.write(try encoder.encode(report))
        FileHandle.standardOutput.write(Data([0x0a]))
    }
}
