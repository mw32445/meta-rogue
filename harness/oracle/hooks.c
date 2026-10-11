/*
 * harness/oracle/hooks.c
 *
 * Link-time hooks (gcc -Wl,--wrap=SYMBOL) that turn the original Rogue 5.4.4
 * into a deterministic, scriptable reference oracle for the Godot port.
 * The game sources themselves are only touched by oracle.patch.
 *
 * At every keyboard read the oracle writes one line to the step log with the
 * RNG state, the cursor, a hash of the visible screen (curscr) and a hash of a
 * game-state digest.  The Godot port writes the same log in test mode, so a
 * divergence shows up at the exact step where it happens.
 * Format: harness/DUMP_FORMAT.md.
 *
 * Environment:
 *   ROGUE_KEYS  key script: whitespace-separated decimal key codes, '#' comments
 *   ROGUE_DUMP  path of the step log (default: stderr)
 *   ROGUE_FULL  write full screens + digests from this step on (unset: never)
 *   ROGUE_SEED  RNG seed (default 1)
 *   ROGUE_TIME  value returned by time() (default 1000000000)
 *   ROGUE_NAME  player name returned by md_getusername (default "rodney")
 *   ROGUE_HOME  home directory, with trailing '/' (default "/home/rodney/")
 *   ROGUE_UID   uid returned by md_getuid (default 1000)
 */

#define NCURSES_INTERNALS 1	/* WINDOW fields: _flags, _cury, _curx */
#include <curses.h>
#include <errno.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include "rogue.h"

extern void __real_exit(int) __attribute__((noreturn));
extern char *__real_fgets(char *, int, FILE *);
extern int __real_halfdelay(int);
extern int __real_nocbreak(void);
extern int __real_raw(void);
extern int __real_delwin(WINDOW *);
extern FILE *__real_fopen(const char *, const char *);
extern int __real_unlink(const char *);
extern int __real_chmod(const char *, mode_t);

static FILE *dumpf;
static int *keys, nkeys, keypos;
static long step;
static long full_from = -1;
static int in_halfdelay;	/* md_readchar's ESC look-ahead: getch must time out */
static int curses_gone;		/* score() deleted curscr; only stdout remains */

static long
env_long(const char *name, long def)
{
    const char *v = getenv(name);

    return v != NULL && *v != '\0' ? strtol(v, NULL, 10) : def;
}

static FILE *
dump(void)
{
    const char *path;

    if (dumpf == NULL)
    {
	path = getenv("ROGUE_DUMP");
	dumpf = path != NULL ? __real_fopen(path, "w") : stderr;
	if (dumpf == NULL)
	{
	    perror("oracle: ROGUE_DUMP");
	    __real_exit(97);
	}
	if (getenv("ROGUE_FULL") != NULL)
	    full_from = env_long("ROGUE_FULL", 0);
    }
    return dumpf;
}

static void
load_keys(void)
{
    const char *path = getenv("ROGUE_KEYS");
    FILE *f;
    int c, cap = 0;
    long v;

    nkeys = 0;
    if (path == NULL || (f = __real_fopen(path, "r")) == NULL)
	return;
    for (;;)
    {
	c = getc(f);
	if (c == EOF)
	    break;
	if (c == '#')
	{
	    while ((c = getc(f)) != EOF && c != '\n')
		continue;
	    continue;
	}
	if (c == '-' || (c >= '0' && c <= '9'))
	{
	    ungetc(c, f);
	    if (fscanf(f, "%ld", &v) != 1)
		break;
	    if (nkeys == cap)
	    {
		cap = cap ? cap * 2 : 1024;
		keys = realloc(keys, cap * sizeof *keys);
	    }
	    keys[nkeys++] = (int) v;
	}
    }
    fclose(f);
}

/* ---------------------------------------------------------------- hashing */

