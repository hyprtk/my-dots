"""Render the merged GTK3/GTK4 E2E results into ``e2e-output.html``.

The JSON collected by ``conftest.py`` for each stack is merged here: a test that
passes on GTK3 but fails on GTK4 is a **port regression** — the headline signal.
Visual captures (base64 PNG) are embedded inline.
"""
from __future__ import annotations

import base64
import html
import json
from pathlib import Path

LAYER_TITLES = {
    "L0": "L0 · static (imports + removed-API scan)",
    "L1": "L1 · construct (every window / page / widget)",
    "L2": "L2 · settings-apply matrix (control → Apply → live reaction)",
    "L3": "L3 · functional (signals, handlers, menus, dialogs)",
    "L4": "L4 · visual captures (grim, review-only)",
    "L5": "L5 · real-process smoke (the actual bar binary)",
    "??": "Uncategorised",
}
LAYER_ORDER = ["L0", "L1", "L2", "L3", "L4", "L5", "??"]

STATUS_ORDER = {"regression": 0, "fail": 1, "gtk3-only-fail": 2, "pass": 3, "gtk4-only-pass": 4, "skip": 5}


def _layer_of(nodeid: str) -> str:
    name = nodeid.rsplit("/", 1)[-1]
    for tag in ("l0", "l1", "l2", "l3", "l4", "l5"):
        if f"_{tag}_" in name or name.startswith(f"test_{tag}"):
            return "L" + tag[1]
    return "??"


def _parity(g3: str | None, g4: str | None) -> str:
    ok = {"passed"}
    if g3 is None or g4 is None:
        s = g4 or g3 or "skipped"
        return "pass" if s == "passed" else ("skip" if s in ("skipped", None) else "fail")
    if g3 in ok and g4 in ok:
        return "pass"
    if g3 in ok and g4 not in ok:
        return "regression"
    if g3 not in ok and g4 in ok:
        return "gtk4-only-pass"
    return "fail"


def _cls(parity: str) -> str:
    return {
        "pass": "ok", "regression": "bad", "fail": "bad",
        "gtk4-only-pass": "warn", "gtk3-only-fail": "warn", "skip": "skip",
    }.get(parity, "")


def _esc(value) -> str:
    return html.escape(str(value)) if value is not None else ""


def _unwrap(details: dict) -> dict:
    """Flatten the reporter's historical ``details.details`` nesting."""
    inner = details.get("details")
    if isinstance(inner, dict):
        merged = {k: v for k, v in details.items() if k != "details"}
        merged.update(inner)
        return merged
    return details


