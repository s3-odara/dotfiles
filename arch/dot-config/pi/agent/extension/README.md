# Extension

`index.ts` is the package extension entry point. It registers OSC99 notification handlers and the lightweight `webfetch` tool.

The local Pi 0.80.2 loader accepts this direct `.ts` entry far enough to reach provider API-key selection in a smoke test. The implementation still guards each registrar so startup degrades gracefully if an older adapter lacks `pi.on` or `pi.registerTool`.
