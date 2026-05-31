import type { Plugin } from "@opencode-ai/plugin"

const NOTIFICATION_EVENTS = new Set([
  "question.asked",
  "permission.asked",
  "session.idle",
  "session.error",
])

const EVENT_MESSAGES: Record<string, { title: string; body: string }> = {
  "question.asked": {
    title: "opencode: Question",
    body: "Input is needed to continue.",
  },
  "permission.asked": {
    title: "opencode: Permission",
    body: "Permission approval is needed.",
  },
  "session.idle": {
    title: "opencode: Complete",
    body: "Session is idle; work appears complete.",
  },
  "session.error": {
    title: "opencode: Error",
    body: "Session reported an error.",
  },
}

const textEncoder = new TextEncoder()
let nextNotificationID = 0

function encodeBase64(value: string) {
  const bytes = textEncoder.encode(value)
  let binary = ""
  for (const byte of bytes) binary += String.fromCharCode(byte)

  const btoa = (globalThis as { btoa?: (input: string) => string }).btoa
  if (btoa) return btoa(binary)

  const buffer = (
    globalThis as {
      Buffer?: {
        from(input: Uint8Array): { toString(encoding: "base64"): string }
      }
    }
  ).Buffer
  if (buffer) return buffer.from(bytes).toString("base64")

  throw new Error("No Base64 encoder is available for OSC99 notifications")
}

function wrapForTmux(sequence: string) {
  return `\x1bPtmux;${sequence.replaceAll("\x1b", "\x1b\x1b")}\x1b\\`
}

function wrapForTmuxLayers(sequence: string, layers: number) {
  let wrapped = sequence
  for (let i = 0; i < layers; i++) wrapped = wrapForTmux(wrapped)
  return wrapped
}

function writeOSC99(metadata: string, payload: string) {
  const process = (
    globalThis as {
      process?: {
        stdout?: { write(chunk: string): unknown }
      }
    }
  ).process

  const sequence = `\x1b]99;${metadata};${encodeBase64(payload)}\x1b\\`
  process?.stdout?.write(wrapForTmuxLayers(sequence, 2))
}

function notify(title: string, body: string) {
  const id = `opencode-${Date.now().toString(36)}-${(nextNotificationID++).toString(36)}`

  writeOSC99(`i=${id}:d=0:e=1`, title)
  writeOSC99(`i=${id}:p=body:e=1`, body)
}

export default (async () => {
  return {
    event: async ({ event }) => {
      if (!NOTIFICATION_EVENTS.has(event.type)) return

      const message = EVENT_MESSAGES[event.type]
      if (!message) return

      notify(message.title, message.body)
    },
  }
}) satisfies Plugin
