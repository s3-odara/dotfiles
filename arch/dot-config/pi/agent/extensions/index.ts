import type { ExtensionAPI } from "../extension-src/types.ts";
import { registerOsc99Notify } from "../extension-src/osc99-notify/index.ts";
import { registerWebfetchTool } from "../extension-src/webfetch/index.ts";
import registerAgents from "../extension-src/agents/index.ts";

export default function piCodingKit(pi: ExtensionAPI): void {
  registerOsc99Notify(pi);
  registerWebfetchTool(pi);
  registerAgents(pi);
}