static uint32_t
fnv(uint32_t h, const void *p, size_t n)
{
    const unsigned char *b = p;

    while (n--)
    {
	h ^= *b++;
	h *= 16777619u;
    }
    return h;
}

#define FNV_INIT 2166136261u

/* ----------------------------------------------------------------- digest */

static char dg[1 << 16];
static size_t dglen;

static void
ap(const char *fmt, ...)
{
    va_list args;
    int n;

    va_start(args, fmt);
    n = vsnprintf(dg + dglen, sizeof dg - dglen, fmt, args);
    va_end(args);
    if (n > 0)
	dglen += (size_t) n;
    if (dglen >= sizeof dg)
	dglen = sizeof dg - 1;
}

static int
room_idx(struct room *rp)
{
    if (rp == NULL)
	return -1;
    if (rp >= rooms && rp < &rooms[MAXROOMS])
	return (int) (rp - rooms);
    if (rp >= passages && rp < &passages[MAXPASS])
	return 100 + (int) (rp - passages);
    return -2;
}

static int
list_idx(THING *list, THING *item)
{
    int i;

    if (item == NULL)
	return -1;
    for (i = 0; list != NULL; list = list->l_next, i++)
	if (list == item)
	    return i;
    return -2;
}

static void
dest_code(char *buf, coord *d)
{
    THING *tp, *op;
    int i, j;

    if (d == NULL)
    {
	strcpy(buf, "-");
	return;
    }
    if (d == &player.t_pos)
    {
	strcpy(buf, "h");
	return;
    }
    for (i = 0, op = lvl_obj; op != NULL; op = op->l_next, i++)
	if (d == &op->o_pos)
	{
	    sprintf(buf, "o%d", i);
	    return;
	}
    for (i = 0; i < MAXROOMS; i++)
	if (d == &rooms[i].r_gold)
	{
	    sprintf(buf, "g%d", i);
	    return;
	}
    for (i = 0; i < MAXPASS; i++)
	if (d == &passages[i].r_gold)
	{
	    sprintf(buf, "G%d", i);
	    return;
	}
    for (i = 0, tp = mlist; tp != NULL; tp = tp->l_next, i++)
	if (d == &tp->t_pos)
	{
	    sprintf(buf, "m%d", i);
	    return;
	}
    for (i = 0, op = player.t_pack; op != NULL; op = op->l_next, i++)
	if (d == &op->o_pos)
	{
	    sprintf(buf, "k%d", i);
	    return;
	}
    for (i = 0, tp = mlist; tp != NULL; tp = tp->l_next, i++)
	for (j = 0, op = tp->t_pack; op != NULL; op = op->l_next, j++)
	    if (d == &op->o_pos)
	    {
		sprintf(buf, "p%d.%d", i, j);
		return;
	    }
    strcpy(buf, "?");
}

typedef void (*dfunc_t)();

static const char *
dfunc_name(dfunc_t f)
{
    static const struct { dfunc_t f; const char *name; } tab[] = {
	{ (dfunc_t) runners, "runners" },
	{ (dfunc_t) doctor, "doctor" },
	{ (dfunc_t) swander, "swander" },
	{ (dfunc_t) stomach, "stomach" },
	{ (dfunc_t) rollwand, "rollwand" },
	{ (dfunc_t) unconfuse, "unconfuse" },
	{ (dfunc_t) nohaste, "nohaste" },
	{ (dfunc_t) unsee, "unsee" },
	{ (dfunc_t) sight, "sight" },
	{ (dfunc_t) land, "land" },
	{ (dfunc_t) come_down, "come_down" },
	{ (dfunc_t) visuals, "visuals" },
	{ (dfunc_t) turn_see, "turn_see" },
    };
    size_t i;

    if (f == NULL)
	return "null";
    for (i = 0; i < sizeof tab / sizeof tab[0]; i++)
	if (tab[i].f == f)
	    return tab[i].name;
    return "unknown";
}

