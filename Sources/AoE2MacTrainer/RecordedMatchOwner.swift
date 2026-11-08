import Compression
import Foundation

// Layout adapted from aoc-mgz, mgz/fast/header.py, with the save >= 67 changes.
// MIT License
// Copyright (c) 2021 happyleavesaoc
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

/// Reads only the recorder identity from the Mac DE build whose layout is verified.
enum RecordedMatchOwner {
    static func civilizationID(at recording: URL) -> String? {
        guard let file = try? FileHandle(forReadingFrom: recording) else { return nil }
        defer { try? file.close() }
        do {
            guard let prefix = try file.read(upToCount: 8), prefix.count == 8 else { return nil }
            var outer = Cursor(data: prefix)
            let headerLength = try outer.uint32()
            guard (9...8_388_608).contains(headerLength),
                  let compressed = try file.read(upToCount: headerLength - 8),
                  compressed.count == headerLength - 8 else { return nil }
            // Human-only matches have metadata immediately after the roster/options.
            // AI scripts may occupy a few MiB. Expand only if this format declares AI.
            let small = try decodedPrefix(compressed, limit: 64 * 1024)
            var fields = Cursor(data: small)
            let civ = try readRosterAndOptions(&fields)
            let ai = try fields.uint32()
            if ai == 1 {
                let larger = try decodedPrefix(compressed, limit: 4 * 1024 * 1024)
                fields = Cursor(data: larger, offset: fields.offset)
                // DE terminates its embedded AI with 4096 zero bytes. Check the
                // independent metadata speed and player count before accepting it.
                guard let end = larger.range(of: Data(repeating: 0, count: 4096),
                                             in: fields.offset..<larger.count) else { return nil }
                fields.offset = end.upperBound
            } else if ai != 0 { return nil }
            try fields.skip(24)
            guard try fields.uint32() == civ.speed else { return nil }
            try fields.skip(17)
            let owner = try fields.uint16()
            guard try fields.byte() == civ.count + 1, let id = civ.humans[owner] else { return nil }
            return CivilizationCatalog.standard.first { $0.xsID == id }?.id
        } catch { return nil }
    }

    private static func decodedPrefix(_ compressed: Data, limit: Int) throws -> Data {
        var result = Data(count: limit)
        let count = result.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) in
            compressed.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
                compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, limit,
                                          input.bindMemory(to: UInt8.self).baseAddress!, input.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard count > 0 else { throw Format.invalid }
        result.count = count
        return result
    }

    private static func readRosterAndOptions(_ fields: inout Cursor) throws
        -> (humans: [Int: Int], count: Int, speed: Int) {
        guard try fields.bytes(8) == Data("VER 9.4\0".utf8),
              try fields.uint32() == 0xbf800000,
              try fields.uint32() == 0x0044e666, // save 68.9, fixed point
              try fields.uint32() == 188329 else { throw Format.invalid }
        try fields.skip(16) // timestamp and option versions
        let dlcCount = try fields.uint32()
        guard dlcCount <= 64 else { throw Format.invalid }
        for _ in 0..<dlcCount {
            guard try fields.uint32() != 11 else { throw Format.invalid } // Return of Rome
        }
        try fields.skip(48) // dataset reference through game type and separators
        let speed = try fields.uint32()
        guard (0.1...10).contains(Float(bitPattern: UInt32(speed))) else { throw Format.invalid }
        try fields.skip(8)
        let playerCount = try fields.uint32()
        guard (1...8).contains(playerCount) else { throw Format.invalid }
        try fields.skip(42) // settings, flags and last separator before the eight slots
        var humans: [Int: Int] = [:]
        var players = Set<Int>()
        for _ in 0..<8 {
            try fields.skip(20)
            let civ = try fields.uint32()
            try fields.skip(4 * fields.uint32())
            try fields.skipString()
            try fields.skip(1)
            for _ in 0..<3 { try fields.skipString() }
            let type = try fields.uint32()
            try fields.skip(8)
            let number = try fields.uint32()
            if number != Int(UInt32.max) {
                guard (1...8).contains(number), players.insert(number).inserted else { throw Format.invalid }
                if type == 2 { humans[number] = civ }
            }
            try fields.skip(14) // random flag, AI flag, handicap and post-64.3 field
            try fields.skipString()
        }
        guard players.count == playerCount else { throw Format.invalid }
        try fields.skip(29)
        for block in 0..<21 {
            if block == 1 { try fields.skip(8) }
            while !(1..<255).contains(try fields.uint32()) { try fields.skipString() }
        }
        try fields.skip(4 * fields.uint32()) // strategic numbers
        let aiFiles = try fields.uint32()
        guard try fields.uint32() == 0, aiFiles <= 1024 else { throw Format.invalid }
        for _ in 0..<aiFiles {
            try fields.skip(4)
            try fields.skipString()
            try fields.skip(4)
        }
        try fields.skip(24) // GUID and preceding bytes
        try fields.skipString() // lobby name
        try fields.skip(8)
        guard try fields.stringLength() == 0 else { throw Format.invalid } // modded dataset
        try fields.skip(92)
        let optionCount = try fields.uint32()
        try fields.skip(12 + 4 * optionCount)
        try fields.skipString()
        try fields.skip(24)
        return (humans, playerCount, speed)
    }

    private enum Format: Error { case invalid }

    private struct Cursor {
        let data: Data
        var offset = 0

        mutating func skip(_ count: Int) throws {
            guard count >= 0, count <= data.count - offset else { throw Format.invalid }
            offset += count
        }

        mutating func bytes(_ count: Int) throws -> Data {
            let start = offset
            try skip(count)
            return data.subdata(in: start..<offset)
        }

        mutating func byte() throws -> Int {
            try skip(1)
            return Int(data[offset - 1])
        }

        mutating func uint16() throws -> Int {
            try byte() | byte() << 8
        }

        mutating func uint32() throws -> Int {
            try uint16() | uint16() << 16
        }

        mutating func stringLength() throws -> Int {
            guard try uint16() == 0x0a60 else { throw Format.invalid }
            return try uint16()
        }

        mutating func skipString() throws {
            try skip(stringLength())
        }
    }
}
