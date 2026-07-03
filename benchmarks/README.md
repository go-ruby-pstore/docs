<!-- SPDX-License-Identifier: BSD-3-Clause -->
# `go-ruby-pstore` library-level benchmark harness

Reproducible, cross-runtime benchmark of the **pure-Go `go-ruby-pstore` library**
against the reference Ruby runtimes (MRI, MRI + YJIT, JRuby, TruffleRuby). It runs
the same read and write transactions over the **same fixed data and store file**
every runtime uses, so the numbers answer: *is the pure-Go transaction + Marshal
engine as fast as the reference runtime's own `PStore`?*

## I/O + Marshal-bound benchmark

`PStore` is a **Marshal-backed, file-backed** transactional store: a read
transaction `Marshal.load`s the store file, a write transaction `Marshal.dump`s
the table back and writes it. So this workload is dominated by **file I/O and the
Marshal codec**, not interpreter compute. The pure-Go library serialises through
the sibling [`go-ruby-marshal`](https://github.com/go-ruby-marshal/marshal) codec,
which is byte-compatible with MRI's `Marshal`; the harness writes the fixed
read-only store with **MRI's own PStore** (the oracle) and checks the pure-Go
write op reproduces the store file **byte-for-byte**.

## Layout

- `go/`             — self-contained Go driver; `go.mod` pins the published library
  by pseudo-version. The `Backend` seam is a real file (`os.ReadFile`/`os.WriteFile`).
- `ruby/pstore.rb`  — the equivalent workload; also has a `setup` mode that writes
  the fixed read-only store with MRI's PStore. `ruby/_harness.rb` is the shared timer.
- `run.sh`          — writes the fixed store, verifies every runtime's per-op
  checksum equals MRI, then prints one Markdown table per sub-benchmark.

## Ops

- `read-txn`  — a read-only transaction (`transaction(true)`) that Marshal-loads
  the store and fetches all 30 root keys.
- `write-txn` — a read-write round-trip: reset the store to empty, then a
  transaction that inserts the fixed 30-entry dataset and commits (Marshal-dump +
  file write).

## Run

```sh
bash benchmarks/run.sh
```

Environment knobs: `OUTER` (timed passes, default 25), `WARM` (untimed warm-up
passes, default 3), and `RUBY`/`JRUBY`/`TRUFFLERUBY` to select runtime binaries.

## Method

Each process runs `WARM` untimed passes (to let the JVM/GraalVM JITs warm up),
then `OUTER` timed passes of a fixed inner loop, timed with a monotonic clock; the
**best** pass is reported as **ns/op**. Interpreter start-up is outside the timed
region. Before any timing, each runtime is run with `CHECK=1` and its per-op
checksum (folded Marshal bytes of the fetched values, and of the written store
file) is required to equal MRI's, so the comparison is the same observable
operation, apples-to-apples. Results are published, dated, in
`../docs/performance.md`.
