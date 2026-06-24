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
#endif
