"""Generates docs/IsdaSafe_Admin_System_Diagrams.pdf: the admin panel's
system analysis & design diagrams, in the same style and order as the farmer
app's docs/IsdaSafe_System_Diagrams.pdf (IsdaSafeV2).

    py -3 tools/system_diagrams.py          (needs: pip install reportlab)
"""

import math
import os

from reportlab.lib.colors import HexColor, white
from reportlab.lib.pagesizes import A3, A4, landscape
from reportlab.pdfgen import canvas

OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "docs",
    "IsdaSafe_Admin_System_Diagrams.pdf",
)
BRAND = "IsdaSafe Admin - System Diagrams"

# Palette (matches the farmer PDF).
NAVY = HexColor("#1F3A5F")
TEAL = HexColor("#2B7A8B")
INK = HexColor("#1E2A33")
MUTED = HexColor("#5B6770")
LINE = HexColor("#2E3A44")
ENT_FILL, ENT_STROKE = HexColor("#FFF1D6"), HexColor("#5C4A26")
PROC_FILL, PROC_STROKE = HexColor("#DDEFF4"), HexColor("#2B7A8B")
STORE_FILL, STORE_STROKE = HexColor("#E8E8F4"), HexColor("#4B4F7A")
DFD_ENT = HexColor("#3D5A2A")
DFD_PROC = HexColor("#C55A11")
DFD_STORE = HexColor("#C9A23A")
FC_START = HexColor("#DFF0E0")
FC_PROC = HexColor("#DCEEF2")
FC_IO = HexColor("#FFF0D0")
FC_DEC = HexColor("#FBE3E8")
ST_GREEN = HexColor("#DFF0E0")
ST_BLUE = HexColor("#DCEEF2")
ST_RED = HexColor("#FBE3E8")
ST_GOLD = HexColor("#FFF0D0")
ST_LILAC = HexColor("#ECECF8")
ROW_ALT = HexColor("#F2F6F8")
WIRE_COLORS = [
    HexColor(h)
    for h in (
        "#1F3A5F", "#C55A11", "#2E7D32", "#7B1FA2", "#C62828",
        "#00838F", "#AD8B00", "#5D4037", "#3949AB", "#D81B60",
    )
]


class Page:
    """A canvas page with a top-left coordinate helper (y grows downward)."""

    def __init__(self, c, size):
        self.c = c
        self.W, self.H = size

    def Y(self, y):
        return self.H - y


# --------------------------------------------------------------------- basics

def text(p, x, y, s, size=8, color=INK, bold=False, italic=False, align="left"):
    c = p.c
    font = "Helvetica"
    if bold and italic:
        font = "Helvetica-BoldOblique"
    elif bold:
        font = "Helvetica-Bold"
    elif italic:
        font = "Helvetica-Oblique"
    c.setFont(font, size)
    c.setFillColor(color)
    if align == "center":
        c.drawCentredString(x, p.Y(y), s)
    elif align == "right":
        c.drawRightString(x, p.Y(y), s)
    else:
        c.drawString(x, p.Y(y), s)


def lines_in(p, cx, cy, lines, size=8, color=INK, bold=False, lead=None,
             align="center", x=None):
    """Vertically centred block of lines around (cx, cy)."""
    lead = lead or size * 1.25
    n = len(lines)
    top = cy - (n - 1) * lead / 2 + size * 0.35
    for i, s in enumerate(lines):
        b = bold if not isinstance(bold, (list, tuple)) else bold[i]
        if align == "center":
            text(p, cx, top + i * lead, s, size, color, b, align="center")
        else:
            text(p, x, top + i * lead, s, size, color, b)


def rect(p, x, y, w, h, fill=None, stroke=LINE, r=0, lw=0.8, dash=None):
    c = p.c
    c.setLineWidth(lw)
    c.setStrokeColor(stroke if stroke is not None else white)
    if dash:
        c.setDash(*dash)
    if fill is not None:
        c.setFillColor(fill)
    if r:
        c.roundRect(x, p.Y(y + h), w, h, r, stroke=1 if stroke else 0,
                    fill=1 if fill is not None else 0)
    else:
        c.rect(x, p.Y(y + h), w, h, stroke=1 if stroke else 0,
               fill=1 if fill is not None else 0)
    c.setDash()


def box(p, x, y, w, h, lines, fill, stroke=LINE, size=8, color=INK,
        bold=True, r=4, lw=0.9, sub=None):
    rect(p, x, y, w, h, fill, stroke, r, lw)
    if sub:
        # Title, then the smaller description under it, centred as a block.
        lt, ls = size * 1.25, (size - 1.5) * 1.25
        top = y + h / 2 - (len(lines) * lt + 3 + len(sub) * ls) / 2
        for i, s_ in enumerate(lines):
            text(p, x + w / 2, top + (i + 0.8) * lt, s_, size, color, bold,
                 align="center")
        st = top + len(lines) * lt + 3
        for j, s_ in enumerate(sub):
            text(p, x + w / 2, st + (j + 0.8) * ls, s_, size - 1.5,
                 MUTED if color == INK else color, align="center")
    else:
        lines_in(p, x + w / 2, y + h / 2, lines, size, color, bold)


def arrowhead(p, x1, y1, x2, y2, color=LINE, size=5):
    c = p.c
    ang = math.atan2(p.Y(y2) - p.Y(y1), x2 - x1)
    a1, a2 = ang + math.radians(155), ang - math.radians(155)
    path = c.beginPath()
    path.moveTo(x2, p.Y(y2))
    path.lineTo(x2 + size * math.cos(a1), p.Y(y2) + size * math.sin(a1))
    path.lineTo(x2 + size * math.cos(a2), p.Y(y2) + size * math.sin(a2))
    path.close()
    c.setFillColor(color)
    c.drawPath(path, stroke=0, fill=1)


def poly(p, pts, color=LINE, lw=0.7, head=True, tail=False, dash=None):
    c = p.c
    c.setStrokeColor(color)
    c.setLineWidth(lw)
    if dash:
        c.setDash(*dash)
    path = c.beginPath()
    path.moveTo(pts[0][0], p.Y(pts[0][1]))
    for x, y in pts[1:]:
        path.lineTo(x, p.Y(y))
    c.drawPath(path, stroke=1, fill=0)
    c.setDash()
    if head:
        arrowhead(p, *pts[-2], *pts[-1], color)
    if tail:
        arrowhead(p, *pts[1], *pts[0], color)


def header(p, title, subtitle):
    rect(p, 0, 0, p.W, 48, NAVY, None)
    text(p, 30, 31, title, 17, white, bold=True)
    text(p, p.W - 30, 30, BRAND, 8, white, align="right")
    text(p, 30, 66, subtitle, 8, MUTED, italic=True)


def footer(p, n, legend=()):
    text(p, p.W - 30, p.H - 18, f"Page {n}", 7.5, MUTED, align="right")
    x = 30
    for kind, fill, stroke, label in legend:
        y = p.H - 26
        if kind == "box":
            rect(p, x, y, 11, 7, fill, stroke, 0, 0.6)
        elif kind == "dash":
            rect(p, x, y, 11, 7, None, stroke, 0, 0.6, dash=(2, 2))
        elif kind == "dec":
            c = p.c
            c.setFillColor(fill)
            c.setStrokeColor(stroke)
            path = c.beginPath()
            path.moveTo(x + 5.5, p.Y(y - 1))
            path.lineTo(x + 11, p.Y(y + 3.5))
            path.lineTo(x + 5.5, p.Y(y + 8))
            path.lineTo(x, p.Y(y + 3.5))
            path.close()
            c.drawPath(path, stroke=1, fill=1)
        elif kind == "circle":
            c = p.c
            c.setFillColor(white)
            c.setStrokeColor(stroke)
            c.circle(x + 5.5, p.Y(y + 3.5), 4.5, stroke=1, fill=1)
        text(p, x + 15, y + 6.5, label, 7, MUTED)
        x += 22 + len(label) * 3.6


# ------------------------------------------------------------- DFD helpers

def dfd_process(p, x, y, w, h, pid, lines, size=8.5):
    rect(p, x, y, w, h, DFD_PROC, None, 6)
    text(p, x + w / 2, y + 13, pid, 8, white, bold=True, align="center")
    c = p.c
    c.setStrokeColor(white)
    c.setLineWidth(0.6)
    c.line(x, p.Y(y + 18), x + w, p.Y(y + 18))
    lines_in(p, x + w / 2, y + 18 + (h - 18) / 2, lines, size, white, True)


def dfd_store(p, x, y, w, h, sid, name):
    rect(p, x, y, w, h, DFD_STORE, None)
    c = p.c
    c.setStrokeColor(white)
    c.setLineWidth(0.8)
    c.line(x + 26, p.Y(y), x + 26, p.Y(y + h))
    text(p, x + 13, y + h / 2 + 3, sid, 7.5, white, bold=True, align="center")
    lines_in(p, x + 26 + (w - 26) / 2, y + h / 2, name.split("\n"), 7.5,
             white, False)


def dfd_entity(p, x, y, w, h, lines):
    rect(p, x, y, w, h, DFD_ENT, None)
    lines_in(p, x + w / 2, y + h / 2, lines, 8.5, white, True)


def elbow(p, x1, y1, x2, y2, lane, label=None, label_at="end", color=LINE,
          label_side=None):
    """x1,y1 -> lane -> x2,y2 with an arrowhead at the end."""
    pts = [(x1, y1), (lane, y1), (lane, y2), (x2, y2)]
    if abs(y1 - y2) < 0.5:
        pts = [(x1, y1), (x2, y2)]
    poly(p, pts, color)
    if label:
        if label_at == "end":
            lx, ly = x2, y2
        else:
            lx, ly = x1, y1
        side = label_side or ("right" if lx > lane else "left")
        if side == "right":
            text(p, lx - 4, ly - 2.5, label, 6, INK, align="right")
        else:
            text(p, lx + 4, ly - 2.5, label, 6, INK)


# ===================================================================== pages

def page_cover(c, n):
    p = Page(c, landscape(A4))
    rect(p, 0, 0, p.W, p.H, NAVY, None)
    text(p, 60, 130, "IsdaSafe Admin", 30, white, bold=True)
    text(p, 60, 160, "Admin Panel of the Pond Water Quality Monitoring System",
         15, white)
    text(p, 60, 182,
         "System analysis & design diagrams - admin side (companion to the "
         "farmer app's IsdaSafe System Diagrams)", 9.5, HexColor("#C9D6E3"),
         italic=True)
    items = [
        ("Context Diagram",
         "The admin panel as one process and the outside parties it talks to."),
        ("Level 0 Data Flow Diagram",
         "The admin panel broken into its five major processes and data stores."),
        ("Child Diagrams (Processes 1.0 - 5.0)",
         "Each Level 0 process exploded into its sub-processes."),
        ("State Transition Diagrams",
         "Life cycle of an admin account and of an admin's session at the login gate."),
        ("Flowchart",
         "The whole panel step by step: register, verify, approval, monitoring, trends, settings."),
        ("Entity Relationship Diagram",
         "The admin tables and the shared farmer tables the panel reads, and how they relate."),
        ("Data Dictionary",
         "Every column of the admin tables, plus the database functions and triggers."),
        ("Software Block Diagram",
         "The admin software split into its major blocks: app, cloud backend and outside services."),
        ("Software Schematic Diagram",
         "Every screen, service, backend function and outside service wired together, plus an interface list."),
    ]
    y = 218
    for i, (t, d) in enumerate(items, 1):
        c.setFillColor(TEAL)
        c.circle(73, p.Y(y + 4), 11, stroke=0, fill=1)
        text(p, 73, y + 7.5, str(i), 9, white, bold=True, align="center")
        text(p, 97, y + 1, t, 11, white, bold=True)
        text(p, 97, y + 13, d, 7.5, HexColor("#C9D6E3"))
        y += 32
    text(p, 60, 535,
         "Context diagram: Yourdon/DeMarco notation. Level 0 and child DFDs: "
         "Gane & Sarson notation. ERD: crow's-foot notation. Block & schematic "
         "diagrams: software architecture view.", 7, HexColor("#8FA6BD"),
         italic=True)
    text(p, 60, 547,
         "The admin panel shares the IsdaSafe Supabase project with the farmer "
         "app: farmer tables are written by the farmer app and only read here.",
         7, HexColor("#8FA6BD"), italic=True)
    c.showPage()


