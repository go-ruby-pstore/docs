# Performance

`go-ruby-pstore/pstore` is the pure-Go library that
[`rbgo`](https://github.com/go-embedded-ruby/ruby) binds for Ruby's `PStore`. This
page records the **methodology** of the comparative benchmark of that module against
the reference Ruby runtimes, part of the ecosystem-wide per-module parity suite.

!!! note "Methodology only"
    No measured numbers are published here yet. This page documents *how* the
    benchmark is run so the result is reproducible and apples-to-apples; the
    measured table will be added once the run is recorded, the same way it is for
    the sibling modules — never fabricated.

## What is measured

The **same** Ruby script — opening a `PStore`, running a read-write transaction that
populates a representative table, committing, then a read-only transaction that reads
it back — is run under every runtime. `rbgo`'s number reflects **this pure-Go library
running the transaction engine over the go-ruby-marshal codec** (the file/locking
layer is the host's); every other column is that interpreter's own `pstore` stdlib.
So the comparison is the **Ruby-visible operation**, apples-to-apples across
interpreters. The script prints a deterministic checksum, and — because the on-disk
format is byte-compatible — the committed file is checked **byte-identical to MRI's
`PStore`** before timing.

!!! note "Isolating the engine from the disk"
    To compare the transaction engine and Marshal serialisation rather than disk
    jitter, the harness uses a fixed store path on a warm filesystem (or a tmpfs
    where available) and reports best-of-N, so I/O variance is suppressed and what is
    measured is the engine's own work.

## How it is run

- **Method:** best-of-N wall time (best, not mean, to suppress scheduler and I/O
  noise); single-shot processes, no warm-up beyond the script's own loop.
- **Runtimes:** `ruby` (MRI, the oracle) and `ruby --yjit`; `jruby` (on the JVM);
  `truffleruby` (GraalVM). JVM/Graal rows are timed **cold, single-shot**, so they
  carry runtime startup on every run — read them as one-shot `ruby file.rb` costs,
  the same way `rbgo` and MRI are measured, not as steady-state JIT numbers.
- The benchmark script and harness live in rbgo's repo under
  [`bench/modules/`](https://github.com/go-embedded-ruby/ruby/tree/main/bench/modules)
  (`pstore.rb` + `run.sh`). Reproduce with the same
  `RBGO=./rbgo TRUFFLE=truffleruby bash bench/modules/run.sh N` invocation used
  across the ecosystem.

## Honest framing

Rows that complete in well under ~200 ms carry the most relative noise; their ratios
should be read as order-of-magnitude. Any numbers added here will be real measured
numbers from a dated run — nothing cherry-picked.
