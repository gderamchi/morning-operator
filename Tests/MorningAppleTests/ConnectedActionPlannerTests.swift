import Foundation
import Testing
@testable import MorningApple

@Suite("Local connected-action preparation")
@MainActor
struct ConnectedActionPlannerTests {
    @Test("Nested details are prepared locally and manually entered values remain authoritative")
    func nestedProposal() async throws {
        let expected = "{\"arguments\":{\"recipient\":\"person@example.test\",\"details\":{\"title\":\"Morning\",\"minutes\":15},\"labels\":[\"work\"]},\"question\":\"\"}"
        var captured = ""
        let planner = ConnectedActionPlanner(generator: { prompt in captured = prompt; return expected })
        let json = try await planner.propose(intention: "Prepare my fifteen-minute morning", tool: tool(),
            enteredArguments: ["recipient": .string("person@example.test")])
        let result = try ComposioJSONValue.parseObject(json)
        #expect(result["details"]?.objectValue?["minutes"] == .number(15))
        let prompt = try ComposioJSONValue.parseObject(captured)
        #expect(prompt["ownerIntention"] == .string("Prepare my fifteen-minute morning"))
        #expect(prompt["ownerEnteredValues"]?.objectValue?["recipient"] == .string("person@example.test"))
        #expect(ConnectedActionPlanner.instructions.contains("You have no tools"))
    }

    @Test("Unknown fields, wrong nested types and values outside constraints are refused")
    func invalidArguments() throws {
        let schema = try tool().inputSchema
        for value in [
            "{\"recipient\":\"a\",\"details\":{\"title\":\"Morning\",\"minutes\":15},\"sendNow\":true}",
            "{\"recipient\":\"a\",\"details\":{\"title\":\"Morning\",\"minutes\":1.5}}",
            "{\"recipient\":\"a\",\"details\":{\"title\":\"Morning\",\"minutes\":90}}",
            "{\"recipient\":\"a\",\"details\":{\"title\":\"Morning\",\"minutes\":15},\"labels\":[\"invented\"]}",
            "{\"details\":{\"title\":\"Morning\",\"minutes\":15}}"
        ] {
            let arguments = try ComposioJSONValue.parseObject(value)
            #expect(throws: ConnectedActionPlanningError.invalidProposal) {
                try ConnectedActionPlanner.validate(arguments: arguments, schema: schema)
            }
        }
    }

    @Test("Schema references validate nested values and cyclic schemas stay bounded")
    func references() throws {
        let schema = try schema("""
        {"type":"object","properties":{"details":{"$ref":"#/$defs/Details"}},"required":["details"],
         "$defs":{"Details":{"type":"object","properties":{"title":{"type":"string"}},"required":["title"]}}}
        """)
        try ConnectedActionPlanner.validate(arguments: ["details": .object(["title": .string("Morning")])], schema: schema)
        #expect(throws: ConnectedActionPlanningError.invalidProposal) {
            try ConnectedActionPlanner.validate(arguments: ["details": .object(["title": .number(4)])], schema: schema)
        }
        let cycle = try self.schema("{\"$ref\":\"#/$defs/loop\",\"$defs\":{\"loop\":{\"$ref\":\"#/$defs/loop\"}}}")
        #expect(throws: ConnectedActionPlanningError.invalidProposal) {
            try ConnectedActionPlanner.validate(arguments: [:], schema: cycle)
        }
    }

    @Test("Unavailable local model never invokes a generator")
    func unavailable() async throws {
        var generated = false
        let planner = ConnectedActionPlanner(generator: { _ in generated = true; return "{}" }, available: { false })
        let selected = try tool()
        await #expect(throws: ConnectedActionPlanningError.unavailable) {
            try await planner.propose(intention: "Do this", tool: selected)
        }
        #expect(!generated)
    }

    @Test("Missing information asks a question; proposed values cannot override owner fields")
    func clarificationAndOverride() async throws {
        let selected = try tool()
        let question = ConnectedActionPlanner(generator: { _ in "{\"arguments\":{},\"question\":\"Who should receive it?\"}" })
        await #expect(throws: ConnectedActionPlanningError.needsDetails("Who should receive it?")) {
            try await question.propose(intention: "Prepare it", tool: selected)
        }
        let override = ConnectedActionPlanner(generator: { _ in
            "{\"arguments\":{\"recipient\":\"other@example.test\",\"details\":{\"title\":\"Morning\",\"minutes\":15}},\"question\":\"\"}"
        })
        await #expect(throws: ConnectedActionPlanningError.invalidProposal) {
            try await override.propose(intention: "Prepare it", tool: selected, enteredArguments: ["recipient": .string("owner@example.test")])
        }
    }

    @Test("Unsupported constraints fail closed and generated operation names are never accepted")
    func unsupportedSchemaAndOperation() async throws {
        let unsupported = try schema("{\"type\":\"object\",\"if\":{\"required\":[\"a\"]},\"then\":{\"required\":[\"b\"]}}")
        #expect(throws: ConnectedActionPlanningError.invalidProposal) {
            try ConnectedActionPlanner.validate(arguments: [:], schema: unsupported)
        }
        let planner = ConnectedActionPlanner(generator: { _ in "{\"arguments\":{},\"tool\":\"SEND_MESSAGE\"}" })
        let selected = try tool()
        await #expect(throws: ConnectedActionPlanningError.invalidProposal) {
            try await planner.propose(intention: "Prepare it", tool: selected)
        }
    }

    @Test("A canceled preparation cannot return a late proposal")
    func cancellation() async throws {
        let selected = try tool()
        let operation = Task { @MainActor in
            let planner = ConnectedActionPlanner(generator: { _ in
                try await Task.sleep(for: .seconds(60)); return "{}"
            })
            return try await planner.propose(intention: "Prepare it", tool: selected)
        }
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
    }

    private func tool() throws -> ComposioTool {
        ComposioTool(slug: "EXAMPLE_CREATE_ITEM", name: "Create item", description: "Prepare a harmless test item",
            inputSchema: try schema("""
            {"type":"object","properties":{
                "recipient":{"type":"string","minLength":1},
                "details":{"type":"object","properties":{"title":{"type":"string","minLength":1},"minutes":{"type":"integer","minimum":1,"maximum":60}},"required":["title","minutes"]},
                "labels":{"type":"array","maxItems":3,"items":{"type":"string","enum":["work","personal"]}}
            },"required":["recipient","details"],"additionalProperties":false}
            """))
    }

    private func schema(_ json: String) throws -> ComposioJSONValue {
        .object(try ComposioJSONValue.parseObject(json))
    }
}
