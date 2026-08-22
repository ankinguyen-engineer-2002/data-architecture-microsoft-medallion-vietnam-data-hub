import type { ResourceReference } from "../contracts/types.js";

export interface McpResourceLink {
  type: "resource_link";
  uri: string;
  name: string;
  description: string;
  mimeType: ResourceReference["mimeType"];
  annotations: {
    audience: ["assistant"];
    priority: number;
  };
}

/**
 * Adapter shape for an MCP tool response. The tool returns a pointer first;
 * the user-scoped resource is read only if the client needs the detail.
 */
export function toMcpResourceLink(reference: ResourceReference): McpResourceLink {
  return {
    type: "resource_link",
    uri: reference.uri,
    name: reference.name,
    description: reference.description,
    mimeType: reference.mimeType,
    annotations: {
      audience: ["assistant"],
      priority: 0.8,
    },
  };
}
