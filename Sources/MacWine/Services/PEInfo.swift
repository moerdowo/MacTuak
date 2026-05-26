import Foundation
import AppKit

/// Minimal PE/COFF reader: detects the target architecture and extracts the
/// embedded application icon (RT_GROUP_ICON / RT_ICON) into an NSImage.
/// Best-effort — returns nil on anything unexpected so callers fall back.
enum PEInfo {
    // MARK: - Public

    /// "x64" / "x86" / "arm64", or nil if not a recognizable PE.
    static func architecture(of path: String) -> String? {
        guard let r = Reader(path: path), let machine = r.machine() else { return nil }
        switch machine {
        case 0x8664: return "x64"
        case 0x014c: return "x86"
        case 0xAA64: return "arm64"
        default:     return nil
        }
    }

    /// Extracts the embedded icon as an NSImage, or nil.
    static func icon(of path: String) -> NSImage? {
        guard let r = Reader(path: path), let ico = r.assembleICO() else { return nil }
        return NSImage(data: ico)
    }

    // MARK: - Reader

    private final class Reader {
        let data: Data
        let base: Data.Index
        var peOff = 0
        var sections: [(va: UInt32, vsize: UInt32, raw: UInt32, rawSize: UInt32)] = []
        var rsrcRVA: UInt32 = 0

        init?(path: String) {
            guard let d = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe), d.count > 0x40 else { return nil }
            data = d
            base = d.startIndex
            guard parseHeaders() else { return nil }
        }

        // little-endian readers with bounds checks
        func u8(_ o: Int) -> UInt8? { o >= 0 && o + 1 <= data.count ? data[base + o] : nil }
        func u16(_ o: Int) -> UInt16? {
            guard o >= 0, o + 2 <= data.count else { return nil }
            return UInt16(data[base + o]) | (UInt16(data[base + o + 1]) << 8)
        }
        func u32(_ o: Int) -> UInt32? {
            guard o >= 0, o + 4 <= data.count else { return nil }
            return UInt32(data[base + o]) | (UInt32(data[base + o + 1]) << 8)
                 | (UInt32(data[base + o + 2]) << 16) | (UInt32(data[base + o + 3]) << 24)
        }
        func bytes(_ o: Int, _ len: Int) -> Data? {
            guard o >= 0, len >= 0, o + len <= data.count else { return nil }
            return data.subdata(in: (base + o)..<(base + o + len))
        }

        func machine() -> UInt16? { u16(peOff + 4) }

        private func parseHeaders() -> Bool {
            guard u16(0) == 0x5A4D, let lfanew = u32(0x3C) else { return false }   // "MZ"
            peOff = Int(lfanew)
            guard u32(peOff) == 0x00004550 else { return false }                    // "PE\0\0"
            guard let numSections = u16(peOff + 6),
                  let optSize = u16(peOff + 20), let optMagic = u16(peOff + 24) else { return false }
            let optOff = peOff + 24
            // Resource data directory (index 2) lives after the fixed optional header.
            let ddOff = optMagic == 0x20b ? optOff + 112 : optOff + 96
            rsrcRVA = u32(ddOff + 8 * 2) ?? 0

            var secOff = optOff + Int(optSize)
            for _ in 0..<Int(numSections) {
                guard let vsize = u32(secOff + 8), let va = u32(secOff + 12),
                      let rawSize = u32(secOff + 16), let raw = u32(secOff + 20) else { return false }
                sections.append((va, vsize, raw, rawSize))
                secOff += 40
            }
            return rsrcRVA != 0
        }

        /// Translate an RVA into a file offset using the section table.
        private func fileOffset(rva: UInt32) -> Int? {
            for s in sections where rva >= s.va && rva < s.va &+ max(s.vsize, s.rawSize) {
                return Int(s.raw &+ (rva &- s.va))
            }
            return nil
        }

        // MARK: Resource tree

        private struct DirEntry { let id: UInt32; let isDir: Bool; let offset: UInt32; let isName: Bool }

        private func readDir(at off: Int) -> [DirEntry]? {
            guard let named = u16(off + 12), let ids = u16(off + 14) else { return nil }
            let count = Int(named) + Int(ids)
            var entries: [DirEntry] = []
            var e = off + 16
            for _ in 0..<count {
                guard let name = u32(e), let dataOff = u32(e + 4) else { return nil }
                entries.append(DirEntry(id: name & 0x7FFFFFFF,
                                        isDir: dataOff & 0x80000000 != 0,
                                        offset: dataOff & 0x7FFFFFFF,
                                        isName: name & 0x80000000 != 0))
                e += 8
            }
            return entries
        }

