import Testing
import Foundation
@testable import iOSExploreServer

@Test("JSON 字典字面量构造与下标")
func jsonLiteralAndSubscript() {
    let json: JSON = ["pong": true, "count": 3, "name": "hi"]
    #expect(json["pong"] == .bool(true))
    #expect(json["count"] == .double(3))
    #expect(json["name"]?.stringValue == "hi")
}

@Test("encode/decode 往返")
func coderRoundTrip() throws {
    let original: JSON = ["ok": true, "msg": "hi", "n": 1.5]
    let data = JSONCoder.encode(original)
    let decoded = try #require(JSONCoder.decode(data))
    #expect(decoded["ok"] == .bool(true))
    #expect(decoded["msg"]?.stringValue == "hi")
    #expect(decoded["n"]?.doubleValue == 1.5)
}

@Test("decode 非法 JSON 返回 nil")
func decodeInvalid() {
    #expect(JSONCoder.decode(Data("not json".utf8)) == nil)
}

@Test("encode NaN double 不再 abort 且消毒为 0")
func encodeSanitizesNaN() throws {
    // 直接走 .double(NaN)：JSONSerialization 在底层 _writeJSONNumber 遇 NaN 会抛
    // Objective-C NSException，Swift try?/do-catch 无法 catch，进程会 abort。
    // 这里覆盖 JSONCoder.toAny 的边界消毒：NaN → 0，让序列化稳定成功。
    let nan: JSON = ["v": .double(.nan)]
    let data = JSONCoder.encode(nan)
    let decoded = try #require(JSONCoder.decode(data))
    #expect(decoded["v"] == .double(0))
}

@Test("encode +Infinity double 消毒为 0")
func encodeSanitizesPositiveInfinity() throws {
    let inf: JSON = ["v": .double(.infinity)]
    let data = JSONCoder.encode(inf)
    let decoded = try #require(JSONCoder.decode(data))
    #expect(decoded["v"] == .double(0))
}

@Test("encode -Infinity double 消毒为 0")
func encodeSanitizesNegativeInfinity() throws {
    let inf: JSON = ["v": .double(-.infinity)]
    let data = JSONCoder.encode(inf)
    let decoded = try #require(JSONCoder.decode(data))
    #expect(decoded["v"] == .double(0))
}

@Test("嵌套数组/对象内的 NaN 一并被消毒")
func encodeSanitizesNestedNaN() throws {
    let nested: JSON = [
        "outer": .object([
            "inner": .array([.double(.nan), .double(1.5), .double(.infinity)])
        ])
    ]
    let data = JSONCoder.encode(nested)
    let decoded = try #require(JSONCoder.decode(data))
    guard case .object(let outer)? = decoded["outer"] else {
        Issue.record("outer not object"); return
    }
    guard case .array(let arr)? = outer["inner"] else {
        Issue.record("inner not array"); return
    }
    #expect(arr == [.double(0), .double(1.5), .double(0)])
}

@Test("有限 double 不受消毒影响")
func encodeKeepsFiniteDoubles() throws {
    let json: JSON = ["a": .double(0), "b": .double(-1.5), "c": .double(1e308)]
    let data = JSONCoder.encode(json)
    let decoded = try #require(JSONCoder.decode(data))
    #expect(decoded["a"] == .double(0))
    #expect(decoded["b"] == .double(-1.5))
    #expect(decoded["c"] == .double(1e308))
}