def page_context(c, n):
    p = Page(c, landscape(A4))
    header(p, "1. Context Diagram",
           "Shows the IsdaSafe Admin Panel as a single process (0) and every "
           "external entity that sends data to it or receives data from it.")
    cx, cy, r = 421, 315, 92
    c.setFillColor(PROC_FILL)
    c.setStrokeColor(LINE)
    c.setLineWidth(1)
    c.circle(cx, p.Y(cy), r, stroke=1, fill=1)
    text(p, cx, cy - 40, "0", 12, TEAL, bold=True, align="center")
    lines_in(p, cx, cy + 6, ["IsdaSafe", "Admin Panel"], 12, INK, True)
    lines_in(p, cx, cy + 40, ["(web & Android)"], 8, MUTED)

    ents = {
        "admin": (60, 290, ["Administrator", "(approved admin)"]),
        "farm": (60, 100, ["IsdaSafe Farmer App", "(shared database)"]),
        "google": (60, 470, ["Google Sign-In", "(OAuth)"]),
        "turn": (640, 100, ["Cloudflare Turnstile", "(CAPTCHA)"]),
        "sms": (650, 225, ["SMS Gateway", "(Semaphore)"]),
        "mail": (650, 360, ["Email Service", "(Supabase Auth mailer)"]),
        "maps": (640, 470, ["Google Maps", "(map tiles)"]),
    }
    ew, eh = 135, 42
    for x, y, ls in ents.values():
        box(p, x, y, ew, eh, ls, ENT_FILL, ENT_STROKE, 8.5)

    def edge(key, inbound, outbound, off=7):
        x, y, _ = ents[key]
        ex, ey = x + ew / 2, y + eh / 2
        ang = math.atan2(ey - cy, ex - cx)
        # point on circle and on box edge
        px, py = cx + r * math.cos(ang), cy + r * math.sin(ang)
        bx = ex - math.cos(ang) * (ew / 2 + 2) if abs(math.cos(ang)) * eh > abs(
            math.sin(ang)) * ew else ex - math.cos(ang) * (eh / 2) / max(
                abs(math.sin(ang)), 0.01) * abs(math.sin(ang)) * 0 - 0
        # simpler: clamp to box rectangle
        t = min((ew / 2 + 1) / max(abs(math.cos(ang)), 1e-6),
                (eh / 2 + 1) / max(abs(math.sin(ang)), 1e-6))
        bx, by = ex - math.cos(ang) * t, ey - math.sin(ang) * t
        nx, ny = -math.sin(ang) * off, math.cos(ang) * off
        mx, my = (px + bx) / 2, (py + by) / 2
        if inbound:
            poly(p, [(bx + nx, by + ny), (px + nx, py + ny)])
            lines_in(p, mx + nx * 3.2, my + ny * 3.2, inbound, 6.3, INK)
        if outbound:
            poly(p, [(px - nx, py - ny), (bx - nx, by - ny)])
            lines_in(p, mx - nx * 3.2, my - ny * 3.2, outbound, 6.3, INK)

    edge("admin", ["Login & registration details, name,",
                   "birth date, phone, OTP codes,",
                   "approvals, filters & timeframe"],
         ["Dashboard, pond status, readings,", "trends & guidance,",
          "admin requests"], off=9)
    edge("farm", ["Ponds, devices, owners", "& sensor readings"], None)
    edge("google", ["Google identity", "(name, email)"],
         ["Sign-in request"])
    edge("turn", ["CAPTCHA token"], ["Challenge /", "token check"])
    edge("sms", ["Delivery result"], ["OTP SMS request"])
    edge("mail", None, ["Password-reset code,", "email-change link"])
    edge("maps", ["Map tiles"], ["Pond coordinates"])

    footer(p, n, [("box", ENT_FILL, ENT_STROKE, "External entity"),
                  ("box", PROC_FILL, LINE, "Process")])
    c.showPage()


# --- Level 0 ------------------------------------------------------------

L0_ENTITIES = {
    "Admin": (["Administrator"], 135),
    "Google": (["Google Sign-In"], 55),
    "Turnstile": (["Cloudflare", "Turnstile"], 50),
    "SMS": (["SMS Gateway", "(Semaphore)"], 55),
    "Email": (["Email Service"], 60),
    "Maps": (["Google Maps"], 50),
}
L0_STORES = [
    ("D1", "admins"), ("D2", "auth.users\n(logins)"), ("D3", "phone_otps"),
    ("D4", "otp_send_log"), ("D5", "profiles *"), ("D6", "ponds *"),
    ("D7", "devices *"), ("D8", "sensor_readings *"),
]
L0_PROCS = [
    ("1.0", ["Manage Admin", "Account"], [
        ("in", "Admin", "Registration details (name, birth date, phone)"),
        ("in", "Admin", "Login credentials"),
        ("out", "Admin", "Session & access status"),
        ("in", "Turnstile", "CAPTCHA token"),
        ("in", "Google", "Google identity"),
        ("out", "Email", "Password-reset code"),
    ], [
        ("out", "D2", "New login / password"),
        ("in", "D2", "Sign-in method"),
        ("out", "D1", "Admin request & profile"),
        ("in", "D1", "Admin profile & status"),
    ]),
    ("2.0", ["Verify Phone &", "Credentials"], [
        ("in", "Admin", "Phone number / OTP code"),
        ("in", "Admin", "New email / password"),
        ("out", "Admin", "Verification result"),
        ("out", "SMS", "OTP SMS"),
        ("out", "Email", "Email-change link"),
    ], [
        ("out", "D3", "OTP code hash"),
        ("in", "D3", "Stored OTP & attempts"),
        ("out", "D4", "OTP send record"),
        ("in", "D4", "Recent sends (rate limit)"),
        ("out", "D1", "Verified phone / email"),
        ("out", "D2", "New email / password"),
    ]),
    ("3.0", ["Review Admin", "Access"], [
        ("in", "Admin", "Approve / decline decision"),
        ("out", "Admin", "Admin requests & accounts"),
    ], [
        ("in", "D1", "Admin list"),
        ("out", "D1", "Updated status"),
    ]),
    ("4.0", ["Monitor Ponds"], [
        ("in", "Admin", "Search, filter & sort"),
        ("out", "Admin", "Pond cards, map & status"),
        ("out", "Maps", "Pond coordinates"),
        ("in", "Maps", "Map tiles"),
    ], [
        ("in", "D5", "Owner name, email, phone"),
        ("in", "D6", "Ponds & locations"),
        ("in", "D7", "Device & last seen"),
        ("in", "D8", "Latest readings"),
    ]),
    ("5.0", ["Analyze Pond", "Trends"], [
        ("in", "Admin", "Pond, timeframe & metric"),
        ("out", "Admin", "Trend charts, stats & guidance"),
    ], [
        ("in", "D7", "Paired device check"),
        ("in", "D8", "Reading history"),
    ]),
]


def page_level0(c, n):
    p = Page(c, landscape(A3))
    header(p, "2. Level 0 Data Flow Diagram",
           "Process 0 exploded into its five major processes (Gane & Sarson "
           "notation). Green = external entity, orange = process, gold = data "
           "store. * = farmer-app table, read only by the admin panel.")
    # Processes
    PX, PW = 560, 140
    proc_pos = {}
    y = 92
    for pid, name, left, right in L0_PROCS:
        slots = max(len(left), len(right))
        h = max(70, 18 + slots * 16 + 10)
        dfd_process(p, PX, y, PW, h, pid, name)
        proc_pos[pid] = (y, h)
        y += h + 30

    # Entities (left), spaced over the same height
    EX, EW = 40, 120
    ent_y = {}
    total = sum(v[1] for v in L0_ENTITIES.values())
    gap = (y - 92 - 30 - total) / (len(L0_ENTITIES) - 1)
    ey = 92
    for key, (ls, h) in L0_ENTITIES.items():
        dfd_entity(p, EX, ey, EW, h, ls)
        ent_y[key] = (ey, h)
        ey += h + gap

    # Stores (right)
    SX, SW, SH = 1010, 140, 32
    store_y = {}
    sgap = (y - 92 - 30 - SH * len(L0_STORES)) / (len(L0_STORES) - 1)
    sy = 92
    for sid, name in L0_STORES:
        dfd_store(p, SX, sy, SW, SH, sid, name)
        store_y[sid] = sy
        sy += SH + sgap

    # Left flows: entity <-> process
    ent_flows = {k: [] for k in L0_ENTITIES}
    left_list = []
    for pid, _, left, _ in L0_PROCS:
        py0, h = proc_pos[pid]
        for i, (d, ent, label) in enumerate(left):
            sy_ = py0 + 26 + i * 16
            left_list.append((pid, d, ent, label, sy_))
            ent_flows[ent].append(len(left_list) - 1)
    ent_slot = {}
    for ent, idxs in ent_flows.items():
        ey0, eh = ent_y[ent]
        for j, idx in enumerate(idxs):
            ent_slot[idx] = ey0 + eh * (j + 1) / (len(idxs) + 1)
    lanes = len(left_list)
    for k, (pid, d, ent, label, py_) in enumerate(left_list):
        # Lanes stay left of the labels written beside each process.
        lane = 190 + (k + 0.5) * ((PX - 175 - 190) / lanes)
        ey_ = ent_slot[k]
        if d == "in":
            elbow(p, EX + EW, ey_, PX, py_, lane, label)
        else:
            elbow(p, PX, py_, EX + EW, ey_, lane)
            text(p, PX - 4, py_ - 2.5, label, 6, INK, align="right")

    # Right flows: process <-> store
    right_list = []
    store_flows = {s: [] for s, _ in L0_STORES}
    for pid, _, _, right in L0_PROCS:
        py0, h = proc_pos[pid]
        for i, (d, sid, label) in enumerate(right):
            right_list.append((pid, d, sid, label, py0 + 26 + i * 16))
            store_flows[sid].append(len(right_list) - 1)
    store_slot = {}
    for sid, idxs in store_flows.items():
        for j, idx in enumerate(idxs):
            store_slot[idx] = store_y[sid] + SH * (j + 1) / (len(idxs) + 1)
    lanes = len(right_list)
    for k, (pid, d, sid, label, py_) in enumerate(right_list):
        lane = PX + PW + 150 + (k + 0.5) * (150 / lanes)
        sy_ = store_slot[k]
        if d == "out":
            elbow(p, PX + PW, py_, SX, sy_, lane)
        else:
            elbow(p, SX, sy_, PX + PW, py_, lane)
        text(p, PX + PW + 4, py_ - 2.5, label, 6, INK)

    text(p, 40, y + 4,
         "* D5-D8 are written by the IsdaSafe farmer app (see its own "
         "diagrams). The admin panel reads them only through admin_* database "
         "functions that first check the caller is an approved admin.",
         7, MUTED, italic=True)
    footer(p, n, [("box", DFD_ENT, DFD_ENT, "External entity"),
                  ("box", DFD_PROC, DFD_PROC, "Process"),
                  ("box", DFD_STORE, DFD_STORE, "Data store")])
    c.showPage()


