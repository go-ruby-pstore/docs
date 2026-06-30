# Why pure Go

`go-ruby-pstore/pstore` reimplements the transaction engine at the heart of Ruby's
`PStore` in **pure Go, with cgo disabled**. The slice of Ruby it covers — the
load → body → commit/abort state machine over a `Marshal`-serialised table — is
**deterministic and interpreter-independent**: given its inputs and the store
bytes, the result is a pure function of those inputs. That is exactly the part that
can — and should — live as a standalone Go library, separate from the interpreter.

## The transactional core vs. the file seam

PStore's semantics are deterministic: commit on normal exit (skipping the write
when nothing changed), `Commit` / `Abort` early exit, read-only transactions,
refusing a nested transaction, raising outside one, and MRI's exact error messages.
All of that lives here, over the
[go-ruby-marshal](https://github.com/go-ruby-marshal/marshal) codec. The **file**
half — opening the store (`O_CREAT`), `flock(LOCK_SH/LOCK_EX)`, the atomic-rename /
rewind-truncate save strategies — is impure and platform-specific, so it is isolated
behind a two-method `Backend` and injected: rbgo wires the real `os.File` +
`syscall.Flock`, and tests use an in-memory backend, so the whole suite is
deterministic and Ruby-free.

## Marshal-backed, MRI-compatible on disk

Because the table is `Marshal.dump` / `load`ed through go-ruby-marshal — which is
itself MRI byte-exact — a file this engine commits is read back unchanged by MRI's
`PStore`, and a real `ruby -rpstore` file loads here. The on-disk format is not
approximated; it is the same bytes MRI writes.

## Extracted from rbgo, reusable by anyone

This library began life inside
[go-embedded-ruby](https://github.com/go-embedded-ruby/ruby)'s `rbgo`. It has been
**extracted into a reusable standalone library** so that:

- any Go program can import `github.com/go-ruby-pstore/pstore` directly, with no
  Ruby runtime;
- the dependency runs the *other* way — `rbgo` binds this module as a native module
  (the same pattern as [go-ruby-regexp](https://github.com/go-ruby-regexp) and
  [go-ruby-erb](https://github.com/go-ruby-erb)), rather than this module depending
  on the interpreter;
- the behavior is pinned by a **differential oracle** against the system `ruby`,
  round-tripping real `PStore` files both directions, independent of any one
  consumer.

## Why pure Go matters here

Because the library is CGO-free, it:

- cross-compiles to every Go target with no C toolchain, and links into a single
  static binary;
- has **no dependency on the Ruby runtime** — the dependency runs the other way;
- can be differentially tested against the `ruby` binary wherever one is on `PATH`,
  while the cross-arch and Windows lanes (where `ruby` is absent) still validate the
  library itself, since the in-memory backend keeps the whole suite deterministic
  and ruby-free.

See [Usage & API](api.md) for the surface and [Roadmap](roadmap.md) for what is in
scope.