static const char *
digest(void)
{
    THING *tp, *op;
    char dest[32];
    int i;

    dglen = 0;
    dg[0] = '\0';
    ap("L%d M%d G%d F%d H%d N%d V%d C%d U%d T%d I%d A%d",
       level, max_level, purse, food_left, hungry_state, no_command,
       no_move, count, running, to_death, inpack, amulet);
    ap(" P%d,%d f%x s%u e%d l%d a%d h%d/%d d%s r%d",
       player.t_pos.y, player.t_pos.x, (unsigned) (unsigned short) player.t_flags,
       (unsigned) player.t_stats.s_str, player.t_stats.s_exp, player.t_stats.s_lvl,
       player.t_stats.s_arm, player.t_stats.s_hpt, player.t_stats.s_maxhp,
       player.t_stats.s_dmg, room_idx(player.t_room));
    ap(" W%d R%d Q%d,%d", list_idx(player.t_pack, cur_weapon),
       list_idx(player.t_pack, cur_armor), list_idx(player.t_pack, cur_ring[LEFT]),
       list_idx(player.t_pack, cur_ring[RIGHT]));
    ap(" m:");
    for (tp = mlist; tp != NULL; tp = tp->l_next)
    {
	dest_code(dest, tp->t_dest);
	ap("[%d %d,%d f%x h%d g%d o%d t%s r%d]", tp->t_type, tp->t_pos.y,
	   tp->t_pos.x, (unsigned) (unsigned short) tp->t_flags, tp->t_stats.s_hpt,
	   tp->t_disguise, tp->t_oldch, dest, room_idx(tp->t_room));
    }
    ap(" o:");
    for (op = lvl_obj; op != NULL; op = op->l_next)
	ap("[%d %d %d,%d c%d f%x a%d]", op->o_type, op->o_which, op->o_pos.y,
	   op->o_pos.x, op->o_count, (unsigned) op->o_flags, op->o_arm);
    ap(" k:");
    for (op = player.t_pack; op != NULL; op = op->l_next)
	ap("[%d %d %d c%d f%x h%d d%d a%d g%d]", op->o_packch, op->o_type,
	   op->o_which, op->o_count, (unsigned) op->o_flags, op->o_hplus,
	   op->o_dplus, op->o_arm, op->o_group);
    ap(" d:");
    for (i = 0; i < MAXDAEMONS; i++)
	if (d_list[i].d_type != 0)	/* EMPTY (daemon.c) */
	    ap("[%d t%d %s a%d n%d]", i, d_list[i].d_type,
	       dfunc_name((dfunc_t) d_list[i].d_func), d_list[i].d_arg,
	       d_list[i].d_time);
    return dg;
}

/* ------------------------------------------------------------- step log */

static void
log_step(int key)
{
    static chtype cells[NUMLINES][NUMCOLS];
    FILE *f = dump();
    const char *d = digest();
    uint32_t sh = FNV_INIT, dh;
    short flags;
    int y, x, cy, cx, c;

    step++;
    dh = fnv(FNV_INIT, d, strlen(d));
    if (curses_gone)
    {
	fprintf(f, "S%ld K%d R%u Z D%08x\n", step, key, (unsigned) seed, dh);
    }
    else
    {
	/* read curscr without disturbing its cursor or flags (quit() reads them) */
	flags = curscr->_flags;
	cy = curscr->_cury;
	cx = curscr->_curx;
	for (y = 0; y < NUMLINES; y++)
	    for (x = 0; x < NUMCOLS; x++)
	    {
		uint32_t v;

		cells[y][x] = mvwinch(curscr, y, x);
		v = (uint32_t) cells[y][x];
		sh = fnv(sh, &v, 4);	/* little-endian on x86-64 */
	    }
	curscr->_flags = flags;
	curscr->_cury = (NCURSES_SIZE_T) cy;
	curscr->_curx = (NCURSES_SIZE_T) cx;
	fprintf(f, "S%ld K%d R%u C%d,%d X%08x D%08x\n", step, key,
		(unsigned) seed, cy, cx, sh, dh);
	if (full_from >= 0 && step >= full_from)
	{
	    for (y = 0; y < NUMLINES; y++)
	    {
		putc('|', f);
		for (x = 0; x < NUMCOLS; x++)
		{
		    c = (int) (cells[y][x] & A_CHARTEXT);
		    putc(c >= ' ' && c < 0x7f ? c : '?', f);
		}
		fputs("|\n", f);
	    }
	    fputs("E", f);
	    for (y = 0; y < NUMLINES; y++)
		for (x = 0; x < NUMCOLS; x++)
		{
		    c = (int) (cells[y][x] & A_CHARTEXT);
		    if ((cells[y][x] & ~A_CHARTEXT) != 0 || c < ' ' || c >= 0x7f)
			fprintf(f, " %d,%d=%x", y, x, (unsigned) cells[y][x]);
		}
	    putc('\n', f);
	}
    }
    if (full_from >= 0 && step >= full_from)
	fprintf(f, "G %s\n", d);
    fflush(f);
}

