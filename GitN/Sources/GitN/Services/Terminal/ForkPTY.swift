import Darwin
import Foundation

/// Thin wrapper over the system `forkpty(3)` call. Owns the master FD and the
/// child PID for one PTY. No VT parsing, no rendering — raw bytes only.
///
/// This is the route-B backend: the PTY comes from the OS, not from node-pty.
/// Rendering happens in xterm.js; this type just moves bytes and manages the
/// child process lifecycle (resize, signals, reaping).
final class ForkPTY {
    enum PTYError: Error {
        case forkFailed(Int32)
        case alreadyStarted
    }

    private(set) var masterFD: Int32 = -1
    private(set) var childPID: pid_t = -1
    private(set) var isRunning = false

    /// Spawn `executable` with `arguments` inside a new PTY.
    ///
    /// - Parameters:
    ///   - execName: argv[0] for the child. A leading "-" marks a login shell.
    ///   - environment: full environment array ("KEY=VALUE"); replaces the child's env.
    ///   - cols/rows: initial window size written into the PTY before exec.
    func start(
        executable: String,
        arguments: [String],
        execName: String,
        environment: [String],
        directory: String,
        cols: UInt16,
        rows: UInt16
    ) throws {
        guard !isRunning else { throw PTYError.alreadyStarted }

        var master: Int32 = -1
        var winsize = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)

        // forkpty: opens a PTY pair, forks, and makes the child the session
        // leader with the slave as its controlling terminal.
        let pid = withUnsafeMutablePointer(to: &winsize) { winPtr in
            forkpty(&master, nil, nil, winPtr)
        }

        if pid < 0 {
            throw PTYError.forkFailed(errno)
        }

        if pid == 0 {
            // ── Child process ──
            // Change directory; ignore failure (shell will start in CWD).
            _ = directory.withCString { chdir($0) }

            // Build argv: [execName, arguments..., NULL].
            var argv: [UnsafeMutablePointer<CChar>?] = []
            argv.append(strdup(execName))
            for arg in arguments { argv.append(strdup(arg)) }
            argv.append(nil)

            // Build envp: [environment..., NULL].
            var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) }
            envp.append(nil)

            execve(executable, &argv, &envp)
            // execve only returns on failure.
            _exit(127)
        }

        // ── Parent process ──
        masterFD = master
        childPID = pid
        isRunning = true

        // Non-blocking reads so the read loop can be cancelled cleanly.
        let flags = fcntl(master, F_GETFL, 0)
        _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)
    }

    /// Write raw bytes to the PTY master (user input). Returns on partial writes.
    func write(_ data: Data) {
        guard isRunning, masterFD >= 0, !data.isEmpty else { return }
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            let total = raw.count
            while offset < total {
                let n = Darwin.write(masterFD, base + offset, total - offset)
                if n > 0 {
                    offset += n
                } else if n < 0 && errno == EAGAIN {
                    // Kernel buffer full; brief spin. Input is small, so this is rare.
                    usleep(1000)
                } else {
                    break
                }
            }
        }
    }

    /// Read whatever is currently available. Returns nil on EOF, empty Data when
    /// nothing is pending (EAGAIN).
    func read(maxBytes: Int = 65536) -> Data? {
        guard isRunning, masterFD >= 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: maxBytes)
        let n = buffer.withUnsafeMutableBytes { ptr -> Int in
            Darwin.read(masterFD, ptr.baseAddress, maxBytes)
        }
        if n > 0 {
            return Data(buffer[0..<n])
        } else if n == 0 {
            return nil // EOF: child closed the PTY
        } else {
            if errno == EAGAIN || errno == EINTR { return Data() }
            return nil
        }
    }

    /// Apply a new window size (clamped to positive by the caller).
    func resize(cols: UInt16, rows: UInt16) {
        guard isRunning, masterFD >= 0 else { return }
        var ws = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
    }

    /// Hang up the shell's process group, then reap the child, escalating to
    /// SIGKILL if it ignores the hangup. Mirrors the SwiftTerm panel's reaping
    /// so interactive zsh and any children do not become orphans/zombies.
    func terminate() {
        guard isRunning else { return }
        let pid = childPID
        isRunning = false

        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }

        guard pid > 0 else { return }

        // The child is a process-group leader (forkpty → setsid). Signal the
        // whole group so children of the shell are hung up too.
        let target = (getpgid(pid) == pid) ? -pid : pid
        _ = kill(target, SIGHUP)

        let deadPID = pid
        Task.detached(priority: .utility) {
            for _ in 0..<20 {
                var status: Int32 = 0
                let result = waitpid(deadPID, &status, WNOHANG)
                if result == deadPID || (result < 0 && errno == ECHILD) { return }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            let killTarget = (getpgid(deadPID) == deadPID) ? -deadPID : deadPID
            _ = kill(killTarget, SIGKILL)
            var status: Int32 = 0
            _ = waitpid(deadPID, &status, 0)
        }
    }

    deinit {
        if isRunning { terminate() }
    }
}
