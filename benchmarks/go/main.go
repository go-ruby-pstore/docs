// Copyright (c) the go-ruby-pstore authors
// SPDX-License-Identifier: BSD-3-Clause
//
// Library-level benchmark driver for the pure-Go go-ruby-pstore library. It runs
// PStore transactions over a real store file, so the ns/op numbers compare the
// pure-Go transaction+Marshal engine against each Ruby runtime's own stdlib
// PStore over the SAME fixed data.
//
// Two ops are measured:
//
//   - read-txn:  a read-only transaction that Marshal-loads the store file and
//     fetches every root key. I/O(read) + Marshal-load bound.
//   - write-txn: a read-write round-trip — reset the store to empty, then a
//     transaction that inserts the fixed dataset and commits, Marshal-dumping the
//     table back to the file. I/O(write) + Marshal-dump bound.
//
// PStore is Marshal-backed, so this exercises the sibling go-ruby-marshal codec:
// the fixed read store is written by MRI's own PStore (the oracle) and read here,
// and the write op's resulting file bytes are checksummed — a byte-exact Marshal
// equality proof against MRI.
//
// With CHECK=1 it prints one "CHECK\t<label>\t<value>" line per op used to prove
// the Go result is identical to MRI before any timing is trusted.
package main

import (
	"fmt"
	"os"

	"github.com/go-ruby-marshal/marshal"
	"github.com/go-ruby-pstore/pstore"
)

// storeR is the fixed, read-only store file (written once by MRI in run.sh);
// storeW is the scratch file the write op rewrites each iteration.
var (
	storeR = mustEnv("BENCH_STORE_R")
	storeW = mustEnv("BENCH_STORE_W")
)

func mustEnv(k string) string {
	v := os.Getenv(k)
	if v == "" {
		fmt.Fprintln(os.Stderr, k+" not set (run via benchmarks/run.sh)")
		os.Exit(2)
	}
	return v
}

// fileBackend is the injected store seam over a real file: Load reads the bytes
// (a missing/empty file is the empty table), Store overwrites them. This is the
// role rbgo fills with a real os.File; here it makes the benchmark genuinely
// I/O-bound, like MRI's PStore.
type fileBackend struct{ path string }

func (f fileBackend) Load() ([]byte, error) {
	b, err := os.ReadFile(f.path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	return b, err
}

func (f fileBackend) Store(data []byte) error { return os.WriteFile(f.path, data, 0o644) }

// dataset builds the fixed PStore table — 30 root entries mixing every common
// value shape (Integer, String, Array, nested Hash, Float) — identically to the
// Ruby driver, so the Marshal bytes are byte-for-byte the same.
func dataset() (keys, vals []marshal.Value) {
	for i := 0; i < 30; i++ {
		keys = append(keys, marshal.Symbol(fmt.Sprintf("root%d", i)))
		switch i % 5 {
		case 0:
			vals = append(vals, marshal.NewInt(int64(i*1000+7)))
		case 1:
			vals = append(vals, marshal.NewString(fmt.Sprintf("value-%d-payload", i)))
		case 2:
			vals = append(vals, &marshal.Array{Elems: []marshal.Value{
				marshal.NewInt(int64(i)), marshal.NewInt(int64(i + 1)), marshal.NewInt(int64(i + 2)),
			}})
		case 3:
			vals = append(vals, &marshal.Hash{
				Keys: []marshal.Value{marshal.Symbol("a"), marshal.Symbol("b")},
				Vals: []marshal.Value{marshal.NewInt(int64(i)), marshal.NewString(fmt.Sprintf("s%d", i))},
			})
		default:
			vals = append(vals, marshal.Float(float64(i)+0.5))
		}
	}
	return keys, vals
}

var keys, vals = dataset()

const mod = 1000000007

// fold folds a byte slice into an order- and content-sensitive rolling hash,
// computed identically on the Ruby side; kept in int64 range via mod a prime so
// Go's fixed-width ints and Ruby's arbitrary-precision ints agree.
func fold(acc int64, b []byte) int64 {
	for _, x := range b {
		acc = (acc*131 + int64(x)) % mod
	}
	return acc
}

// opRead: read-only transaction fetching every key; checksum folds the Marshal
// bytes of each fetched value, proving the values are byte-identical to MRI.
func opRead() int64 {
	s := pstore.New(fileBackend{storeR})
	var acc int64
	_ = s.Transaction(true, func(t *pstore.Tx) error {
		for _, k := range keys {
			v, ok, _ := t.Get(k)
			if !ok {
				continue
			}
			acc = fold(acc, marshal.Dump(v))
		}
		return nil
	})
	return acc
}

// opWrite: reset the store to empty, then a read-write transaction that inserts
// the fixed dataset and commits (Marshal-dump + file write). The checksum folds
// the resulting file bytes — a byte-exact Marshal equality proof against MRI's
// PStore file.
func opWrite() int64 {
	_ = os.WriteFile(storeW, nil, 0o644)
	s := pstore.New(fileBackend{storeW})
	_ = s.Transaction(false, func(t *pstore.Tx) error {
		for i, k := range keys {
			_ = t.Set(k, vals[i])
		}
		return nil
	})
	b, _ := os.ReadFile(storeW)
	return fold(0, b)
}

var ops = []struct {
	label string
	fn    func() int64
}{
	{"read-txn", opRead},
	{"write-txn", opWrite},
}

func main() {
	if os.Getenv("CHECK") != "" {
		for _, o := range ops {
			fmt.Printf("CHECK\t%s\t%d\n", o.label, o.fn())
		}
		return
	}
	const inner = 200
	for _, o := range ops {
		fn := o.fn
		bench(o.label, inner, func() { sink = fn() })
	}
}
