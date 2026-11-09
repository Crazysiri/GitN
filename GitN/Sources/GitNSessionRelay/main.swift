import Foundation

// Reporting is fail-open: no stdout, no raw event retention, and always exit 0.
func relay() throws {
    let args = CommandLine.arguments
    guard args.count == 4, ["Codex", "Kiro"].contains(args[1]) else { return }
    let provider = args[1]
    let namespace = args[2]
    let inbox = URL(fileURLWithPath: args[3], isDirectory: true)
    var input = Data()
    while input.count <= 65536 {
        guard let chunk = try FileHandle.standardInput.read(upToCount: min(4096, 65537 - input.count)), !chunk.isEmpty else { break }
        input.append(chunk)
    }
    guard input.count <= 65536,
          let raw = try JSONSerialization.jsonObject(with: input) as? [String: Any],
          let session = raw["session_id"] as? String, !session.isEmpty, session.count <= 256,
          let event = raw["hook_event_name"] as? String, event.count <= 128,
          namespace.count <= 4096 else { return }
    var envelope: [String: Any] = ["version": 1, "id": UUID().uuidString, "agent": provider,
        "namespace": namespace, "sessionID": session, "event": event,
        // JSONEncoder's default Date representation is seconds since 2001.
        "timestamp": Date().timeIntervalSinceReferenceDate]
    if let cwd = raw["cwd"] as? String, cwd.hasPrefix("/"), cwd.count <= 4096 { envelope["cwd"] = cwd }
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
    let destination = inbox.appendingPathComponent(UUID().uuidString + ".json")
    try JSONSerialization.data(withJSONObject: envelope).write(to: destination, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
}
try? relay()
