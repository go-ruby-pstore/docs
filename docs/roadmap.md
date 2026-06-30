# Roadmap

`go-ruby-pstore/pstore` is grown **test-first**, each capability differential-tested
against MRI rather than built in isolation. PStore's transaction engine — the
deterministic, interpreter-independent slice extracted from rbgo's internals — is
**complete**.

| Stage | What | Status |
| --- | --- | --- |
| Transaction state machine | `Transaction(readOnly, body)` runs PStore's load → body → commit/abort machine over a Hash table, refusing a nested transaction and raising outside one. | **Done** |
| Commit on normal exit | A read-write transaction whose body returns normally Marshal-dumps the table back through the backend — only if the bytes changed (MRI's checksum/size guard). | **Done** |
| Commit / Abort early exit | `t.Commit()` / `t.Abort()` from the body exit it early (MRI's `throw :pstore_abort_transaction`): `Abort` discards every change, `Commit` persists the work so far. | **Done** |
| Read-only transactions & error taxonomy | In a read-only transaction `Set` / `Delete` raise `PStore::Error` and the backend is never written; a single `*pstore.Error` carries MRI's exact messages. | **Done** |
| MRI-compatible on-disk Marshal | The table is `Marshal.dump` / `load`ed via go-ruby-marshal, so files round-trip both directions with MRI's `PStore`. | **Done** |
| Differential oracle & coverage | Real `ruby -rpstore` files loaded here, the table round-tripped both directions, and MRI's commit / abort / read-only sequence replayed and asserted; 100% coverage, gofmt + go vet clean, green across all six 64-bit Go arches and three OSes. | **Done** |

## Documented out-of-scope boundaries

These are **deliberate**, recorded so the module's surface is unambiguous:

- **The file/locking layer is the consumer's.** Opening the store, `flock`, and the
  atomic-rename / rewind-truncate save strategies are injected through a two-method
  `Backend`. The host supplies the real `os.File` + `syscall.Flock` — that is why
  `rbgo` binds this module rather than the reverse.
- **Reference is reference Ruby (MRI).** Byte-for-byte on-disk compatibility targets
  MRI's `PStore`; differences across MRI releases are matched to the reference used
  by the differential oracle.
- **Standalone & reusable.** The module has no dependency on the Ruby runtime; the
  dependency runs the other way.

See [Usage & API](api.md) for the surface and [Why pure Go](why.md) for the
deterministic/file-seam split.
