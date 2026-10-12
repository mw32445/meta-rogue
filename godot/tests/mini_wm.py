#!/usr/bin/env python3
"""A minimal X11 window manager for the UI tests under Xvfb (needs only libX11).

Xvfb has no window manager, and an X11 program goes fullscreen by asking the window
manager (the EWMH _NET_WM_STATE_FULLSCREEN request): without one, Godot's fullscreen
modes do nothing there. This window manager does what the video tests need and no more:
  - it maps windows and grants their move and resize requests (no decorations);
  - on a fullscreen request it makes the window cover its monitor (Xinerama) and sets
    _NET_WM_STATE; leaving fullscreen restores the window's previous geometry;
  - --workarea=X,Y,W,H publishes _NET_WORKAREA, the usable area a desktop panel
    leaves (Godot's DisplayServer.screen_get_usable_rect());
  - --monitors=WxH+X+Y,... splits the screen into several monitors (RandR 1.5
    monitors, which Xinerama reports, so Godot sees one screen per monitor).

usage: DISPLAY=:N python3 godot/tests/mini_wm.py [--workarea=0,0,1920,1040]
           [--monitors=1920x1080+0+0,1280x1024+1920+0] [--daemon]
It runs until the X server goes away. With --daemon it goes to the background once
it manages the display (so what starts next finds it ready). godot/tests/
with_display.sh starts it.
"""
import ctypes
import os
import re
import sys

X = ctypes.cdll.LoadLibrary("libX11.so.6")
try:
    XINERAMA = ctypes.cdll.LoadLibrary("libXinerama.so.1")
except OSError:
    XINERAMA = None
try:
    XRANDR = ctypes.cdll.LoadLibrary("libXrandr.so.2")
except OSError:
    XRANDR = None

c_int, c_uint, c_long, c_ulong, c_void_p = (ctypes.c_int, ctypes.c_uint, ctypes.c_long,
                                            ctypes.c_ulong, ctypes.c_void_p)


def _head(*fields):
    return [("type", c_int), ("serial", c_ulong), ("send_event", c_int),
            ("display", c_void_p)] + list(fields)


class XMapRequestEvent(ctypes.Structure):
    _fields_ = _head(("parent", c_ulong), ("window", c_ulong))


class XConfigureRequestEvent(ctypes.Structure):
    _fields_ = _head(("parent", c_ulong), ("window", c_ulong), ("x", c_int), ("y", c_int),
                     ("width", c_int), ("height", c_int), ("border_width", c_int),
                     ("above", c_ulong), ("detail", c_int), ("value_mask", c_ulong))


class XClientMessageEvent(ctypes.Structure):
    _fields_ = _head(("window", c_ulong), ("message_type", c_ulong), ("format", c_int),
                     ("l", c_long * 5))


class XEvent(ctypes.Union):
    _fields_ = [("type", c_int), ("xmaprequest", XMapRequestEvent),
                ("xconfigurerequest", XConfigureRequestEvent), ("xclient", XClientMessageEvent),
                ("pad", c_long * 24)]


class XWindowChanges(ctypes.Structure):
    _fields_ = [("x", c_int), ("y", c_int), ("width", c_int), ("height", c_int),
                ("border_width", c_int), ("sibling", c_ulong), ("stack_mode", c_int)]


class XineramaScreenInfo(ctypes.Structure):
    _fields_ = [("screen_number", c_int), ("x_org", ctypes.c_short), ("y_org", ctypes.c_short),
                ("width", ctypes.c_short), ("height", ctypes.c_short)]


class XRRMonitorInfo(ctypes.Structure):
    _fields_ = [("name", c_ulong), ("primary", c_int), ("automatic", c_int), ("noutput", c_int),
                ("x", c_int), ("y", c_int), ("width", c_int), ("height", c_int),
                ("mwidth", c_int), ("mheight", c_int), ("outputs", ctypes.POINTER(c_ulong))]


MAP_REQUEST, CONFIGURE_REQUEST, CLIENT_MESSAGE = 20, 23, 33
SUBSTRUCTURE_NOTIFY, SUBSTRUCTURE_REDIRECT = 1 << 19, 1 << 20
CW_X, CW_Y, CW_WIDTH, CW_HEIGHT = 1, 2, 4, 8
XA_ATOM, XA_CARDINAL = 4, 6
NET_WM_STATE_REMOVE, NET_WM_STATE_ADD, NET_WM_STATE_TOGGLE = 0, 1, 2

