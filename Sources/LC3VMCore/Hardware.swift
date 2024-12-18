//
//  Hardware.swift
//  lc3vm
//
//  Created by İbrahim Çetin on 9.10.2024.
//

import Foundation

// MARK: - LC-3 Hardware

/// The LC-3 hardware.
@MainActor
public class Hardware {
    /// The memory of the LC-3 machine. It is an array of 65536 16-bit values.
    /// 128KB of memory.
    public private(set) var memory = [UInt16](repeating: 0, count: Constant.memorySize)

    /// 8 general-purpose registers, each 16 bits wide (0-7) and a program counter (PC) register.
    /// The condition flag register(COND) is also stored in the register array.
    public private(set) var registers = [UInt16](repeating: 0, count: Constant.registerCount)

    /// Indicates whether the hardware is running or not.
    public var isRunning = false

    /// Updates the value of a register.
    ///
    /// - Parameters:
    ///   - registerType: The register to update.
    ///   - value: The new value of the register.
    ///
    /// - SeeAlso: ``Register``
    public func updateRegister(_ registerType: RegisterType, with value: UInt16) {
        registers[registerType.rawValue] = value
    }

    /// Reads the value of a register.
    ///
    /// - Parameter registerType: The register to read the value from.
    ///
    /// - Returns: The value of the register.
    ///
    /// - Tip: You can also use ``Register/value`` to read the value of a register.
    public func readRegister(_ registerType: RegisterType) -> UInt16 {
        return registers[registerType.rawValue]
    }

    /// Reads the condition flag.
    ///
    /// - Returns: The condition flag.
    public func readConditionFlag() -> ConditionFlag {
        ConditionFlag(rawValue: Register(type: .cond, hardware: self).value)!
    }

    /// Updates the condition flag to a new value.
    ///
    /// - Parameter value: The new value of the condition flag.
    public func updateConditionFlag(to value: ConditionFlag) {
        updateRegister(.cond, with: value.rawValue)
    }

    /// Updates the condition flag based on the value of a register.
    ///
    /// - Parameter registerType: The register to read the value from.
    ///
    /// - SeeAlso: ``ConditionFlag``
    public func updateConditionFlag(from registerType: RegisterType) {
        let value = readRegister(registerType)

        let condition: ConditionFlag = if value == 0 {
            .zro
        } else if (value >> 15) & 1 == 1 { // a 1 in the left-most bit indicates negative
            .neg
        } else {
            .pos
        }

        updateConditionFlag(to: condition)
    }

    /// Reads a value from memory at a given address.
    ///
    /// - Parameter address: The address to read the value from.
    public func readMemory(at address: UInt16) -> UInt16 {
        if address == MemoryRegister.kbsr.rawValue {
            if check_key() {
                writeMemory(at: MemoryRegister.kbsr.rawValue, with: 1 << 15)
                writeMemory(at: MemoryRegister.kbdr.rawValue, with: UInt16(getchar()))
            } else {
                writeMemory(at: MemoryRegister.kbsr.rawValue, with: 0)
            }
        }

        return memory[Int(address)]
    }

    /// Writes a value to memory at a given address.
    ///
    /// - Parameters:
    ///   - address: The address to write the value to.
    ///   - value: The value to write to memory.
    public func writeMemory(at address: UInt16, with value: UInt16) {
        memory[Int(address)] = value
    }

    /// Reads the next instruction from memory.
    ///
    /// - Returns: The next instruction.
    public func readNextInstruction() -> Instruction {
        var programCounter = Register(type: .pc, hardware: self)

        let instruction = readMemory(at: programCounter.value)
        programCounter.value &+= 1

        return Instruction(rawValue: instruction, hardware: self)
    }

    /// Reads the image file and loads it into memory.
    ///
    /// - Parameter path: The path to the image file.
    public func readImage(_ path: URL) throws {
        guard let file = fopen(path.path, "rb") else {
            throw LC3VMError.unableToReadImageFile
        }

        readImageFile(file)

        fclose(file)
    }

