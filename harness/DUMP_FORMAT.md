# Step log format (oracle and port)

Both the C oracle (`harness/oracle/hooks.c`) and the Godot port in test mode write
the same step log. `harness/difftest.py` compares them line by line. The first
differing line is the first divergence.

## When a step is logged
- **One step per keyboard read.** That means every scripted key consumed by
  `wgetch`, `wgetnstr`, or the post-`endwin` `fgets(stdin)`.
- **What a step records.** The state at the moment the program is waiting:
  after `wgetch`'s implicit refresh and before the key is applied.
- **ESC look-ahead.** md_readchar's second `getch` after ESC runs in halfdelay
  mode. It returns ERR, consumes no key, and logs nothing.
- **Running out of keys.** When the script is exhausted, the step is logged with
  `K-1`. Then `END <step>` is written and the program exits with status 0.
- **Exiting.** A real exit (`exit()`/`my_exit()`) writes `EXIT <code>`.

## Step line
```
S<step> K<key> R<seed> C<y>,<x> X<screenhash> D<digesthash>
S<step> K<key> R<seed> Z D<digesthash>          (after score() deleted curscr)
```
- `step`: 1-based count of keyboard reads.
- `key`: the decimal code about to be returned (`-1` at end of script).
- `seed`: the RNG state, as an unsigned 32-bit decimal.
- `y,x`: curscr's cursor, i.e. where the physical cursor is.
  - The port writes `C?` when the cursor is undefined because the last refresh
    used `leaveok`. The comparator then ignores the cursor.
- `screenhash`: FNV-1a 32-bit (offset 2166136261, prime 16777619), as 8 lowercase
  hex digits.
  - Input: the 24×80 curscr cells in row-major order.
  - Each cell contributes its full `chtype` as 4 bytes, little-endian.
  - `chtype` is the character (bits 0–7) OR'd with the ncurses attribute bits.
    The game only uses `A_STANDOUT` = `0x10000`.
- `digesthash`: FNV-1a 32-bit of the digest string (below), over its bytes.

## Full mode (`ROGUE_FULL=<n>`: steps ≥ n)
After the step line:
- 24 lines of `|<80 chars>|`. Characters outside printable ASCII are shown as `?`.
- One line starting with `E`, listing every cell whose chtype is not plain
  printable ASCII: ` y,x=<chtype hex>`.
- One line `G <digest>`.

## Digest string
Fields are separated by single spaces.
1. `L<level> M<max_level> G<purse> F<food_left> H<hungry_state> N<no_command>
   V<no_move> C<count> U<running> T<to_death> I<inpack> A<amulet>`.
   Booleans are written as 0/1.
2. `P<y>,<x> f<t_flags hex16> s<s_str> e<s_exp> l<s_lvl> a<s_arm> h<s_hpt>/<s_maxhp>
   d<s_dmg> r<room>`. These are the player's position, flags, stats and room.
3. `W<i> R<i> Q<i>,<i>`: pack indices of cur_weapon, cur_armor, and the
   left/right rings.
   - Pack indices are 0-based positions in the pack list.
   - -1 means NULL. -2 means the item is not in the pack.
4. ` m:` then one `[<t_type> <y>,<x> f<t_flags hex16> h<s_hpt> g<t_disguise>
   o<t_oldch> t<dest> r<room>]` per monster, in `mlist` order.
   - `t_type` and `t_disguise` are written as decimal.
   - `t_oldch` is written as a signed decimal C `char`.
5. ` o:` then one `[<o_type> <o_which> <y>,<x> c<o_count> f<o_flags hex>
   a<o_arm>]` per object, in `lvl_obj` order.
6. ` k:` then one `[<o_packch> <o_type> <o_which> c<o_count> f<o_flags hex>
   h<o_hplus> d<o_dplus> a<o_arm> g<o_group>]` per pack item.
7. ` d:` then one `[<slot> t<d_type> <func> a<d_arg> n<d_time>]` per non-empty
   `d_list` slot, in slot order.
   - `func` is one of: `runners doctor swander stomach rollwand unconfuse
     nohaste unsee sight land come_down visuals turn_see`.

Encodings used above:
- **Rooms** (`r`): 0–8 for `rooms[i]`, 100+i for `passages[i]`, and -1 for NULL.
- **Destinations** (`t`):

| Code | Meaning |
|---|---|
| `-` | NULL |
| `h` | `&hero` |
| `o<i>` | the i-th `lvl_obj` entry's `o_pos` |
| `g<i>` | `rooms[i].r_gold` |
| `G<i>` | `passages[i].r_gold` |
| `m<i>` | the i-th monster's `t_pos` |
| `k<i>` | the i-th pack object's `o_pos` |
| `p<m>.<j>` | monster m's j-th pack object |
| `?` | anything else, e.g. a discarded object |

Hex numbers are lowercase with no leading zeros. Flags are shown as unsigned:
`t_flags` as 16-bit, `o_flags` as 32-bit.

## Other outputs of a run
- **stdout:** the raw byte stream. It includes `Hello …`, BEL characters from
  `get_str`, shell-escape text, and the post-`endwin` top-ten list. It is compared
  byte for byte.
- **Exit status:** compared.
