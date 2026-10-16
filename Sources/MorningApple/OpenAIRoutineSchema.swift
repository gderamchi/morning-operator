import Foundation
import MorningCore

/// The remote model proposes the same values as the local model. Citation and
/// preference validation remains in LearningBatchRunner and the app-owned assembler.
enum OpenAIRoutineSchema {
    static func make(unitIDs: [UUID]? = nil) -> ComposioJSONValue {
        func string(_ values: [String]? = nil) -> ComposioJSONValue {
            var properties: [String: ComposioJSONValue] = ["type": .string("string")]
            if let values { properties["enum"] = .array(values.map { .string($0) }) }
            return .object(properties)
        }
        func object(_ properties: [String: ComposioJSONValue]) -> ComposioJSONValue {
            .object(["type": .string("object"), "properties": .object(properties),
                     "required": .array(properties.keys.sorted().map { .string($0) }),
                     "additionalProperties": .bool(false)])
        }
        var step: [String: ComposioJSONValue] = [
            "title": string(), "detail": string(), "kind": string(StepKind.allCases.map(\.rawValue)),
            "durationMinutes": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(60)])
        ]
        if let unitIDs {
            step["citations"] = .object(["type": .string("array"), "minItems": .number(1), "maxItems": .number(5),
                "items": object(["unitID": string(unitIDs.map(\.uuidString)), "quote": string()])])
        } else {
            step["evidenceQuote"] = string()
            step["evidenceKind"] = string(["userReportedActivity", "visibleTaskContent"])
        }
        return object([
            "outcome": string(["insufficientEvidence", "supportedActivities"]),
            "steps": .object(["type": .string("array"), "maxItems": .number(4), "items": object(step)])
        ])
    }
}
