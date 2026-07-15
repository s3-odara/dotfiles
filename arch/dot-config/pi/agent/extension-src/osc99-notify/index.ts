import type { ExtensionAPI } from "../types.ts";

type EventType = "session-idle";

interface NotificationBodyInput {
  eventType: EventType | string;
  message?: unknown;
  project?: unknown;
}

interface Osc99NotificationInput {
  title: string;
  body: string;
  layers?: number;
  idPrefix?: string;
}

type NotificationContext = { cwd?: string } | undefined;

const EVENT_MESSAGES: Record<EventType, string> = {
  "session-idle": "session idle",
};

let nextNotificationID = 0;

export function encodeBase64(value: string): string {
  return Buffer.from(value, "utf8").toString("base64");
}

export function wrapForTmux(sequence: string): string {
  return `\x1bPtmux;${sequence.replaceAll("\x1b", "\x1b\x1b")}\x1b\\`;
}

export function wrapForTmuxLayers(sequence: string, layers: number): string {
  let wrapped = sequence;
  for (let index = 0; index < layers; index += 1) wrapped = wrapForTmux(wrapped);
  return wrapped;
}

export function tmuxWrapLayers(env: Record<string, string | undefined> = process.env): number {
  const configured = env.PI_CODING_KIT_OSC99_TMUX_LAYERS;
  if (configured !== undefined) {
    const parsed = Number.parseInt(configured, 10);
    return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
  }
  return env.TMUX ? 2 : 0;
}

export function formatNotificationBody({ eventType, message, project }: NotificationBodyInput): string {
  const defaultMessage = Object.hasOwn(EVENT_MESSAGES, eventType) ? EVENT_MESSAGES[eventType as EventType] : "notification";
  const shortMessage = String(message ?? defaultMessage).replace(/\s+/g, " ").trim().slice(0, 120);
  const projectID = String(project ?? process.cwd()).split(/[\\/]/).filter(Boolean).at(-1) || String(project ?? process.cwd());
  return `${eventType}: ${shortMessage} (${projectID})`;
}

export function formatOsc99Sequence(metadata: string, payload: string): string {
  return `\x1b]99;${metadata};${encodeBase64(payload)}\x1b\\`;
}

export function createOsc99Notification({ title, body, layers = tmuxWrapLayers(), idPrefix = "pi" }: Osc99NotificationInput): string {
  const id = `${idPrefix}-${Date.now().toString(36)}-${(nextNotificationID += 1).toString(36)}`;
  return [
    wrapForTmuxLayers(formatOsc99Sequence(`i=${id}:d=0:e=1`, title), layers),
    wrapForTmuxLayers(formatOsc99Sequence(`i=${id}:p=body:e=1`, body), layers),
  ].join("");
}

function notify(eventType: EventType, message: string, ctx: NotificationContext): void {
  const project = ctx?.cwd ?? process.cwd();
  const body = formatNotificationBody({ eventType, message, project });
  const title = `pi: ${eventType}`;
  process.stdout.write(createOsc99Notification({ title, body, idPrefix: "pi-coding-kit" }));
}

export function registerOsc99Notify(pi: ExtensionAPI): void {
  if (typeof pi?.on !== "function") {
    console.warn("pi-coding-kit: OSC99 notifications disabled because pi.on is unavailable");
    return;
  }

  pi.on("agent_end", (_event: unknown, ctx: NotificationContext) => {
    notify("session-idle", EVENT_MESSAGES["session-idle"], ctx);
  });
}
