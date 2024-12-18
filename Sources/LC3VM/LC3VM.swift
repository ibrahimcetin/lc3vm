//
//  LC3VM.swift
//  lc3vm
//
//  Created by İbrahim Çetin on 9.10.2024.
//

import ArgumentParser
import Foundation
import LC3VMCore

/// The LC-3 virtual machine.
@main
@available(macOS 12, *) // https://forums.swift.org/t/asyncparsablecommand-doesnt-work/71300
@MainActor
struct LC3VM: AsyncParsableCommand {
    @Argument(help: "The path to the LC3 binary file to run.", transform: URL.init(fileURLWithPath:))
    var binary: URL

    func run() async throws {
        // Set up the signal handler
        signal(SIGINT) { handle_interrupt($0) }
        // Disable input buffering
        disable_input_buffering()

        // Create the LC-3 hardware
        let hardware = Hardware()

        // Read the binary file and load it into memory
        try hardware.readImage(binary)

        // Run the LC-3 machine
        try hardware.run()

        // Restore input buffering
        restore_input_buffering()
    }
}
