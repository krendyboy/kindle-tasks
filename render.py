#!/usr/bin/env python3
"""Notion «Kindle Tasks» → PNG 758×1024 для Kindle Paperwhite 2.

  NOTION_TOKEN=... python render.py                 # тягне з Notion
  python render.py --fixture sample.json            # рендер з JSON (без мережі)
  python render.py --dump tasks.json                # зберегти витягнуті задачі

Вихід: out/tasks.png; якщо задано TASKS_KEY (64 hex), ще й out/tasks.bin —
AES-256-CBC (16 байт IV + шифротекст), Kindle розшифровує своїм openssl.
"""
import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path
from zoneinfo import ZoneInfo

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
TZ = ZoneInfo(os.environ.get("TASKS_TZ", "Europe/Kyiv"))
DATA_SOURCE = os.environ.get("NOTION_DATA_SOURCE", "844aba39-b127-44a3-825d-bfb22d0bb309")
DONE = {"Готово"}
IN_PROGRESS = {"В роботі"}
PRIORITY_RANK = {"Високий": 0, "Середній": 1, "Низький": 2}

W, H = 758, 1024
M = 28  # поля
FONT_R = str(ROOT / "fonts/PT_Sans-Web-Regular.ttf")
FONT_B = str(ROOT / "fonts/PT_Sans-Web-Bold.ttf")
AA_MIN = 26  # кегль, нижче якого текст без антиаліасингу

WEEKDAYS = ["Понеділок", "Вівторок", "Середа", "Четвер", "Пʼятниця", "Субота", "Неділя"]
WD_SHORT = ["пн", "вт", "ср", "чт", "пт", "сб", "нд"]
MONTHS = ["січня", "лютого", "березня", "квітня", "травня", "червня",
          "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"]


# ---------- Notion ----------

def notion_query(token):
    url = f"https://api.notion.com/v1/data_sources/{DATA_SOURCE}/query"
    body = {"filter": {"and": [{"property": "Status", "status": {"does_not_equal": n}} for n in DONE]},
            "page_size": 100}
    pages, cursor = [], None
    while True:
        if cursor:
            body["start_cursor"] = cursor
        req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST", headers={
            "Authorization": f"Bearer {token}",
            "Notion-Version": "2025-09-03",
            "Content-Type": "application/json",
        })
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.load(r)
        pages += data["results"]
        if not data.get("has_more"):
            return pages
        cursor = data["next_cursor"]


def parse_page(p):
    props = p["properties"]
    title = "".join(t["plain_text"] for t in props["Name"]["title"]).strip() or "(без назви)"
    status = (props["Status"].get("status") or {}).get("name")
    prio = (props["Priority"].get("select") or {}).get("name")
    due = (props["Due"].get("date") or {}).get("start")
    return {"title": title, "status": status, "priority": prio, "due": due}


# ---------- дані ----------

def due_info(due, now):
    """→ (sort_dt, дата у TZ або None, чи є час)"""
    if not due:
        return None, None, False
    if "T" in due:
        d = dt.datetime.fromisoformat(due.replace("Z", "+00:00")).astimezone(TZ)
        return d, d.date(), True
    d = dt.date.fromisoformat(due)
    return dt.datetime.combine(d, dt.time(23, 59), TZ), d, False


SECTIONS = ["Прострочено", "Сьогодні", "Завтра", "Найближчі 7 днів", "Пізніше", "Без дати"]


def section_of(day, now):
    if day is None:
        return "Без дати"
    delta = (day - now.date()).days
    if delta < 0:
        return "Прострочено"
    if delta == 0:
        return "Сьогодні"
    if delta == 1:
        return "Завтра"
    if delta <= 7:
        return "Найближчі 7 днів"
    return "Пізніше"


def date_label(day, has_time, sort_dt, sec):
    if day is None:
        return ""
    t = sort_dt.strftime("%H:%M") if has_time else ""
    if sec in ("Сьогодні", "Завтра"):
        return t
    s = f"{WD_SHORT[day.weekday()]} {day.day:02d}.{day.month:02d}"
    return f"{s} {t}".strip()


def prepare(tasks, now):
    out = {s: [] for s in SECTIONS}
    for t in tasks:
        if t.get("status") in DONE:
            continue
        sort_dt, day, has_time = due_info(t.get("due"), now)
        sec = section_of(day, now)
        out[sec].append({
            **t,
            "label": date_label(day, has_time, sort_dt, sec),
            "key": (sort_dt or dt.datetime.max.replace(tzinfo=TZ),
                    PRIORITY_RANK.get(t.get("priority"), 3), t["title"].lower()),
        })
    for s in out:
        out[s].sort(key=lambda x: x["key"])
    return out


# ---------- рендер ----------

_fonts = {}


def font(size, bold=False):
    k = (size, bold)
    if k not in _fonts:
        _fonts[k] = ImageFont.truetype(FONT_B if bold else FONT_R, size)
    return _fonts[k]


def text(d, xy, s, f, fill=0, anchor="la"):
    d.fontmode = "L" if f.size >= AA_MIN else "1"
    d.text(xy, s, font=f, fill=fill, anchor=anchor)


def wrap(s, f, width, max_lines):
    words, lines, cur = s.split(), [], ""
    for w in words:
        cand = f"{cur} {w}".strip()
        if f.getlength(cand) <= width:
            cur = cand
            continue
        if cur:
            lines.append(cur)
        cur = w
        while f.getlength(cur) > width:  # дуже довге слово
            i = len(cur)
            while i > 1 and f.getlength(cur[:i]) > width:
                i -= 1
            lines.append(cur[:i])
            cur = cur[i:]
    if cur:
        lines.append(cur)
    if len(lines) > max_lines:
        lines = lines[:max_lines]
        last = lines[-1]
        while last and f.getlength(last + "…") > width:
            last = last[:-1].rstrip()
        lines[-1] = last + "…"
    return lines


