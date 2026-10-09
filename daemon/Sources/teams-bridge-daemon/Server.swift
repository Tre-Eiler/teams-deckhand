import Foundation
import Swifter

/// Two servers, separated by *where they listen* (Swifter can't reliably tell
/// a request's origin, so a check inside a handler isn't trustworthy):
///
/// - `server` — all interfaces, port N. Read-only: just the status feed
///   (`/status`, `/ws`) that Homey and Home Assistant on the network consume.
///   Nothing here can change anything or reveal more than call/mic/camera state.
/// - `localServer` — 127.0.0.1 only, port N+1. Everything that acts or exposes
///   activity: the controls (mic, camera, hang up, auto-mute…), key images,
///   diagnostics and logs. Unreachable from the network by construction. It
///   also serves the status feed, which is what the Stream Deck plugin uses.
final class BridgeServer {
    private let server = HttpServer()
    private let localServer = HttpServer()
    private var sessions: [WebSocketSession] = []
    private let lock = NSLock()

    var statusProvider: (() -> Status)?
    /// Each command returns the fresh, post-action status (not a stale cache)
    /// so the HTTP response and the caller's local UI update are correct
    /// immediately.
    var onMicToggle: (() -> Status)?
    var onCameraToggle: (() -> Status)?
    var onHandToggle: (() -> Status)?
    var onLeaveCall: (() -> Status)?
    var onAutoMuteToggle: (() -> Status)?
    var onAutoMuteTimeout: ((Int) -> Status)?
    var onAutoMuteAddTime: ((Int) -> Status)?
    var onAutoMuteMargin: ((Double) -> Void)?
    var onAutoMuteListen: ((Int) -> Void)?
    var onAutoMuteInput: ((String?) -> Void)?
    /// Everything we can see about Teams, permissions and audio, for support.
    var diagnostics: (() -> [String: Any])?
    /// Builds a zip of logs + diagnostics and returns where it was written.
    var logArchive: (() -> URL?)?
    /// Detector internals (level, noise floor, threshold) for tuning.
    var autoMuteDetails: (() -> [String: Any])?

    func start(port: in_port_t) throws {
        registerStatusFeed(on: server)
        registerStatusFeed(on: localServer)

        // Everything below changes state or exposes activity: loopback only.
        localServer["/mic/toggle"] = { [weak self] _ in
            guard let status = self?.onMicToggle?() else { return .internalServerError }
            return .ok(.json(Self.dict(status)))
        }
        localServer["/camera/toggle"] = { [weak self] _ in
            guard let status = self?.onCameraToggle?() else { return .internalServerError }
            return .ok(.json(Self.dict(status)))
        }
        localServer["/call/leave"] = { [weak self] _ in
            guard let status = self?.onLeaveCall?() else { return .internalServerError }
            return .ok(.json(Self.dict(status)))
        }
        localServer["/hand/toggle"] = { [weak self] _ in
            guard let status = self?.onHandToggle?() else { return .internalServerError }
            return .ok(.json(Self.dict(status)))
        }

        localServer["/automute/toggle"] = { [weak self] _ in
            guard let status = self?.onAutoMuteToggle?() else { return .internalServerError }
            return .ok(.json(Self.dict(status)))
        }
        localServer["/automute/timeout"] = { [weak self] request in
            guard let seconds = Self.intParam("seconds", in: request) else { return .badRequest(.text("seconds=<int> required")) }
            guard let status = self?.onAutoMuteTimeout?(seconds) else { return .internalServerError }
            return .ok(.json(Self.dict(status)))
        }
        localServer["/automute/add"] = { [weak self] request in
            guard let seconds = Self.intParam("seconds", in: request) else { return .badRequest(.text("seconds=<int> required")) }
            guard let status = self?.onAutoMuteAddTime?(seconds) else { return .internalServerError }
            return .ok(.json(Self.dict(status)))
        }
        localServer["/automute/margin"] = { [weak self] request in
            guard let db = request.queryParams.first(where: { $0.0 == "db" }).flatMap({ Double($0.1) }) else {
                return .badRequest(.text("db=<number> required"))
            }
            self?.onAutoMuteMargin?(db)
            return .ok(.json(self?.autoMuteDetails?() ?? [:]))
        }
        // Picks which mic to listen to by part of its name; empty = system default.
        localServer["/automute/input"] = { [weak self] request in
            // Swifter hands query values back still percent-encoded.
            let name = request.queryParams.first(where: { $0.0 == "name" })?.1.removingPercentEncoding
            self?.onAutoMuteInput?(name)
            return .ok(.json(self?.autoMuteDetails?() ?? [:]))
        }
        // Opens the mic for N seconds (max 60) even outside a call, so levels
        // can be watched via GET /automute while tuning sensitivity.
        localServer["/automute/listen"] = { [weak self] request in
            self?.onAutoMuteListen?(min(max(Self.intParam("seconds", in: request) ?? 10, 1), 60))
            return .ok(.json(self?.autoMuteDetails?() ?? [:]))
        }
        localServer["/automute"] = { [weak self] _ in
            .ok(.json(self?.autoMuteDetails?() ?? [:]))
        }

        localServer["/neo-panel.png"] = { [weak self] _ in
            guard let status = self?.statusProvider?() else { return .internalServerError }
            return Self.png(NeoPanelRenderer.render(status: status))
        }
        // The key images are a pure function of their query string (the state
        // to draw is passed in: timeout, enabled, remaining), so a client that
        // just received a status can never get an image of an older one.
        localServer["/key/timeout.png"] = { [weak self] request in
            guard let seconds = Self.intParam("seconds", in: request),
                  let status = self?.statusProvider?() else { return .badRequest(.text("seconds=<int> required")) }
            return Self.png(KeyRenderer.timeoutKey(seconds: seconds, status: Self.autoMuteState(in: request, fallback: status)))
        }
        localServer["/key/addtime.png"] = { [weak self] request in
            guard let seconds = Self.intParam("seconds", in: request),
                  let status = self?.statusProvider?() else { return .badRequest(.text("seconds=<int> required")) }
            return Self.png(KeyRenderer.addTimeKey(seconds: seconds, status: Self.autoMuteState(in: request, fallback: status)))
        }

        try server.start(port, forceIPv4: false, priority: .userInitiated)
        startLocalOnlyServer(port: port &+ 1)
    }