def _load(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return {"tests": []}


def render(report_dir: Path, stacks: list[str]) -> Path:
    by_stack = {s: {t["id"]: t for t in _load(report_dir / f"report-gtk{s}.json").get("tests", [])} for s in stacks}
    ids: list[str] = []
    for s in stacks:
        for tid in by_stack[s]:
            if tid not in ids:
                ids.append(tid)

    rows = []
    counts = {"pass": 0, "regression": 0, "fail": 0, "gtk4-only-pass": 0, "skip": 0}
    for tid in ids:
        g3 = by_stack.get("3", {}).get(tid, {}).get("status")
        g4 = by_stack.get("4", {}).get(tid, {}).get("status")
        par = _parity(g3, g4)
        counts[par] = counts.get(par, 0) + 1
        primary = by_stack.get("4", {}).get(tid) or by_stack.get("3", {}).get(tid) or {}
        rows.append({
            "id": tid, "layer": _layer_of(tid), "name": primary.get("name", tid),
            "g3": g3, "g4": g4, "parity": par,
            "message": primary.get("message", ""),
            "duration": primary.get("duration", 0.0),
            "details": _unwrap(primary.get("details") or {}),
        })

    rows.sort(key=lambda r: (LAYER_ORDER.index(r["layer"]) if r["layer"] in LAYER_ORDER else 99,
                             STATUS_ORDER.get(r["parity"], 9), r["name"]))

    total = len(rows)
    regressions = [r for r in rows if r["parity"] == "regression"]
    failures = [r for r in rows if r["parity"] == "fail"]

    parts = ["""<!doctype html><html><head><meta charset="utf-8">
<title>hyprtk-bar · E2E results</title>
<style>
:root{--bg:#14141c;--panel:#1c1c28;--fg:#e6e6f0;--dim:#9a9ab0;--ok:#3fb950;--bad:#f85149;--warn:#d29922;--skip:#6e7681;--accent:#c084fc;--sky:#22d3ee}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif}
header{padding:22px 28px;background:linear-gradient(90deg,#211b33,#14141c);border-bottom:1px solid #2a2a3a}
h1{margin:0 0 4px;font-size:20px;color:var(--accent)}
h1 span{color:var(--sky)}
.sub{color:var(--dim);font-size:13px}
.cards{display:flex;gap:12px;padding:18px 28px;flex-wrap:wrap}
.card{background:var(--panel);border:1px solid #2a2a3a;border-radius:10px;padding:12px 18px;min-width:120px}
.card b{display:block;font-size:26px}
.card.bad b{color:var(--bad)}.card.ok b{color:var(--ok)}.card.warn b{color:var(--warn)}
.card .l{color:var(--dim);font-size:12px;text-transform:uppercase;letter-spacing:.06em}
main{padding:0 28px 60px}
h2{font-size:15px;color:var(--sky);margin:26px 0 8px;border-bottom:1px solid #2a2a3a;padding-bottom:6px}
table{width:100%;border-collapse:collapse;background:var(--panel);border-radius:10px;overflow:hidden}
th,td{text-align:left;padding:8px 12px;border-bottom:1px solid #24242f;vertical-align:top}
th{color:var(--dim);font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:.05em;background:#191922}
td.name{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12.5px}
.pill{display:inline-block;padding:1px 8px;border-radius:999px;font-size:11px;font-weight:600}
.p-ok{background:#12351f;color:var(--ok)}.p-bad{background:#3a1516;color:var(--bad)}
.p-warn{background:#3a2f10;color:var(--warn)}.p-skip{background:#22222c;color:var(--skip)}
.p-na{background:#22222c;color:var(--dim)}
details{margin-top:4px}summary{cursor:pointer;color:var(--dim);font-size:12px}
pre{background:#0f0f16;border:1px solid #2a2a3a;border-radius:8px;padding:10px;overflow:auto;font-size:12px;max-height:320px}
.shots{display:flex;gap:10px;flex-wrap:wrap;margin-top:6px}
.shots figure{margin:0;background:#0f0f16;border:1px solid #2a2a3a;border-radius:8px;padding:6px}
.shots img{max-width:340px;display:block;border-radius:4px}
.shots figcaption{color:var(--dim);font-size:11px;margin-top:4px;text-align:center}
.legend{color:var(--dim);font-size:12px;padding:0 28px 8px}
</style></head><body>"""]

    parts.append('<header><h1>hyprtk-bar <span>GTK4</span> · end-to-end results</h1>')
    parts.append(f'<div class="sub">stacks: {", ".join("GTK"+s for s in stacks)} · layers L0–L5 · parity = same tree, two toolkits</div></header>')
    parts.append('<div class="cards">')
    parts.append(f'<div class="card ok"><b>{counts.get("pass",0)}</b><span class="l">pass</span></div>')
    parts.append(f'<div class="card bad"><b>{counts.get("regression",0)}</b><span class="l">GTK4 regressions</span></div>')
    parts.append(f'<div class="card bad"><b>{counts.get("fail",0)}</b><span class="l">both fail</span></div>')
    parts.append(f'<div class="card warn"><b>{counts.get("gtk4-only-pass",0)}</b><span class="l">GTK4-only pass</span></div>')
    parts.append(f'<div class="card"><b>{counts.get("skip",0)}</b><span class="l">skipped</span></div>')
    parts.append(f'<div class="card"><b>{total}</b><span class="l">total</span></div>')
    parts.append('</div>')
    parts.append('<div class="legend">A <b>GTK4 regression</b> = the same test that passes on GTK3 fails on GTK4. '
                 'That is the class of bug we are hunting (e.g. a settings toggle that no longer applies).</div>')

    parts.append('<main>')
    for layer in LAYER_ORDER:
        layer_rows = [r for r in rows if r["layer"] == layer]
        if not layer_rows:
            continue
        parts.append(f'<h2>{_esc(LAYER_TITLES.get(layer, layer))} · {len(layer_rows)}</h2>')
        parts.append('<table><tr><th>Test</th><th>GTK3</th><th>GTK4</th><th>Parity</th><th>Detail</th></tr>')
        for r in layer_rows:
            parts.append("<tr>")
            parts.append(f'<td class="name">{_esc(r["name"])}</td>')
            parts.append(f'<td>{_badge(r["g3"])}</td>')
            parts.append(f'<td>{_badge(r["g4"])}</td>')
            parts.append(f'<td><span class="pill p-{_cls(r["parity"]) or "na"}">{_esc(r["parity"])}</span></td>')
            parts.append(f'<td>{_detail(r)}</td>')
            parts.append("</tr>")
        parts.append('</table>')
    parts.append('</main></body></html>')

    out = report_dir / "e2e-output.html"
    out.write_text("".join(parts))
    return out


def _badge(status) -> str:
    if status is None:
        return '<span class="pill p-na">–</span>'
    cls = "ok" if status == "passed" else ("skip" if status in ("skipped",) else "bad")
    return f'<span class="pill p-{cls}">{_esc(status)}</span>'


def _detail(row: dict) -> str:
    bits = []
    if row["parity"] in ("regression", "fail") and row["message"]:
        bits.append(f'<details open><summary>failure</summary><pre>{_esc(row["message"])}</pre></details>')
    elif row["message"]:
        bits.append(f'<details><summary>log</summary><pre>{_esc(row["message"])}</pre></details>')
    shots = row["details"].get("screenshots")
    if shots:
        figs = []
        for name, b64 in shots.items():
            figs.append(f'<figure><img src="data:image/png;base64,{b64}"><figcaption>{_esc(name)}</figcaption></figure>')
        bits.append('<div class="shots">' + "".join(figs) + "</div>")
    extra = {k: v for k, v in row["details"].items() if k != "screenshots"}
    if extra:
        bits.append(f'<details><summary>data</summary><pre>{_esc(json.dumps(extra, indent=2))}</pre></details>')
    return "".join(bits) or '<span class="l" style="color:var(--dim)">·</span>'