# --- Child diagrams -----------------------------------------------------

def page_child(c, n, title, subtitle, procs, stores, between):
    """procs: [(id, [name lines], [(dir, entity, label)], [(dir, sid, label)])]
    stores: {sid: name}. between: labels on the arrows joining procs."""
    p = Page(c, landscape(A4))
    header(p, title, subtitle)
    PX, PW = 300, 130
    top, bottom = 88, p.H - 46
    hs = []
    for _, name, left, right in procs:
        hs.append(max(52, 22 + max(len(left), len(right), 1) * 13 + 6))
    gap = (bottom - top - sum(hs)) / max(len(procs) - 1, 1)
    gap = min(gap, 60)
    y = top
    pos = {}
    for (pid, name, left, right), h in zip(procs, hs):
        dfd_process(p, PX, y, PW, h, pid, name, 8)
        pos[pid] = (y, h)
        y += h + gap
    # between-process arrows
    for i in range(len(procs) - 1):
        if i < len(between) and between[i]:
            a, b = procs[i][0], procs[i + 1][0]
            ya, ha = pos[a]
            yb, _ = pos[b]
            poly(p, [(PX + PW / 2, ya + ha), (PX + PW / 2, yb)])
            text(p, PX + PW / 2 + 4, (ya + ha + yb) / 2 + 2, between[i], 6, INK)

    # left flows
    for pid, _, left, _ in procs:
        y0, h = pos[pid]
        for i, (d, ent, label) in enumerate(left):
            yy = y0 + 26 + i * 13
            if d == "in":
                poly(p, [(30, yy), (PX, yy)])
                text(p, 32, yy - 2.5, f"from {ent}", 6, DFD_ENT, italic=True)
            else:
                poly(p, [(PX, yy), (30, yy)])
                text(p, 40, yy - 2.5, f"to {ent}", 6, DFD_ENT, italic=True)
            text(p, PX - 4, yy - 2.5, label, 6, INK, align="right")

    # stores: placed at the y of the first process that uses them
    SX, SW, SH = 660, 130, 30
    placed = {}
    next_free = top
    for pid, _, _, right in procs:
        y0, h = pos[pid]
        for d, sid, label in right:
            if sid not in placed:
                sy = max(y0 + 6, next_free)
                placed[sid] = sy
                next_free = sy + SH + 10
    for sid, sy in placed.items():
        dfd_store(p, SX, sy, SW, SH, sid, stores[sid])
    uses = {sid: 0 for sid in placed}
    counts = {}
    for _, _, _, right in procs:
        for _, sid, _ in right:
            counts[sid] = counts.get(sid, 0) + 1
    k = 0
    total = sum(len(r) for _, _, _, r in procs)
    for pid, _, _, right in procs:
        y0, h = pos[pid]
        for i, (d, sid, label) in enumerate(right):
            yy = y0 + 26 + i * 13
            uses[sid] += 1
            sy = placed[sid] + SH * uses[sid] / (counts[sid] + 1)
            lane = PX + PW + 150 + (k + 0.5) * (70 / max(total, 1))
            k += 1
            if d == "out":
                elbow(p, PX + PW, yy, SX, sy, lane)
            else:
                elbow(p, SX, sy, PX + PW, yy, lane)
            text(p, PX + PW + 4, yy - 2.5, label, 6, INK)
    footer(p, n, [("box", DFD_PROC, DFD_PROC, "Process"),
                  ("box", DFD_STORE, DFD_STORE, "Data store")])
    c.showPage()


CHILDREN = [
    ("3. Child Diagram - Process 1.0: Manage Admin Account",
     "Explodes process 1.0 of the Level 0 DFD. External entities are not "
     "drawn: each arrow from the left edge names its entity at the open end.",
     [
         ("1.1", ["Check Email"], [
             ("in", "Administrator", "Email address"),
             ("out", "Administrator", "Existing-account notice"),
         ], [("in", "D2", "Sign-in method (email_sign_in_method)")]),
         ("1.2", ["Create Account"], [
             ("in", "Administrator", "Name, birth date (18+), phone, password"),
             ("in", "Cloudflare Turnstile", "CAPTCHA token"),
         ], [
             ("out", "D2", "New login"),
             ("out", "D1", "Pending request (on_admin_signup)"),
         ]),
         ("1.3", ["Log In"], [
             ("in", "Administrator", "Email & password"),
             ("in", "Google Sign-In", "Google identity"),
             ("out", "Administrator", "Login result"),
         ], [("in", "D2", "Signed-in user")]),
         ("1.4", ["Request Admin", "Access"], [
             ("in", "Administrator", "Name, phone, birth date, password"),
         ], [
             ("out", "D1", "Admin request (request_admin_access)"),
             ("out", "D2", "New password (Google accounts)"),
         ]),
         ("1.5", ["Complete Profile &", "Reset Password"], [
             ("in", "Administrator", "Missing name / birth date"),
             ("out", "Email Service", "Password-reset code"),
         ], [
             ("out", "D1", "Name & birth date"),
             ("in", "D1", "Admin profile & status"),
         ]),
     ],
     {"D1": "admins", "D2": "auth.users"},
     ["Email has no login", "New account", "Signed-in, no admin row",
      "Admin row"]),
    ("3. Child Diagram - Process 2.0: Verify Phone & Credentials",
     "Explodes process 2.0. Codes are texted by the shared send-semaphore-otp "
     "Edge Function and checked in the database, never on the device.",
     [
         ("2.1", ["Send OTP Code"], [
             ("in", "Administrator", "Phone number"),
             ("out", "SMS Gateway (Semaphore)", "OTP SMS"),
         ], [
             ("in", "D1", "Verified admin numbers"),
             ("in", "D4", "Recent sends (rate limit)"),
             ("out", "D4", "OTP send record"),
             ("out", "D3", "OTP code hash"),
         ]),
         ("2.2", ["Verify OTP Code"], [
             ("in", "Administrator", "6-digit OTP code"),
             ("out", "Administrator", "Verification result"),
         ], [
             ("in", "D3", "Stored OTP & attempts"),
             ("out", "D1", "Verified phone"),
         ]),
         ("2.3", ["Change Phone", "Number"], [
             ("in", "Administrator", "New number + its code"),
         ], [("out", "D1", "New verified phone (admin_change_phone)")]),
         ("2.4", ["Change Email"], [
             ("in", "Administrator", "New email"),
             ("out", "Email Service", "Confirmation link"),
         ], [
             ("out", "D2", "Confirmed email"),
             ("out", "D1", "Synced email (trigger)"),
         ]),
         ("2.5", ["Change Password"], [
             ("in", "Administrator", "OTP code + new password"),
             ("out", "Administrator", "Password updated"),
         ], [("out", "D2", "New password")]),
     ],
     {"D1": "admins", "D3": "phone_otps", "D4": "otp_send_log",
      "D2": "auth.users"},
     ["Code sent", "", "", ""]),
    ("3. Child Diagram - Process 3.0: Review Admin Access",
     "Explodes process 3.0. Every function first checks is_approved_admin(); "
     "nobody can change their own access, and the last approved admin can't "
     "leave.",
     [
         ("3.1", ["Check Approved", "Admin"], [], [
             ("in", "D1", "Caller's status (is_approved_admin)")]),
         ("3.2", ["List Admins &", "Requests"], [
             ("out", "Administrator", "Requests & accounts (name, age, phone)"),
         ], [("in", "D1", "All admin rows (admin_list_admins)")]),
         ("3.3", ["Approve /", "Decline"], [
             ("in", "Administrator", "Approve / decline decision"),
         ], [("out", "D1", "status, reviewed_by, reviewed_at")]),
         ("3.4", ["Leave Admin", "Access"], [
             ("in", "Administrator", "Leave request"),
         ], [
             ("in", "D1", "Other approved admins"),
             ("out", "D1", "Own row deleted (admin_leave)"),
         ]),
     ],
     {"D1": "admins"},
     ["Approved caller", "Selected request", "Own account"]),
    ("3. Child Diagram - Process 4.0: Monitor Ponds",
     "Explodes process 4.0. admin_monitored_ponds() joins every pond that has "
     "a paired device with its owner and latest reading.",
     [
         ("4.1", ["Load Monitored", "Ponds"], [], [
             ("in", "D6", "Ponds & locations"),
             ("in", "D7", "Device, paired & last seen"),
             ("in", "D5", "Owner name, email, phone"),
             ("in", "D8", "Latest reading"),
         ]),
         ("4.2", ["Classify Status &", "Connection"], [
             ("out", "Administrator", "Needs-attention count (sidebar)"),
         ], []),
         ("4.3", ["Filter, Sort &", "Search"], [
             ("in", "Administrator", "Filter, sort, search"),
             ("out", "Administrator", "Pond cards / list"),
         ], []),
         ("4.4", ["Show Pond Map"], [
             ("out", "Google Maps", "Pond coordinates"),
             ("in", "Google Maps", "Map tiles"),
             ("out", "Administrator", "Map pins by status"),
         ], []),
         ("4.5", ["Open Pond Page"], [
             ("in", "Administrator", "Selected pond"),
             ("out", "Administrator", "Status, latest readings, owner & device"),
         ], []),
     ],
     {"D6": "ponds", "D7": "devices", "D5": "profiles",
      "D8": "sensor_readings"},
     ["Pond rows", "Normal / Warning / Critical", "Ponds", "Chosen pond"]),
    ("3. Child Diagram - Process 5.0: Analyze Pond Trends",
     "Explodes process 5.0. admin_pond_reading_trend() groups readings into "
     "15-minute / hour / day / week / month / year steps on the server.",
     [
         ("5.1", ["Choose", "Timeframe"], [
             ("in", "Administrator", "Preset or custom range"),
         ], []),
         ("5.2", ["Load Trend", "Steps"], [], [
             ("in", "D7", "Paired device check"),
             ("in", "D8", "Readings in the window"),
         ]),
         ("5.3", ["Draw Charts &", "Summary"], [
             ("out", "Administrator", "Trend charts, lowest / average / highest"),
         ], []),
         ("5.4", ["Show Metric Detail", "& Guidance"], [
             ("in", "Administrator", "Selected reading"),
             ("out", "Administrator", "Detail view & what the farmer should do"),
         ], []),
         ("5.5", ["Page Readings", "Table"], [
             ("out", "Administrator", "Readings table, a page at a time"),
         ], []),
     ],
     {"D7": "devices", "D8": "sensor_readings"},
     ["Window & step", "Steps (avg / min / max)", "Chart tapped",
      "Same steps"]),
]


# --- State transition --------------------------------------------------------

def state(p, x, y, w, h, label, fill):
    box(p, x, y, w, h, [label], fill, TEAL, 9, INK, True, 9, 1.1)


def start_dot(p, x, y):
    p.c.setFillColor(INK)
    p.c.circle(x, p.Y(y), 6, stroke=0, fill=1)


def end_dot(p, x, y):
    c = p.c
    c.setStrokeColor(INK)
    c.setFillColor(white)
    c.setLineWidth(1.2)
    c.circle(x, p.Y(y), 7.5, stroke=1, fill=1)
    c.setFillColor(INK)
    c.circle(x, p.Y(y), 4.5, stroke=0, fill=1)


