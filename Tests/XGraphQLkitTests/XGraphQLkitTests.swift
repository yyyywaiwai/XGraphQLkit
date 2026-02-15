import Testing
@testable import XGraphQLkit

@Test func extractOperationIDs_handlesEscapedAndUnescapedAndOrder() async throws {
    let body = #"""
    /* minified-ish */
    a={queryId:\"AAAA1111bbbb2222CCCC3333dddd4444\",operationName:\"UserTweets\"};
    b={operationName:"UserByScreenName",queryId:"zzzz9999YYYY8888xxxx7777WWWW6666"};
    c={QueryId:"MiXeD5555MiXeD6666MiXeD7777MiXeD8888",OperationName:"SomeOp"};
    """#

    let map = XOperationIDExtractor.extractOperationIDs(from: body)

    #expect(map["UserTweets"] == "AAAA1111bbbb2222CCCC3333dddd4444")
    #expect(map["UserByScreenName"] == "zzzz9999YYYY8888xxxx7777WWWW6666")
    #expect(map["SomeOp"] == "MiXeD5555MiXeD6666MiXeD7777MiXeD8888")
}
