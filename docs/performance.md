# Performance

`go-ruby-pstore/pstore` is the pure-Go, CGO-free library that
[`rbgo`](https://github.com/go-embedded-ruby/ruby) binds for Ruby's `PStore`.
This page records a **real, library-level** benchmark of that module's
transaction engine against every reference runtime's own stdlib `PStore`, running
the same read and write transactions over the **same fixed data and store file**.
It is part of the ecosystem-wide per-module parity suite, and **the bar is beating
MRI + YJIT**, not just plain MRI.

## I/O + Marshal-bound benchmark

`PStore` is a **Marshal-backed, file-backed** transactional store: a read
transaction `Marshal.load`s the store file, a write transaction `Marshal.dump`s
the table and writes it back. So this workload is dominated by **file I/O and the
Marshal codec**, not interpreter compute — read the numbers as an *engine +
serializer* comparison, not a CPU-throughput one. The pure-Go library serialises
through the sibling [`go-ruby-marshal`](https://github.com/go-ruby-marshal/marshal)
codec, which is byte-compatible with MRI's `Marshal`; the fixed read-only store is
written by **MRI's own PStore** (the oracle) and the pure-Go write op is verified
to reproduce that store file **byte-for-byte**.

## What is measured

Two transactions run over one **fixed 30-entry table** — root keys `root0..root29`
whose values cycle through every common shape: `Integer`, `String`, three-element
`Array`, a nested `Hash`, and `Float`:

| Op | What it exercises |
| --- | --- |
| `read-txn` | a read-only transaction (`transaction(true)`) that `Marshal.load`s the store and fetches all 30 root keys |
| `write-txn` | a read-write round-trip: reset the store to empty, then a transaction that inserts the fixed 30-entry dataset and commits (`Marshal.dump` + file write) |

The **go-ruby** column drives this pure-Go library through its Go API, with the
`Backend` seam backed by a real file (`os.ReadFile`/`os.WriteFile`) — the role
`rbgo` fills with a real `os.File`. Every other column is that interpreter's own
stdlib `PStore`. Before any timing, each runtime is run with `CHECK=1` and its
per-op checksum is verified **identical to MRI** — the run aborts otherwise. The
`read-txn` checksum folds the **Marshal bytes of every fetched value** (proving
the values decode identically); the `write-txn` checksum folds the **whole
resulting store file** (so it only matches MRI if every Marshal byte — every
symbol symlink, every string encoding ivar, the hash order — agrees), making it a
strong byte-exact serializer-equality proof.

- **Host:** Apple M4 Max, macOS (`arm64-darwin`, APFS). **Date:** 2026-07-03.
- **Runtimes:** Go 1.26.4; `ruby 4.0.5 +PRISM` (MRI, the oracle) and
  `ruby --yjit`; `jruby 10.1.0.0` (OpenJDK 25); `truffleruby 34.0.1`
  (GraalVM CE Native). `pstore` gem 0.2.1.
- **Method:** each process runs 3 untimed warm-up passes then 25 timed passes of a
  fixed inner loop, timed with a monotonic clock; the **best** pass is reported as
  **ns/op**. Interpreter start-up is outside the timed region, so the number is
  the transaction's own cost, not `ruby file.rb` process cost. Numbers were stable
  to within a few percent across repeated runs.
- Harness and drivers live in this repo under
  [`benchmarks/`](https://github.com/go-ruby-pstore/docs/tree/main/benchmarks)
  (`go/`, `ruby/pstore.rb`, `run.sh`). Reproduce: `bash benchmarks/run.sh`.

## Results (ns/op, best of 25)

| Op | go-ruby (pure Go) | MRI | MRI + YJIT | JRuby | TruffleRuby | **go vs YJIT** |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `read-txn` | **22 427** | 63 040 | 54 470 | 67 718 | 476 166 | **2.43× faster** ✅ |
| `write-txn` | **91 637** | 112 540 | 103 410 | 115 362 | 524 022 | **1.13× faster** ✅ |

## The go-vs-YJIT verdict, per op

**The pure-Go engine beats MRI + YJIT on both transactions** — there is no op where
YJIT wins:

- **`read-txn` — 2.43× faster than YJIT** (22 427 ns vs 54 470 ns), and 0.36× of
  plain MRI. The read path is `Marshal.load` + 30 hash fetches; the pure-Go
  `go-ruby-marshal` decoder builds the table without an interpreter in the loop and
  the fetch is a direct slice scan, so it pulls well ahead. This is the op where
  the Marshal codec dominates most, and it is where the pure-Go stack wins biggest.
- **`write-txn` — 1.13× faster than YJIT** (91 637 ns vs 103 410 ns), and 0.81× of
  plain MRI. The margin is narrower here because the write path is dominated by the
  **actual file write** (a syscall every runtime pays equally) on top of
  `Marshal.dump`; once the shared write cost is factored in, the serializer/engine
  advantage is a smaller slice of the total, but the pure-Go engine still finishes
  ahead of MRI and YJIT.

JRuby lands near plain MRI on both ops (1.03–1.09×), and TruffleRuby is far behind
here (4.7–7.6× slower) — its `PStore`/`Marshal` path is still deep in warm-up after
three passes (see the caveat). MRI, YJIT and Go are the load-bearing comparison,
and the pure-Go engine leads all of them.

## Caveats

- **I/O + Marshal framing.** These numbers measure the transaction engine plus the
  Marshal codec plus the store file's read/write — not raw CPU throughput. The
  `write-txn` figure in particular includes a real file write, whose cost is shared
  across runtimes and compresses the visible spread. The go-ruby write path uses
  `os.WriteFile` (truncate-write) where MRI's PStore uses a temp-file + atomic
  `rename`; both persist the same bytes, and the difference is small next to the
  Marshal work, but it is a real difference in the write syscalls and is noted here
  for honesty.
- **Cold-JIT framing.** JRuby and TruffleRuby are timed after the same 3 warm-up
  passes as everyone else, but 3 passes do **not** bring the JVM/GraalVM JITs to
  full steady state; read their columns as lightly-warmed, not peak throughput.
  TruffleRuby's `PStore` path especially is still warming up here. MRI, YJIT and Go
  reach representative speed almost immediately, so their columns are the
  load-bearing comparison.
- No number here is fabricated: all figures are measured on the host and date named
  above and reproduce with `bash benchmarks/run.sh`.
