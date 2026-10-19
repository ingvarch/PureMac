import Darwin
import Foundation
import TerminalUI

struct MemoryStatus: Equatable {
    let total: Int64
    let free: Int64
    let inactive: Int64
    let active: Int64
    let wired: Int64
    let compressed: Int64

    var usedFraction: Double {
        total > 0 ? Double(total - free) / Double(total) : 0
    }
}

enum MemoryPressure: Equatable {
    case normal, warning, critical

    init?(level: Int) {
        switch level {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }

    var color: TerminalColor {
        switch self {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}

struct VolumeStatus: Equatable {
    let availableNow: Int64
    let availableForImportantUsage: Int64
    let total: Int64

    var systemManagedCapacity: Int64 {
        max(0, availableForImportantUsage - availableNow)
    }

    var freeFraction: Double {
        total > 0 ? Double(availableNow) / Double(total) : 1
    }

    var usedFraction: Double { 1 - freeFraction }

    var freeColor: TerminalColor {
        switch freeFraction {
        case ..<0.1: return .red
        case ..<0.2: return .yellow
        default: return .green
        }
    }
}

enum SystemInfoError: LocalizedError {
    case memoryUnavailable(kern_return_t)
    case volumeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .memoryUnavailable(let status):
            return "macOS did not return memory statistics (status \(status))."
        case .volumeUnavailable(let path):
            return "macOS did not return storage capacity for \(path)."
        }
    }
}

enum SystemInfo {
    static func memoryStatus() throws -> MemoryStatus {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else {
            throw SystemInfoError.memoryUnavailable(status)
        }

        let page = Int64(vm_kernel_page_size)
        return MemoryStatus(
            total: Int64(ProcessInfo.processInfo.physicalMemory),
            free: Int64(stats.free_count) * page,
            inactive: Int64(stats.inactive_count) * page,
            active: Int64(stats.active_count) * page,
            wired: Int64(stats.wire_count) * page,
            compressed: Int64(stats.compressor_page_count) * page
        )
    }

    static func memoryPressure() -> MemoryPressure? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return nil }
        return MemoryPressure(level: Int(level))
    }

    static func volumeStatus(_ path: String) throws -> VolumeStatus {
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
        ])
        guard let available = values.volumeAvailableCapacity,
              let total = values.volumeTotalCapacity
        else {
            throw SystemInfoError.volumeUnavailable(path)
        }
        let important = values.volumeAvailableCapacityForImportantUsage ?? Int64(available)
        return VolumeStatus(
            availableNow: max(0, Int64(available)),
            availableForImportantUsage: max(0, important),
            total: max(0, Int64(total))
        )
    }

}
