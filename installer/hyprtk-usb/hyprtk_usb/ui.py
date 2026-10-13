"""rich-based UI carrying the hyprtk look: double-border panels, mauve/cyan.

No full-screen app — the flow is inline prompts and panels, matching the
gum-styled menus used across hyprtk-merged.
"""

from __future__ import annotations

from typing import Iterable, Optional

from rich import box
from rich.console import Console, Group
from rich.panel import Panel
from rich.prompt import Confirm, Prompt
from rich.progress import BarColumn, Progress, TextColumn, TimeRemainingColumn
from rich.text import Text

from . import core
from .palette import Palette, human_bytes, load_palette  # noqa: F401  (re-exported)

console = Console()
err_console = Console(stderr=True)


class UI:
    def __init__(self, palette: Optional[Palette] = None) -> None:
        self.p = palette or load_palette()

    # ── panels ─────────────────────────────────────────────────────────
    def header(self, title: str, subtitle: str = "") -> None:
        body = Text(title, style=f"bold {self.p.accent}", justify="center")
        if subtitle:
            body.append("\n" + subtitle, style=self.p.dim)
        console.print(
            Panel(body, box=box.DOUBLE, border_style=self.p.accent, padding=(0, 2))
        )

    def box(self, title: str, body: str, style: Optional[str] = None) -> None:
        console.print(
            Panel(
                Text(body, style=style or self.p.fg),
                title=Text(title, style=self.p.accent2),
                box=box.DOUBLE,
                border_style=self.p.accent,
                padding=(0, 2),
            )
        )

    def info(self, msg: str) -> None:
        console.print(f"  [bold {self.p.accent2}]→[/] {msg}")

    def ok(self, msg: str) -> None:
        console.print(f"  [bold {self.p.accent2}]✓[/] {msg}")

    def warn(self, msg: str) -> None:
        console.print(f"  [bold {self.p.warn}]![/] {msg}")

    def err(self, msg: str) -> None:
        err_console.print(f"  [bold {self.p.err}]✗[/] {msg}")

    # ── prompts ────────────────────────────────────────────────────────
    def choose(self, title: str, items: Iterable[str], default: int = 0) -> int:
        items = list(items)
        lines: list[Text] = []
        for i, it in enumerate(items):
            selected = i == default
            style = f"bold black on {self.p.accent}" if selected else self.p.fg
            marker = "▸" if selected else " "
            lines.append(Text(f" {marker} {i + 1}. {it}", style=style))
        console.print(
            Panel(Group(*lines), title=Text(title, style=self.p.accent2),
                  box=box.DOUBLE, border_style=self.p.accent, padding=(0, 1))
        )
        while True:
            raw = Prompt.ask(
                f"  [{self.p.accent}]select[/] [dim](1-{len(items)})[/]",
                default=str(default + 1),
                show_default=False,
            )
            try:
                n = int(raw)
            except ValueError:
                self.warn("enter a number")
                continue
            if 1 <= n <= len(items):
                return n - 1
            self.warn(f"enter a number between 1 and {len(items)}")

    def confirm(self, question: str, default: bool = False) -> bool:
        return Confirm.ask(f"  [{self.p.accent}]{question}[/]", default=default)

    def ask(self, question: str, default: str = "") -> str:
        return Prompt.ask(f"  [{self.p.accent}]{question}[/]", default=default, show_default=bool(default))

    # ── plan / progress ────────────────────────────────────────────────
    def show_plan(self, iso: core.ISO, dev: core.Device, plan: core.Plan) -> None:
        mode = {
            core.MODE_NONE: "none",
            core.MODE_REFRESH: f"{plan.partition_dev} (kept)",
            core.MODE_FRESH: f"{plan.partition_dev}  label {core.PERSIST_LABEL}",
        }[plan.mode]
        body = (
            f"[{self.p.dim}]ISO[/]     {iso.path} ({human_bytes(iso.size)})\n"
            f"[{self.p.dim}]Label[/]   {iso.label or '?'}\n"
            f"[{self.p.dim}]Target[/]  {dev.describe()}\n"
            f"[{self.p.dim}]Size[/]    {human_bytes(dev.size)}\n"
            f"[{self.p.dim}]Persist[/] {mode}"
        )
        if plan.mode in (core.MODE_FRESH, core.MODE_REFRESH):
            body += (
                f"\n[{self.p.dim}]Region[/]  sectors {plan.start_sectors}.."
                f"{plan.start_sectors + plan.size_sectors - 1} "
                f"({human_bytes(plan.size_sectors * 512)})"
            )
        console.print(
            Panel(Text.from_markup(body), title=Text("plan", style=self.p.accent2),
                  box=box.DOUBLE, border_style=self.p.accent, padding=(1, 2))
        )
        for w in plan.warnings:
            self.warn(w)

    def run_write(self, iso: core.ISO, plan: core.Plan, runner: core.Runner) -> None:
        with Progress(
            TextColumn("  [{task.description}]"),
            BarColumn(complete_style=self.p.accent, finished_style=self.p.accent2),
            TextColumn("[progress.percentage]{task.percentage:>5.1f}%"),
            TextColumn("[dim]{task.fields[rate]}[/]"),
            TimeRemainingColumn(),
            console=console,
        ) as prog:
            task = prog.add_task("copying", total=iso.size, rate="")

            def cb(p: core.Progress) -> None:
                if p.stage == "copy":
                    prog.update(task, completed=p.written)
                elif p.stage == "partition":
                    prog.update(task, description="partitioning")
                    console.print(f"  [bold {self.p.accent}]→[/] adding the persistence partition...")
                elif p.stage == "format":
                    prog.update(task, description="formatting")
                    console.print(f"  [bold {self.p.accent}]→[/] formatting {core.PERSIST_LABEL}...")

            core.write(iso, plan, runner, cb)