def page_states(c, n):
    p = Page(c, landscape(A4))
    header(p, "4. State Transition Diagrams",
           "Left: life cycle of an admin account (its admins.status). Right: "
           "the screens AdminGate walks a signed-in admin through.")
    c.setStrokeColor(HexColor("#C8CFD4"))
    c.setDash(3, 3)
    c.line(370, p.Y(80), 370, p.Y(545))
    c.setDash()
    text(p, 190, 95, "A. Admin Account", 10, NAVY, bold=True, align="center")
    text(p, 600, 95, "B. Admin Session (login gate)", 10, NAVY, bold=True,
         align="center")

    # A
    start_dot(p, 190, 120)
    state(p, 140, 190, 100, 34, "Pending", ST_GOLD)
    state(p, 30, 340, 100, 34, "Approved", ST_GREEN)
    state(p, 250, 340, 100, 34, "Rejected", ST_RED)
    end_dot(p, 80, 480)
    poly(p, [(190, 126), (190, 190)])
    lines_in(p, 240, 150, ["Registers or requests", "access"], 6.3)
    poly(p, [(184, 126), (60, 200), (60, 340)])
    lines_in(p, 66, 250, ["First admin ever", "(auto-approved)"], 6.3,
             align="left", x=66)
    poly(p, [(160, 224), (110, 340)])
    lines_in(p, 168, 296, ["Approved by an", "approved admin"], 6.3)
    poly(p, [(220, 224), (285, 340)])
    lines_in(p, 290, 268, ["Declined by an", "approved admin"], 6.3)
    poly(p, [(250, 352), (130, 352)])
    lines_in(p, 190, 343, ["Approved later"], 6.3)
    poly(p, [(130, 364), (250, 364)])
    lines_in(p, 190, 376, ["Access revoked"], 6.3)
    poly(p, [(80, 374), (80, 472)])
    lines_in(p, 140, 420, ["Leaves admin access", "(row deleted; not the",
                          "last approved admin)"], 6.3)
    poly(p, [(205, 224), (210, 232), (210, 480), (88, 480)])
    lines_in(p, 216, 440, ["Withdraws", "(leaves)"], 6.3, align="left",
             x=216)
    lines_in(p, 190, 515, ["A declined account can't clear its row and",
                          "request again; another admin must approve it."],
             6.5, MUTED)

    # B
    sx = 470
    start_dot(p, 600, 118)
    state(p, 545, 140, 110, 30, "Signed Out", ST_LILAC)
    state(p, 400, 205, 120, 30, "Requesting Access", ST_GOLD)
    state(p, 545, 205, 110, 30, "Signed In", ST_BLUE)
    state(p, 680, 205, 130, 30, "Resetting Password", ST_GOLD)
    state(p, 545, 275, 110, 30, "Completing Profile", ST_GOLD)
    state(p, 545, 345, 110, 30, "Verifying Phone", ST_GOLD)
    state(p, 400, 415, 120, 30, "Waiting Approval", ST_GOLD)
    state(p, 545, 415, 110, 30, "Dashboard", ST_GREEN)
    state(p, 690, 415, 110, 30, "Declined", ST_RED)
    poly(p, [(600, 124), (600, 140)])
    poly(p, [(600, 170), (600, 205)])
    lines_in(p, 640, 187, ["Log in / register"], 6.3)
    poly(p, [(545, 220), (520, 220)])
    lines_in(p, 470, 248, ["No admin row"], 6.3)
    poly(p, [(460, 205), (460, 192), (560, 192), (560, 205)])
    lines_in(p, 505, 186, ["Request filed"], 6.3)
    poly(p, [(655, 220), (680, 220)])
    lines_in(p, 668, 197, ["Reset", "code / link"], 6.3)
    poly(p, [(745, 205), (745, 155), (655, 155)])
    lines_in(p, 760, 180, ["New password", "saved"], 6.3, align="left", x=750)
    poly(p, [(600, 235), (600, 275)])
    lines_in(p, 660, 255, ["Name or birth", "date missing"], 6.3)
    poly(p, [(600, 305), (600, 345)])
    lines_in(p, 650, 325, ["Profile saved;", "phone unverified"], 6.3)
    poly(p, [(600, 375), (600, 415)])
    lines_in(p, 640, 395, ["Code correct", "& approved"], 6.3)
    poly(p, [(560, 375), (480, 415)])
    lines_in(p, 500, 388, ["Code correct", "& pending"], 6.3)
    poly(p, [(520, 438), (545, 438)])
    lines_in(p, 532, 462, ["Approved", "(Check again)"], 6.3)
    poly(p, [(655, 430), (690, 430)])
    lines_in(p, 672, 455, ["Declined"], 6.3)
    poly(p, [(800, 430), (828, 430), (828, 150), (655, 150)], dash=(2, 2))
    lines_in(p, 822, 300, ["Sign out", "(from any", "screen)"], 6.3,
             align="left", x=788)
    lines_in(p, 600, 500, ["Event / action notation: \"trigger / what the "
                          "system does\".",
                          "Each screen is chosen again on every sign-in from "
                          "the admin row (AdminGate)."], 6.5, MUTED)
    c.showPage()


# --- Flowcharts -------------------------------------------------------------

def fc_term(p, x, y, w, h, lines):
    box(p, x, y, w, h, lines, FC_START, HexColor("#3F7A47"), 7.5, INK, True,
        h / 2)


def fc_proc(p, x, y, w, h, lines):
    box(p, x, y, w, h, lines, FC_PROC, TEAL, 7.2, INK, False, 0)


def fc_io(p, x, y, w, h, lines):
    c = p.c
    k = 10
    c.setFillColor(FC_IO)
    c.setStrokeColor(HexColor("#A07A2A"))
    c.setLineWidth(0.8)
    path = c.beginPath()
    path.moveTo(x + k, p.Y(y))
    path.lineTo(x + w, p.Y(y))
    path.lineTo(x + w - k, p.Y(y + h))
    path.lineTo(x, p.Y(y + h))
    path.close()
    c.drawPath(path, stroke=1, fill=1)
    lines_in(p, x + w / 2, y + h / 2, lines, 7.2, INK)


def fc_dec(p, cx, cy, w, h, lines):
    c = p.c
    c.setFillColor(FC_DEC)
    c.setStrokeColor(HexColor("#A33A55"))
    c.setLineWidth(0.8)
    path = c.beginPath()
    path.moveTo(cx, p.Y(cy - h / 2))
    path.lineTo(cx + w / 2, p.Y(cy))
    path.lineTo(cx, p.Y(cy + h / 2))
    path.lineTo(cx - w / 2, p.Y(cy))
    path.close()
    c.drawPath(path, stroke=1, fill=1)
    lines_in(p, cx, cy, lines, 7, INK)


def fc_conn(p, cx, cy, letter):
    c = p.c
    c.setFillColor(white)
    c.setStrokeColor(INK)
    c.setLineWidth(0.9)
    c.circle(cx, p.Y(cy), 9, stroke=1, fill=1)
    text(p, cx, cy + 3, letter, 8, INK, bold=True, align="center")


def yes(p, x, y):
    text(p, x, y, "Yes", 6.8, TEAL, bold=True)


def no(p, x, y):
    text(p, x, y, "No", 6.8, HexColor("#B3261E"), bold=True)


FC_LEGEND = [("box", FC_START, HexColor("#3F7A47"), "Start / End"),
             ("box", FC_PROC, TEAL, "Process"),
             ("box", FC_IO, HexColor("#A07A2A"), "Input / Output"),
             ("dec", FC_DEC, HexColor("#A33A55"), "Decision"),
             ("circle", None, INK, "Connector (same letter = same point)")]


def page_flow1(c, n):
    p = Page(c, landscape(A4))
    header(p, "5. Flowchart (1 of 2) - Register, Log In & Get Approved",
           "From opening the admin panel to reaching the dashboard. Read top "
           "to bottom, left to right.")
    for t, x in [("Register", 105), ("Log in", 310),
                 ("Complete & verify", 515), ("Approval", 715)]:
        text(p, x, 88, t, 8.5, NAVY, bold=True, align="center")
    W = 150

    # Column 1 - register
    x = 105
    fc_term(p, x - 65, 98, 130, 26, ["START", "Open admin panel"])
    poly(p, [(x, 124), (x, 134)])
    fc_dec(p, x, 156, 120, 44, ["Has an", "account?"])
    yes(p, x + 62, 152)
    poly(p, [(x + 60, 156), (245, 156)])          # -> log in
    no(p, x + 4, 188)
    poly(p, [(x, 178), (x, 196)])
    fc_io(p, x - 75, 196, W, 36, ["Enter first & last name, birth",
                                 "date, email, phone, password"])
    poly(p, [(x, 232), (x, 244)])
    fc_dec(p, x, 266, 120, 44, ["18 or older?"])
    no(p, x - 76, 262)
    poly(p, [(x - 60, 266), (x - 88, 266), (x - 88, 214), (x - 72, 214)])
    lines_in(p, x - 70, 292, ["Show", "error"], 6.2)
    yes(p, x + 4, 298)
    poly(p, [(x, 288), (x, 306)])
    fc_dec(p, x, 330, 128, 48, ["Email already", "has a login?"])
    yes(p, x + 66, 326)
    poly(p, [(x + 64, 330), (225, 330), (225, 170), (242, 170)])
    lines_in(p, 210, 352, ["Use that", "account's", "password"], 6.2)
    no(p, x + 4, 364)
    poly(p, [(x, 354), (x, 372)])
    fc_proc(p, x - 75, 372, W, 34, ["Create login; database files a",
                                   "PENDING admin request"])
    poly(p, [(x, 406), (x, 420)])
    fc_conn(p, x, 430, "A")

    # Column 2 - log in
    x = 310
    fc_io(p, x - 75, 140, W, 36, ["Log in with email &",
                                 "password, or Google"])
    poly(p, [(x, 176), (x, 190)])
    fc_dec(p, x, 214, 124, 48, ["Credentials", "valid?"])
    no(p, x + 64, 210)
    poly(p, [(x + 62, 214), (405, 214), (405, 158), (x + 67, 158)])
    lines_in(p, 420, 186, ["Show", "error"], 6.2)
    yes(p, x + 4, 248)
    poly(p, [(x, 238), (x, 254)])
    fc_dec(p, x, 278, 124, 48, ["Has an", "admin row?"])
    yes(p, x + 64, 274)
    poly(p, [(x + 62, 278), (x + 82, 278)])
    fc_conn(p, x + 92, 278, "A")
    no(p, x + 4, 312)
    poly(p, [(x, 302), (x, 318)])
    fc_io(p, x - 75, 318, W, 40, ["Request access: name, birth",
                                 "date, phone (+ password for", "Google)"])
    poly(p, [(x, 358), (x, 372)])
    fc_proc(p, x - 75, 372, W, 34, ["Database files a PENDING", "admin request"])
    poly(p, [(x, 406), (x, 420)])
    fc_conn(p, x, 430, "A")

    # Column 3 - complete profile & verify phone
    x = 515
    fc_conn(p, x, 108, "A")
    poly(p, [(x, 117), (x, 128)])
    fc_dec(p, x, 152, 130, 48, ["Name & birth", "date on file?"])
    yes(p, x + 67, 148)
    poly(p, [(x + 65, 152), (x + 92, 152), (x + 92, 232), (x, 232)])
    no(p, x + 4, 184)
    poly(p, [(x, 176), (x, 190)])
    fc_io(p, x - 75, 190, W, 30, ["Complete profile:", "name & birth date"])
    poly(p, [(x, 220), (x, 246)])
    fc_dec(p, x, 270, 124, 48, ["Phone", "verified?"])
    yes(p, x + 64, 266)
    no(p, x + 4, 302)
    poly(p, [(x, 294), (x, 308)])
    fc_proc(p, x - 75, 308, W, 30, ["Text a 6-digit code",
                                   "(send-semaphore-otp)"])
    poly(p, [(x, 338), (x, 350)])
    fc_io(p, x - 75, 350, W, 26, ["Admin enters the code"])
    poly(p, [(x, 376), (x, 388)])
    fc_dec(p, x, 410, 120, 44, ["Code", "correct?"])
    no(p, x - 76, 406)
    poly(p, [(x - 60, 410), (x - 90, 410), (x - 90, 363), (x - 71, 363)])
    lines_in(p, x - 92, 436, ["Retry /", "resend"], 6.2)
    yes(p, x + 4, 442)
    poly(p, [(x, 432), (x, 446)])
    fc_proc(p, x - 75, 446, W, 26, ["Mark phone verified"])
    # both "verified" paths go to Approval
    poly(p, [(x + 62, 270), (620, 270), (620, 100), (715, 100), (715, 126)])
    poly(p, [(x, 472), (x, 484), (605, 484), (605, 270)], head=False)

    # Column 4 - approval
    x = 715
    fc_dec(p, x, 150, 110, 48, ["Approved?"])
    yes(p, x + 57, 146)
    poly(p, [(x + 55, 150), (798, 150)])
    fc_conn(p, 808, 150, "B")
    lines_in(p, 808, 173, ["Dashboard", "(next page)"], 6.3, MUTED)
    no(p, x + 4, 182)
    poly(p, [(x, 174), (x, 196)])
    fc_dec(p, x, 220, 110, 48, ["Declined?"])
    yes(p, x + 57, 216)
    poly(p, [(x + 55, 220), (764, 220), (764, 246)])
    fc_term(p, 730, 246, 84, 30, ["Access denied;", "sign out"])
    no(p, x + 4, 252)
    poly(p, [(x, 244), (x, 290)])
    fc_io(p, x - 65, 290, 130, 30, ["Waiting for approval", "screen"])
    poly(p, [(x, 320), (x, 334)])
    fc_proc(p, x - 65, 334, 130, 26, ["Admin taps Check again"])
    poly(p, [(x - 65, 347), (640, 347), (640, 150), (x - 55, 150)])
    footer(p, n, FC_LEGEND)
    c.showPage()


