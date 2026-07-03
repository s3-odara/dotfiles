// Minimal compatibility shim for Pi's extension API.
// The local Pi 0.80.2 docs confirm `on` and `registerTool`; keeping this tiny
// avoids pinning a moving SDK package just to type the small surface used here.
export interface ExtensionAPI {
  on?: (eventName: string, handler: (...args: unknown[]) => unknown) => unknown;
  registerTool?: (definition: unknown) => unknown;
  readonly [capability: string]: unknown;
}
