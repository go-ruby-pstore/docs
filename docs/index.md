# go-ruby-pstore documentation

**Ruby's PStore transaction engine in pure Go — MRI-compatible, no cgo.**

`go-ruby-pstore/pstore` is a faithful, pure-Go (zero cgo) reimplementation of the
transaction engine at the heart of Ruby's `PStore` — MRI 4.0.5's transactional,
`Marshal`-backed object store (the `pstore-0.2.1` gem). The module path is
`github.com/go-ruby-pstore/pstore`.

It runs the load → transaction-body → commit/abort state machine over a Hash
"table" and serialises that table with
[go-ruby-marshal](https://github.com/go-ruby-marshal/marshal), so the on-disk bytes
are **byte-compatible with a file written by MRI's `PStore`**: a real
`ruby -rpstore` file loads here, and a file this engine commits is read back
unchanged by MRI. It was **extracted from rbgo's internals into a reusable
standalone library**: the module is standalone and importable by any Go program, and
it is the backend bound into
[go-embedded-ruby](https://github.com/go-embedded-ruby/ruby) by `rbgo` as a native
module — just like [go-ruby-regexp](https://github.com/go-ruby-regexp) and
[go-ruby-erb](https://github.com/go-ruby-erb). The dependency runs the other way:
this library has **no dependency on the Ruby runtime**.

!!! success "Status: complete — MRI byte-exact on disk"
    PStore's transaction semantics: **commit on normal exit** (skipping the write when nothing changed, MRI's checksum/size guard), **`Commit` / `Abort` early exit**, **read-only transactions** (writes raise `PStore::Error`), the full **error taxonomy** with MRI's exact messages, and the **on-disk Marshal format** via go-ruby-marshal — so files round-trip both directions with MRI's `PStore`. Validated at 100% coverage, `gofmt` + `go vet` clean, CI green across the six 64-bit Go targets and three OSes.

## What it is — and isn't

The transactional core — load the table, run the body, commit on normal exit
(skipping the write when nothing changed), abort or commit early, forbid writes in a
read-only transaction, refuse a nested transaction, raise outside one — is fully
deterministic and needs **no interpreter**, so it lives here as pure Go over the
Marshal codec. The *file* half — opening the store file (`O_CREAT`),
`flock(LOCK_SH/LOCK_EX)`, the atomic-rename / rewind-truncate save strategies — is
the host's job, injected as a two-method `Backend`. rbgo wires the real `os.File` +
`syscall.Flock`; tests use an in-memory backend, so the whole suite is deterministic
and Ruby-free.

## Quick taste

```go
store := pstore.New(backend)

// A read-write transaction: writes commit on normal return.
store.Transaction(false, func(t *pstore.Tx) error {
	t.Set(marshal.Symbol("foo"), marshal.NewInt(0))
	return nil // commit
})

// A read-only transaction: a write here would raise PStore::Error.
store.Transaction(true, func(t *pstore.Tx) error {
	v, ok, _ := t.Get(marshal.Symbol("foo"))
	_ = v; _ = ok
	return nil
})
```

## Repositories

| Repo | What it is |
| --- | --- |
| [`pstore`](https://github.com/go-ruby-pstore/pstore) | the library — Ruby's PStore transaction engine in pure Go |
| [`docs`](https://github.com/go-ruby-pstore/docs) | this documentation site (MkDocs Material, versioned with mike) |
| [`go-ruby-pstore.github.io`](https://github.com/go-ruby-pstore/go-ruby-pstore.github.io) | the organization landing page (Hugo) |
| [`brand`](https://github.com/go-ruby-pstore/brand) | logo and brand assets |

## Principles

- **Pure Go, `CGO_ENABLED=0`** — trivial cross-compilation, a single static
  binary, no C toolchain.
- **MRI byte-exact on disk.** The table is `Marshal.dump` / `load`ed through
  go-ruby-marshal, so a committed file is byte-compatible with one written by MRI's
  `PStore` — validated by a differential oracle against the `ruby` binary.
- **The file seam is injected.** Locking and the save strategy are the host's job,
  supplied through a two-method `Backend`: rbgo wires the real `os.File` +
  `syscall.Flock`, tests use an in-memory backend.
- **Standalone & reusable.** Extracted from rbgo's internals; no dependency on the
  Ruby runtime — the dependency runs the other way.
- **100% test coverage** is the target, enforced as a CI gate, across 6 arches and
  3 OSes.

## Where to go next

- [Why pure Go](why.md) — why this slice of Ruby is deterministic enough to live
  as a standalone, interpreter-independent Go library.
- [Usage & API](api.md) — the public surface and worked examples.
- [Roadmap](roadmap.md) — what is done and what is downstream by design.

Source lives at [github.com/go-ruby-pstore/pstore](https://github.com/go-ruby-pstore/pstore).
