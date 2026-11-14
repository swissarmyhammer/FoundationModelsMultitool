// `MCPToolContent` — the content blocks of one MCP tool result, for the host.
//
// The request (TestudoApp ^v30ggjj): the model reads an MCP tool result as
// text (`ToolContentRenderer`). The renderer changes an image block to
// `[image: <mimeType>]`, thus the image data was lost before the host got
// the result. The host (for example FoundationModelsACPAgent) must show the
// image to the user.
//
// **The lane.** A verb of the MCP grammar runs as a plain `Tool`, often
// inside a `runCode` snippet, thus the host never holds its return value. The
// host gets what a tool shows through the display lane of the ambient
// `ToolContext` (`ToolDisplayEvent`). Thus `MCPTool` posts the blocks as one
// display chunk. The chunk is a `ToolDisplayContent.json`: the lane says that
// the tool owns the shape of a JSON part. This type owns that shape, and
// `init(display:)` reads it.
//
// **The shape.** One JSON object with one key, `mcpToolContent`. Its value
// holds `content`, the blocks in the MCP wire shape, and `isError`. The one
// key keeps the JSON part of another tool apart from this one.

import Foundation
import FoundationModelsExtras
import MCP

/// The ordered content blocks of one MCP tool result, with their full data:
/// text, image and audio data with the mime type, resources and resource
/// links.
///
/// The model reads a text form of the result, in which an image is only a
/// placeholder. Under an ambient `ToolContext`, an MCP verb posts this value
/// as one display chunk (``display``) when the result has a block that is not
/// text. A host reads the chunk of each display event with
/// ``init(display:)``:
///
/// ```swift
/// if case .contentChunk(let part) = event.kind, let result = MCPToolContent(display: part) {
///     for case .image(let data, let mimeType, _, _) in result.content {
///         // Show the base64 `data` of type `mimeType`.
///     }
/// }
/// ```
public struct MCPToolContent: Sendable, Hashable, Codable {
    /// The content blocks of the result, in the order that the server gave.
    public var content: [MCP.Tool.Content]

    /// Whether the server marked the result as an error.
    public var isError: Bool

    /// Creates the content of one result.
    ///
    /// - Parameters:
    ///   - content: the content blocks, in order.
    ///   - isError: whether the server marked the result as an error.
    public init(content: [MCP.Tool.Content], isError: Bool) {
        self.content = content
        self.isError = isError
    }

    /// The one key of the JSON object of the display part.
    private struct Envelope: Codable {
        /// The content of the result.
        let mcpToolContent: MCPToolContent
    }

    /// The display part of this content: a JSON part in the shape that this
    /// type owns.
    public var display: ToolDisplayContent {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Each block of the MCP wire shape encodes, thus the encode does not
        // fail.
        let data = (try? encoder.encode(Envelope(mcpToolContent: self))) ?? Data()
        return .json(String(decoding: data, as: UTF8.self))
    }

    /// Reads the content of an MCP tool result from a display part.
    ///
    /// - Parameter display: the display part of a display event.
    /// - Returns: `nil` when the part is not the ``display`` part of an MCP
    ///   tool result, for example the part of another tool.
    public init?(display: ToolDisplayContent) {
        guard case .json(let text) = display,
            let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(text.utf8))
        else { return nil }
        self = envelope.mcpToolContent
    }

    /// The content of `result`, or `nil` when each block is text. The model
    /// text holds each text block, thus the host needs no chunk for it.
    ///
    /// - Parameter result: the `tools/call` result.
    /// - Returns: the content of the result, or `nil`.
    static func displayed(from result: CallTool.Result) -> MCPToolContent? {
        let hasOtherBlock = result.content.contains { block in
            if case .text = block { return false }
            return true
        }
        guard hasOtherBlock else { return nil }
        return MCPToolContent(content: result.content, isError: result.isError ?? false)
    }
}
