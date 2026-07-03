# frozen_string_literal: true
# Copyright (c) the go-ruby-pstore authors
# SPDX-License-Identifier: BSD-3-Clause
#
# Reference `pstore` workload, mirroring benchmarks/go/main.go op-for-op over the
# SAME fixed data and store files. It exercises Ruby's stdlib PStore:
#
#   - read-txn:  a read-only transaction Marshal-loading the store and fetching
#     every root key. I/O(read) + Marshal-load bound.
#   - write-txn: a read-write round-trip — reset the store to empty, then a
#     transaction inserting the fixed dataset and committing (Marshal-dump + file
#     write). I/O(write) + Marshal-dump bound.
#
# PStore is Marshal-backed, so the numbers reflect the Marshal codec too. The
# fixed read store is created (once) by THIS script's `setup` mode using MRI's own
# PStore, so it is the oracle both drivers read.
#
# Modes:
#   ruby pstore.rb setup    # write the fixed read-only store to $BENCH_STORE_R
#   CHECK=1 ruby pstore.rb  # print CHECK lines (result equality proof vs MRI)
#   ruby pstore.rb          # report ns/op per op through the shared harness
require "pstore"
require_relative "_harness"

STORE_R = ENV.fetch("BENCH_STORE_R") { warn "BENCH_STORE_R not set"; exit 2 }
STORE_W = ENV.fetch("BENCH_STORE_W") { warn "BENCH_STORE_W not set"; exit 2 }

# dataset builds the fixed PStore table — 30 root entries mixing every common
# value shape (Integer, String, Array, nested Hash, Float) — byte-for-byte the
# same table the Go driver builds.
def dataset
  keys = []
  vals = []
  30.times do |i|
    keys << "root#{i}".to_sym
    vals << case i % 5
            when 0 then i * 1000 + 7
            when 1 then "value-#{i}-payload"
            when 2 then [i, i + 1, i + 2]
            when 3 then { a: i, b: "s#{i}" }
            else i + 0.5
            end
  end
  [keys, vals]
end

KEYS, VALS = dataset

# fold: order- and content-sensitive rolling hash over a byte string, computed
# identically on the Go side.
def fold(acc, str)
  str.each_byte { |b| acc = (acc * 131 + b) % 1_000_000_007 }
  acc
end

# read-txn: read-only transaction fetching every key; checksum folds the Marshal
# bytes of each fetched value (proves values byte-identical to MRI).
def op_read
  st = PStore.new(STORE_R)
  acc = 0
  st.transaction(true) do
    KEYS.each { |k| acc = fold(acc, Marshal.dump(st[k])) }
  end
  acc
end

# write-txn: reset the store to empty, then a read-write transaction inserting the
# fixed dataset and committing; checksum folds the resulting file bytes (byte-exact
# Marshal equality proof).
def op_write
  File.binwrite(STORE_W, "")
  st = PStore.new(STORE_W)
  st.transaction { KEYS.each_with_index { |k, i| st[k] = VALS[i] } }
  fold(0, File.binread(STORE_W))
end

# setup: write the fixed read-only store with MRI's own PStore (the oracle).
def setup
  File.binwrite(STORE_R, "")
  st = PStore.new(STORE_R)
  st.transaction { KEYS.each_with_index { |k, i| st[k] = VALS[i] } }
end

OPS = [
  ["read-txn",  method(:op_read)],
  ["write-txn", method(:op_write)],
].freeze

if ARGV[0] == "setup"
  setup
elsif ENV["CHECK"] && !ENV["CHECK"].empty?
  OPS.each { |label, m| printf("CHECK\t%s\t%d\n", label, m.call) }
else
  INNER = 200
  OPS.each { |label, m| bench(label, INNER) { m.call } }
end
