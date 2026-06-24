import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("QueryDecoder bool 缺失或非布尔取默认值，并记录 key")
func queryDecoderBoolDefaults() {
    var missing = QueryDecoder([:])
    #expect(missing.bool("flag", default: true) == true)
    var nonBool = QueryDecoder(["flag": "yes"])
    #expect(nonBool.bool("flag", default: false) == false)
    var present = QueryDecoder(["flag": true])
    #expect(present.bool("flag", default: false) == true)
    #expect(present.accessedKeys == ["flag"])
}

@Test("QueryDecoder string 缺失返回 nil")
func queryDecoderStringOptional() {
    var missing = QueryDecoder([:])
    #expect(missing.string("name") == nil)
    var present = QueryDecoder(["name": "abc"])
    #expect(present.string("name") == "abc")
}

@Test("QueryDecoder optionalNonNegativeInt 文案与边界")
func queryDecoderOptionalNonNegativeInt() throws {
    var missing = QueryDecoder([:])
    #expect(try missing.optionalNonNegativeInt("depth") == nil)
    var valid = QueryDecoder(["depth": 5])
    #expect(try valid.optionalNonNegativeInt("depth") == 5)
    #expect(throws: QueryParseError("depth must be a non-negative integer")) {
        var d = QueryDecoder(["depth": -1])
        try d.optionalNonNegativeInt("depth")
    }
    // throw 后 key 仍记录（insert before throw，tracing 一致性核心）
    var dNonNeg = QueryDecoder(["depth": -1])
    do {
        _ = try dNonNeg.optionalNonNegativeInt("depth")
        Issue.record("expected throw")
    } catch {
        #expect(dNonNeg.accessedKeys.contains("depth"))
    }
}

@Test("QueryDecoder rangedInt 文案与边界")
func queryDecoderRangedInt() throws {
    var missing = QueryDecoder([:])
    #expect(try missing.rangedInt("n", in: 1...200, default: 80) == 80)
    var valid = QueryDecoder(["n": 50])
    #expect(try valid.rangedInt("n", in: 1...200, default: 80) == 50)
    #expect(throws: QueryParseError("n must be an integer between 1 and 200")) {
        var d = QueryDecoder(["n": 201])
        try d.rangedInt("n", in: 1...200, default: 80)
    }
    // throw 后 key 仍记录（insert before throw，tracing 一致性核心）
    var dRanged = QueryDecoder(["n": 201])
    do {
        _ = try dRanged.rangedInt("n", in: 1...200, default: 80)
        Issue.record("expected throw")
    } catch {
        #expect(dRanged.accessedKeys.contains("n"))
    }
}

@Test("QueryDecoder enumValue 文案与默认")
func queryDecoderEnumValue() throws {
    enum Level: String, CaseIterable { case basic, appearance, full }
    var missing = QueryDecoder([:])
    #expect(try missing.enumValue("level", default: Level.appearance) == .appearance)
    var valid = QueryDecoder(["level": "basic"])
    #expect(try valid.enumValue("level", default: Level.appearance) == .basic)
    #expect(throws: QueryParseError("level must be one of basic, appearance, full")) {
        var d = QueryDecoder(["level": "nope"])
        try d.enumValue("level", default: Level.appearance)
    }
    // throw 后 key 仍记录（insert before throw，tracing 一致性核心）
    var dEnum = QueryDecoder(["level": "nope"])
    do {
        _ = try dEnum.enumValue("level", default: Level.appearance)
        Issue.record("expected throw")
    } catch {
        #expect(dEnum.accessedKeys.contains("level"))
    }
}

@Test("QueryDecoder requiredEnum 缺失与非法文案")
func queryDecoderRequiredEnum() throws {
    enum Event: String, CaseIterable { case touchDown, touchUpInside }
    #expect(throws: QueryParseError("missing required parameter 'event'")) {
        var d = QueryDecoder([:])
        _ = try d.requiredEnum("event") as Event
    }
    #expect(throws: QueryParseError("event must be one of touchDown, touchUpInside")) {
        var d = QueryDecoder(["event": "nope"])
        _ = try d.requiredEnum("event") as Event
    }
    // throw 后 key 仍记录（insert before throw，tracing 一致性核心）
    var dReqEnum = QueryDecoder(["event": "nope"])
    do {
        _ = try dReqEnum.requiredEnum("event") as Event
        Issue.record("expected throw")
    } catch {
        #expect(dReqEnum.accessedKeys.contains("event"))
    }
    var valid = QueryDecoder(["event": "touchUpInside"])
    let e: Event = try valid.requiredEnum("event")
    #expect(e == .touchUpInside)
}

@Test("QueryDecoder requiredEnum 真实事件文案锁顺序")
func queryDecoderRequiredEnumRealEventOrder() {
    #expect(throws: QueryParseError("event must be one of touchDown, touchUpInside, valueChanged, editingChanged, editingDidBegin, editingDidEnd")) {
        var d = QueryDecoder(["event": "nope"])
        _ = try d.requiredEnum("event") as UIControlSendActionEvent
    }
}