    /// The read-only status feed, served on both servers.
    private func registerStatusFeed(on target: HttpServer) {
        target["/status"] = { [weak self] _ in
            guard let status = self?.statusProvider?() else { return .internalServerError }
            return .ok(.json(Self.dict(status)))
        }
        target["/ws"] = websocket(
            text: { _, _ in },
            connected: { [weak self] session in
                self?.addSession(session)
                if let status = self?.statusProvider?() {
                    session.writeText(Self.jsonString(status))
                }
            },
            disconnected: { [weak self] session in
                self?.removeSession(session)
            }
        )
    }

    private func startLocalOnlyServer(port: in_port_t) {
        localServer["/diagnostics"] = { [weak self] _ in
            .ok(.json(self?.diagnostics?() ?? [:]))
        }
        localServer["/logs"] = { request in
            let lines = Self.intParam("lines", in: request) ?? 500
            return .ok(.text(Log.tail(min(max(lines, 1), 20_000))))
        }
        localServer["/logs.zip"] = { [weak self] _ in
            guard let url = self?.logArchive?(), let data = try? Data(contentsOf: url) else { return .internalServerError }
            try? FileManager.default.removeItem(at: url)
            return .raw(200, "OK", ["Content-Type": "application/zip",
                                    "Content-Disposition": "attachment; filename=\"Deckhand Logs.zip\""], { writer in
                try writer.write([UInt8](data))
            })
        }
        localServer.listenAddressIPv4 = "127.0.0.1"
        do {
            try localServer.start(port, forceIPv4: true, priority: .utility)
            Log.info("http", "Local-only server (controls, diagnostics, logs) on 127.0.0.1:\(port)")
        } catch {
            Log.warn("http", "Couldn't start the local-only server on port \(port): \(error)")
        }
    }

    func stop() {
        server.stop()
    }

    /// Push the current status to every connected client. Call whenever
    /// the polled status changes.
    func broadcast(_ status: Status) {
        lock.lock()
        let current = sessions
        lock.unlock()
        let json = Self.jsonString(status)
        for session in current {
            session.writeText(json)
        }
    }

    private func addSession(_ session: WebSocketSession) {
        lock.lock()
        sessions.append(session)
        lock.unlock()
    }

    private func removeSession(_ session: WebSocketSession) {
        lock.lock()
        sessions.removeAll { $0 === session }
        lock.unlock()
    }

    private static func intParam(_ name: String, in request: HttpRequest) -> Int? {
        request.queryParams.first(where: { $0.0 == name }).flatMap { Int($0.1) }
    }

    /// Overlays any auto-mute state given in the query string (timeout,
    /// enabled, remaining) onto `fallback`; omitted ones keep the fallback's
    /// value. `remaining` absent from the query means "no countdown" only if
    /// the other state params were given.
    private static func autoMuteState(in request: HttpRequest, fallback: Status) -> Status {
        let timeout = intParam("timeout", in: request)
        let enabled = intParam("enabled", in: request)
        guard timeout != nil || enabled != nil else { return fallback }
        var status = fallback
        if let timeout { status.autoMuteTimeoutSeconds = timeout }
        if let enabled { status.autoMuteEnabled = enabled != 0 }
        status.autoMuteRemainingSeconds = intParam("remaining", in: request)
        status.autoMuteHolding = (intParam("holding", in: request) ?? 0) != 0
        return status
    }

    private static func png(_ data: Data) -> HttpResponse {
        .raw(200, "OK", ["Content-Type": "image/png", "Cache-Control": "no-store"], { writer in
            try writer.write([UInt8](data))
        })
    }

    private static func dict(_ status: Status) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(status),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private static func jsonString(_ status: Status) -> String {
        guard let data = try? JSONEncoder().encode(status) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
