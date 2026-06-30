# Usage & API

The public API lives at the module root (`github.com/go-ruby-pstore/pstore`). It is
**Ruby-shaped but Go-idiomatic**: the methods mirror `PStore`'s, while the surface
follows Go conventions — explicit errors, an injected `Backend`, no global state.
The table's keys and values are
[go-ruby-marshal](https://github.com/go-ruby-marshal/marshal) `Value`s, the same
typed model the rest of the go-embedded-ruby stack speaks.

!!! success "Status: implemented"
    The library is built and importable as `github.com/go-ruby-pstore/pstore`,
    bound into `rbgo` as a native module; see [Roadmap](roadmap.md).

## Install

```sh
go get github.com/go-ruby-pstore/pstore
```

## Worked example

```go
package main

import (
	"fmt"

	"github.com/go-ruby-marshal/marshal"
	"github.com/go-ruby-pstore/pstore"
)

func main() {
	// The host supplies the file seam (real os.File + flock in rbgo); here an
	// in-memory backend stands in.
	be := &mem{}
	store := pstore.New(be)

	// A read-write transaction: writes commit on normal return.
	store.Transaction(false, func(t *pstore.Tx) error {
		t.Set(marshal.Symbol("foo"), marshal.NewInt(0))
		t.Set(marshal.NewString("baz"), &marshal.Array{
			Elems: []marshal.Value{marshal.NewInt(1), marshal.NewInt(2)},
		})
		return nil // commit
	})

	// A read-only transaction: reads only; a write here would raise PStore::Error.
	store.Transaction(true, func(t *pstore.Tx) error {
		roots, _ := t.Roots()           // [:foo, "baz"]
		v, ok, _ := t.Get(marshal.Symbol("foo"))
		fmt.Println(roots, v, ok)
		return nil
	})
}

type mem struct{ b []byte }

func (m *mem) Load() ([]byte, error) { return m.b, nil }
func (m *mem) Store(b []byte) error  { m.b = b; return nil }
```

## API

```go
// New returns a Store over an injected Backend.
func New(b Backend) *Store

// Backend is the file seam the host injects (real os.File + flock in rbgo).
type Backend interface {
	Load() ([]byte, error)   // current store bytes (empty == fresh store)
	Store(data []byte) error // overwrite with the marshalled table
}

// Transaction loads the table, runs body, and — on a committing read-write
// transaction whose table changed — Marshal-dumps it back to the backend.
// body returns t.Commit()/t.Abort() to exit early, any other error to propagate
// (no commit), or nil to finish (a read-write transaction then commits).
func (s *Store) Transaction(readOnly bool, body func(t *Tx) error) error

// In-transaction API (mirrors PStore#[], #[]=, #delete, #fetch, #roots/#keys,
// #root?/#key?, #commit, #abort). Keys and values are go-ruby-marshal Values.
func (t *Tx) Get(key marshal.Value) (marshal.Value, bool, error)            // PStore#[]
func (t *Tx) Set(key, val marshal.Value) error                             // PStore#[]=
func (t *Tx) Delete(key marshal.Value) (marshal.Value, error)              // PStore#delete
func (t *Tx) Fetch(key marshal.Value, def marshal.Value) (marshal.Value, error) // PStore#fetch
func (t *Tx) Roots() ([]marshal.Value, error)                              // PStore#roots
func (t *Tx) RootQ(key marshal.Value) (bool, error)                        // PStore#root?
func (t *Tx) Commit() error                                                // PStore#commit
func (t *Tx) Abort() error                                                 // PStore#abort

// Error is PStore::Error.
type Error struct{ /* … */ }
```

The table's keys and values are
[go-ruby-marshal](https://github.com/go-ruby-marshal/marshal) `Value`s
(`marshal.Symbol`, `*marshal.Str`, `marshal.Int`, `*marshal.Array`, `*marshal.Hash`,
…) — so a host binds its own Ruby objects to and from this engine exactly as it does
for Marshal.

## The error taxonomy

A single `*pstore.Error` (Ruby's `PStore::Error`) carries MRI's exact messages:
`"not in transaction"`, `"in read-only transaction"`, `"nested transaction"`,
`"undefined key '…'"`, and `"PStore file seems to be corrupted."`.

## MRI conformance

Correctness is defined by reference Ruby. A **differential oracle** writes a store
with the real `ruby -rpstore`, loads its file bytes here, and round-trips the table
both directions (MRI→Go and Go→MRI), plus replays MRI's own commit / abort /
read-only sequence and asserts the engine produces the identical persisted roots.
The oracle scripts `$stdout.binmode` so Windows text-mode never corrupts the raw
Marshal bytes, and skip themselves where `ruby` is absent — so the cross-arch and
Windows lanes still validate the library.

## Relationship to Ruby

`go-ruby-pstore/pstore` is **standalone and reusable**, and is the backend bound
into [go-embedded-ruby](https://github.com/go-embedded-ruby/ruby) by `rbgo` as a
native module — the same way [go-ruby-regexp](https://github.com/go-ruby-regexp) and
[go-ruby-erb](https://github.com/go-ruby-erb) are bound. The host supplies the real
file + locking backend; this library has no dependency on the Ruby runtime.
