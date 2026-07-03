# Extension entry points

`index.ts` is the only Pi auto-discovered extension entry point in this directory. Keep implementation modules outside `extensions/` so Pi does not try to load them as independent extensions.

Internal modules live under `../extension-src/`.
