import Foundation

/// Local, bounded diagnostics for assistant calls. Prompts, responses, and credentials are
/// never stored. A missing URL keeps diagnostics in memory for tests and previews.
public actor AssistantDiagnosticsStore {
    private let url: URL?
    private var memory: [AssistantDiagnostic] = []

    public init(url: URL? = nil) {
        self.url = url
    }

    public func record(_ diagnostic: AssistantDiagnostic) {
        memory.append(diagnostic)
        if memory.count > 500 { memory.removeFirst(memory.count - 500) }
        guard let url, let data = try? Self.encoder.encode(diagnostic) else { return }
        var line = data
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? AtomicFile.write(line, to: url)
        }
        trimIfNeeded(url)
    }

    /// Keeps the on-disk diagnostic log bounded without retaining prompts or responses.
    private func trimIfNeeded(_ url: URL) {
        guard let data = try? Data(contentsOf: url), data.count > 256_000,
              let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).suffix(200)
        let trimmed = lines.joined(separator: "\n") + "\n"
        try? AtomicFile.write(Data(trimmed.utf8), to: url)
    }

    public func recent(limit: Int = 20) -> [AssistantDiagnostic] {
        Array(memory.suffix(max(0, limit)).reversed())
    }

    public func loadRecent(limit: Int = 20) -> [AssistantDiagnostic] {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            return recent(limit: limit)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = text.split(separator: "\n").compactMap {
            try? decoder.decode(AssistantDiagnostic.self, from: Data($0.utf8))
        }
        return Array(decoded.suffix(max(0, limit)).reversed())
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