        /// Returns the file offset + size of a leaf resource data blob.
        private func leaf(at dataEntryOff: Int) -> (off: Int, size: Int)? {
            guard let rva = u32(dataEntryOff), let size = u32(dataEntryOff + 4),
                  let fo = fileOffset(rva: rva) else { return nil }
            return (fo, Int(size))
        }

        /// Descend to the first language leaf under a type/name subdirectory entry.
        private func firstLeaf(dirFileOff: Int, rsrcBase: Int) -> (off: Int, size: Int)? {
            guard let entries = readDir(at: dirFileOff), let first = entries.first else { return nil }
            if first.isDir {
                return firstLeaf(dirFileOff: rsrcBase + Int(first.offset), rsrcBase: rsrcBase)
            }
            return leaf(at: rsrcBase + Int(first.offset))
        }

        /// Build a standalone .ico from RT_GROUP_ICON + the referenced RT_ICON images.
        func assembleICO() -> Data? {
            guard let rsrcBase = fileOffset(rva: rsrcRVA) else { return nil }
            guard let root = readDir(at: rsrcBase) else { return nil }

            // Type-level entries: find RT_GROUP_ICON (14) and RT_ICON (3) subdirs.
            guard let groupEntry = root.first(where: { $0.id == 14 && $0.isDir }),
                  let iconEntry = root.first(where: { $0.id == 3 && $0.isDir }) else { return nil }

            // First group → its data is a GRPICONDIR.
            guard let grp = firstLeaf(dirFileOff: rsrcBase + Int(groupEntry.offset), rsrcBase: rsrcBase),
                  let header = bytes(grp.off, 6), header.count == 6 else { return nil }
            let count = Int(UInt16(header[header.startIndex + 4]) | (UInt16(header[header.startIndex + 5]) << 8))
            guard count > 0, count < 64 else { return nil }

            // Map RT_ICON id → (fileOffset, size)
            guard let iconDir = readDir(at: rsrcBase + Int(iconEntry.offset)) else { return nil }
            func iconData(id: UInt32) -> (off: Int, size: Int)? {
                guard let entry = iconDir.first(where: { $0.id == id }), entry.isDir else { return nil }
                return firstLeaf(dirFileOff: rsrcBase + Int(entry.offset), rsrcBase: rsrcBase)
            }

            // Assemble ICONDIR + entries + image blobs.
            var entriesBlob = Data()
            var imagesBlob = Data()
            var written = 0
            let headerSize = 6 + 16 * count
            for i in 0..<count {
                let geOff = grp.off + 6 + 14 * i
                guard let ge = bytes(geOff, 14), ge.count == 14 else { continue }
                let s = ge.startIndex
                let nID = UInt16(ge[s + 12]) | (UInt16(ge[s + 13]) << 8)
                guard let img = iconData(id: UInt32(nID)), let blob = bytes(img.off, img.size) else { continue }

                var entry = Data()
                entry.append(contentsOf: ge[s..<(s + 12)])   // bWidth..dwBytesInRes (12 bytes)
                let imageOffset = UInt32(headerSize + imagesBlob.count)
                withUnsafeBytes(of: imageOffset.littleEndian) { entry.append(contentsOf: $0) }
                entriesBlob.append(entry)
                imagesBlob.append(blob)
                written += 1
            }
            guard written > 0 else { return nil }

            var ico = Data()
            ico.append(contentsOf: [0, 0, 1, 0])                       // reserved, type=1 (icon)
            ico.append(UInt8(written & 0xFF)); ico.append(UInt8((written >> 8) & 0xFF))
            // Fix the count in the header (we may have skipped some) and recompute offsets
            // relative to the actual header size.
            let realHeaderSize = 6 + 16 * written
            // Rebuild entries with corrected offsets.
            var fixedEntries = Data()
            var runningOffset = realHeaderSize
            var idx = 0
            while idx < written {
                let eStart = entriesBlob.startIndex + idx * 16
                var e = entriesBlob.subdata(in: eStart..<(eStart + 12))
                // image size is bytes 8..12 of the entry (dwBytesInRes)
                let sizeBytes = entriesBlob.subdata(in: (eStart + 8)..<(eStart + 12))
                let imgSize = Int(UInt32(sizeBytes[sizeBytes.startIndex]) |
                                  (UInt32(sizeBytes[sizeBytes.startIndex + 1]) << 8) |
                                  (UInt32(sizeBytes[sizeBytes.startIndex + 2]) << 16) |
                                  (UInt32(sizeBytes[sizeBytes.startIndex + 3]) << 24))
                withUnsafeBytes(of: UInt32(runningOffset).littleEndian) { e.append(contentsOf: $0) }
                fixedEntries.append(e)
                runningOffset += imgSize
                idx += 1
            }
            ico.append(fixedEntries)
            ico.append(imagesBlob)
            return ico
        }
    }
}