def draw_checkbox(d, x, y, size, in_progress):
    d.rectangle([x, y, x + size, y + size], outline=0, width=3, fill=255)
    if in_progress:  # напівзаповнений = «в роботі»
        d.polygon([(x + 3, y + size - 3), (x + size - 3, y + 3), (x + size - 3, y + size - 3)], fill=0)


def draw_priority(d, x_right, y, prio):
    n = {"Високий": 2, "Середній": 1}.get(prio, 0)
    if not n:
        return x_right
    f = font(26, True)
    s = "!" * n
    w = int(f.getlength(s)) + 16
    d.rounded_rectangle([x_right - w, y, x_right, y + 32], radius=6, fill=0)
    text(d, (x_right - w / 2, y + 16), s, f, fill=255, anchor="mm")
    return x_right - w - 10


def render(tasks, now):
    im = Image.new("L", (W, H), 255)
    d = ImageDraw.Draw(im)
    sections = prepare(tasks, now)
    total = sum(len(v) for v in sections.values())

    # шапка
    text(d, (M, 26), f"{WEEKDAYS[now.weekday()]}, {now.day} {MONTHS[now.month - 1]}", font(42, True))
    text(d, (W - M, 50), f"задач: {total}", font(28), anchor="rm")
    d.rectangle([M, 86, W - M, 90], fill=0)

    footer_top = H - 52
    y = 104
    f_title, f_title_b, f_lbl = font(32), font(32, True), font(24)
    line_h = 38
    shown = 0

    if total == 0:
        text(d, (W / 2, H / 2 - 40), "Усе зроблено", font(56, True), anchor="mm")
        text(d, (W / 2, H / 2 + 20), "відкритих задач немає", font(30), anchor="mm")

    for sec in SECTIONS:
        items = sections[sec]
        if not items:
            continue
        if y + 40 + line_h > footer_top:
            break
        # заголовок секції: прострочене — інвертоване
        hdr = f"{sec.upper()}  ·  {len(items)}"
        if sec == "Прострочено":
            d.rectangle([M, y, W - M, y + 34], fill=0)
            text(d, (M + 10, y + 17), hdr, font(24, True), fill=255, anchor="lm")
        else:
            d.rectangle([M, y, W - M, y + 34], fill=0xDD)
            text(d, (M + 10, y + 17), hdr, font(24, True), anchor="lm")
        y += 46

        for t in items:
            x_text = M + 46
            x_right = W - M
            label = t["label"]
            lbl_w = int(f_lbl.getlength(label)) + 12 if label else 0
            # місце праворуч під пріоритет і дату
            prio_w = {"Високий": 50, "Середній": 37}.get(t.get("priority"), 0)
            avail = x_right - x_text - lbl_w - (prio_w + 10 if prio_w else 0)
            ft = f_title_b if t.get("priority") == "Високий" or t.get("status") in IN_PROGRESS else f_title
            lines = wrap(t["title"], ft, avail, 2)
            row_h = max(len(lines) * line_h, line_h) + 10
            if y + row_h > footer_top:
                break
            draw_checkbox(d, M + 2, y + 6, 28, t.get("status") in IN_PROGRESS)
            for i, ln in enumerate(lines):
                text(d, (x_text, y + i * line_h), ln, ft)
            xr = x_right
            if label:
                text(d, (xr, y + 22), label, f_lbl, anchor="rm")
                xr -= lbl_w
            draw_priority(d, xr, y + 4, t.get("priority"))
            y += row_h
            d.line([(x_text, y - 5), (W - M, y - 5)], fill=0xAA, width=1)
            shown += 1
        else:
            y += 8
            continue
        break

    # підвал
    d.rectangle([M, footer_top, W - M, footer_top + 2], fill=0)
    text(d, (M, footer_top + 26), f"Оновлено {now:%d.%m %H:%M}", font(24), anchor="lm")
    if shown < total:
        text(d, (W - M, footer_top + 26), f"ще {total - shown} не влізло", font(24, True), anchor="rm")

    # 16 рівнів сірого — як у панелі, без дизерингу на пристрої
    return im.point(lambda v: min(255, round(v / 17) * 17))


def encrypt(png: bytes, key_hex: str) -> bytes:
    iv = os.urandom(16)
    ct = subprocess.run(["openssl", "enc", "-aes-256-cbc", "-K", key_hex, "-iv", iv.hex()],
                        input=png, capture_output=True, check=True).stdout
    return iv + ct


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fixture")
    ap.add_argument("--dump")
    ap.add_argument("--now", help="ISO datetime для тестів")
    ap.add_argument("--out", default=str(ROOT / "out"))
    a = ap.parse_args()

    now = dt.datetime.fromisoformat(a.now).astimezone(TZ) if a.now else dt.datetime.now(TZ)
    if a.fixture:
        tasks = json.loads(Path(a.fixture).read_text())
    else:
        token = os.environ.get("NOTION_TOKEN")
        if not token:
            sys.exit("NOTION_TOKEN не задано")
        tasks = [parse_page(p) for p in notion_query(token)]
    if a.dump:
        Path(a.dump).write_text(json.dumps(tasks, ensure_ascii=False, indent=1))

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    im = render(tasks, now)
    im.save(out / "tasks.png", optimize=True)
    key = os.environ.get("TASKS_KEY")
    if key:
        (out / "tasks.bin").write_bytes(encrypt((out / "tasks.png").read_bytes(), key))
    print(f"{len(tasks)} задач → {out / 'tasks.png'}" + (" + tasks.bin" if key else ""))


if __name__ == "__main__":
    main()
