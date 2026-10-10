import Foundation

enum Wire {
    static let maximum = 192001
    static func packet(_ kind: UInt8, _ body: Data = Data()) -> Data {
        var n = UInt32(body.count + 1).bigEndian
        var result = withUnsafeBytes(of: &n) { Data($0) }
        result.append(kind); result.append(body); return result
    }
    static func take(_ data: inout Data) throws -> (UInt8, Data)? {
        guard data.count >= 4 else { return nil }
        let n = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard n >= 1, n <= maximum else { throw NSError(domain: "无效音频桥协议长度", code: 1) }
        guard data.count >= n + 4 else { return nil }
        let kind = data[data.startIndex + 4]
        let body = Data(data.dropFirst(5).prefix(n - 1))
        data = Data(data.dropFirst(n + 4))
        return (kind, body)
    }
}
