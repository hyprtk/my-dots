"""Shared fixtures + the per-stack JSON reporter for the E2E suite.

Every test runs twice — once per GTK stack — selected by ``HYPRTK_GTK`` which the
orchestrator (``run_e2e.py``) sets before pytest starts. This file turns the
pytest run into ``report-gtk<N>.json``; ``reporter.py`` merges the two into
``e2e-output.html``.
"""
from __future__ import annotations

import base64
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
for p in (str(REPO / "src"), str(HERE)):
    if p not in sys.path:
        sys.path.insert(0, p)

import pytest  # noqa: E402

STACK = os.environ.get("E2E_STACK", os.environ.get("HYPRTK_GTK", "?"))


# ── JSON reporter ───────────────────────────────────────────────────────────

_RESULTS: dict[str, dict] = {}


def _store(report, status: str) -> None:
    entry = _RESULTS.setdefault(
        report.nodeid,
        {"id": report.nodeid, "name": report.nodeid.split("::")[-1],
         "status": "passed", "duration": 0.0, "message": "", "details": {}},
    )
    entry["duration"] += getattr(report, "duration", 0.0)
    if status != "passed":
        entry["status"] = status
        entry["message"] = (report.longreprtext or "").strip()[-4000:]
    props = dict(getattr(report, "user_properties", []) or [])
    if props:
        box = props.pop("details", None)
        entry["details"].update(props)
        if isinstance(box, dict):
            entry["details"].update(box)


def pytest_runtest_logreport(report) -> None:
    if report.when == "call":
        _store(report, "passed" if report.passed else ("failed" if report.failed else "skipped"))
    elif report.when == "setup" and report.failed:
        _store(report, "error")
    elif report.when == "setup" and report.skipped:
        _store(report, "skipped")
        _RESULTS[report.nodeid]["message"] = (report.longreprtext or "").strip()[-2000:]
    elif report.when == "teardown" and report.failed:
        _store(report, "error")


def pytest_sessionfinish(session, exitstatus) -> None:
    out = os.environ.get("E2E_JSON")
    if not out:
        return
    payload = {"stack": STACK, "tests": list(_RESULTS.values())}
    Path(out).write_text(json.dumps(payload, indent=2))


# ── fixtures ────────────────────────────────────────────────────────────────

@pytest.fixture(scope="session", autouse=True)
def _require_display():
    if not (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")):
        pytest.exit("no WAYLAND_DISPLAY/DISPLAY — run via tools/e2e/run-e2e.sh", returncode=2)


@pytest.fixture
def details(request):
    """A dict a test can fill; it is attached to the JSON report row."""
    box: dict = {}
    request.node.user_properties.append(("details", box))
    return box


@pytest.fixture
def screenshot(details):
    """Capture the whole output to a PNG and embed it in the report row."""
    def _shot(name: str = "capture") -> Path:
        import subprocess
        path = Path("/tmp") / f"e2e-{name}-gtk{STACK}.png"
        subprocess.run(["grim", str(path)], check=False)
        if path.is_file():
            details.setdefault("screenshots", {})[name] = base64.b64encode(
                path.read_bytes()).decode()
        return path
    return _shot


@pytest.fixture
def fresh_config():
    """Write DEFAULTS to the sandboxed config path and return the loaded cfg."""
    from hyprtk_bar import config as config_module

    config_module.save(dict(config_module.DEFAULTS))
    return config_module.load()


@pytest.fixture
def ipc():
    from harness.fake_ipc import FakeIPC

    return FakeIPC()


@pytest.fixture
def make_runtime(fresh_config, ipc):
    """Factory: build the real bar graph with optional config overrides.

    Each call resets config.json to DEFAULTS (deep-merged with ``overrides``)
    and returns a fresh :class:`~harness.runtime.Runtime`. All runtimes are torn
    down when the test ends, so nothing leaks between tests.
    """
    from harness.runtime import build_runtime, pump
    from hyprtk_bar import config as config_module

    built = []

    def _make(overrides: dict | None = None, *, keep_config: bool = False):
        if not keep_config:
            cfg = _deep(config_module.DEFAULTS, overrides or {})
            config_module.save(cfg)
        loaded = config_module.load()
        rt = build_runtime(loaded, ipc)
        pump(80)
        built.append(rt)
        return rt

    try:
        yield _make
    finally:
        for rt in built:
            rt.teardown()
        pump(40)


def _deep(base, over):
    out = dict(base)
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _deep(out[k], v)
        else:
            out[k] = v
    return out


@pytest.fixture
def runtime(make_runtime):
    """The full real bar object graph with default config."""
    return make_runtime()
