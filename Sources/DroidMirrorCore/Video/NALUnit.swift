import Foundation
import CoreMedia

public struct NALUnit {
    public let type: UInt8
    public let data: Data

    public var isSPS: Bool { type == 7 }
    public var isPPS: Bool { type == 8 }
    public var isIDR: Bool { type == 5 }
    public var isSlice: Bool { type == 1 || type == 5 }
}

public final class NALParser {
    /// Extracts all NAL units from an Annex-B formatted data buffer.
    /// Handles both 3-byte (00 00 01) and 4-byte (00 00 00 01) start codes.
    public static func parseAnnexB(data: Data) -> [NALUnit] {
        var nals: [NALUnit] = []
        let count = data.count
        guard count >= 4 else { return [] }

        data.withUnsafeBytes { rawPtr in
            guard let bytes = rawPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

            var startIndices: [Int] = []
            var headerLengths: [Int] = []

            var i = 0
            while i < count - 2 {
                if bytes[i] == 0 && bytes[i + 1] == 0 {
                    if bytes[i + 2] == 1 {
                        // 3-byte start code: 00 00 01
                        startIndices.append(i + 3)
                        headerLengths.append(3)
                        i += 3
                        continue
                    } else if i + 3 < count && bytes[i + 2] == 0 && bytes[i + 3] == 1 {
                        // 4-byte start code: 00 00 00 01
                        startIndices.append(i + 4)
                        headerLengths.append(4)
                        i += 4
                        continue
                    }
                }
                i += 1
            }

            for idx in 0..<startIndices.count {
                let start = startIndices[idx]
                let end: Int
                if idx + 1 < startIndices.count {
                    end = startIndices[idx + 1] - headerLengths[idx + 1]
                } else {
                    end = count
                }

                if end > start {
                    let nalLength = end - start
                    let nalBytes = bytes.advanced(by: start)
                    let nalType = nalBytes.pointee & 0x1F
                    let nalData = Data(bytes: nalBytes, count: nalLength)
                    nals.append(NALUnit(type: nalType, data: nalData))
                }
            }
        }

        return nals
    }
}
