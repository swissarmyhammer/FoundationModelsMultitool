@testable import FoundationModelsMultitool
import Testing

/// ``MultitoolTelemetry`` holds each telemetry name of the library target. Each
/// name starts with the module name, and no two names are the same.
///
/// A host application builds its dashboards, queries and alerts on these
/// names. A name that is not unique mixes two facts in one series, and a name
/// without the module prefix mixes the library with the host.
@Suite("MultitoolTelemetry: the telemetry vocabulary of the library target")
struct MultitoolTelemetryTests {
    /// The text that each name of the vocabulary must start with.
    private static let modulePrefix = "FoundationModelsMultitool."

    /// Each span name of the vocabulary.
    private static let spanNames = MultitoolTelemetry.SpanName.allCases.map(\.rawValue)

    /// Each attribute key of the vocabulary.
    private static let attributeKeys = MultitoolTelemetry.AttributeKey.allCases.map(\.rawValue)

    /// Each metric name of the vocabulary.
    private static let metricNames = MultitoolTelemetry.MetricName.allCases.map(\.rawValue)

    /// Each log metadata key of the vocabulary.
    private static let logMetadataKeys = MultitoolTelemetry.LogMetadataKey.allCases.map(\.rawValue)

    /// Each name of the vocabulary: the log label, the span names, the
    /// attribute keys, the metric names and the log metadata keys.
    private static let allNames =
        [MultitoolTelemetry.logLabel] + spanNames + attributeKeys + metricNames + logMetadataKeys

    @Test("each name starts with the module name")
    func eachNameStartsWithTheModuleName() {
        let unprefixed = Self.allNames.filter { !$0.hasPrefix(Self.modulePrefix) }
        #expect(unprefixed.isEmpty, "These names do not start with \(Self.modulePrefix): \(unprefixed)")
    }

    @Test("each name has text after the module name")
    func eachNameHasTextAfterTheModuleName() {
        let bare = Self.allNames.filter { $0 == Self.modulePrefix }
        #expect(bare.isEmpty, "These names hold the module prefix and nothing more: \(bare)")
    }

    @Test("no two names are the same")
    func noTwoNamesAreTheSame() {
        let counts = Dictionary(Self.allNames.map { ($0, 1) }, uniquingKeysWith: +)
        let repeated = counts.filter { $0.value > 1 }.keys.sorted()
        #expect(repeated.isEmpty, "These names occur more than one time: \(repeated)")
    }

    @Test("no two log messages are the same, so that one message finds the records of one event")
    func noTwoLogMessagesAreTheSame() {
        let messages = MultitoolTelemetry.LogMessage.allCases.map(\.rawValue)
        #expect(Set(messages).count == messages.count, "A log message occurs more than one time: \(messages)")
    }

    @Test("each metric has dimensions, and each dimension key is an attribute key of the same fact")
    func eachMetricHasItsDimensions() {
        let expected: [MultitoolTelemetry.MetricName: [MultitoolTelemetry.AttributeKey]] = [
            .toolCalls: [.toolName, .outcome],
            .toolDuration: [.toolName, .outcome],
            .mcpServerErrors: [.serverName, .errorKind],
            .mcpServerRestarts: [.serverName],
            .interpreterRunDuration: [.outcome],
        ]
        for metric in MultitoolTelemetry.MetricName.allCases {
            #expect(metric.dimensionKeys == expected[metric], "The dimensions of \(metric.rawValue) are not correct.")
        }
    }
}
