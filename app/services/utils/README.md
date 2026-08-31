# Base62

Base62 is a way of writing numbers using a larger "alphabet" of digits. It works like decimal or binary: each position is a power of the base, except there are 62 symbols per place instead of 10 or 2.

## Bases at a glance

| Base | Name    | Symbols used              | Count |
|-----:|---------|---------------------------|------:|
| 2    | Binary  | `0`, `1`                  | 2     |
| 10   | Decimal | `0`–`9`                   | 10    |
| 16   | Hex     | `0`–`9`, `a`–`f`          | 16    |
| 62   | Base62  | digits, lower, upper case | 62    |

## Alphabet (this project)

`Utils::Base62Service` uses this order:

```
0 1 2 3 4 5 6 7 8 9 a b c d e f g h i j k l m n o p q r s t u v w x y z A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
```

That is 62 characters total:

- 10 digits (`0`–`9`)
- 26 lowercase letters (`a`–`z`)
- 26 uppercase letters (`A`–`Z`)

The ordering is **convention only**. Encode and decode must use the same alphabet (see `ALPHABET` in [`base62_service.rb`](../base62_service.rb)).

## Encode

**Input:** integer. Intended use is **non-negative** ids (e.g. snowflake values).

1. If the number is `0`, return the first alphabet character (`"0"`).
2. If the number is **negative**, the `while number > 0` loop never runs, so the method returns **`""`** (empty string). There is no error.
3. Otherwise, repeatedly take `number % 62`, map the remainder to a character via `ALPHABET`, integer-divide `number` by 62, until `number` is 0.
4. The remainders are produced least-significant digit first; **reverse** the collected characters and join to get the final string.

Example in this app: [`UrlMapping`](../../../models/url_mapping.rb) sets `url_code` from `encode(snowflake_id)` so slugs stay short and URL-friendly.

## Decode

**Input:** base62 string (characters must all appear in `ALPHABET`).

1. Walk left to right. Maintain an accumulator starting at `0` (so an **empty string** decodes to `0`).
2. For each character: `acc = acc * 62 + index_of(char)` in `ALPHABET`.
3. Return the final integer.

**Round-trip:**

- `decode(encode(n)) == n` for any non-negative `n` that `encode` handles normally (not negative).
- `encode(decode(s)) == s` only when `s` is **canonical** (exactly what `encode` would output). Aliases like `"01"` decode to `1` but re-encode to `"1"`.

This app does **not** call `decode` for short codes—only `encode` when creating codes.

## Notes / gotchas

- **Invalid characters:** `decode` raises `ArgumentError` with message `invalid base62 character: ...` if any character is not in `ALPHABET`. Handle that at the call site (e.g. treat as unknown url code) or validate before decoding.
- **Negative numbers:** `encode(-n)` returns an empty string `""`, not an error. Validate non-negative inputs at the call site if that matters (e.g. snowflake ids).
- **Leading zeros:** `encode` never emits redundant leading zeros (`encode(1)` is always `"1"`, never `"01"`). `decode` is **permissive**: `"1"`, `"01"`, and `"001"` all decode to `1`; `"0"`, `"00"`, and `""` all decode to `0`. Strings that **start** with `0` are not always zero (e.g. `"0a"` → `10`). No extra handling is required for short codes (DB lookup by exact `url_code`).
- **Not covered:** no validation for `nil` or non-integer `encode` inputs; callers should pass integers. `decode` uses linear `ALPHABET.index` per character—fine for short codes.
