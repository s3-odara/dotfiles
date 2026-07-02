import type { ExtensionAPI } from "./types.ts";
import { registerOsc99Notify } from "./osc99-notify/index.ts";
import { registerWebfetchTool } from "./webfetch/index.ts";

export default function piCodingKit(pi: ExtensionAPI): void {
  // Register only APIs confirmed in the local Pi 0.80.2 docs. Each registrar
  // checks for the method it needs so the package remains loadable in older or
  // adapter-style environments instead of inventing fallback behavior.
  registerOsc99Notify(pi);
  registerWebfetchTool(pi);
}
