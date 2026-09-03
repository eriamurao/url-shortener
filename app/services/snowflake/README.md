# Snowflake ID generation

[`GeneratorService`](generator_service.rb) produces **sortable, 64-bit integer IDs** by packing a timestamp, machine identifier, and per-millisecond sequence into one number. In this app, those ids are **Base62-encoded** into short link slugs (`url_code`).

## Why Snowflake here

- **No DB round-trip** to allocate the next id on create (unlike a single global auto-increment).
- **Opaque slugs** after Base62 encoding (unlike guessable sequential ids).
- **High create rate:** many ids can be minted in the same millisecond via the **sequence** field; a **mutex** prevents duplicate ids from concurrent threads on the **same generator instance**.

Race conditions on id generation are the main concurrency concern at high request rates; `next_id` runs entirely inside `@next_id_mutex.synchronize`.

## ID layout

Constants live on `Snowflake::GeneratorService`:

| Field | Bits | Role |
|-------|-----:|------|
| Timestamp | 41 | Milliseconds since **`CUSTOM_EPOCH`** (not Unix epoch) |
| Machine id | 10 | Distinguish generators on different hosts/pods |
| Sequence | 12 | Counter within the same timestamp (0…**4095**) |

Packed as:

```text
id = (timestamp << 22) | (machine_id << 12) | sequence
```

- **`CUSTOM_EPOCH`:** `1785542400000` → 2026-07-31 00:00:00 UTC. Subtracting it keeps the timestamp component small so everything fits in 64 bits with room for machine + sequence.
- **`MAX_SEQUENCE`:** `(1 << 12) - 1` → **4095**. When the sequence wraps in the same millisecond, the code **spins** in `wait_for_next_millisecond` until the clock advances.

### Decoding an id (debugging)

```ruby
seq   = id & 0xFFF
mid   = (id >> 12) & 0x3FF
ts    = id >> 22   # ms since CUSTOM_EPOCH
```

Specs use the same unpacking helpers in [`spec/services/snowflake/generator_service_spec.rb`](../../spec/services/snowflake/generator_service_spec.rb).

## `next_id` behavior (summary)

1. Read current time in ms, minus `CUSTOM_EPOCH`.
2. If same millisecond as last call: increment sequence (with wrap at 4095); if sequence wrapped to 0, wait for the next millisecond.
3. If new millisecond: reset sequence to 0.
4. Bit-or timestamp, machine id, and sequence; return integer.

All of step 1–4 runs under a **Mutex** on that `GeneratorService` instance.

## Usage

| Consumer | How |
|----------|-----|
| URL shortener | [`UrlMapping#generate_url_code`](../../app/models/url_mapping.rb) → `encode(GeneratorService.instance.next_id)` |

One generator is memoized per process (`GeneratorService.instance` / `reset!`). `new` is private. First init is synchronized so two threads cannot both construct a generator. Puma’s `before_worker_boot` hook calls `reset!` after fork so workers do not reuse the parent’s mutex and sequence.

The unique index on `url_code` is a last-resort backstop if two processes still mint the same id.

## Machine id

**Current:** trailing digits of the hostname (`Socket.gethostname[/\d+\z/].to_i`). On a Kubernetes StatefulSet pod `my-app-2` this is `2`. A hostname with no trailing digit (typical local dev) becomes `0`.

This is enough for a **single process per host/pod** (default Puma). It is **not** unique across:

- Puma workers on the same host (they share the hostname ordinal)
- Two different StatefulSets that both have a `*-0` pod

Ruled out:

- **`Socket.gethostname.hash % 1024`** — Ruby's `Object#hash` is randomly reseeded **per process** (intentional, prevents hash-DoS attacks). Same hostname produces a *different* value on every restart.
- **`hostname.unpack1("H*")`** (hex-encode) — deterministic, but still needs reduction into the 10-bit range (e.g. `% 1024`), which is probabilistic uniqueness, not a guarantee.

Before multi-worker or multi-cluster deploy, pick one of:

**A. Fold in Puma worker index** (plus hostname/pod ordinal or `SNOWFLAKE_MACHINE_ID`):

```text
machine_id = (pod_ordinal * WEB_CONCURRENCY) + worker_index
```

Stay in `0..1023`. Reset the generator in `before_worker_boot` after setting the worker index.

**B. DB-coordinator-assigned id:**

A `MachineIdLease` table pre-seeded with rows `0`–`1023`. On boot, each process atomically claims an unused row inside a DB transaction + row lock. Open question: whether a shutting-down process should release its lease.

## Tests

```bash
bundle exec rspec spec/services/snowflake/generator_service_spec.rb
```

Covers timestamp embedding, sequence increment in the same ms, sequence reset on a new ms, bulk uniqueness, concurrent `next_id` on one generator, and hostname ordinal packing.

## Related docs

| Doc | Content |
|-----|---------|
| [Base62](../utils/README.md) | Encoding ids into `url_code` |

## Follow-ups

- [x] Process-scoped `GeneratorService.instance` for `UrlMapping`.
- [x] Set `@machine_id` from hostname trailing digits (single-cluster stopgap).
- [ ] Unique machine id per worker / cluster (option A or B above).
- [ ] Optional `notes/generator.md` for deep dive and diagrams.
