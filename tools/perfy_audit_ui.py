#!/usr/bin/env python3
"""
Small desktop UI for the MSUF Perfy workflow tool.

Uses only Python's standard library. It wraps tools/perfy_audit.py so users can
build Perfy zips and analyze !!!Perfy.lua without touching the command line.
"""

from __future__ import annotations

import os
import queue
import subprocess
import sys
import threading
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "perfy_audit.py"
DEFAULT_TRACE = (
    r"e:\World of Warcraft\_retail_\WTF\Account\1108323981#1"
    r"\SavedVariables\!!!Perfy.lua"
)
DOWNLOADS = Path(os.environ.get("USERPROFILE") or str(Path.home())) / "Downloads"
DEFAULT_REPORT = DOWNLOADS / "MSUF_Perfy_Offline_Report.txt"


class PerfyUI(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("MSUF Perfy Workflow")
        self.geometry("960x680")
        self.minsize(840, 560)

        self.log_queue: queue.Queue[str] = queue.Queue()
        self.running = False

        self.trace_var = tk.StringVar(value=DEFAULT_TRACE)
        self.report_var = tk.StringVar(value=str(DEFAULT_REPORT))
        self.repo_var = tk.StringVar(value=str(ROOT))
        self.output_var = tk.StringVar(value=str(DOWNLOADS))
        self.name_var = tk.StringVar(value="")
        self.top_var = tk.StringVar(value="35")

        self.scope_unitframes = tk.BooleanVar(value=True)
        self.scope_castbars = tk.BooleanVar(value=False)
        self.scope_classpower = tk.BooleanVar(value=False)
        self.scope_all = tk.BooleanVar(value=False)
        self.no_static = tk.BooleanVar(value=False)
        self.keep_stage = tk.BooleanVar(value=False)
        self.no_coverage = tk.BooleanVar(value=False)

        self._build()
        self.after(100, self._drain_log)

    def _build(self) -> None:
        outer = ttk.Frame(self, padding=12)
        outer.pack(fill=tk.BOTH, expand=True)
        outer.columnconfigure(0, weight=1)
        outer.rowconfigure(4, weight=1)

        title = ttk.Label(outer, text="MSUF Perfy Workflow", font=("Segoe UI", 16, "bold"))
        title.grid(row=0, column=0, sticky="w")
        subtitle = ttk.Label(
            outer,
            text="Build Perfy zips, analyze !!!Perfy.lua, and open reports from one small UI.",
        )
        subtitle.grid(row=1, column=0, sticky="w", pady=(2, 12))

        notebook = ttk.Notebook(outer)
        notebook.grid(row=2, column=0, sticky="ew")

        build_tab = ttk.Frame(notebook, padding=10)
        analyze_tab = ttk.Frame(notebook, padding=10)
        notebook.add(build_tab, text="Build Zip")
        notebook.add(analyze_tab, text="Analyze Trace")
        self._build_zip_tab(build_tab)
        self._build_analyze_tab(analyze_tab)

        actions = ttk.Frame(outer)
        actions.grid(row=3, column=0, sticky="ew", pady=(10, 8))
        actions.columnconfigure(5, weight=1)

        self.build_button = ttk.Button(actions, text="Build Perfy Zip", command=self.build_zip)
        self.build_button.grid(row=0, column=0, padx=(0, 8))
        self.analyze_button = ttk.Button(actions, text="Analyze Trace", command=self.analyze_trace)
        self.analyze_button.grid(row=0, column=1, padx=(0, 8))
        ttk.Button(actions, text="Open Report", command=self.open_report).grid(row=0, column=2, padx=(0, 8))
        ttk.Button(actions, text="Open Downloads", command=lambda: self.open_path(DOWNLOADS)).grid(row=0, column=3, padx=(0, 8))
        ttk.Button(actions, text="Clear Log", command=self.clear_log).grid(row=0, column=4, padx=(0, 8))

        log_frame = ttk.LabelFrame(outer, text="Output")
        log_frame.grid(row=4, column=0, sticky="nsew")
        log_frame.rowconfigure(0, weight=1)
        log_frame.columnconfigure(0, weight=1)
        self.log = tk.Text(log_frame, wrap="word", height=18, font=("Consolas", 10))
        self.log.grid(row=0, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(log_frame, command=self.log.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.log.configure(yscrollcommand=scroll.set)

        self.status_var = tk.StringVar(value="Ready")
        status = ttk.Label(outer, textvariable=self.status_var)
        status.grid(row=5, column=0, sticky="ew", pady=(8, 0))

    def _path_row(self, parent: ttk.Frame, row: int, label: str, var: tk.StringVar, browse_cmd) -> None:
        parent.columnconfigure(1, weight=1)
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", padx=(0, 8), pady=4)
        ttk.Entry(parent, textvariable=var).grid(row=row, column=1, sticky="ew", pady=4)
        ttk.Button(parent, text="Browse", command=browse_cmd).grid(row=row, column=2, padx=(8, 0), pady=4)

    def _build_zip_tab(self, tab: ttk.Frame) -> None:
        self._path_row(tab, 0, "Repo root", self.repo_var, self.choose_repo)
        self._path_row(tab, 1, "Output folder", self.output_var, self.choose_output)
        self._path_row(tab, 2, "Zip name optional", self.name_var, self.noop)

        scopes = ttk.LabelFrame(tab, text="Instrumentation Scope")
        scopes.grid(row=3, column=0, columnspan=3, sticky="ew", pady=(10, 0))
        ttk.Checkbutton(scopes, text="UnitFrames", variable=self.scope_unitframes).grid(row=0, column=0, sticky="w", padx=8, pady=6)
        ttk.Checkbutton(scopes, text="Castbars", variable=self.scope_castbars).grid(row=0, column=1, sticky="w", padx=8, pady=6)
        ttk.Checkbutton(scopes, text="ClassPower", variable=self.scope_classpower).grid(row=0, column=2, sticky="w", padx=8, pady=6)
        ttk.Checkbutton(scopes, text="All first-party Lua", variable=self.scope_all).grid(row=0, column=3, sticky="w", padx=8, pady=6)

        opts = ttk.LabelFrame(tab, text="Build Options")
        opts.grid(row=4, column=0, columnspan=3, sticky="ew", pady=(10, 0))
        ttk.Checkbutton(opts, text="No static instrumentation", variable=self.no_static).grid(row=0, column=0, sticky="w", padx=8, pady=6)
        ttk.Checkbutton(opts, text="Keep staging folder", variable=self.keep_stage).grid(row=0, column=1, sticky="w", padx=8, pady=6)

    def _build_analyze_tab(self, tab: ttk.Frame) -> None:
        self._path_row(tab, 0, "Trace file", self.trace_var, self.choose_trace)
        self._path_row(tab, 1, "Report file", self.report_var, self.choose_report)
        ttk.Label(tab, text="Top rows").grid(row=2, column=0, sticky="w", padx=(0, 8), pady=4)
        ttk.Entry(tab, textvariable=self.top_var, width=8).grid(row=2, column=1, sticky="w", pady=4)
        ttk.Checkbutton(tab, text="Skip source coverage scan", variable=self.no_coverage).grid(row=3, column=1, sticky="w", pady=4)

    def noop(self) -> None:
        return

    def choose_repo(self) -> None:
        path = filedialog.askdirectory(initialdir=self.repo_var.get() or str(ROOT))
        if path:
            self.repo_var.set(path)

    def choose_output(self) -> None:
        path = filedialog.askdirectory(initialdir=self.output_var.get() or str(DOWNLOADS))
        if path:
            self.output_var.set(path)

    def choose_trace(self) -> None:
        path = filedialog.askopenfilename(
            initialdir=str(Path(self.trace_var.get()).parent if self.trace_var.get() else DOWNLOADS),
            title="Select !!!Perfy.lua",
            filetypes=[("Lua SavedVariables", "*.lua"), ("All files", "*.*")],
        )
        if path:
            self.trace_var.set(path)

    def choose_report(self) -> None:
        path = filedialog.asksaveasfilename(
            initialdir=str(Path(self.report_var.get()).parent if self.report_var.get() else DOWNLOADS),
            initialfile=Path(self.report_var.get()).name or "MSUF_Perfy_Offline_Report.txt",
            defaultextension=".txt",
            filetypes=[("Text report", "*.txt"), ("All files", "*.*")],
        )
        if path:
            self.report_var.set(path)

    def scopes(self) -> list[str]:
        out = []
        if self.scope_unitframes.get():
            out.append("UnitFrames")
        if self.scope_castbars.get():
            out.append("Castbars")
        if self.scope_classpower.get():
            out.append("ClassPower")
        return out or ["UnitFrames"]

    def build_zip(self) -> None:
        cmd = [sys.executable, str(TOOL), "build", "--repo-root", self.repo_var.get(), "--output-dir", self.output_var.get()]
        if self.scope_all.get():
            cmd.append("--all")
        else:
            for scope in self.scopes():
                cmd.extend(["--scope", scope])
        if self.name_var.get().strip():
            cmd.extend(["--name", self.name_var.get().strip()])
        if self.no_static.get():
            cmd.append("--no-static")
        if self.keep_stage.get():
            cmd.append("--keep-stage")
        self.run_command(cmd, "Building Perfy zip...")

    def analyze_trace(self) -> None:
        try:
            top = str(max(1, int(self.top_var.get() or "35")))
        except ValueError:
            messagebox.showerror("Invalid value", "Top rows must be a number.")
            return
        cmd = [
            sys.executable,
            str(TOOL),
            "analyze",
            self.trace_var.get(),
            "--out",
            self.report_var.get(),
            "--top",
            top,
            "--source-root",
            str(ROOT / "MidnightSimpleUnitFrames"),
            "--scope",
            "UnitFrames",
        ]
        if self.no_coverage.get():
            cmd.append("--no-coverage")
        self.run_command(cmd, "Analyzing trace...")

    def run_command(self, cmd: list[str], status: str) -> None:
        if self.running:
            messagebox.showinfo("Busy", "A Perfy task is already running.")
            return
        self.running = True
        self.status_var.set(status)
        self.build_button.configure(state=tk.DISABLED)
        self.analyze_button.configure(state=tk.DISABLED)
        self.append_log("> " + " ".join(f'"{part}"' if " " in part else part for part in cmd) + "\n")

        def worker() -> None:
            try:
                proc = subprocess.Popen(
                    cmd,
                    cwd=str(ROOT),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                )
                assert proc.stdout is not None
                for line in proc.stdout:
                    self.log_queue.put(line)
                code = proc.wait()
                self.log_queue.put(f"\n[exit {code}]\n")
                self.log_queue.put("__DONE__" if code == 0 else "__FAILED__")
            except Exception as exc:
                self.log_queue.put(f"\n[error] {exc}\n")
                self.log_queue.put("__FAILED__")

        threading.Thread(target=worker, daemon=True).start()

    def _drain_log(self) -> None:
        try:
            while True:
                item = self.log_queue.get_nowait()
                if item in ("__DONE__", "__FAILED__"):
                    self.running = False
                    self.build_button.configure(state=tk.NORMAL)
                    self.analyze_button.configure(state=tk.NORMAL)
                    self.status_var.set("Done" if item == "__DONE__" else "Failed")
                    continue
                self.append_log(item)
        except queue.Empty:
            pass
        self.after(100, self._drain_log)

    def append_log(self, text: str) -> None:
        self.log.insert(tk.END, text)
        self.log.see(tk.END)

    def clear_log(self) -> None:
        self.log.delete("1.0", tk.END)
        self.status_var.set("Ready")

    def open_report(self) -> None:
        self.open_path(Path(self.report_var.get()))

    def open_path(self, path: Path) -> None:
        try:
            if not path.exists():
                messagebox.showwarning("Not found", str(path))
                return
            os.startfile(str(path))
        except Exception as exc:
            messagebox.showerror("Open failed", str(exc))


def main() -> int:
    app = PerfyUI()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