X.XOpenDisplay.restype = c_void_p
X.XOpenDisplay.argtypes = [ctypes.c_char_p]
X.XDefaultRootWindow.restype = c_ulong
X.XDefaultRootWindow.argtypes = [c_void_p]
X.XDefaultScreen.argtypes = [c_void_p]
X.XDisplayWidth.argtypes = [c_void_p, c_int]
X.XDisplayHeight.argtypes = [c_void_p, c_int]
X.XInternAtom.restype = c_ulong
X.XInternAtom.argtypes = [c_void_p, ctypes.c_char_p, c_int]
X.XSelectInput.argtypes = [c_void_p, c_ulong, c_long]
X.XNextEvent.argtypes = [c_void_p, ctypes.POINTER(XEvent)]
X.XMapWindow.argtypes = [c_void_p, c_ulong]
X.XSetInputFocus.argtypes = [c_void_p, c_ulong, c_int, c_ulong]
X.XConfigureWindow.argtypes = [c_void_p, c_ulong, c_uint, ctypes.POINTER(XWindowChanges)]
X.XMoveResizeWindow.argtypes = [c_void_p, c_ulong, c_int, c_int, c_uint, c_uint]
X.XGetGeometry.argtypes = [c_void_p, c_ulong, ctypes.POINTER(c_ulong), ctypes.POINTER(c_int),
                           ctypes.POINTER(c_int), ctypes.POINTER(c_uint), ctypes.POINTER(c_uint),
                           ctypes.POINTER(c_uint), ctypes.POINTER(c_uint)]
X.XChangeProperty.argtypes = [c_void_p, c_ulong, c_ulong, c_ulong, c_int, c_int, c_void_p, c_int]
X.XSync.argtypes = [c_void_p, c_int]
X.XFlush.argtypes = [c_void_p]
ERROR_HANDLER = ctypes.CFUNCTYPE(c_int, c_void_p, c_void_p)
X.XSetErrorHandler.argtypes = [ERROR_HANDLER]
if XINERAMA is not None:
    XINERAMA.XineramaIsActive.argtypes = [c_void_p]
    XINERAMA.XineramaQueryScreens.restype = ctypes.POINTER(XineramaScreenInfo)
    XINERAMA.XineramaQueryScreens.argtypes = [c_void_p, ctypes.POINTER(c_int)]
if XRANDR is not None:
    XRANDR.XRRGetMonitors.restype = ctypes.POINTER(XRRMonitorInfo)
    XRANDR.XRRGetMonitors.argtypes = [c_void_p, c_ulong, c_int, ctypes.POINTER(c_int)]
    XRANDR.XRRSetMonitor.argtypes = [c_void_p, c_ulong, ctypes.POINTER(XRRMonitorInfo)]


@ERROR_HANDLER
def _ignore_errors(_display, _event):
    return 0	# a window that went away before we handled its request


IO_ERROR_HANDLER = ctypes.CFUNCTYPE(c_int, c_void_p)
X.XSetIOErrorHandler.argtypes = [IO_ERROR_HANDLER]


@IO_ERROR_HANDLER
def _server_gone(_display):
    os._exit(0)	# the X server went away: the test is over