def page_flow2(c, n):
    p = Page(c, landscape(A4))
    header(p, "5. Flowchart (2 of 2) - Monitoring, Trends, Admins & Settings",
           "What an approved admin does in the panel, until signing out. "
           "Read top to bottom, left to right.")
    for t, x in [("Monitor ponds", 110), ("Pond page & trends", 315),
                 ("Review admins", 520), ("Settings & end", 715)]:
        text(p, x, 88, t, 8.5, NAVY, bold=True, align="center")
    W = 150

    # Column 1 - monitoring
    x = 110
    fc_conn(p, x, 108, "B")
    poly(p, [(x, 117), (x, 128)])
    fc_proc(p, x - 75, 128, W, 34, ["Load every pond with a paired",
                                   "device, every minute",
                                   "(admin_monitored_ponds)"])
    poly(p, [(x, 162), (x, 174)])
    fc_proc(p, x - 75, 174, W, 34, ["Classify: Normal / Warning /",
                                   "Critical, online / offline"])
    poly(p, [(x, 208), (x, 220)])
    fc_io(p, x - 75, 220, W, 34, ["Greeting, stat tiles, pond",
                                 "cards / list, map pins"])
    poly(p, [(x, 254), (x, 266)])
    fc_io(p, x - 75, 266, W, 30, ["Admin filters, sorts or", "searches"])
    poly(p, [(x, 296), (x, 310)])
    fc_dec(p, x, 334, 120, 48, ["Open a", "pond?"])
    yes(p, x + 62, 330)
    poly(p, [(x + 60, 334), (212, 334), (212, 146), (242, 146)])
    no(p, x + 4, 366)
    poly(p, [(x, 358), (x, 420)])
    fc_conn(p, x, 430, "C")
    lines_in(p, x, 375, [""], 6)

    # Column 2 - pond page & trends
    x = 315
    fc_io(p, x - 75, 128, W, 36, ["Pond page: status banner,",
                                 "latest readings, owner & device"])
    poly(p, [(x, 164), (x, 176)])
    fc_proc(p, x - 75, 176, W, 30, ["Choose timeframe (15 min ...",
                                   "yearly, or custom dates)"])
    poly(p, [(x, 206), (x, 218)])
    fc_proc(p, x - 75, 218, W, 30, ["Load trend steps",
                                   "(admin_pond_reading_trend)"])
    poly(p, [(x, 248), (x, 260)])
    fc_io(p, x - 75, 260, W, 30, ["Individual trend charts &",
                                 "readings table"])
    poly(p, [(x, 290), (x, 304)])
    fc_dec(p, x, 328, 124, 48, ["Tap a", "reading?"])
    no(p, x + 64, 324)
    poly(p, [(x + 62, 328), (x + 92, 328), (x + 92, 412), (x, 412)])
    yes(p, x + 4, 360)
    poly(p, [(x, 352), (x, 364)])
    fc_io(p, x - 75, 364, W, 36, ["Metric detail: value, range,",
                                 "what to do, trend & stats"])
    poly(p, [(x, 400), (x, 420)])
    fc_conn(p, x, 430, "C")

    # Column 3 - review admins
    x = 520
    fc_conn(p, x, 108, "C")
    poly(p, [(x, 117), (x, 128)])
    fc_dec(p, x, 152, 130, 48, ["Pending admin", "requests?"])
    no(p, x + 67, 148)
    poly(p, [(x + 65, 152), (x + 92, 152), (x + 92, 330), (x, 330)])
    yes(p, x + 4, 184)
    poly(p, [(x, 176), (x, 190)])
    fc_io(p, x - 75, 190, W, 34, ["Admins page: requests with",
                                 "email, phone & age"])
    poly(p, [(x, 224), (x, 236)])
    fc_dec(p, x, 258, 130, 44, ["Approve or", "decline"])
    poly(p, [(x, 280), (x, 290)])
    fc_proc(p, x - 75, 290, W, 30, ["Save status, reviewer & time",
                                   "(admin_set_status)"])
    poly(p, [(x, 320), (x, 420)])
    fc_conn(p, x, 430, "D")

    # Column 4 - settings & end
    x = 715
    fc_conn(p, x, 108, "D")
    poly(p, [(x, 117), (x, 128)])
    fc_dec(p, x, 152, 134, 48, ["Change phone,", "email or password?"])
    no(p, x + 69, 148)
    poly(p, [(x + 67, 152), (x + 92, 152), (x + 92, 286), (x, 286)])
    yes(p, x + 4, 184)
    poly(p, [(x, 176), (x, 190)])
    fc_proc(p, x - 75, 190, W, 44, ["Phone: code to the new number",
                                   "Email: confirmation link",
                                   "Password: code to phone first"])
    poly(p, [(x, 234), (x, 246)])
    fc_proc(p, x - 75, 246, W, 26, ["Save the change"])
    poly(p, [(x, 272), (x, 300)])
    fc_dec(p, x, 324, 110, 48, ["Sign out?"])
    no(p, x - 57, 320)
    poly(p, [(x - 55, 324), (x - 92, 324), (x - 92, 108), (x - 9, 108)])
    lines_in(p, x - 92, 350, ["Keep working", "(back to D;", "B from the", "sidebar)"],
             6.2, MUTED)
    yes(p, x + 4, 356)
    poly(p, [(x, 348), (x, 366)])
    fc_term(p, x - 60, 366, 120, 30, ["END", "Signed out"])
    footer(p, n, FC_LEGEND)
    c.showPage()


# --- ERD ----------------------------------------------------------------

def erd_table(p, x, y, w, name, rows, read_only=False):
    """rows: [(key, column)]. Returns (x, y, w, h)."""
    rh = 12.3
    head = NAVY if not read_only else HexColor("#5A6B7A")
    rect(p, x, y, w, 17, head, None)
    text(p, x + w / 2, y + 12, name, 7.8, white, bold=True, align="center")
    for i, (key, col) in enumerate(rows):
        ry = y + 17 + i * rh
        rect(p, x, ry, w, rh, ROW_ALT if i % 2 else white, None)
        kc = HexColor("#C77C02") if "PK" in key else TEAL
        text(p, x + 5, ry + 8.8, key, 6.3, kc, bold=True)
        text(p, x + 38, ry + 8.8, col, 6.6, INK, bold=key.startswith("PK"))
    h = 17 + len(rows) * rh
    rect(p, x, y, w, h, None, NAVY, 0, 0.9)
    return x, y, w, h


def crow(p, x, y, direction, many=False, optional=False):
    """Crow's-foot end marker at (x, y); direction 'l','r','u','d' is the side
    the line comes from (marker drawn toward the table)."""
    c = p.c
    c.setStrokeColor(NAVY)
    c.setLineWidth(0.8)
    dx, dy = {"l": (-1, 0), "r": (1, 0), "u": (0, -1), "d": (0, 1)}[direction]
    # bar(s) / feet are drawn 4-12px out from the table edge
    px, py = -dy, dx  # perpendicular

    def L(a, b, a2, b2):
        c.line(a, p.Y(b), a2, p.Y(b2))

    if many:
        tip = (x + dx * 10, y + dy * 10)
        for s in (-5, 0, 5):
            L(tip[0], tip[1], x + px * s, y + py * s)
    else:
        bx, by = x + dx * 6, y + dy * 6
        L(bx + px * 5, by + py * 5, bx - px * 5, by - py * 5)
    if optional:
        ox, oy = x + dx * 16, y + dy * 16
        c.setFillColor(white)
        c.circle(ox, p.Y(oy), 3.2, stroke=1, fill=1)
    else:
        bx, by = x + dx * (14 if many else 10), y + dy * (14 if many else 10)
        L(bx + px * 5, by + py * 5, bx - px * 5, by - py * 5)


def erd_link(p, pts, a_end, b_end, label=None, label_at=None):
    poly(p, pts, NAVY, 0.8, head=False)
    crow(p, pts[0][0], pts[0][1], *a_end[:1], **a_end[1])
    crow(p, pts[-1][0], pts[-1][1], *b_end[:1], **b_end[1])
    if label:
        lx, ly = label_at
        w = len(label) * 3.2 + 6
        rect(p, lx - w / 2, ly - 6, w, 10, white, None)
        text(p, lx, ly + 1.5, label, 6.2, INK, align="center")