/*
 * Interactive mode (ROGUE_KEYS=-, used by harness/bot.py): the step is
 * logged with K-2 before the key is known, then the key is read from stdin,
 * one decimal number per line; end of input ends the run.
 */
static int interactive = -1;

static int
interactive_key(void)
{
    char line[64];

    log_step(-2);
    if (__real_fgets(line, sizeof line, stdin) == NULL)
	return -1;
    return atoi(line);
}

/* Next scripted key.  Logs the step; ends the run when the script is used up. */
static int
scripted_key(void)
{
    int key;

    if (interactive < 0)
    {
	const char *p = getenv("ROGUE_KEYS");

	interactive = p != NULL && strcmp(p, "-") == 0;
    }
    if (interactive)
    {
	key = interactive_key();
	if (key < 0)
	{
	    fprintf(dump(), "END %ld\n", step);
	    fflush(dumpf);
	    fflush(stdout);
	    __real_exit(0);
	}
	return key;
    }
    if (keys == NULL)
	load_keys();
    key = keypos < nkeys ? keys[keypos++] : -1;
    log_step(key);
    if (key < 0)
    {
	fprintf(dump(), "END %ld\n", step);
	fflush(dumpf);
	fflush(stdout);
	__real_exit(0);
    }
    return key;
}

/* ------------------------------------------------------------ input hooks */

/*
 * wgetch: ncurses refreshes the window first (recur_wrefresh: only if the
 * window is touched or its cursor moved since the last refresh), then waits
 * for input.  In halfdelay mode (md_readchar's ESC look-ahead) the wait times
 * out: an ESC is never merged with the following key.
 */
int
__wrap_wgetch(WINDOW *win)
{
    if (win != NULL && !(win->_flags & _ISPAD)
	&& (is_wintouched(win) || (win->_flags & _HASMOVED)))
	wrefresh(win);
    if (in_halfdelay)
	return ERR;
    return scripted_key();
}

/* wgetnstr (score's "[Press return to continue]"): ncurses semantics, noecho. */
int
__wrap_wgetnstr(WINDOW *win, char *str, int n)
{
    char erase = (char) CTRL('H'), kill = (char) CTRL('U');
    int len = 0, ch;

    for (;;)
    {
	ch = __wrap_wgetch(win);
	if (ch == '\n' || ch == '\r' || ch == KEY_DOWN || ch == KEY_ENTER)
	    break;
	if (ch == erase || ch == KEY_LEFT || ch == KEY_BACKSPACE)
	{
	    if (len > 0)
		len--;
	}
	else if (ch == kill)
	    len = 0;
	else if (ch >= KEY_MIN || (n >= 0 && len >= n))
	    continue;	/* ncurses beeps; that goes to the terminal, not stdout */
	else
	    str[len++] = (char) ch;
    }
    str[len] = '\0';
    return OK;
}

