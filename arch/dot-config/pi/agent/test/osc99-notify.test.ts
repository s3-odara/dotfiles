import assert from "node:assert/strict";
import {
  createOsc99Notification,
  encodeBase64,
  formatNotificationBody,
  formatOsc99Sequence,
  tmuxWrapLayers,
  wrapForTmuxLayers,
} from "../extension-src/osc99-notify/index.ts";

assert.equal(encodeBase64("pi ✓"), Buffer.from("pi ✓", "utf8").toString("base64"));

const sequence = formatOsc99Sequence("i=test:e=1", "Title");
assert.equal(sequence, `\x1b]99;i=test:e=1;${Buffer.from("Title").toString("base64")}\x1b\\`);

const wrapped = wrapForTmuxLayers(sequence, 2);
assert.match(wrapped, /^\x1bPtmux;/);
assert.match(wrapped, /\x1b\\$/);
assert.ok(wrapped.includes("\x1b\x1bPtmux;"), "second tmux layer escapes the inner passthrough");

assert.equal(tmuxWrapLayers({}), 0);
assert.equal(tmuxWrapLayers({ TMUX: "/tmp/tmux" }), 2);
assert.equal(tmuxWrapLayers({ TMUX: "/tmp/tmux", PI_CODING_KIT_OSC99_TMUX_LAYERS: "1" }), 1);

assert.equal(
  formatNotificationBody({ eventType: "assistant-complete", message: "done", project: "/work/project" }),
  "assistant-complete: done (project)",
);

const notification = createOsc99Notification({ title: "pi: test", body: "body", layers: 0, idPrefix: "test" });
assert.match(notification, /\x1b\]99;i=test-/);
assert.match(notification, /:p=body:e=1;/);

console.log("osc99 notify tests passed");
