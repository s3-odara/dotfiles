import type { ExtensionAPI } from "../extension-src/types.ts";
import { registerOsc99Notify } from "../extension-src/osc99-notify/index.ts";
import { registerWebfetchTool } from "../extension-src/webfetch/index.ts";
import registerSkillTmuxRunner from "../extension-src/skill-tmux-runner.ts";

export default function piCodingKit(pi: ExtensionAPI): void {
  registerOsc99Notify(pi);
  registerWebfetchTool(pi);
  registerSkillTmuxRunner(pi);
}
