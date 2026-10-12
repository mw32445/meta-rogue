/*
 * harness/curses_fuzz/cfuzz.c
 *
 * Reference side of the curses differential fuzzer: executes an op script
 * against real ncurses (newterm on /dev/null, 24x80) and prints the result of
 * every op.  godot/tests/curses_fuzz.gd runs the same script on the GDScript
 * emulation; harness/curses_fuzz/run.py compares the outputs.
 *
 * Window ids: 0 = stdscr, 1 = curscr, 2.. = created by newwin/subwin.
 * Op lines (whitespace separated, ints decimal, strings as hex bytes):
 *   newwin ID LINES COLS BEGY BEGX      subwin ID PARENT LINES COLS BEGY BEGX
 *   delwin ID          wmove ID Y X      waddch ID CH      waddstr ID HEX
 *   mvwaddch ID Y X CH   mvwaddstr ID Y X HEX   wclrtoeol ID   werase ID
 *   wclear ID   touchwin ID   wrefresh ID   clearok ID B   leaveok ID B
 *   wstandout ID   wstandend ID   wattrset ID A   winch ID   mvwinch ID Y X
 *   getyx ID   mvwin ID Y X   getch ID (wgetch's implicit refresh only)
 *   dump (curscr cells + cursor)   wdump ID (a window's own cells)
 */
#define NCURSES_INTERNALS 1
#include <curses.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAXW 64
static WINDOW *win[MAXW];

static char *
unhex(const char *h)
{
    static char buf[4096];
    size_t n = 0;
    unsigned v;

    while (h[0] && h[1] && n < sizeof buf - 1 && sscanf(h, "%2x", &v) == 1)
    {
	buf[n++] = (char) v;
	h += 2;
    }
    buf[n] = '\0';
    return buf;
}

static void
dump_cells(WINDOW *w, const char *tag)
{
    short flags = w->_flags;
    int cy = w->_cury, cx = w->_curx, y, x, maxy = getmaxy(w), maxx = getmaxx(w);

    printf("%s %d,%d", tag, cy, cx);
    for (y = 0; y < maxy; y++)
    {
	printf("\n ");
	for (x = 0; x < maxx; x++)
	    printf("%x ", (unsigned) mvwinch(w, y, x));
    }
    putchar('\n');
    w->_flags = flags;
    w->_cury = (NCURSES_SIZE_T) cy;
    w->_curx = (NCURSES_SIZE_T) cx;
}

int
main(int argc, char **argv)
{
    FILE *ops, *out = fopen("/dev/null", "w"), *in = fopen("/dev/null", "r");
    char line[8192], op[32], s[8192];
    int id, a, b, c, d, e, n, r;
    unsigned ch;

    if (argc < 2 || (ops = fopen(argv[1], "r")) == NULL)
    {
	fprintf(stderr, "usage: cfuzz OPS\n");
	return 2;
    }
    if (newterm(getenv("TERM") ? getenv("TERM") : "xterm", out, in) == NULL)
	return 3;
    win[0] = stdscr;
    win[1] = curscr;
    while (fgets(line, sizeof line, ops) != NULL)
    {
	if (sscanf(line, "%31s %n", op, &n) != 1 || op[0] == '#')
	    continue;
	r = 0;
	printf("%s", line);
	if (!strcmp(op, "newwin") && sscanf(line + n, "%d %d %d %d %d", &id, &a, &b, &c, &d) == 5)
	{
	    win[id] = newwin(a, b, c, d);
	    r = win[id] ? OK : ERR;
	}
	else if (!strcmp(op, "subwin") && sscanf(line + n, "%d %d %d %d %d %d", &id, &e, &a, &b, &c, &d) == 6)
	{
	    win[id] = subwin(win[e], a, b, c, d);
	    r = win[id] ? OK : ERR;
	}
	else if (!strcmp(op, "dump"))
	{
	    dump_cells(curscr, "=curscr");
	    continue;
	}
	else if (sscanf(line + n, "%d", &id) != 1 || id < 0 || id >= MAXW || win[id] == NULL)
	{
	    printf("=bad\n");
	    continue;
	}
	else if (!strcmp(op, "delwin"))
	{
	    r = delwin(win[id]);
	    win[id] = NULL;
	}
	else if (!strcmp(op, "wmove") && sscanf(line + n, "%d %d %d", &id, &a, &b) == 3)
	    r = wmove(win[id], a, b);
	else if (!strcmp(op, "waddch") && sscanf(line + n, "%d %u", &id, &ch) == 2)
	    r = waddch(win[id], (chtype) ch);
	else if (!strcmp(op, "waddstr") && sscanf(line + n, "%d %8191s", &id, s) == 2)
	    r = waddstr(win[id], unhex(s));
	else if (!strcmp(op, "mvwaddch") && sscanf(line + n, "%d %d %d %u", &id, &a, &b, &ch) == 4)
	    r = mvwaddch(win[id], a, b, (chtype) ch);
	else if (!strcmp(op, "mvwaddstr") && sscanf(line + n, "%d %d %d %8191s", &id, &a, &b, s) == 4)
	    r = mvwaddstr(win[id], a, b, unhex(s));
	else if (!strcmp(op, "wclrtoeol"))
	    r = wclrtoeol(win[id]);
	else if (!strcmp(op, "werase"))
	    r = werase(win[id]);
	else if (!strcmp(op, "wclear"))
	    r = wclear(win[id]);
	else if (!strcmp(op, "touchwin"))
	    r = touchwin(win[id]);
	else if (!strcmp(op, "wrefresh"))
	    r = wrefresh(win[id]);
	else if (!strcmp(op, "clearok") && sscanf(line + n, "%d %d", &id, &a) == 2)
	    r = clearok(win[id], a);
	else if (!strcmp(op, "leaveok") && sscanf(line + n, "%d %d", &id, &a) == 2)
	    r = leaveok(win[id], a);
	else if (!strcmp(op, "wstandout"))
	    r = wstandout(win[id]);
	else if (!strcmp(op, "wstandend"))
	    r = wstandend(win[id]);
	else if (!strcmp(op, "wattrset") && sscanf(line + n, "%d %d", &id, &a) == 2)
	    r = wattrset(win[id], a);
	else if (!strcmp(op, "winch"))
	{
	    printf("=%x\n", (unsigned) winch(win[id]));
	    continue;
	}
	else if (!strcmp(op, "mvwinch") && sscanf(line + n, "%d %d %d", &id, &a, &b) == 3)
	{
	    printf("=%x\n", (unsigned) mvwinch(win[id], a, b));
	    continue;
	}
	else if (!strcmp(op, "getyx"))
	{
	    getyx(win[id], a, b);
	    printf("=%d,%d\n", a, b);
	    continue;
	}
	else if (!strcmp(op, "mvwin") && sscanf(line + n, "%d %d %d", &id, &a, &b) == 3)
	    r = mvwin(win[id], a, b);
	else if (!strcmp(op, "getch"))
	{
	    /* wgetch's recur_wrefresh: refresh only if touched or the cursor moved */
	    WINDOW *w = win[id];
	    if (!(w->_flags & _ISPAD) && (is_wintouched(w) || (w->_flags & _HASMOVED)))
		r = wrefresh(w);
	    else
		r = 1;	/* "no refresh" */
	}
	else if (!strcmp(op, "wdump"))
	{
	    dump_cells(win[id], "=win");
	    continue;
	}
	else
	{
	    printf("=bad\n");
	    continue;
	}
	printf("=%d\n", r);
    }
    endwin();
    return 0;
}