/* fgets(stdin): a cooked-mode line read after endwin (death, busy score lock). */
char *
__wrap_fgets(char *s, int size, FILE *stream)
{
    int len = 0, ch;

    if (stream != stdin)
	return __real_fgets(s, size, stream);
    while (len < size - 1)
    {
	ch = scripted_key();
	if (ch == '\r')
	    ch = '\n';	/* ICRNL */
	s[len++] = (char) ch;
	if (ch == '\n')
	    break;
    }
    s[len] = '\0';
    return s;
}

int
__wrap_halfdelay(int tenths)
{
    in_halfdelay = 1;
    return __real_halfdelay(tenths);
}

int
__wrap_nocbreak(void)
{
    in_halfdelay = 0;
    return __real_nocbreak();
}

int
__wrap_raw(void)
{
    in_halfdelay = 0;
    return __real_raw();
}

/* ---------------------------------------------------------- terminal hooks */

/* initscr -> newterm with /dev/null for both output and input */
WINDOW *
__wrap_initscr(void)
{
    FILE *out = __real_fopen("/dev/null", "w"), *in = __real_fopen("/dev/null", "r");
    const char *term = getenv("TERM");

    if (term == NULL)
	term = "xterm";
    if (out == NULL || in == NULL || newterm((char *) term, out, in) == NULL)
    {
	fprintf(stderr, "oracle: newterm failed\n");
	__real_exit(98);
    }
    return stdscr;
}

int
__wrap_delwin(WINDOW *win)
{
    if (win == curscr)
	curses_gone = 1;
    return __real_delwin(win);
}

int  __wrap_baudrate(void) { return 38400; }
char __wrap_erasechar(void) { return (char) CTRL('H'); }
char __wrap_killchar(void) { return (char) CTRL('U'); }

/* ------------------------------------------------------- environment hooks */

time_t
__wrap_time(time_t *t)
{
    time_t v = (time_t) env_long("ROGUE_TIME", 1000000000L);

    if (t != NULL)
	*t = v;
    return v;
}

/* seed = (int) time() + getpid()  =>  getpid() = ROGUE_SEED - ROGUE_TIME */
pid_t
__wrap_getpid(void)
{
    return (pid_t) (env_long("ROGUE_SEED", 1L) - (long) (int) env_long("ROGUE_TIME", 1000000000L));
}

/* score-file uid (rip.c); libc getuid is left alone so md_normaluser keeps working */
int __wrap_md_getuid(void) { return (int) env_long("ROGUE_UID", 1000L); }

char *
__wrap_md_getusername(void)
{
    static char name[MAXSTR];
    const char *v = getenv("ROGUE_NAME");

    snprintf(name, sizeof name, "%s", v != NULL ? v : "rodney");
    return name;
}

char *
__wrap_md_gethomedir(void)
{
    static char dir[MAXSTR];
    const char *v = getenv("ROGUE_HOME");

    snprintf(dir, sizeof dir, "%s", v != NULL ? v : "/home/rodney/");
    return dir;
}

/* the wizard's "names" score listing: the pinned user name, not getpwuid() */
char *
__wrap_md_getrealname(int uid)
{
    const char *n = getenv("ROGUE_NAME");

    (void) uid;
    return (char *) (n != NULL ? n : "rodney");
}

/*
 * ROGUEOPTS is handed out from a NUL-padded copy: parse_opts() reads past the
 * end of a string option with no value ("name", "file=~"); the padding makes
 * that read NULs, as the port does.  parse_opts() writes into the string (the
 * inven value's case), and main() and playit() both parse it: one buffer.
 */
extern char *__real_getenv(const char *);

