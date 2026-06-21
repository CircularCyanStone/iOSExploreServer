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
