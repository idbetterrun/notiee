import Foundation

final class AgentToolRegistry: @unchecked Sendable {
    private let tools: [String: any AgentTool]

    init(tools: [any AgentTool]) {
        var dict: [String: any AgentTool] = [:]
        for tool in tools {
            dict[tool.name] = tool
        }
        self.tools = dict
    }

    func get(_ name: String) -> (any AgentTool)? {
        tools[name]
    }

    func allTools(for trustLevel: AgentTrustLevel) -> [any AgentTool] {
        tools.values.filter { $0.permission.isAllowed(by: trustLevel) }
    }

    func openAITools(for trustLevel: AgentTrustLevel) -> [[String: Any]] {
        allTools(for: trustLevel).map { tool in
            let funcDef: [String: Any] = [
                "name": tool.name,
                "description": tool.description,
                "parameters": Self.buildJSONSchema(from: tool.parametersSchema)
            ]
            return ["type": "function", "function": funcDef]
        }
    }

    func anthropicTools(for trustLevel: AgentTrustLevel) -> [[String: Any]] {
        allTools(for: trustLevel).map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": Self.buildJSONSchema(from: tool.parametersSchema)
            ]
        }
    }

    static func buildJSONSchema(from schema: AgentToolParametersSchema) -> [String: Any] {
        var props: [String: Any] = [:]
        for (key, prop) in schema.properties {
            var p: [String: Any] = ["type": prop.type, "description": prop.description]
            if let ev = prop.enumValues { p["enum"] = ev }
            if let items = prop.items {
                p["items"] = ["type": items.type]
            }
            props[key] = p
        }
        return [
            "type": "object",
            "properties": props,
            "required": schema.required
        ]
    }
}
