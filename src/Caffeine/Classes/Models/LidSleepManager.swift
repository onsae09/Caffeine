//
//  LidSleepManager.swift
//  Caffeine
//

import Foundation

/// Controls the system-wide `pmset disablesleep` flag, which keeps the Mac awake
/// even when the lid is closed. Changing it requires root privileges, which are obtained
/// only through a passwordless sudoers rule: an interactive password prompt could block
/// with the lid closed, at sleep or at quit and leave the flag stuck on.
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

    /// Terminal command that installs the sudoers rule letting Caffeine run `pmset` without a password
    var sudoersSetupCommand: String {
        let rule = "\(NSUserName()) ALL=(root) NOPASSWD: " +
            "\(self.pmsetPath) -a disablesleep 0, \(self.pmsetPath) -a disablesleep 1"
        return "echo '\(rule)' > /tmp/caffeine-sudoers && " +
            "sudo install -m 0440 -o root -g wheel /tmp/caffeine-sudoers /etc/sudoers.d/caffeine"
    }

    /// Sets `pmset -a disablesleep` through passwordless sudo, never prompting.
    /// Returns `true` if the system now matches `disabled`.
    @discardableResult
    func setSleepDisabled(_ disabled: Bool) -> Bool {
        let value = disabled ? "1" : "0"
        let result = self.run(self.sudoPath, arguments: ["-n", self.pmsetPath, "-a", "disablesleep", value])
        return result.status == 0 && self.isSleepDisabled() == disabled
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
