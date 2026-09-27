# Attached-UI microbenchmark

Run from the repository root:

```sh
nvim --clean --headless -l benchmarks/ui.lua > /tmp/terminal-benchmark.json
```

The harness starts an embedded Neovim with a 160 × 50 RPC UI, two terminal tabs,
four panes per tab, rounded borders, and no dimming overlay. Each operation has
10 warmup iterations, followed by 40–100 timed iterations. Timings include
synchronous plugin work and redraw generation. They exclude host terminal
rendering, user input latency, and asynchronous shell/PTTY work.

## Measurement — 2026-09-27

macOS arm64, Neovim `v0.13.0-dev-1738+g521edde`. Three alternating baseline/candidate
runs used the same script; the baseline was an isolated snapshot of `7826021`,
and the candidate added the canvas content/configuration cache. The table reports
the median of three per-run medians, in milliseconds. Individual samples and
per-run p95 values are in [results.json](results.json).

| Operation | Before | After |
| --- | ---: | ---: |
| unchanged canvas | 0.545 | 0.264 |
| matching geometry tab switch | 0.826 | 0.829 |
| four-pane rebuild | 2.606 | 2.132 |
| changing pane geometry | 0.944 | 0.906 |

Unchanged canvas refreshes dropped from 110 buffer writes to zero in every run
(100 timed iterations plus 10 warmups). Their measured median cost roughly
halved. Tab-switch timing was essentially unchanged. Small differences in the
other operations should not be treated as established gains from this sample.

The cache tracks only drawing inputs, with changedtick invalidation for external
buffer edits. Tests cover geometry, border, title, fillchars, screen position,
and buffer recreation. There is no machine-dependent performance pass/fail gate.
