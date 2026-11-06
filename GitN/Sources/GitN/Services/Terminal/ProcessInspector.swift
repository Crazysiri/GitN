import Darwin
import Foundation

/// Reads live process facts from the OS: the working directory of a PID and the
/// foreground process of a PTY. Pure system-call plumbing, no policy.
enum ProcessInspector {
    /// Current working directory of `pid` via `proc_pidinfo(PROC_PIDVNODEPATHINFO)`.
    /// Returns nil when the process is gone or the call fails (e.g. permissions).
    static func workingDirectory(ofPID pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, ptr, size)
        }
        guard result > 0 else { return nil }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        return path.isEmpty ? nil : path
    }

    /// Short name of `pid` via `proc_name`. Returns nil when unavailable.
    static func name(ofPID pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 256)
        let result = proc_name(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }

    /// Foreground process group of a PTY master FD via `tcgetpgrp`.
    /// Returns nil when there is no controlling foreground group.
    static func foregroundProcessGroup(ofMasterFD fd: Int32) -> pid_t? {
        guard fd >= 0 else { return nil }
        let pgrp = tcgetpgrp(fd)
        return pgrp > 0 ? pgrp : nil
    }

    /// The foreground process name of a PTY: resolve the foreground group, then
    /// name it. When the foreground equals the shell itself, the caller treats
    /// that as "at the prompt" (no foreground command).
    static func foregroundProcessName(masterFD: Int32) -> String? {
        guard let pgrp = foregroundProcessGroup(ofMasterFD: masterFD) else { return nil }
        return name(ofPID: pgrp)
    }
}