def page_erd(c, n):
    p = Page(c, landscape(A4))
    header(p, "6. Entity Relationship Diagram",
           "Admin tables (navy) and the shared farmer tables the panel reads "
           "(grey). Crow's-foot notation: | = one, < = many, o = optional. "
           "Key columns only - see the Data Dictionary.")
    users = erd_table(p, 300, 86, 175, "AUTH.USERS (logins)", [
        ("PK", "id"), ("", "email"), ("", "encrypted_password"),
        ("", "raw_user_meta_data"), ("", "email_change"),
        ("", "created_at")])
    admins = erd_table(p, 30, 86, 175, "ADMINS", [
        ("PK,FK", "user_id"), ("", "first_name, last_name"),
        ("", "full_name"), ("", "email"), ("", "phone"),
        ("", "phone_verified"), ("", "birth_date"), ("", "status"),
        ("FK", "reviewed_by"), ("", "reviewed_at"), ("", "created_at")])
    otps = erd_table(p, 600, 86, 175, "PHONE_OTPS", [
        ("PK,FK", "user_id"), ("", "phone"), ("", "code_hash"),
        ("", "expires_at"), ("", "attempts"), ("", "locked")])
    log = erd_table(p, 600, 230, 175, "OTP_SEND_LOG", [
        ("PK", "id"), ("", "user_id"), ("", "phone"), ("", "created_at")])
    prof = erd_table(p, 300, 270, 175, "PROFILES", [
        ("PK,FK", "id (auth user)"), ("", "full_name"), ("", "email"),
        ("", "phone")], read_only=True)
    ponds = erd_table(p, 300, 380, 175, "PONDS", [
        ("PK", "id"), ("FK", "user_id"), ("", "name"),
        ("", "latitude, longitude"), ("", "species_names"),
        ("", "verification_status")], read_only=True)
    dev = erd_table(p, 30, 395, 175, "DEVICES", [
        ("PK", "id (MAC address)"), ("FK", "pond_id"), ("", "paired_at"),
        ("", "last_seen_at")], read_only=True)
    reads = erd_table(p, 600, 360, 175, "SENSOR_READINGS", [
        ("PK", "id"), ("FK", "pond_id"), ("", "ph, dissolved_oxygen"),
        ("", "ammonia, water_temperature"), ("", "air_temperature, humidity"),
        ("", "created_at")], read_only=True)

    # users 1 -- 0..1 admins
    erd_link(p, [(300, 110), (205, 110)], ("l", {}),
             ("r", {"optional": True}), "is an admin", (252, 110))
    # admins.reviewed_by >o -- || users
    erd_link(p, [(205, 207), (250, 207), (250, 150), (300, 150)],
             ("r", {"many": True, "optional": True}), ("l", {}),
             "reviews", (250, 180))
    # users 1 -- 0..1 phone_otps
    erd_link(p, [(475, 110), (600, 110)], ("r", {}),
             ("l", {"optional": True}), "has pending OTP", (537, 110))
    # users 1 -- 0..* otp_send_log (logical)
    erd_link(p, [(475, 150), (540, 150), (540, 250), (600, 250)],
             ("r", {}), ("l", {"many": True, "optional": True}),
             "OTP sends", (540, 200))
    # users 1 -- 1 profiles (farmer)
    erd_link(p, [(387, 160), (387, 270)], ("d", {}),
             ("u", {"optional": True}), "farmer profile", (387, 225))
    # profiles 1 -- many ponds
    erd_link(p, [(387, 336), (387, 380)], ("d", {}),
             ("u", {"many": True, "optional": True}), "owns", (420, 358))
    # ponds 1 -- 0..1 devices
    erd_link(p, [(300, 420), (205, 420)], ("l", {}),
             ("r", {"optional": True}), "monitored by", (252, 420))
    # ponds 1 -- many readings
    erd_link(p, [(475, 420), (600, 420)], ("r", {}),
             ("l", {"many": True, "optional": True}), "has", (537, 420))
    lines_in(p, 30 + 87, 500, [
        "The panel only reads the grey tables, through",
        "admin_monitored_ponds() and admin_pond_reading_trend()."], 6.5,
        MUTED)
    lines_in(p, 690, 470, [
        "otp_send_log.user_id has no foreign key", "(a log, kept for rate limits)."],
        6.5, MUTED)
    footer(p, n, [("box", NAVY, NAVY, "Admin table"),
                  ("box", HexColor("#5A6B7A"), HexColor("#5A6B7A"),
                   "Farmer table (read only)")])
    c.showPage()


# --- Data dictionary -----------------------------------------------------

DD_COLS = [("Column", 120), ("Data type", 80), ("Null", 34), ("Key", 46),
           ("Default", 70), ("Description", 432)]


def dd_table(p, y, title, desc, rows, cols=DD_COLS, x=30):
    text(p, x, y, title, 10, NAVY, bold=True)
    text(p, x + 9 + len(title) * 5.6, y, desc, 7.3, MUTED, italic=True)
    y += 8
    rh = 13
    total = sum(w for _, w in cols)
    rect(p, x, y, total, rh, TEAL, None)
    cx = x
    for name, w in cols:
        text(p, cx + 5, y + 9, name, 6.8, white, bold=True)
        cx += w
    y += rh
    for i, row in enumerate(rows):
        rect(p, x, y, total, rh, ROW_ALT if i % 2 else white, None)
        cx = x
        for j, ((_, w), v) in enumerate(zip(cols, row)):
            text(p, cx + 5, y + 9, v, 6.5, INK, bold=(j == 0 and "PK" in row[3]
                                                      if len(row) > 3 else False))
            cx += w
        y += rh
    rect(p, x, y - rh * (len(rows) + 1), total, rh * (len(rows) + 1), None,
         HexColor("#C8D3D9"), 0, 0.5)
    return y + 22


def page_dd1(c, n):
    p = Page(c, landscape(A4))
    header(p, "7. Data Dictionary",
           "Admin tables in the public schema of the shared IsdaSafe Supabase "
           "database. PK = primary key, FK = foreign key, timestamptz = "
           "timestamp with time zone.")
    y = dd_table(p, 92, "Table 7.1  admins",
                 "One row per admin account or admin request (created at "
                 "sign-up or by request_admin_access).", [
        ("user_id", "uuid", "No", "PK, FK", "-",
         "Login; references auth.users.id (deleted with the login)"),
        ("first_name", "text", "Yes", "-", "-",
         "First name (null for admins from before it was asked)"),
        ("last_name", "text", "Yes", "-", "-", "Last name"),
        ("full_name", "text", "No", "-", "-",
         "\"first last\", kept in step by the functions; shown in lists"),
        ("email", "text", "No", "-", "-",
         "Login email; updated by a trigger when an email change is confirmed"),
        ("phone", "text", "Yes", "-", "-",
         "PH mobile in E.164 (+639XXXXXXXXX) for OTP codes; may match a farmer's"),
        ("phone_verified", "boolean", "No", "-", "false",
         "True once an OTP sent to phone was confirmed (required to use the panel)"),
        ("birth_date", "date", "Yes", "-", "-",
         "Date of birth; must be 18 or older (is_adult)"),
        ("status", "text", "No", "-", "'pending'",
         "'pending', 'approved' or 'rejected'; the first admin ever is approved"),
        ("reviewed_by", "uuid", "Yes", "FK", "-",
         "Admin who last approved / declined it; references auth.users.id"),
        ("reviewed_at", "timestamptz", "Yes", "-", "-", "When it was last reviewed"),
        ("created_at", "timestamptz", "No", "-", "now()", "When the request was filed"),
    ])
    y = dd_table(p, y, "Table 7.2  phone_otps",
                 "The one OTP code currently waiting per login (shared with "
                 "the farmer app).", [
        ("user_id", "uuid", "No", "PK, FK", "-",
         "Login the code belongs to; references auth.users.id"),
        ("phone", "text", "No", "-", "-", "Number the code was texted to"),
        ("code_hash", "text", "No", "-", "-", "SHA-256 hash of the code (never stored plain)"),
        ("expires_at", "timestamptz", "No", "-", "-", "5 minutes after sending"),
        ("attempts", "integer", "No", "-", "0", "Wrong guesses so far"),
        ("locked", "boolean", "No", "-", "false", "True after 5 wrong guesses"),
    ])
    footer(p, n)
    c.showPage()


def page_dd2(c, n):
    p = Page(c, landscape(A4))
    header(p, "7. Data Dictionary (continued)",
           "Admin-side tables and the shared tables the panel reads.")
    y = dd_table(p, 92, "Table 7.3  otp_send_log",
                 "Every OTP SMS sent; limits sends to 1/min, 3 per 10 min "
                 "and 8 per day per login and number.", [
        ("id", "bigint", "No", "PK", "identity", "Auto-increment log ID"),
        ("user_id", "uuid", "No", "-", "-", "Login that requested the code"),
        ("phone", "text", "No", "-", "-", "Number the code was sent to"),
        ("created_at", "timestamptz", "No", "-", "now()", "When it was sent"),
    ])
    y = dd_table(p, y, "Table 7.4  auth.users (Supabase Auth)",
                 "Shared logins of admins and farmers; managed by Supabase "
                 "Auth. Columns the admin side relies on.", [
        ("id", "uuid", "No", "PK", "-", "Login ID (admins.user_id)"),
        ("email", "text", "Yes", "-", "-", "Login email (copied to admins.email)"),
        ("encrypted_password", "text", "Yes", "-", "-",
         "Empty for Google-only logins (email_sign_in_method returns 'oauth')"),
        ("raw_user_meta_data", "jsonb", "Yes", "-", "-",
         "Sign-up data: admin_signup, first_name, last_name, birth_date, admin_phone"),
        ("email_change", "text", "Yes", "-", "-", "New email waiting for its confirmation link"),
    ])
    cols = [("Table", 120), ("Columns read", 330), ("Read through", 332)]
    y = dd_table(p, y, "Table 7.5  Farmer tables read by the panel",
                 "Written by the IsdaSafe farmer app; see its Data Dictionary "
                 "for every column.", [
        ("profiles", "full_name, email, phone",
         "admin_monitored_ponds() (pond owner)"),
        ("ponds", "id, name, latitude, longitude, species_names, "
         "verification_status, user_id", "admin_monitored_ponds()"),
        ("devices", "id, pond_id, paired_at, last_seen_at",
         "admin_monitored_ponds(), admin_pond_reading_trend()"),
        ("sensor_readings", "ph, dissolved_oxygen, ammonia, water/air "
         "temperature, humidity, created_at",
         "latest per pond; trend steps (avg / min / max)"),
    ], cols)
    footer(p, n)
    c.showPage()


def page_dd3(c, n):
    p = Page(c, landscape(A4))
    header(p, "7. Data Dictionary (continued) - Functions & Triggers",
           "SECURITY DEFINER functions the panel calls (PostgREST RPC). "
           "Admin-only ones check is_approved_admin() first.")
    cols = [("Function", 150), ("Arguments", 170), ("Returns", 92),
            ("Who may call", 70), ("Purpose", 300)]
    y = dd_table(p, 90, "Table 7.6  Database functions", "", [
        ("is_approved_admin", "-", "boolean", "signed in",
         "Whether the caller has an approved admins row"),
        ("request_admin_access", "first, last, phone, birth_date", "text",
         "signed in", "Files a request (or fills a missing name / birth date)"),
        ("admin_set_own_name", "first, last", "void", "signed in",
         "Sets the caller's first / last / full name"),
        ("admin_set_own_birth_date", "birth_date", "void", "signed in",
         "Sets the caller's birth date (18+, not in the future)"),
        ("admin_set_own_phone", "phone", "void", "signed in",
         "Sets an unverified number before the first code (login gate)"),
        ("admin_verify_phone_otp", "code", "text", "signed in",
         "Checks the code for the number on file; null = success"),
        ("admin_check_phone_available", "phone", "void", "signed in",
         "Refuses a number another verified admin has"),
        ("admin_change_phone", "code", "text", "signed in",
         "Swaps in a new number once its code is right"),
        ("admin_list_admins", "-", "setof admins", "approved",
         "Every admin and request, newest first"),
        ("admin_set_status", "user_id, status", "void", "approved",
         "Approves / declines another admin (never self)"),
        ("admin_leave", "-", "void", "signed in",
         "Deletes own row (not the last approved admin)"),
        ("admin_monitored_ponds", "-", "table", "approved",
         "Ponds with a paired device, owner & latest reading"),
        ("admin_pond_reading_trend", "pond_id, start, end, step", "table",
         "approved", "Readings grouped per step: avg / min / max / count"),
        ("email_has_account", "email", "boolean", "anyone",
         "Whether a login uses the email (Register)"),
        ("email_sign_in_method", "email", "text", "anyone",
         "null / 'password' / 'oauth' (Google-only)"),
        ("is_adult", "birth_date", "boolean", "anyone",
         "18 or older today (Manila time)"),
    ], cols)
    cols = [("Trigger", 190), ("On", 120), ("Function", 130), ("What it does", 342)]
    dd_table(p, y, "Table 7.7  Triggers", "", [
        ("on_admin_signup", "auth.users INSERT", "handle_admin_signup",
         "Sign-ups with admin_signup metadata become a pending admins row (18+)"),
        ("on_auth_email_change_sync_admin", "auth.users UPDATE OF email",
         "sync_admin_email", "Copies a confirmed new email onto admins.email"),
    ], cols)
    footer(p, n)
    c.showPage()