class WindowManager:
    def __init__(self, workarea, monitors):
        self.d = X.XOpenDisplay(None)
        if not self.d:
            sys.exit("mini_wm: cannot open the display")
        X.XSetErrorHandler(_ignore_errors)
        X.XSetIOErrorHandler(_server_gone)
        self.root = X.XDefaultRootWindow(self.d)
        self.atom = lambda name: X.XInternAtom(self.d, name.encode(), 0)
        self.wm_state = self.atom("_NET_WM_STATE")
        self.fullscreen = self.atom("_NET_WM_STATE_FULLSCREEN")
        self.saved = {}	# window -> geometry before fullscreen
        X.XSelectInput(self.d, self.root, SUBSTRUCTURE_REDIRECT | SUBSTRUCTURE_NOTIFY)
        self._set_atoms(self.root, "_NET_SUPPORTED", [self.wm_state, self.fullscreen])
        if workarea:
            self._set_cardinals(self.root, "_NET_WORKAREA", workarea)
        if monitors:
            self._split(monitors)
        X.XSync(self.d, 0)

    def _split(self, monitors):
        """One RandR monitor per (x, y, w, h); the first takes over the screen's output."""
        if XRANDR is None:
            sys.exit("mini_wm: --monitors needs libXrandr")
        n = c_int()
        auto = XRANDR.XRRGetMonitors(self.d, self.root, 0, ctypes.byref(n))
        if not auto or n.value < 1 or auto[0].noutput < 1:
            sys.exit("mini_wm: the X server has no RandR output to split")
        output = (c_ulong * 1)(auto[0].outputs[0])
        for i, (x, y, w, h) in enumerate(monitors):
            info = XRRMonitorInfo(self.atom("MONITOR-%d" % (i + 1)), 1 if i == 0 else 0, 0,
                                  1 if i == 0 else 0, x, y, w, h, w * 254 // 960, h * 254 // 960,
                                  output if i == 0 else None)
            XRANDR.XRRSetMonitor(self.d, self.root, ctypes.byref(info))

    def _set_atoms(self, w, name, atoms):
        data = (c_long * max(1, len(atoms)))(*atoms)
        X.XChangeProperty(self.d, w, self.atom(name), XA_ATOM, 32, 0, data, len(atoms))

    def _set_cardinals(self, w, name, values):
        data = (c_long * len(values))(*values)
        X.XChangeProperty(self.d, w, self.atom(name), XA_CARDINAL, 32, 0, data, len(values))

    def geometry(self, w):
        root, x, y = c_ulong(), c_int(), c_int()
        width, height, border, depth = c_uint(), c_uint(), c_uint(), c_uint()
        X.XGetGeometry(self.d, w, ctypes.byref(root), ctypes.byref(x), ctypes.byref(y),
                       ctypes.byref(width), ctypes.byref(height), ctypes.byref(border),
                       ctypes.byref(depth))
        return x.value, y.value, width.value, height.value

    def monitors(self):
        if XINERAMA is not None and XINERAMA.XineramaIsActive(self.d):
            n = c_int()
            info = XINERAMA.XineramaQueryScreens(self.d, ctypes.byref(n))
            if info and n.value > 0:
                return [(info[i].x_org, info[i].y_org, info[i].width, info[i].height)
                        for i in range(n.value)]
        s = X.XDefaultScreen(self.d)
        return [(0, 0, X.XDisplayWidth(self.d, s), X.XDisplayHeight(self.d, s))]

    def monitor_of(self, w):
        x, y, width, height = self.geometry(w)
        cx, cy = x + width // 2, y + height // 2
        mons = self.monitors()
        for m in mons:
            if m[0] <= cx < m[0] + m[2] and m[1] <= cy < m[1] + m[3]:
                return m
        return mons[0]

    def set_fullscreen(self, w, on):
        if on == (w in self.saved):
            return
        if on:
            self.saved[w] = self.geometry(w)
            X.XMoveResizeWindow(self.d, w, *self.monitor_of(w))
            self._set_atoms(w, "_NET_WM_STATE", [self.fullscreen])
        else:
            X.XMoveResizeWindow(self.d, w, *self.saved.pop(w))
            self._set_atoms(w, "_NET_WM_STATE", [])

    def run(self):
        ev = XEvent()
        while True:
            X.XNextEvent(self.d, ctypes.byref(ev))	# _server_gone() ends it
            if ev.type == MAP_REQUEST:
                w = ev.xmaprequest.window
                X.XMapWindow(self.d, w)
                X.XSetInputFocus(self.d, w, 1, 0)	# RevertToPointerRoot, CurrentTime
            elif ev.type == CONFIGURE_REQUEST:
                r = ev.xconfigurerequest
                if r.window in self.saved:
                    continue	# a fullscreen window keeps covering its monitor
                ch = XWindowChanges(r.x, r.y, r.width, r.height, r.border_width, r.above, r.detail)
                X.XConfigureWindow(self.d, r.window, r.value_mask & 0x7F, ctypes.byref(ch))
            elif ev.type == CLIENT_MESSAGE and ev.xclient.message_type == self.wm_state:
                c = ev.xclient
                if self.fullscreen in (c.l[1], c.l[2]):
                    on = {NET_WM_STATE_REMOVE: False, NET_WM_STATE_ADD: True}.get(
                        c.l[0], c.window not in self.saved)
                    self.set_fullscreen(c.window, on)
            X.XFlush(self.d)


def main():
    workarea = None
    monitors = []
    daemon = False
    for a in sys.argv[1:]:
        if a == "--daemon":
            daemon = True
        elif a.startswith("--workarea="):
            workarea = [int(v) for v in a[len("--workarea="):].split(",")]
            if len(workarea) != 4:
                sys.exit("mini_wm: --workarea=X,Y,W,H")
        elif a.startswith("--monitors="):
            for m in a[len("--monitors="):].split(","):
                g = re.fullmatch(r"(\d+)x(\d+)\+(\d+)\+(\d+)", m)
                if not g:
                    sys.exit("mini_wm: --monitors=WxH+X+Y,...")
                w, h, x, y = (int(v) for v in g.groups())
                monitors.append((x, y, w, h))
        else:
            sys.exit(__doc__)
    wm = WindowManager(workarea, monitors)	# managing the display from here on
    if daemon:
        if os.fork() != 0:
            os._exit(0)	# the child keeps the connection
        null = os.open(os.devnull, os.O_RDWR)
        for fd in (0, 1, 2):	# let go of the caller's terminal and pipes
            os.dup2(null, fd)
    wm.run()


if __name__ == "__main__":
    main()
