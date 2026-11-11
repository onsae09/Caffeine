//
//  LidSleepManager.swift
//  Caffeine
//

import Foundation

/// Controls the system-wide `pmset disablesleep` flag, which keeps the Mac awake
/// even when the lid is closed. Changing it requires root privileges.
final class LidSleepManager {
    static let shared = LidSleepManager()

    private let pmsetPath = "/usr/bin/pmset"
    private let sudoPath = "/usr/bin/sudo"

    private init() {}

    // MARK: - Public Methods

    /// Returns whether `SleepDisabled` is currently set in the system power settings
    func isSleepDisabled() -> Bool {
        guard let output = self.run(self.pmsetPath, arguments: ["-g"]).output else { return false }

        return output
            .split(separator: "\n")
            .contains { line in
                let parts = line.split(whereSeparator: \.isWhitespace)
                return parts.count >= 2 && parts[0] == "SleepDisabled" && parts[1] == "1"
            }
    }

    /// Sets `pmset -a disablesleep`. Tries passwordless sudo first, then falls back
    /// to the administrator password prompt. Returns `true` if the system now matches `disabled`.
    @discardableResult
    func setSleepDisabled(_ disabled: Bool) -> Bool {
        let value = disabled ? "1" : "0"

        // Silent path: works if the user added a NOPASSWD sudoers rule for pmset
        let sudoResult = self.run(self.sudoPath, arguments: ["-n", self.pmsetPath, "-a", "disablesleep", value])
        if sudoResult.status == 0 {
            return self.isSleepDisabled() == disabled
        }

        // Fallback: ask for the administrator password
        let prompt = String(localized: "Caffeine needs administrator privileges to change lid-closed sleep.")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source =
            "do shell script \"\(self.pmsetPath) -a disablesleep \(value)\" " +
            "with prompt \"\(prompt)\" with administrator privileges"

        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)

        return self.isSleepDisabled() == disabled
    }

    // MARK: - Private Methods

    private func run(_ path: String, arguments: [String]) -> (status: Int32, output: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return (-1, nil)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8))
    }
}
