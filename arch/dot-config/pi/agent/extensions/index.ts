import type { ExtensionAPI } from "../extension-src/types.ts";
import { registerOsc99Notify } from "../extension-src/osc99-notify/index.ts";
import { registerWebfetchTool } from "../extension-src/webfetch/index.ts";
import registerSkillTmuxAutoRunner from "../extension-src/skill-tmux/auto.ts";
import registerSkillTmuxManualRunner from "../extension-src/skill-tmux/manual.ts";

export default function piCodingKit(pi: ExtensionAPI): void {
  registerOsc99Notify(pi);
  registerWebfetchTool(pi);
  registerSkillTmuxManualRunner(pi);
  registerSkillTmuxAutoRunner(pi);
}
