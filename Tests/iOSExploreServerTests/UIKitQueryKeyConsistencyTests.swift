#if canImport(UIKit)
import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("ui.viewTargets parse 读取的 builder key 全部声明在 parameters")
func viewTargetsKeysCoveredByParameters() throws {
    var d = QueryDecoder([:])
    _ = try UIViewTargetsQuery.parse(decoding: &d)
    let params = Set(ViewTargetsCommand().parameters.map(\.name))
    #expect(d.accessedKeys.isSubset(of: params))
}

@Test("ui.topViewHierarchy parse 读取的 builder key 全部声明在 parameters")
func topViewHierarchyKeysCoveredByParameters() throws {
    var d = QueryDecoder([:])
    _ = try UIViewHierarchyQuery.parse(decoding: &d)
    let params = Set(TopViewHierarchyCommand().parameters.map(\.name))
    #expect(d.accessedKeys.isSubset(of: params))
}

@Test("ui.control.sendAction parse 读取的 builder key 全部声明在 parameters")
func controlSendActionKeysCoveredByParameters() throws {
    var d = QueryDecoder(["event": "touchUpInside", "path": "root"])
    _ = try UIControlSendActionQuery.parse(decoding: &d)
    let params = Set(UIControlSendActionCommand().parameters.map(\.name))
    #expect(d.accessedKeys.isSubset(of: params))
}

@Test("ui.tap parse 读取的 builder key 全部声明在 parameters")
func tapKeysCoveredByParameters() throws {
    var d = QueryDecoder(["path": "root"])
    _ = try UITapQuery.parse(decoding: &d)
    let params = Set(UITapCommand().parameters.map(\.name))
    #expect(d.accessedKeys.isSubset(of: params))
}
#endif