# --- Block diagram -------------------------------------------------------

def page_block(c, n):
    p = Page(c, landscape(A4))
    header(p, "8. Software Block Diagram",
           "The admin software as its major blocks and the main data passed "
           "between them. Dashed outlines group the blocks that run on the same "
           "platform.")
    box(p, 25, 230, 110, 46, ["Administrator"], ENT_FILL, ENT_STROKE, 8.5,
        sub=["web browser or", "Android phone"])
    # App
    rect(p, 165, 105, 330, 410, None, NAVY, 6, 0.9, dash=(4, 3))
    text(p, 175, 120, "IsdaSafe Admin App (Flutter: Web & Android)", 8.3,
         NAVY, bold=True)
    box(p, 180, 135, 140, 56, ["Presentation Layer"], PROC_FILL, TEAL, 8,
        sub=["login gate, dashboard,", "monitoring, map, pond page,",
             "admins, settings"])
    box(p, 180, 225, 140, 60, ["State"], PROC_FILL, TEAL, 8,
        sub=["StatefulWidgets; ValueNotifiers:", "ownProfile, recoveryPending,",
             "adminRequestFiled; ThemeController"])
    box(p, 180, 320, 140, 46, ["Local Storage"], STORE_FILL, STORE_STROKE, 8,
        sub=["shared_preferences:", "light / dark / system theme"])
    box(p, 345, 135, 135, 230, ["Service Layer"], PROC_FILL, TEAL, 8.5,
        sub=["AdminAuthService", "(auth, admin row, OTP,",
             "credentials)", "MonitoringRepository", "AdminTrendController",
             "ReadingsPager", "CaptchaField"])
    box(p, 180, 405, 300, 44, ["Hosting: Vercel (web build)"], STORE_FILL,
        STORE_STROKE, 8, sub=["isdasafe-admin.me / vercel.app,",
                             "email-confirmed.html"])
    poly(p, [(135, 250), (180, 160)])
    text(p, 140, 196, "input", 6.3, INK)
    poly(p, [(180, 168), (135, 262)])
    text(p, 140, 230, "screens", 6.3, INK)
    poly(p, [(250, 191), (250, 225)], tail=True)
    poly(p, [(320, 250), (345, 250)], tail=True)
    poly(p, [(320, 343), (345, 343)], tail=True)
    poly(p, [(320, 165), (345, 165)], tail=True)
    # Supabase
    rect(p, 525, 105, 175, 410, None, NAVY, 6, 0.9, dash=(4, 3))
    text(p, 535, 120, "Supabase Cloud Backend", 8.3, NAVY, bold=True)
    box(p, 540, 135, 145, 52, ["Authentication"], PROC_FILL, TEAL, 8,
        sub=["email + password, Google,", "CAPTCHA check, reset & email",
             "change mail"])
    box(p, 540, 210, 145, 40, ["Edge Function"], PROC_FILL, TEAL, 8,
        sub=["send-semaphore-otp (shared)"])
    box(p, 540, 275, 145, 120, ["PostgreSQL Database"], STORE_FILL,
        STORE_STROKE, 8, sub=["admins, phone_otps,", "otp_send_log",
                              "admin_* RPC functions", "auth.users triggers",
                              "farmer tables (read only)"])
    box(p, 540, 420, 145, 40, ["Shared with the", "IsdaSafe farmer app"],
        HexColor("#F4F4F4"), HexColor("#9AA5AD"), 7.2, MUTED)
    poly(p, [(480, 160), (540, 160)])
    text(p, 488, 155, "sign-in, OTP", 6.2, INK)
    poly(p, [(480, 230), (540, 230)])
    text(p, 488, 225, "invoke", 6.2, INK)
    poly(p, [(480, 320), (540, 320)], tail=True)
    text(p, 488, 315, "RPC, rows", 6.2, INK)
    poly(p, [(612, 250), (612, 275)])
    text(p, 616, 266, "logs & codes", 6.2, INK)
    # outside
    outs = [(110, ["Google Sign-In"]), (170, ["Cloudflare", "Turnstile"]),
            (240, ["Semaphore SMS"]), (300, ["Google Maps", "JavaScript API"]),
            (370, ["Email delivery", "(Supabase mailer)"])]
    for y, ls in outs:
        box(p, 725, y, 95, 40, ls, ENT_FILL, ENT_STROKE, 7.5)
    poly(p, [(685, 150), (725, 130)])
    poly(p, [(685, 170), (725, 190)])
    poly(p, [(685, 230), (725, 260)])
    poly(p, [(685, 180), (705, 180), (705, 390), (725, 390)])
    poly(p, [(480, 300), (505, 300), (505, 90), (770, 90), (770, 110)])
    text(p, 590, 86, "Google sign-in (Android)", 6.2, INK)
    poly(p, [(480, 345), (510, 345), (510, 525), (840, 525), (840, 320),
              (820, 320)])
    text(p, 600, 521, "map tiles & pins (web)", 6.2, INK)
    poly(p, [(480, 285), (515, 285), (515, 96), (830, 96), (830, 190), (820, 190)])
    text(p, 560, 103, "CAPTCHA widget", 6.2, INK)
    footer(p, n, [("box", ENT_FILL, ENT_STROKE, "User / outside service"),
                  ("box", PROC_FILL, TEAL, "Software block"),
                  ("box", STORE_FILL, STORE_STROKE, "Data store / hosting"),
                  ("dash", None, NAVY, "Platform (runs together)")])
    c.showPage()


# --- Schematic --------------------------------------------------------------

def offpage(p, x, y, letter, point="right"):
    c = p.c
    w, h = 26, 16
    c.setFillColor(white)
    c.setStrokeColor(INK)
    c.setLineWidth(0.9)
    path = c.beginPath()
    if point == "right":
        path.moveTo(x, p.Y(y - h / 2))
        path.lineTo(x + w - 7, p.Y(y - h / 2))
        path.lineTo(x + w, p.Y(y))
        path.lineTo(x + w - 7, p.Y(y + h / 2))
        path.lineTo(x, p.Y(y + h / 2))
    else:
        path.moveTo(x + w, p.Y(y - h / 2))
        path.lineTo(x + 7, p.Y(y - h / 2))
        path.lineTo(x, p.Y(y))
        path.lineTo(x + 7, p.Y(y + h / 2))
        path.lineTo(x + w, p.Y(y + h / 2))
    path.close()
    c.drawPath(path, stroke=1, fill=1)
    text(p, x + w / 2 + (-2 if point == "right" else 2), y + 3, letter, 8,
         INK, bold=True, align="center")


def wire_no(p, x, y, num):
    rect(p, x - 9, y - 6, 18, 12, white, TEAL, 3, 0.8)
    text(p, x, y + 3, str(num), 6.8, TEAL, bold=True, align="center")


def page_schem1(c, n):
    p = Page(c, landscape(A4))
    header(p, "9. Software Schematic (Sheet 1 of 2) - Screens & Services",
           "Each screen has its own colour: follow it to the arrowheads to see "
           "which services it uses. Lettered flags continue on Sheet 2.")
    rect(p, 140, 82, 520, 455, None, NAVY, 6, 0.9, dash=(4, 3))
    text(p, 150, 97, "IsdaSafe Admin App (Flutter)", 8.5, NAVY, bold=True)
    text(p, 165, 113, "SCREENS (lib/screens)", 7.5, TEAL, bold=True)
    text(p, 470, 113, "SERVICES (lib/services, lib/analytics)", 7.5, TEAL,
         bold=True)
    screens = [
        ("AdminGate", "auth/admin_gate: request access,", "profile step, waiting / declined"),
        ("Login, Register & Reset", "auth/login, register,", "reset_password; CAPTCHA"),
        ("Phone Verification", "auth/phone_verification_screen", "OTP send & check"),
        ("Dashboard Shell", "dashboard_screen: sidebar,", "badges, account footer"),
        ("Monitoring", "monitoring_view: tiles, filters,", "cards / list, greeting"),
        ("Pond Map", "pond_map_view:", "pins by status"),
        ("Pond Page & Detail", "pond_page, pond_latest_readings,", "metric_detail_view"),
        ("Admins", "admins_view: approve /", "decline requests"),
        ("Settings", "settings_view, account_dialogs:", "name, phone, email, password"),
    ]
    services = [
        ("AdminAuthService", "auth, admin row, OTP,", "credentials", 128),
        ("MonitoringRepository", "admin_monitored_ponds()", "", 245),
        ("AdminTrendController", "admin_pond_reading_trend()", "+ statsOf", 305),
        ("ReadingsPager", "trend steps as table rows,", "a page at a time", 365),
        ("ThemeController", "light / dark / system", "(shared_preferences)", 425),
        ("CaptchaField", "Cloudflare Turnstile", "widget", 480),
    ]
    sy = {}
    for name, a, b, y in services:
        box(p, 455, y, 160, 66 if name == "AdminAuthService" else 44, [name],
            PROC_FILL, TEAL, 8, sub=[a] + ([b] if b else []))
        sy[name] = y
    uses = {
        0: ["AdminAuthService"],
        1: ["AdminAuthService", "CaptchaField"],
        2: ["AdminAuthService"],
        3: ["AdminAuthService", "MonitoringRepository"],
        4: ["MonitoringRepository", "AdminAuthService"],
        5: ["MonitoringRepository"],
        6: ["AdminTrendController", "ReadingsPager"],
        7: ["AdminAuthService"],
        8: ["AdminAuthService", "ThemeController"],
    }
    lane_i = 0
    n_wires = sum(len(v) for v in uses.values())
    for i, (name, a, b) in enumerate(screens):
        y = 122 + i * 46
        col = WIRE_COLORS[i % len(WIRE_COLORS)]
        rect(p, 160, y, 175, 38, PROC_FILL, TEAL, 4, 0.9)
        rect(p, 160, y, 5, 38, col, None)
        text(p, 250, y + 13, name, 8, INK, bold=True, align="center")
        text(p, 250, y + 23, a, 6.2, MUTED, align="center")
        text(p, 250, y + 31, b, 6.2, MUTED, align="center")
        for k, svc in enumerate(uses[i]):
            ty = sy[svc] + 8 + (lane_i % 7) * 4
            lane = 345 + lane_i * (100 / n_wires)
            poly(p, [(335, y + 14 + k * 9), (lane, y + 14 + k * 9),
                     (lane, ty), (455, ty)], col, 0.8)
            lane_i += 1
    # off-page flags
    flags = [("AdminAuthService", "A", 136, "Supabase Auth"),
             ("AdminAuthService", "B", 152, "RPC functions & admins"),
             ("AdminAuthService", "C", 168, "Edge Function (OTP)"),
             ("AdminAuthService", "H", 184, "Google Sign-In"),
             ("MonitoringRepository", "D", 262, "RPC admin_monitored_ponds"),
             ("AdminTrendController", "E", 322, "RPC admin_pond_reading_trend"),
             ("CaptchaField", "F", 497, "Cloudflare Turnstile")]
    for svc, letter, y, label in flags:
        poly(p, [(615, y), (690, y)], INK, 0.7)
        offpage(p, 690, y, letter)
        text(p, 722, y + 2.5, label, 6.3, TEAL, italic=True)
    text(p, 690, 113, "TO SHEET 2 (p. 18)", 7.5, TEAL, bold=True)
    lines_in(p, 760, 420, ["HOW TO READ",
                          "Colour tab on a screen =", "colour of its wires.",
                          "Arrowhead = service the",
                          "screen calls.", "Lettered flag = continues",
                          "on Sheet 2 (p. 18)."], 6.6, MUTED, align="left",
             x=700)
    # The map screen talks to Google Maps itself (google_maps_flutter).
    gy = 122 + 5 * 46 + 19
    poly(p, [(160, gy), (122, gy)], INK, 0.7)
    offpage(p, 96, gy, "G", point="left")
    lines_in(p, 70, gy + 18, ["Google Maps", "(to Sheet 2)"], 6.3, TEAL)
    footer(p, n, [("box", PROC_FILL, TEAL, "Software module"),
                  ("dash", None, NAVY, "Platform"),
                  ("box", WIRE_COLORS[1], WIRE_COLORS[1], "Screen wire (colour per screen)")])
    c.showPage()


