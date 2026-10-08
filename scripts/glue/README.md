# Pinned Zig glue specification

`ZigGlue.roc` is an unmodified copy of the Roc compiler's glue generator at
commit `130536d`, matching `nightly-2026-10-04-130536d`:

https://github.com/roc-lang/roc/blob/130536d/src/glue/src/ZigGlue.roc

Its SHA-256 is `ff18757f6f1f360903bf581720fd1f7348a68d89719ed2a6633df33e3e323733`.
The upstream source is licensed under the MIT license in `LICENSE`.

This nightly archive does not ship glue specifications. Vendoring the matching
source makes regeneration independent of a neighboring Roc checkout and future
upstream changes. It uses the compiler-owned `platform glue`, which supplies
the platform's checked type information, runtime layouts, and ownership rules.

Run `roc scripts/regenerate_glue.roc` from the repository root after changing
`platform/main.roc` or hosted effect signatures. The raw output overwrites
`host-shim/roc_platform_abi.zig`. Do not edit or format that generated file.
`roc scripts/check_all.roc` compares freshly generated output with the checked-in
file, builds both adapters from the fresh output in a temporary workspace, bundles
them, and exercises the managed host through HTTP.
