import Foundation
import Darwin

/// For short, non-interactive helper commands. Never passes arguments through a shell.
enum BoundedProcessRunner {
    struct Output {
        let status: Int32
        let stdout: Data
        let stderr: Data
    }

    enum Failure: LocalizedError {
        case timedOut, outputLimit, cancelled
        var errorDescription: String? {
            switch self {
            case .timedOut: "The helper command timed out."
            case .outputLimit: "The helper command produced too much output."
            case .cancelled: "The helper command was cancelled."
            }
        }
    }

    static func run(executable: String, arguments: [String], directory: URL? = nil,
                    environment: [String: String]? = nil, input: Data = Data(),
                    timeout: TimeInterval = 30, outputLimit: Int = 262_144) async throws -> Output {
        let state = State()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: executable)
                        process.arguments = arguments
                        process.currentDirectoryURL = directory
                        process.environment = environment
                        let out = Pipe(), err = Pipe(), stdin = Pipe()
                        process.standardOutput = out
                        process.standardError = err
                        process.standardInput = stdin
                        try state.start(process)
                        let outHandle = out.fileHandleForReading
                        let errHandle = err.fileHandleForReading
                        let inputHandle = stdin.fileHandleForWriting
                        defer {
                            try? outHandle.close(); try? errHandle.close(); try? inputHandle.close()
                        }
                        let outFD = outHandle.fileDescriptor, errFD = errHandle.fileDescriptor
                        let inputFD = inputHandle.fileDescriptor
                        for fd in [outFD, errFD, inputFD] {
                            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
                        }
                        _ = fcntl(inputFD, F_SETNOSIGPIPE, 1)
                        let started = ProcessInfo.processInfo.systemUptime
                        var outEOF = false, errEOF = false, inputClosed = false, inputOffset = 0
                        var buffer = [UInt8](repeating: 0, count: 16_384)
                        // Poll rather than blocking readers: grandchildren may inherit the pipes.
                        // The deadline must still return even if such a child keeps a pipe open.
                        while true {
                            if ProcessInfo.processInfo.systemUptime - started >= timeout { state.stop(.timedOut) }
                            if state.isStopping { break }
                            let running = process.isRunning
                            if !running && outEOF && errEOF { break }
                            if !inputClosed && (inputOffset == input.count || !running) {
                                try? inputHandle.close()
                                inputClosed = true
                            }
                            var descriptors = [
                                pollfd(fd: outEOF ? -1 : outFD, events: Int16(POLLIN), revents: 0),
                                pollfd(fd: errEOF ? -1 : errFD, events: Int16(POLLIN), revents: 0),
                                pollfd(fd: inputClosed ? -1 : inputFD, events: Int16(POLLOUT), revents: 0)
                            ]
                            _ = poll(&descriptors, nfds_t(descriptors.count), 20)
                            for index in 0..<2 where descriptors[index].revents != 0 {
                                let count = read(descriptors[index].fd, &buffer, buffer.count)
                                if count > 0 {
                                    state.append(Data(buffer.prefix(count)), isError: index == 1, limit: outputLimit)
                                } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
                                    if index == 0 { outEOF = true } else { errEOF = true }
                                }
                            }
                            if !inputClosed && descriptors[2].revents != 0 {
                                let count = input.withUnsafeBytes { bytes in
                                    write(inputFD, bytes.baseAddress!.advanced(by: inputOffset), min(16_384, input.count - inputOffset))
                                }
                                if count > 0 { inputOffset += count }
                                else if errno != EAGAIN && errno != EINTR {
                                    try? inputHandle.close(); inputClosed = true
                                }
                            }
                        }
                        process.waitUntilExit()
                        continuation.resume(with: state.finish(status: process.terminationStatus))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { state.stop(.cancelled) }
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var failure: Failure?
        private var stdout = Data(), stderr = Data()

        var isStopping: Bool {
            lock.lock(); defer { lock.unlock() }; return failure != nil
        }

        func start(_ process: Process) throws {
            lock.lock()
            defer { lock.unlock() }
            if let failure { throw failure }
            try process.run()
            self.process = process
        }

        func stop(_ reason: Failure) {
            lock.lock()
            if failure == nil { failure = reason }
            let running = process
            lock.unlock()
            guard let running, running.isRunning else { return }
            running.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if running.isRunning { kill(running.processIdentifier, SIGKILL) }
            }
        }

        func append(_ chunk: Data, isError: Bool, limit: Int) {
            lock.lock()
            let exceeds = stdout.count + stderr.count + chunk.count > limit
            if !exceeds {
                if isError { stderr.append(chunk) } else { stdout.append(chunk) }
            }
            lock.unlock()
            if exceeds { stop(.outputLimit) }
        }

        func finish(status: Int32) -> Result<Output, Error> {
            lock.lock()
            defer { lock.unlock() }
            process = nil
            if let failure { return .failure(failure) }
            return .success(Output(status: status, stdout: stdout, stderr: stderr))
        }
    }
}