    private func readImageFile(_ file: UnsafeMutablePointer<FILE>) {
        /* the origin tells us where in memory to place the image */
        var origin: UInt16 = 0
        fread(&origin, MemoryLayout.size(ofValue: origin), 1, file)
        origin = origin.bigEndian

        /* we know the maximum file size so we only need one fread */
        let maxRead = Constant.memorySize - Int(origin)

        memory.withUnsafeBufferPointer { buffer in
            var pointer = UnsafeMutableRawPointer(mutating: buffer.baseAddress!.advanced(by: Int(origin)))

            var readCount = fread(pointer, MemoryLayout<UInt16>.stride, Int(maxRead), file)

            while readCount > 0 {
                pointer.storeBytes(of: pointer.load(as: UInt16.self).bigEndian, as: UInt16.self)

                pointer = pointer.advanced(by: MemoryLayout<UInt16>.stride)
                readCount -= 1
            }
        }
    }

    /// Runs the LC-3 machine.
    ///
    /// - Throws: An error if the instruction is invalid.
    public func run() throws {
        isRunning = true

        while isRunning {
            let instruction = readNextInstruction()

            switch try instruction.opcode {
            case .br:
                try BR.execute(instruction)
            case .add:
                try ADD.execute(instruction)
            case .ld:
                try LD.execute(instruction)
            case .st:
                try ST.execute(instruction)
            case .jsr:
                try JSR.execute(instruction)
            case .and:
                try AND.execute(instruction)
            case .ldr:
                try LDR.execute(instruction)
            case .str:
                try STR.execute(instruction)
            case .rti:
                try RTI.execute(instruction)
            case .not:
                try NOT.execute(instruction)
            case .ldi:
                try LDI.execute(instruction)
            case .sti:
                try STI.execute(instruction)
            case .jmp:
                try JMP.execute(instruction)
            case .res:
                try RES.execute(instruction)
            case .lea:
                try LEA.execute(instruction)
            case .trap:
                try TRAP.execute(instruction)
            }
        }
    }

    /// Initializes the LC-3 hardware.
    ///
    /// - Note: Sets the condition register to zero and the program counter to the default starting location.
    public init() {
        // Set condition register to zero which value is 010 (not 000)
        updateConditionFlag(to: .zro)

        // Set the program counter to the default starting location
        updateRegister(.pc, with: Constant.pcStart)
    }
}

// MARK: - LC-3 Register

/// The LC-3 registers.
@MainActor
public struct Register {
    /// The register type.
    public let type: RegisterType

    /// The hardware that the register belongs to.
    public let hardware: Hardware

    public init(type: RegisterType, hardware: Hardware) {
        self.type = type
        self.hardware = hardware
    }

    /// The value of the register.
    ///
    /// This is a shorthand for reading or writing the value of a register.
    /// - Note: You can use this property to read or write the value of a register.
    /// - SeeAlso: ``Hardware/updateRegister(_:with:)`` and ``Hardware/readRegister(_:)``.
    public var value: UInt16 {
        get {
            hardware.readRegister(type)
        }

        set {
            hardware.updateRegister(type, with: newValue)
        }
    }
}

/// The register type.
public enum RegisterType: Int {
    /// General-purpose register.
    case r0, r1, r2, r3, r4, r5, r6, r7
    /// Program counter.
    case pc
    /// Condition flag register.
    case cond

    public init(rawValue: UInt16) throws {
        guard let register = Self(rawValue: Int(rawValue)) else {
            throw LC3VMError.invalidRegister
        }

        self = register
    }
}

/// The LC-3 memory registers.
public enum MemoryRegister: UInt16 {
    /// Keyboard status.
    case kbsr = 0xFE00
    /// Keyboard data.
    case kbdr = 0xFE02
}

/// The condition flags.
public enum ConditionFlag: UInt16 {
    /// Positive
    case pos = 0b001
    /// Zero
    case zro = 0b010
    /// Negative
    case neg = 0b100
}

// MARK: - Constants

/// The LC-3 VM errors.
public enum LC3VMError: Error {
    /// The instruction is invalid.
    case invalidInstruction
    /// The register is invalid.
    case invalidRegister
    /// The opcode is invalid.
    case invalidOpcode
    /// Unable to read the image file.
    case unableToReadImageFile
}

/// The LC-3 constant values.
public enum Constant {
    /// The maximum size of the memory.
    public static let memorySize = 1 << 16

    /// The number of registers.
    public static let registerCount = 10

    /// The default starting location of the program counter.
    public static let pcStart: UInt16 = 0x3000
}