char *
__wrap_getenv(const char *name)
{
    static char opts[4096];
    static int copied;
    char *v;

    if (strcmp(name, "ROGUEOPTS") != 0)
	return __real_getenv(name);
    v = __real_getenv(name);
    if (v == NULL)
	return NULL;
    if (!copied)
    {
	strncpy(opts, v, sizeof opts - 64);
	copied = 1;
    }
    return opts;
}

int  __wrap_md_shellescape(void) { return 0; }	/* never fork a shell */
void __wrap_md_sleep(int s) { (void) s; }

/* MASTER builds: any wizard password is accepted */
char *
__wrap_md_crypt(char *key, char *salt)
{
    (void) salt;
#ifdef PASSWD
    (void) key;
    return PASSWD;
#else
    return key;
#endif
}
char *__wrap_md_getpass(char *prompt) { (void) prompt; return "oracle"; }

/*
 * Sandbox: the game may only touch files in its run directory (the cwd).  A
 * file name typed at a save or option prompt that leaves it ("/x", "../x",
 * "a/b"; a leading "./" is allowed) is refused with ENOENT.  The port's test
 * mode refuses the same names (RogueBase.env_sandbox).
 */
static int
outside_rundir(const char *path)
{
    if (path[0] == '.' && path[1] == '/')
	path += 2;
    return strchr(path, '/') != NULL;
}

FILE *
__wrap_fopen(const char *path, const char *mode)
{
    if (outside_rundir(path))
    {
	errno = ENOENT;
	return NULL;
    }
    return __real_fopen(path, mode);
}

int
__wrap_unlink(const char *path)
{
    if (outside_rundir(path))
    {
	errno = ENOENT;
	return -1;
    }
    return __real_unlink(path);
}

int
__wrap_chmod(const char *path, mode_t mode)
{
    if (outside_rundir(path))
    {
	errno = ENOENT;
	return -1;
    }
    return __real_chmod(path, mode);
}

/*
 * A crash of the C game (a NULL dereference: see docs/FIDELITY.md) is logged
 * as "EXIT 128+signal", like a shell reports it; the port exits with the
 * same status at the same point.  setup() resets the signals to SIG_DFL, so
 * the handlers are installed again after it.
 */
static void
crashed(int sig)
{
    if (dumpf != NULL)
    {
	fprintf(dumpf, "EXIT %d\n", 128 + sig);
	fflush(dumpf);
    }
    fflush(stdout);
    _exit(128 + sig);
}

static void
catch_crashes(void)
{
    signal(SIGSEGV, crashed);
    signal(SIGBUS, crashed);
    signal(SIGFPE, crashed);
    signal(SIGILL, crashed);
}

__attribute__((constructor)) static void
hooks_init(void)
{
    catch_crashes();
}

extern void __real_md_onsignal_default(void);

void
__wrap_md_onsignal_default(void)
{
    __real_md_onsignal_default();
    catch_crashes();
}

/*
 * conn()'s door-picking loops spin forever when a maze room has no passage
 * square on the side the door must go (oracle.patch, passages.c).  After
 * 10000 tries the game ends; the port does the same (docs/FIDELITY.md).
 */
void
oracle_stuck(void)
{
    endwin();
    printf("\nrogue: the level generator is stuck (a hang in Rogue 5.4.4); the game cannot continue.\n");
    exit(1);
}

/* free is a no-op: use-after-free reads see intact objects, like the GC'd port */
void __wrap_free(void *p) { (void) p; }

void
__wrap_exit(int code)
{
    fprintf(dump(), "EXIT %d\n", code);
    fflush(dumpf);
    fflush(stdout);
    __real_exit(code);
}

/* ORACLE: bounds-checked map access (see oracle.patch, rogue.h) */
PLACE *
oracle_place(int y, int x)
{
    static PLACE dummy;
    long idx = (long) x * 32 + y;

    if (idx >= 0 && idx < MAXLINES * MAXCOLS)
	return &places[idx];
    dummy.p_ch = ' ';
    dummy.p_flags = 0;
    dummy.p_monst = NULL;
    return &dummy;
}
