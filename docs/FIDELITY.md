# Fidelity policy

The Godot port reproduces Rogue 5.4.4 exactly. Given the same seed and keystrokes it
shows the same screens and consumes the same random numbers. This is verified against
the original C code built as an oracle (`harness/oracle`).

The original C also has **undefined behavior**: code whose result depends on the
compiler, memory allocator or stack contents. For each such case one deterministic
behavior was chosen. It is applied **identically** in the oracle (via
`harness/oracle/oracle.patch` or `hooks.c`) and in the port. This file lists every
such choice, plus the few deliberate deviations.

## Undefined behavior in the original, and the behavior chosen
| Where | What C does | Port and oracle |
|---|---|---|
| `sticks.c` `fire_bolt()` | `THING bolt` is never initialized. `roll_em()` reads its `o_flags`, `o_launch` and `o_damage`, which are stack garbage. This happens on every fire/ice/lightning hit and dragon-breath hit on a monster. | Zero-initialized, with `o_launch = -1`: the bolt uses its `o_hurldmg` "6x6", as the code intends. |
| `list.c` `discard()` and use-after-free paths | Several paths read freed memory: a discarded object still targeted by a monster's `t_dest`, a nymph stealing from a stack (the freed node stays linked in the pack), a stale `last_pick`, and monsters freed while `runners()` iterates. glibc's tcache then overwrites `l_next`/`l_prev`. | `free()` is a no-op, so a freed object keeps its last contents (GDScript keeps it alive). The stock binary differs here: in the stolen-stack case it may crash. |
| `INDEX(y,x)` with `x == -1` | Left-column mazes let `search`, `fallpos`, `f`/`F`, `^`, zap beams and `fire_bolt` index `places[-32+y]`, reading and writing foreign memory. | An out-of-range index returns a blank dummy square (`' '`, flags 0, no monster). Writes to it are discarded. |
| `daemons.c` `stomach()` | `ring_eat(LEFT) + ring_eat(RIGHT)` is unsequenced, and both calls may consume RNG. | LEFT then RIGHT, which is what stock gcc -O0/-O2 does (made explicit in the oracle). |
| RNG `seed*11109+13849` | Signed overflow. | Wraps modulo 2^32 (`-fwrapv`; the port masks to 32 bits). |
| `io.c` `@` status | `%ld` is given an `int`. | `%d`. |
| `io.c` message buffer | `msgbuf[143]` can overflow on very long messages (`strcat`). | Strings are dynamic. The test generator keeps typed names short, so this never triggers in tests. |
| player-typed names used as a format string (`msg(huh)` etc.) | `%` sequences read missing arguments. | Missing arguments format as 0 / "". The test generator types no `%`. |
| ESC followed quickly by another key | `md_readchar()` swallows the ESC if the next key arrives within ~100 ms. | ESC is always standalone: the look-ahead `getch` in halfdelay mode returns ERR at once. |

## Environment pinned in tests (real values in normal play)
In tests these are fixed: `time()` (seed and tombstone year), the pid (seed), the user
name, home directory and uid, the tty erase/kill characters (^H/^U), the baud rate
(38400), and the terminal (xterm, 24x80, with clear-to-EOL, so the default inventory
style is "Clear").

- **Seed.** In both programs `seed = time + pid`, so tests set
  `pid = SEED - TIME`.
- **Shell escape.** `!` runs no shell. The screen and prompt sequence is kept.

## Deliberate deviations (port only)
- **Save files** use the port's own format.
  - The two C save bugs are fixed: 4 daemon functions missing from `rs_write_daemons`
    (a crash on restore while hallucinating, levitating or detecting monsters), and
    corridor rooms saved as `&rooms[-1]`.
  - The set of state that is saved and restored is otherwise the same as C's.
- **Messages on paths that are unreachable, or that crash the C game**, are reported
  with `push_error` instead of `msg()`. This lets these functions stay ordinary,
  non-coroutine functions. They are listed in `tools/blocking.json` →
  `port_nonblocking`:
  - `roomin` "in some bizarre place"
  - `find_obj` "Non-object"
  - `runto` "couldn't find monster"
  - `new_item` (out of memory)
  - `d_slot` (out of daemon slots)
  - `inv_name` / `new_thing` / `pick_one` / `badcheck`: MASTER consistency checks
- **Wizard mode** (the MASTER build) accepts any password; the oracle does the same.

## Known quirks kept on purpose (bugs in the original)
These are kept because they are part of 5.4.4's behavior:
- Numpad 5 maps to `u`.
- `F` leaves `kamikaze` set after a cancelled direction.
- `relocate()` never calls `find_dest()`.
- `find_dest()` reuses its parameter as a loop variable.
- `add_pack()` doesn't detach a picked-up object from `lvl_obj` when the pack is
  empty.
- Maze rooms are never dark (`r_flags = ISMAZE`).
- `save_game()` unlinks the old file name.
