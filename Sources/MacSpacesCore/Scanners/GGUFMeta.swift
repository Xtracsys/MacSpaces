import Foundation

/// Parses GGUF file headers to extract model metadata (architecture, name,
/// quantization, context length) without reading any tensor data.
///
/// GGUF v2/v3 layout after the 4-byte magic:
///   u32 version · u64 tensor_count · u64 metadata_kv_count
///   then KV pairs: u64 key_len + UTF-8 key + u32 value_type + value
public enum GGUFMeta {
    /// Metadata section is capped: bail out on absurd headers rather than
    /// reading forever on malformed files.
    static let maxMetadataBytes = 8 * 1024 * 1024

    public static func parse(at url: URL) -> GGUFMetaInfo? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var reader = ByteReader(handle: handle, budget: maxMetadataBytes)

        // Magic "GGUF"
        guard let magic = reader.readBytes(4), magic == Data("GGUF".utf8) else { return nil }
        guard let version = reader.readScalar(4) else { return nil }
        guard version >= 2, version <= 3 else { return nil }
        guard let tensorCount = reader.readScalar(8) else { return nil }

        var info = GGUFMetaInfo(version: UInt32(version), tensorCount: tensorCount,
                                architecture: nil, modelName: nil, quantization: nil,
                                contextLength: nil, parameterCountLabel: nil)

        guard let kvCount = reader.readScalar(8) else { return info }
        guard kvCount < 100_000 else { return info }

        var arch = ""
        for _ in 0..<kvCount {
            guard let key = reader.readString() else { break }
            guard let valueType = reader.readScalar(4) else { break }
            let type = GGUFValueType(rawValue: UInt32(valueType)) ?? .u64

            switch type {
            case .string:
                if let value = reader.readString() {
                    switch key {
                    case "general.architecture":
                        info.architecture = value
                        arch = value
                    case "general.name":
                        info.modelName = value
                    case "general.size_label":
                        info.parameterCountLabel = value
                    default:
                        break
                    }
                }
            case .u32:
                if let value = reader.readScalar(4) {
                    if key == "general.file_type" {
                        info.quantization = Self.quantName(UInt32(truncatingIfNeeded: value))
                    } else if key == "\(arch).context_length" {
                        info.contextLength = UInt64(value)
                    }
                }
            case .u64:
                if let value = reader.readScalar(8), key == "\(arch).context_length" {
                    info.contextLength = value
                }
            case .u8, .i8, .bool:
                _ = reader.readBytes(1)
            case .u16, .i16:
                _ = reader.readBytes(2)
            case .i32:
                _ = reader.readBytes(4)
            case .i64:
                _ = reader.readBytes(8)
            case .f32:
                _ = reader.readBytes(4)
            case .f64:
                _ = reader.readBytes(8)
            case .array:
                // elemType(u32) + count(u64) + elems — compute the skip length.
                guard let elemTypeRaw = reader.readScalar(4),
                      let elemCount = reader.readScalar(8)
                else { break }
                guard elemCount < 100_000_000 else { break }
                if let elemSize = Self.scalarSize(GGUFValueType(rawValue: UInt32(truncatingIfNeeded: elemTypeRaw)) ?? .u64) {
                    reader.skip(Int64(elemCount) * Int64(elemSize))
                } else {
                    // Array of strings or nested arrays: pop each element.
                    let elemType = GGUFValueType(rawValue: UInt32(truncatingIfNeeded: elemTypeRaw)) ?? .u64
                    for _ in 0..<elemCount {
                        if elemType == .string {
                            _ = reader.readString()
                        } else if elemType == .array {
                            break // nested arrays unsupported — stop parsing cleanly
                        } else if let size = Self.scalarSize(elemType) {
                            _ = reader.readBytes(size)
                        } else {
                            break
                        }
                    }
                }
            }

            if info.architecture != nil, info.modelName != nil, info.quantization != nil,
               info.contextLength != nil {
                // Everything we care about is present.
                break
            }
        }
        return info
    }

    /// Human quantization label for general.file_type (llama.cpp GGML_FTYPE values).
    static func quantName(_ ftype: UInt32) -> String {
        switch ftype {
        case 0: return "F32"
        case 1: return "F16"
        case 2: return "Q4_0"
        case 3: return "Q4_1"
        case 6: return "Q8_0"
        case 7: return "Q5_0"
        case 8: return "Q5_1"
        case 9: return "Q2_K"
        case 10: return "Q3_K_S"
        case 11: return "Q3_K_M"
        case 12: return "Q3_K_L"
        case 13: return "Q4_K_S"
        case 14: return "Q4_K_M"
        case 15: return "Q5_K_S"
        case 16: return "Q5_K_M"
        case 17: return "Q6_K"
        case 18: return "IQ2_XXS"
        case 19: return "IQ2_XS"
        case 20: return "Q2_K_S"
        case 21: return "IQ3_XS"
        case 22: return "IQ3_XXS"
        case 23: return "IQ1_S"
        case 24: return "IQ4_NL"
        case 25: return "IQ3_S"
        case 26: return "IQ3_M"
        case 27: return "IQ2_S"
        case 28: return "IQ2_M"
        case 29: return "IQ4_XS"
        case 30: return "IQ1_M"
        case 31: return "BF16"
        default: return "ftype \(ftype)"
        }
    }

    static func scalarSize(_ type: GGUFValueType) -> Int? {
        switch type {
        case .u8, .i8, .bool: return 1
        case .u16, .i16: return 2
        case .u32, .i32, .f32: return 4
        case .u64, .i64, .f64: return 8
        case .string, .array: return nil
        }
    }
}

enum GGUFValueType: UInt32 {
    case u8 = 0, i8, u16, i16, u32, i32, f32, bool, string, array, u64, i64, f64
}

/// Sequential little-endian reader over a FileHandle with a total byte budget.
struct ByteReader {
    let handle: FileHandle
    var budget: Int

    mutating func readBytes(_ count: Int) -> Data? {
        guard count >= 0, budget >= count else { return nil }
        guard let data = try? handle.read(upToCount: count), data.count == count else { return nil }
        budget -= count
        return data
    }

    mutating func skip(_ count: Int64) {
        guard count > 0, budget >= Int(min(count, Int64(Int.max))) else {
            budget = -1 // any future read fails
            return
        }
        let next = handle.offsetInFile + UInt64(count)
        try? handle.seek(toOffset: next)
        budget -= Int(count)
    }

    mutating func readScalar(_ width: Int) -> UInt64? {
        guard let data = readBytes(width) else { return nil }
        var value: UInt64 = 0
        for (index, byte) in data.enumerated() {
            value |= UInt64(byte) << (8 * UInt64(index))
        }
        return value
    }

    mutating func readString() -> String? {
        guard let length = readScalar(8), length < 1_000_000,
              let data = readBytes(Int(length))
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
