# Snowflake ID generation

[`GeneratorService`](generator_service.rb) produces **sortable, 64-bit integer IDs** by packing a timestamp, machine identifier, and per-millisecond sequence into one number. In this app, those ids are usually **Base62-encoded** into short link slugs.

## Why Snowflake here

- **No DB round-trip** to allocate the next id on create (unlike a single global auto-increment).
- **Opaque slugs** after Base62 encoding (unlike guessable sequential ids).
- **High create rate:** many ids can be minted in the same millisecond via the **sequence** field; a **mutex** prevents duplicate ids from concurrent threads on the **same generator instance**.

Race conditions on id generation are the main concurrency concern at high request rates; `next_id` runs entirely inside `@mutex.synchronize`.

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
| URL shortener | [`UrlMapping#shorten`](../../app/models/url_mapping.rb) → `encode(GeneratorService.new.next_id)` |

**Important:** each `UrlMapping` create currently does **`GeneratorService.new`**. Sequence and mutex state are **per instance**, not global. Concurrent creates can theoretically collide in the same millisecond until the **unique index on `url_code`** rejects a duplicate. For production, use a **shared generator** (e.g. one per process) and wire a real **machine id**.

## Machine id (planned)

Ruled out:
- **`Socket.gethostname.hash % 1024`** — Ruby's `Object#hash` is randomly reseeded **per process** (intentional, prevents hash-DoS attacks). Same hostname produces a *different* value on every restart, breaking the "stable machine_id" guarantee a restarted pod needs.
- **`hostname.unpack1("H*")`** (hex-encode) — deterministic, but still needs reduction into the 10-bit range (e.g. `% 1024`), which reintroduces the same "probabilistic, not guaranteed" uniqueness problem as hashing. Doesn't add any actual coordination.

Two real options:

**A. Kubernetes StatefulSet ordinal** (fast to wire up, environment-specific):
```ruby
def machine_id
  hostname = Socket.gethostname   # "my-app-2" on a StatefulSet
  hostname[/\d+\z/].to_i           # => 2
end
```
Kubernetes guarantees no two *concurrently running* pods in one StatefulSet share an ordinal, and it's stable across restarts. **Known risk:** only guaranteed unique *within one StatefulSet* — two different StatefulSets (e.g. `api-0` and `worker-0`) would both extract ordinal `0` and collide if they share the same machine_id pool. Also needs a fallback for local dev, since a dev machine's hostname has no trailing digit.

**B. DB-coordinator-assigned id** (environment-agnostic, more robust):
A `MachineIdLease` table pre-seeded with rows `0`–`1023`. On boot, each process atomically claims an unused row inside a DB transaction + row lock:
```ruby
def self.claim_machine_id
  ActiveRecord::Base.transaction do
    lease = MachineIdLease.lock.where(claimed: false).order(:id).first
    raise "No available machine IDs" unless lease
    lease.update!(claimed: true, hostname: Socket.gethostname, claimed_at: Time.current)
    lease.id
  end
end
```
Doesn't depend on Kubernetes topology assumptions. Open question not yet resolved: whether a gracefully-shutting-down pod should release its claimed id back to the pool, or whether leases just accumulate until manually reset.

**Current status:** `@machine_id = 0` for all instances (see Design notes above) — Option A is a faster stopgap for continued local development; Option B is the target before any multi-node deploy.

## Tests

```bash
bundle exec rspec spec/services/snowflake/generator_service_spec.rb
```

Covers timestamp embedding, sequence increment in the same ms, sequence reset on a new ms, bulk uniqueness, and concurrent `next_id` on one generator.

## Related docs

| Doc | Content |
|-----|---------|
| [URL shortener write-up](../../write-ups/url-shortener.md) | Why Snowflake vs auto-increment / UUID / block allocation |
| [Base62 notes](../utils/notes/base62.md) | Encoding ids into `url_code` |

## Follow-ups

- [ ] Set `@machine_id` from hostname/pod ordinal (use existing `machine_id` method or env var).
- [ ] Singleton or container-scoped `GeneratorService` for `UrlMapping`.
- [ ] Optional `notes/generator.md` for deep dive and diagrams.