def page_schem2(c, n):
    p = Page(c, landscape(A4))
    header(p, "9. Software Schematic (Sheet 2 of 2) - Backend & Cloud",
           "Every wire entering from the left comes from Sheet 1 (p. 17) "
           "through the flag with the same letter. Numbers match the Interface "
           "List on the next page.")
    text(p, 30, 100, "FROM SHEET 1 (p. 17)", 7.5, TEAL, bold=True)
    rect(p, 195, 88, 330, 445, None, NAVY, 6, 0.9, dash=(4, 3))
    text(p, 205, 103, "Supabase Backend (shared IsdaSafe project)", 8.3, NAVY,
         bold=True)
    blocks = [
        (115, 56, ["Auth (GoTrue)"], ["email + password, Google OAuth,",
                                      "CAPTCHA check, JWT sessions,",
                                      "reset code & email-change link"]),
        (190, 96, ["RPC Functions (SECURITY DEFINER)"],
         ["request_admin_access, admin_set_own_*,",
          "admin_verify_phone_otp, admin_change_phone,",
          "admin_check_phone_available, admin_list_admins,",
          "admin_set_status, admin_leave, email_has_account,",
          "email_sign_in_method, is_adult, is_approved_admin"]),
        (306, 46, ["Monitoring RPCs"], ["admin_monitored_ponds,",
                                        "admin_pond_reading_trend"]),
        (372, 56, ["Tables"], ["admins, phone_otps, otp_send_log (admin);",
                               "profiles, ponds, devices, sensor_readings",
                               "(farmer, read only)"]),
        (448, 44, ["Triggers on auth.users"], ["on_admin_signup,",
                                               "on_auth_email_change_sync_admin"]),
    ]
    for y, h, t, sub in blocks:
        box(p, 215, y, 290, h, t, PROC_FILL if "Tables" not in t[0] else
            STORE_FILL, TEAL if "Tables" not in t[0] else STORE_STROKE, 8,
            sub=sub)
    box(p, 215, 500, 290, 26, ["Edge Function: send-semaphore-otp"],
        PROC_FILL, TEAL, 7.8)
    # internal arrows
    poly(p, [(360, 171), (360, 190)])
    poly(p, [(360, 286), (360, 306)], head=False)
    poly(p, [(470, 286), (470, 372)])
    text(p, 474, 330, "reads / writes", 6.2, INK)
    poly(p, [(360, 352), (360, 372)])
    poly(p, [(250, 448), (250, 428)])
    text(p, 254, 440, "INSERT / UPDATE", 6.2, INK)
    poly(p, [(505, 513), (515, 513), (515, 410), (505, 410)])
    text(p, 509, 470, "codes", 6.2, INK)
    # incoming flags
    incoming = [("A", 143, 1, "AdminAuthService"),
                ("B", 238, 2, "AdminAuthService"),
                ("D", 322, 4, "MonitoringRepository"),
                ("E", 338, 5, "AdminTrendController"),
                ("C", 513, 6, "AdminAuthService")]
    for letter, y, num, who in incoming:
        text(p, 100, y + 2.5, who, 6.3, TEAL, italic=True, align="right")
        offpage(p, 108, y, letter)
        poly(p, [(134, y), (215, y)])
        wire_no(p, 170, y, num)
    # outside services
    text(p, 600, 100, "OUTSIDE SERVICES", 7.5, TEAL, bold=True)
    outs = [(115, "Google Sign-In", "OAuth 2.0", 9),
            (170, "Cloudflare Turnstile", "CAPTCHA token check", 8),
            (225, "Email delivery", "reset code, email-change link", 10),
            (480, "Semaphore", "OTP SMS (PH)", 7)]
    for y, name, sub, num in outs:
        box(p, 600, y, 150, 36, [name], ENT_FILL, ENT_STROKE, 8, sub=[sub])
    poly(p, [(505, 130), (600, 130)], tail=True)
    wire_no(p, 552, 130, 9)
    poly(p, [(505, 150), (560, 150), (560, 188), (600, 188)])
    wire_no(p, 560, 168, 8)
    poly(p, [(505, 160), (575, 160), (575, 243), (600, 243)])
    wire_no(p, 575, 210, 10)
    poly(p, [(505, 518), (560, 518), (560, 498), (600, 498)])
    wire_no(p, 560, 508, 7)
    # flags F, G, H straight to outside services
    offpage(p, 108, 395, "F")
    text(p, 100, 397.5, "CaptchaField", 6.3, TEAL, italic=True, align="right")
    poly(p, [(134, 395), (175, 395), (175, 76), (780, 76), (780, 188), (750, 188)])
    wire_no(p, 175, 360, 11)
    offpage(p, 108, 420, "G")
    text(p, 100, 422.5, "Pond Map", 6.3, TEAL, italic=True, align="right")
    poly(p, [(134, 420), (185, 420), (185, 545), (790, 545), (790, 420), (750, 420)])
    wire_no(p, 185, 470, 12)
    box(p, 600, 402, 150, 36, ["Google Maps"], ENT_FILL, ENT_STROKE, 8,
        sub=["JavaScript API (web)"])
    offpage(p, 108, 445, "H")
    text(p, 100, 447.5, "AdminAuthService", 6.3, TEAL, italic=True, align="right")
    poly(p, [(134, 445), (160, 445), (160, 70), (795, 70), (795, 133), (750, 133)])
    wire_no(p, 160, 300, 13)
    # hosting
    box(p, 600, 300, 150, 52, ["Vercel"], STORE_FILL, STORE_STROKE, 8,
        sub=["serves the web build and", "email-confirmed.html", "(isdasafe-admin.me)"])
    wire_no(p, 675, 365, 14)
    lines_in(p, 675, 380, ["to the admin's browser"], 6.3, MUTED)
    poly(p, [(675, 352), (675, 395)], head=True)
    # trigger wire number
    wire_no(p, 230, 438, 3)
    footer(p, n, [("box", ENT_FILL, ENT_STROKE, "Outside service"),
                  ("box", PROC_FILL, TEAL, "Software module"),
                  ("box", STORE_FILL, STORE_STROKE, "Data store / hosting"),
                  ("dash", None, NAVY, "Platform")])
    c.showPage()


def page_interfaces(c, n):
    p = Page(c, landscape(A4))
    header(p, "9. Software Schematic Diagram (continued) - Interface List",
           "Each numbered wire of the schematic (Sheets 1-2): the two modules "
           "it joins, the interface or protocol used, and the data carried.")
    cols = [("#", 22), ("From", 150), ("To", 150), ("Interface / protocol", 200),
            ("Data carried", 260)]
    rows = [
        ("1", "AdminAuthService", "Supabase Auth", "supabase_flutter (HTTPS, JWT)",
         "sign-up / sign-in, Google, sessions, CAPTCHA token, reset, email change"),
        ("2", "AdminAuthService", "RPC functions, admins", "PostgREST RPC / select (HTTPS)",
         "admin requests, profile, OTP checks, approvals, own admin row"),
        ("3", "Triggers on auth.users", "admins table", "PL/pgSQL trigger",
         "new admin request at sign-up; confirmed email copied over"),
        ("4", "MonitoringRepository", "admin_monitored_ponds", "PostgREST RPC (HTTPS)",
         "ponds, owners, devices, latest readings"),
        ("5", "AdminTrendController", "admin_pond_reading_trend", "PostgREST RPC (HTTPS)",
         "pond, window, step -> avg / min / max / count per metric"),
        ("6", "AdminAuthService", "send-semaphore-otp", "functions.invoke (HTTPS + JWT)",
         "phone number -> code stored as a hash in phone_otps"),
        ("7", "send-semaphore-otp", "Semaphore", "HTTPS (api.semaphore.co)",
         "6-digit OTP SMS to a PH mobile number"),
        ("8", "Supabase Auth", "Cloudflare Turnstile", "siteverify (HTTPS)",
         "CAPTCHA token check on sign-up, log in and reset"),
        ("9", "Supabase Auth", "Google Sign-In", "OAuth 2.0",
         "Google identity (name, email)"),
        ("10", "Supabase Auth", "Email delivery", "SMTP (Supabase mailer)",
         "password-reset code, email-change confirmation link"),
        ("11", "CaptchaField", "Cloudflare Turnstile", "Turnstile widget (JS / WebView)",
         "one-time CAPTCHA token"),
        ("12", "Pond Map", "Google Maps", "google_maps_flutter (Maps JS API)",
         "pond pins; map tiles"),
        ("13", "AdminAuthService", "Google Sign-In", "OAuth redirect (web) / google_sign_in",
         "Google account choice, ID token"),
        ("14", "Vercel", "Admin's browser", "HTTPS static hosting",
         "web build, email-confirmed.html"),
    ]
    dd_table(p, 92, "", "", rows, cols)
    text(p, 30, 92 + 8 + 13 * (len(rows) + 1) + 18,
         "Wires between screens and services are in-app Dart calls (State "
         "methods, ListenableBuilder / ValueListenableBuilder) and are not "
         "numbered.", 7, MUTED, italic=True)
    footer(p, n)
    c.showPage()


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    c = canvas.Canvas(OUT, pagesize=landscape(A4))
    c.setTitle("IsdaSafe Admin - System Diagrams")
    c.setAuthor("IsdaSafe Team")
    c.setSubject("Admin panel system analysis & design diagrams")
    n = 1
    page_cover(c, n); n += 1
    c.setPageSize(landscape(A4)); page_context(c, n); n += 1
    c.setPageSize(landscape(A3)); page_level0(c, n); n += 1
    c.setPageSize(landscape(A4))
    for title, sub, procs, stores, between in CHILDREN:
        page_child(c, n, title, sub, procs, stores, between); n += 1
    page_states(c, n); n += 1
    page_flow1(c, n); n += 1
    page_flow2(c, n); n += 1
    page_erd(c, n); n += 1
    page_dd1(c, n); n += 1
    page_dd2(c, n); n += 1
    page_dd3(c, n); n += 1
    page_block(c, n); n += 1
    page_schem1(c, n); n += 1
    page_schem2(c, n); n += 1
    page_interfaces(c, n); n += 1
    c.save()
    print(f"wrote {OUT} ({n - 1} pages)")


if __name__ == "__main__":
    main()
