import tkinter as tk
from tkinter import ttk, messagebox, filedialog
import csv
import math
import time
from datetime import datetime, timezone

import numpy as np

from config import APP_TITLE, DEFAULT_BAUD, DEFAULT_PORT, DEFAULT_FS
from data.serial_receiver import SerialReceiver, available_ports, SERIAL_AVAILABLE

try:
    from matplotlib.figure import Figure
    from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
    MATPLOTLIB_OK = True
except Exception:
    MATPLOTLIB_OK = False


class DataModel:
    def __init__(self):
        self.source = "FPGA Internal Test"
        self.load_type = "Resistive"
        self.connected = False
        self.fs = DEFAULT_FS

        self.vrms = 0.0
        self.irms = 0.0
        self.freq = 0.0
        self.p = 0.0
        self.s = 0.0
        self.q = 0.0
        self.pf = 0.0
        self.thd_v = 0.0
        self.thd_i = 0.0

        # Minimum measured RMS levels required before derived power-
        # quality quantities are treated as valid.  These limits sit
        # above the measured zero-input noise floors (about 0.20 V and
        # 0.0077 A) while remaining below the present low-level tests.
        self.minimum_valid_vrms = 0.5
        self.minimum_valid_irms = 0.015
        self.voltage_signal_valid = False
        self.current_signal_valid = False

        self.voltage_samples = []
        self.current_samples = []
        self.voltage_raw = []
        self.current_raw = []
        self.sample_protocol_version = None
        self.sample_sequence = None

        self.metric_packets = 0
        self.sample_packets = 0
        self.sync_losses = 0
        self.last_metric_time = None
        self.last_sample_time = None

        self.nominal_vrms = 1.08
        self.events = []
        self.last_event = "None"
        self.current_pq_state = "Normal"
        self.active_events = set()
        self.thresholds = {
            "Sag": 0.90,
            "Swell": 1.10,
            "Under-frequency": 49.5,
            "Over-frequency": 50.5,
            "High THD-V": 5.0,
            "High THD-I": 5.0,
        }

    def update_metrics(self, m):
        self.vrms = m.vrms_v
        self.irms = m.irms_a

        self.voltage_signal_valid = (
            self.vrms >= self.minimum_valid_vrms
        )
        self.current_signal_valid = (
            self.irms >= self.minimum_valid_irms
        )

        # Frequency and voltage THD require a valid voltage waveform.
        self.freq = (
            m.frequency_hz if self.voltage_signal_valid else 0.0
        )
        self.thd_v = (
            m.thd_v_pct if self.voltage_signal_valid else 0.0
        )

        # Current THD requires a valid current waveform.
        self.thd_i = (
            m.thd_i_pct if self.current_signal_valid else 0.0
        )

        # PF and power require both voltage and current waveforms.
        power_measurement_valid = (
            self.voltage_signal_valid and self.current_signal_valid
        )
        self.p = m.active_power_w if power_measurement_valid else 0.0
        self.s = m.apparent_power_va if power_measurement_valid else 0.0
        self.q = math.sqrt(max(self.s**2 - self.p**2, 0.0))
        self.pf = m.power_factor if power_measurement_valid else 0.0
        self.metric_packets += 1
        self.last_metric_time = time.time()
        self._evaluate_events()

    def update_samples(self, frame):
        self.fs = frame.sample_rate_hz
        self.voltage_samples = frame.voltage_v
        self.current_samples = frame.current_a
        self.voltage_raw = frame.voltage_raw
        self.current_raw = frame.current_raw
        self.sample_protocol_version = frame.version
        self.sample_sequence = frame.sequence
        self.sample_packets += 1
        self.last_sample_time = time.time()

    def _log_event(self, name, measured, threshold):
        now = time.strftime("%H:%M:%S")
        self.last_event = name
        self.events.insert(0, (now, name, measured, threshold))
        self.events = self.events[:100]

    def _evaluate_events(self):
        frequency_available = (
            self.voltage_signal_valid and self.freq > 0.0
        )

        checks = {
            "Sag": (
                self.voltage_signal_valid
                and self.vrms
                < self.thresholds["Sag"] * self.nominal_vrms
            ),
            "Swell": (
                self.voltage_signal_valid
                and self.vrms
                > self.thresholds["Swell"] * self.nominal_vrms
            ),
            "Under-frequency": (
                frequency_available
                and self.freq < self.thresholds["Under-frequency"]
            ),
            "Over-frequency": (
                frequency_available
                and self.freq > self.thresholds["Over-frequency"]
            ),
            "High THD-V": (
                self.voltage_signal_valid
                and self.thd_v > self.thresholds["High THD-V"]
            ),
            "High THD-I": (
                self.current_signal_valid
                and self.thd_i > self.thresholds["High THD-I"]
            ),
        }

        active_now = [name for name, active in checks.items() if active]
        self.current_pq_state = "Normal" if not active_now else " + ".join(active_now)

        for name, active in checks.items():
            if active and name not in self.active_events:
                if name in ("Sag", "Swell"):
                    measured = f"{self.vrms:.2f} V"
                    threshold = (
                        f"{self.thresholds[name] * self.nominal_vrms:.1f} V "
                        f"({self.thresholds[name]:.2f} pu)"
                    )
                elif name in ("Under-frequency", "Over-frequency"):
                    measured = f"{self.freq:.3f} Hz"
                    threshold = f"{self.thresholds[name]:.2f} Hz"
                elif name == "High THD-V":
                    measured = f"{self.thd_v:.2f}%"
                    threshold = f"{self.thresholds[name]:.2f}%"
                else:
                    measured = f"{self.thd_i:.2f}%"
                    threshold = f"{self.thresholds[name]:.2f}%"

                self._log_event(name, measured, threshold)
                self.active_events.add(name)

            elif not active:
                self.active_events.discard(name)



class MetricCard(ttk.Frame):
    def __init__(self, parent, title, unit=""):
        super().__init__(parent, padding=12, style="Card.TFrame")
        ttk.Label(self, text=title, style="CardTitle.TLabel").pack(anchor="w")
        self.value = ttk.Label(self, text="--", style="CardValue.TLabel")
        self.value.pack(anchor="w", pady=(3, 0))
        ttk.Label(self, text=unit, style="CardUnit.TLabel").pack(anchor="w")

    def set(self, value):
        self.value.configure(text=value)


class DashboardPage(ttk.Frame):
    def __init__(self, parent, model):
        super().__init__(parent, padding=12)
        self.model = model

        for c in range(3):
            self.columnconfigure(c, weight=1)

        self.cards = {}
        specs = [
            ("Vrms", "Vrms", "V"),
            ("Irms", "Irms", "A"),
            ("Frequency", "Frequency", "Hz"),
            ("PF", "Power Factor", ""),
            ("THD-V", "THD-V", "%"),
            ("THD-I", "THD-I", "%"),
            ("P", "Active Power", "W"),
            ("Q", "Reactive Power", "VAR"),
            ("S", "Apparent Power", "VA"),
        ]

        for idx, (key, title, unit) in enumerate(specs):
            card = MetricCard(self, title, unit)
            card.grid(
                row=idx // 3,
                column=idx % 3,
                sticky="nsew",
                padx=6,
                pady=6
            )
            self.cards[key] = card

        status = ttk.LabelFrame(
            self,
            text="Live FPGA Status",
            padding=12
        )
        status.grid(
            row=3,
            column=0,
            columnspan=3,
            sticky="ew",
            padx=6,
            pady=8
        )
        status.columnconfigure(1, weight=1)

        ttk.Label(status, text="Current PQ State").grid(row=0, column=0, sticky="w")
        self.current_state = ttk.Label(
            status,
            text="Normal",
            style="StatusGood.TLabel"
        )
        self.current_state.grid(row=0, column=1, sticky="e")

        ttk.Label(status, text="Last Detected Event").grid(
            row=1, column=0, sticky="w", pady=(8, 0)
        )
        self.last_event = ttk.Label(status, text="None")
        self.last_event.grid(row=1, column=1, sticky="e", pady=(8, 0))

        ttk.Label(status, text="Latest sample frame").grid(
            row=2, column=0, sticky="w", pady=(8, 0)
        )
        self.sample_state = ttk.Label(status, text="Waiting")
        self.sample_state.grid(row=2, column=1, sticky="e", pady=(8, 0))

        context = ttk.LabelFrame(
            self,
            text="Current Test Context",
            padding=10
        )
        context.grid(
            row=4,
            column=0,
            columnspan=3,
            sticky="ew",
            padx=6,
            pady=(0, 8)
        )
        context.columnconfigure(1, weight=1)

        ttk.Label(context, text="Selected load").grid(row=0, column=0, sticky="w")
        self.load_context = ttk.Label(context, text=self.model.load_type)
        self.load_context.grid(row=0, column=1, sticky="e")

        ttk.Label(context, text="Interpretation focus").grid(
            row=1, column=0, sticky="w", pady=(6, 0)
        )
        self.focus_context = ttk.Label(context, text="")
        self.focus_context.grid(row=1, column=1, sticky="e", pady=(6, 0))

    def refresh(self):
        m = self.model

        self.cards["Vrms"].set(f"{m.vrms:.2f}")
        self.cards["Irms"].set(f"{m.irms:.4f}")
        self.cards["Frequency"].set(f"{m.freq:.3f}")
        self.cards["PF"].set(f"{m.pf:.3f}")
        self.cards["THD-V"].set(f"{m.thd_v:.2f}")
        self.cards["THD-I"].set(f"{m.thd_i:.2f}")
        self.cards["P"].set(f"{m.p:.2f}")
        self.cards["Q"].set(f"{m.q:.2f}")
        self.cards["S"].set(f"{m.s:.2f}")

        self.last_event.configure(text=m.last_event)
        self.current_state.configure(text=m.current_pq_state)
        self.load_context.configure(text=m.load_type)

        focus_map = {
            "Resistive": "P ≈ S, PF ≈ 1, Q ≈ 0, V/I nearly in phase",
            "Inductive / RL": "P–Q–S, lagging current, phase angle and PF",
            "Nonlinear": "THD-I/THD-V, harmonics, distortion and total PF",
        }
        self.focus_context.configure(
            text=focus_map.get(m.load_type, "")
        )

        if m.current_pq_state == "Normal":
            self.current_state.configure(style="StatusGood.TLabel")
        else:
            self.current_state.configure(style="StatusBad.TLabel")

        if m.last_sample_time is None:
            self.sample_state.configure(text="Waiting")
        else:
            self.sample_state.configure(
                text=(
                    f"Frame #{m.sample_sequence} · "
                    f"{len(m.voltage_samples)} samples · "
                    f"{time.time() - m.last_sample_time:.1f}s ago"
                )
            )



class RawADCPage(ttk.Frame):
    """Display and record the original unsigned 16-bit ADS8320 codes."""

    def __init__(self, parent, model, app):
        super().__init__(parent, padding=12)
        self.model = model
        self.app = app
        self.columnconfigure(0, weight=1)
        self.rowconfigure(2, weight=1)

        summary = ttk.LabelFrame(self, text="Latest Raw ADC Frame", padding=12)
        summary.grid(row=0, column=0, sticky="ew")
        for column in range(4):
            summary.columnconfigure(column, weight=1)

        ttk.Label(summary, text="Voltage ADC code").grid(row=0, column=0, sticky="w")
        ttk.Label(summary, text="Current ADC code").grid(row=0, column=1, sticky="w")
        ttk.Label(summary, text="Frame").grid(row=0, column=2, sticky="w")
        ttk.Label(summary, text="Protocol").grid(row=0, column=3, sticky="w")

        self.v_code = ttk.Label(summary, text="--", style="CardValue.TLabel")
        self.i_code = ttk.Label(summary, text="--", style="CardValue.TLabel")
        self.frame_info = ttk.Label(summary, text="Waiting")
        self.protocol_info = ttk.Label(summary, text="Waiting")
        self.v_code.grid(row=1, column=0, sticky="w", pady=(4, 0))
        self.i_code.grid(row=1, column=1, sticky="w", pady=(4, 0))
        self.frame_info.grid(row=1, column=2, sticky="w", pady=(4, 0))
        self.protocol_info.grid(row=1, column=3, sticky="w", pady=(4, 0))

        controls = ttk.Frame(self)
        controls.grid(row=1, column=0, sticky="ew", pady=(10, 8))
        ttk.Button(
            controls,
            text="Start Raw CSV Recording",
            command=self._start_recording,
        ).pack(side="left")
        ttk.Button(
            controls,
            text="Stop Recording",
            command=self._stop_recording,
        ).pack(side="left", padx=6)
        self.recording_state = ttk.Label(controls, text="Not recording")
        self.recording_state.pack(side="left", padx=12)

        columns = ("index", "voltage_raw", "current_raw", "voltage_v", "current_a")
        self.table = ttk.Treeview(self, columns=columns, show="headings", height=18)
        self.table.heading("index", text="Sample")
        self.table.heading("voltage_raw", text="Voltage raw code")
        self.table.heading("current_raw", text="Current raw code")
        self.table.heading("voltage_v", text="Scaled voltage V")
        self.table.heading("current_a", text="Scaled current A")
        self.table.column("index", width=80, anchor="center")
        self.table.column("voltage_raw", width=150, anchor="center")
        self.table.column("current_raw", width=150, anchor="center")
        self.table.column("voltage_v", width=150, anchor="e")
        self.table.column("current_a", width=150, anchor="e")
        self.table.grid(row=2, column=0, sticky="nsew")

        scrollbar = ttk.Scrollbar(self, orient="vertical", command=self.table.yview)
        scrollbar.grid(row=2, column=1, sticky="ns")
        self.table.configure(yscrollcommand=scrollbar.set)

        ttk.Label(
            self,
            text=(
                "The table shows the first 100 pairs from the latest frame. "
                "CSV recording saves every pair in every received frame."
            ),
        ).grid(row=3, column=0, sticky="w", pady=(8, 0))

        self._last_sequence = None

    def _start_recording(self):
        path = self.app.start_raw_recording()
        if path:
            self.recording_state.configure(text=f"Recording: {path}")

    def _stop_recording(self):
        self.app.stop_raw_recording()
        self.recording_state.configure(text="Not recording")

    def refresh(self):
        m = self.model
        if m.voltage_raw and m.current_raw:
            self.v_code.configure(text=str(m.voltage_raw[-1]))
            self.i_code.configure(text=str(m.current_raw[-1]))
            self.frame_info.configure(
                text=f"#{m.sample_sequence}, {len(m.voltage_raw)} pairs"
            )
            self.protocol_info.configure(text=f"AA56 version {m.sample_protocol_version}")

            if self._last_sequence != m.sample_sequence:
                self._last_sequence = m.sample_sequence
                for item in self.table.get_children():
                    self.table.delete(item)
                limit = min(100, len(m.voltage_raw), len(m.current_raw))
                for index in range(limit):
                    voltage_v = m.voltage_samples[index] if index < len(m.voltage_samples) else 0.0
                    current_a = m.current_samples[index] if index < len(m.current_samples) else 0.0
                    self.table.insert(
                        "",
                        "end",
                        values=(
                            index,
                            m.voltage_raw[index],
                            m.current_raw[index],
                            f"{voltage_v:.6f}",
                            f"{current_a:.9f}",
                        ),
                    )
        elif m.sample_protocol_version == 1:
            self.protocol_info.configure(text="AA56 version 1 has no raw codes")

        if self.app.raw_log_file is None:
            self.recording_state.configure(text="Not recording")


class WaveformsPage(ttk.Frame):
    def __init__(self, parent, model):
        super().__init__(parent, padding=12)
        self.model = model

        self.columnconfigure(0, weight=1)
        self.rowconfigure(2, weight=1)

        # --------------------------------------------------------------
        # Header / source information
        # --------------------------------------------------------------
        self.info = ttk.Label(
            self,
            text="Waiting for FPGA sample frame..."
        )
        self.info.grid(
            row=0,
            column=0,
            sticky="w",
            pady=(0, 6)
        )

        # --------------------------------------------------------------
        # Live waveform interpretation strip
        # --------------------------------------------------------------
        strip = ttk.LabelFrame(
            self,
            text="Waveform Indicators",
            padding=10
        )
        strip.grid(
            row=1,
            column=0,
            sticky="ew",
            pady=(0, 8)
        )

        for c in range(7):
            strip.columnconfigure(c, weight=1)

        indicator_specs = [
            ("Current State", "state_lbl"),
            ("Vrms", "vrms_lbl"),
            ("ΔV vs 230 V", "dv_lbl"),
            ("Frequency", "freq_lbl"),
            ("THD-V", "thdv_lbl"),
            ("THD-I", "thdi_lbl"),
            ("Power Factor", "pf_lbl"),
        ]

        for col, (title, attr) in enumerate(indicator_specs):
            ttk.Label(
                strip,
                text=title
            ).grid(
                row=0,
                column=col,
                sticky="w",
                padx=(0, 8)
            )

            lbl = ttk.Label(
                strip,
                text="--"
            )
            lbl.grid(
                row=1,
                column=col,
                sticky="w",
                padx=(0, 8)
            )
            setattr(self, attr, lbl)

        self.show_reference = tk.BooleanVar(value=True)

        ttk.Checkbutton(
            strip,
            text="Show nominal reference overlay",
            variable=self.show_reference,
            command=self.refresh
        ).grid(
            row=2,
            column=0,
            columnspan=3,
            sticky="w",
            pady=(8, 0)
        )

        ttk.Label(
            strip,
            text="Reference: 230 V RMS, 1 A RMS, 50 Hz, PF = 1"
        ).grid(
            row=2,
            column=3,
            columnspan=4,
            sticky="e",
            pady=(8, 0)
        )

        # --------------------------------------------------------------
        # Waveform figure
        # --------------------------------------------------------------
        if MATPLOTLIB_OK:
            fig = Figure(
                figsize=(9, 6.8),
                dpi=100
            )

            self.ax_v = fig.add_subplot(211)
            self.ax_i = fig.add_subplot(212)

            # Explicit margins prevent title and x-label clipping.
            fig.subplots_adjust(
                left=0.08,
                right=0.985,
                top=0.93,
                bottom=0.11,
                hspace=0.34
            )

            self.canvas = FigureCanvasTkAgg(
                fig,
                master=self
            )

            self.canvas.get_tk_widget().grid(
                row=2,
                column=0,
                sticky="nsew"
            )

        else:
            self.ax_v = None
            self.ax_i = None


    @staticmethod
    def _estimate_start_phase(samples, fs, freq_hz):
        """
        Estimate the measured voltage phase at t=0 using a least-squares
        sine/cosine fit. This is used only to align the nominal overlay
        visually with the measured frame.
        """
        x = np.asarray(samples, dtype=float)

        if len(x) < 8 or fs <= 0 or freq_hz <= 0:
            return 0.0

        n = np.arange(len(x), dtype=float)
        w = 2.0 * np.pi * freq_hz / fs

        A = np.column_stack((
            np.sin(w * n),
            np.cos(w * n),
            np.ones(len(x))
        ))

        coeff, _, _, _ = np.linalg.lstsq(
            A,
            x,
            rcond=None
        )

        sin_c = coeff[0]
        cos_c = coeff[1]

        # a*sin(wt)+b*cos(wt) == R*sin(wt+phi)
        return float(np.arctan2(cos_c, sin_c))


    def refresh(self):
        if (
            self.ax_v is None
            or self.ax_i is None
            or not self.model.voltage_samples
            or not self.model.current_samples
        ):
            return

        m = self.model

        v = np.asarray(
            m.voltage_samples,
            dtype=float
        )

        i = np.asarray(
            m.current_samples,
            dtype=float
        )

        t_s = np.arange(len(v), dtype=float) / m.fs
        t_ms = t_s * 1000.0

        # --------------------------------------------------------------
        # Indicator strip
        # --------------------------------------------------------------
        delta_v_pct = (
            100.0 * (m.vrms - m.nominal_vrms) / m.nominal_vrms
            if m.nominal_vrms
            else 0.0
        )

        self.state_lbl.configure(
            text=m.current_pq_state
        )

        if m.current_pq_state == "Normal":
            self.state_lbl.configure(
                style="StatusGood.TLabel"
            )
        else:
            self.state_lbl.configure(
                style="StatusBad.TLabel"
            )

        self.vrms_lbl.configure(
            text=f"{m.vrms:.2f} V"
        )

        self.dv_lbl.configure(
            text=f"{delta_v_pct:+.1f} %"
        )

        self.freq_lbl.configure(
            text=f"{m.freq:.3f} Hz"
        )

        self.thdv_lbl.configure(
            text=f"{m.thd_v:.2f} %"
        )

        self.thdi_lbl.configure(
            text=f"{m.thd_i:.2f} %"
        )

        self.pf_lbl.configure(
            text=f"{m.pf:.3f}"
        )

        self.info.configure(
            text=(
                f"{len(v)} samples at {m.fs:,} S/s · "
                f"source: {m.source} · "
                f"frame #{m.sample_sequence}"
            )
        )

        # --------------------------------------------------------------
        # Measured traces
        # --------------------------------------------------------------
        self.ax_v.clear()
        self.ax_i.clear()

        self.ax_v.plot(
            t_ms,
            v,
            label="FPGA measured voltage"
        )

        self.ax_i.plot(
            t_ms,
            i,
            label="FPGA measured current"
        )

        # --------------------------------------------------------------
        # Nominal/reference overlays
        #
        # Align phase at the beginning of the measured frame so:
        # - amplitude differences expose sag/swell
        # - frequency differences accumulate visibly over time
        # - harmonic distortion appears as shape deviation
        # - current phase displacement is visible against PF=1 reference
        # --------------------------------------------------------------
        if self.show_reference.get():
            measured_f0 = (
                estimate_fundamental_frequency(
                    v,
                    m.fs,
                    45.0,
                    55.0
                )
            )

            phase0 = self._estimate_start_phase(
                v,
                m.fs,
                measured_f0
            )

            ref_v_peak = (
                m.nominal_vrms *
                math.sqrt(2.0)
            )

            ref_i_rms = 1.0
            ref_i_peak = (
                ref_i_rms *
                math.sqrt(2.0)
            )

            ref_v = (
                ref_v_peak *
                np.sin(
                    2.0 * np.pi * 50.0 * t_s +
                    phase0
                )
            )

            ref_i = (
                ref_i_peak *
                np.sin(
                    2.0 * np.pi * 50.0 * t_s +
                    phase0
                )
            )

            self.ax_v.plot(
                t_ms,
                ref_v,
                linestyle="--",
                linewidth=1.2,
                alpha=0.75,
                label="Nominal reference (230 V, 50 Hz)"
            )

            self.ax_i.plot(
                t_ms,
                ref_i,
                linestyle="--",
                linewidth=1.2,
                alpha=0.75,
                label="Nominal reference (1 A, PF=1)"
            )

        # --------------------------------------------------------------
        # Plot formatting
        # --------------------------------------------------------------
        self.ax_v.set_title(
            "FPGA-Derived Voltage Waveform"
        )
        self.ax_v.set_ylabel(
            "Voltage (V)"
        )
        self.ax_v.grid(
            True,
            alpha=0.25
        )
        self.ax_v.legend(
            loc="upper right"
        )

        self.ax_i.set_title(
            "FPGA-Derived Current Waveform"
        )
        self.ax_i.set_xlabel(
            "Time (ms)"
        )
        self.ax_i.set_ylabel(
            "Current (A)"
        )
        self.ax_i.grid(
            True,
            alpha=0.25
        )
        self.ax_i.legend(
            loc="upper right"
        )

        self.canvas.draw_idle()


def estimate_fundamental_frequency(samples, fs, f_min=45.0, f_max=55.0):
    """
    Independently estimate the mains fundamental from the AA56 waveform.

    The GUI must not use the FPGA frequency result as its reference frequency,
    otherwise an FPGA frequency-estimator error contaminates the GUI THD
    comparison.
    """
    x = np.asarray(samples, dtype=float)

    if len(x) < 16 or fs <= 0:
        return 50.0

    x = x - np.mean(x)
    n = np.arange(len(x), dtype=float)

    def fundamental_fit_error(freq):
        w = 2.0 * np.pi * freq / fs

        # Fundamental plus a small allowance for 3rd/5th harmonic content.
        cols = [
            np.sin(w * n),
            np.cos(w * n),
            np.sin(3.0 * w * n),
            np.cos(3.0 * w * n),
            np.sin(5.0 * w * n),
            np.cos(5.0 * w * n),
        ]

        A = np.column_stack(cols)
        coeff, _, _, _ = np.linalg.lstsq(A, x, rcond=None)
        residual = x - A @ coeff
        return float(np.dot(residual, residual))

    coarse = np.arange(f_min, f_max + 0.0001, 0.05)
    coarse_errors = np.array(
        [fundamental_fit_error(f) for f in coarse]
    )
    best = float(
        coarse[int(np.argmin(coarse_errors))]
    )

    fine_min = max(f_min, best - 0.10)
    fine_max = min(f_max, best + 0.10)

    fine = np.arange(
        fine_min,
        fine_max + 0.000001,
        0.001
    )

    fine_errors = np.array(
        [fundamental_fit_error(f) for f in fine]
    )

    return float(
        fine[int(np.argmin(fine_errors))]
    )



def waveform_phase_analysis(voltage_samples, current_samples, fs, fundamental_hz):
    """
    Independent waveform-derived fundamental phase relationship.

    Returns:
        phase_deg:
            current phase relative to voltage.
            Negative => current lags voltage.
            Positive => current leads voltage.
        displacement_pf:
            cos(phase difference), based on the fundamentals only.
        relation:
            human-readable lead/lag description.
    """
    v = np.asarray(voltage_samples, dtype=float)
    i = np.asarray(current_samples, dtype=float)

    n_samples = min(len(v), len(i))

    if n_samples < 16 or fs <= 0 or fundamental_hz <= 0:
        return None, None, "Unavailable"

    v = v[:n_samples]
    i = i[:n_samples]
    n = np.arange(n_samples, dtype=float)

    w = 2.0 * np.pi * fundamental_hz / fs

    A = np.column_stack((
        np.sin(w * n),
        np.cos(w * n),
        np.ones(n_samples)
    ))

    cv, _, _, _ = np.linalg.lstsq(A, v, rcond=None)
    ci, _, _, _ = np.linalg.lstsq(A, i, rcond=None)

    phase_v = float(np.arctan2(cv[1], cv[0]))
    phase_i = float(np.arctan2(ci[1], ci[0]))

    phase_deg = math.degrees(phase_i - phase_v)

    while phase_deg > 180.0:
        phase_deg -= 360.0
    while phase_deg <= -180.0:
        phase_deg += 360.0

    displacement_pf = math.cos(math.radians(phase_deg))

    if abs(phase_deg) < 2.0:
        relation = "Approximately in phase"
    elif phase_deg < 0.0:
        relation = f"Current lags voltage by {abs(phase_deg):.2f}°"
    else:
        relation = f"Current leads voltage by {abs(phase_deg):.2f}°"

    return phase_deg, displacement_pf, relation


def harmonic_least_squares(samples, fs, fundamental_hz, max_harmonic=25):
    """
    Jointly fit DC + sine/cosine terms at h*f0.

    This handles a short frame that is not exactly an integer number of cycles
    much better than a windowed FFT.
    """
    x = np.asarray(samples, dtype=float)

    if len(x) < 16 or fs <= 0 or fundamental_hz <= 0:
        return [], [], 0.0

    n = np.arange(len(x), dtype=float)

    harmonics = []
    columns = [np.ones(len(x))]

    for h in range(1, max_harmonic + 1):
        f = h * fundamental_hz

        if f >= fs / 2:
            break

        w = 2.0 * np.pi * f / fs

        columns.append(
            np.sin(w * n)
        )

        columns.append(
            np.cos(w * n)
        )

        harmonics.append(h)

    A = np.column_stack(columns)

    coeff, _, _, _ = np.linalg.lstsq(
        A,
        x,
        rcond=None
    )

    magnitudes = []
    index = 1

    for _ in harmonics:
        a = coeff[index]
        b = coeff[index + 1]

        magnitudes.append(
            float(np.hypot(a, b))
        )

        index += 2

    if (
        not magnitudes
        or magnitudes[0] <= 1e-15
    ):
        return (
            harmonics,
            [0.0] * len(harmonics),
            0.0
        )

    h1 = magnitudes[0]

    percent = [
        100.0 * m / h1
        for m in magnitudes
    ]

    if len(magnitudes) > 1:
        thd = (
            100.0
            * math.sqrt(
                sum(
                    m * m
                    for m in magnitudes[1:]
                )
            )
            / h1
        )
    else:
        thd = 0.0

    return harmonics, percent, thd


class SpectrumPage(ttk.Frame):
    def __init__(self, parent, model):
        super().__init__(parent, padding=12)
        self.model = model
        self.columnconfigure(0, weight=1)
        self.rowconfigure(2, weight=1)

        self.info = ttk.Label(self, text="Waiting for FPGA sample frame...")
        self.info.grid(row=0, column=0, sticky="w", pady=(0, 8))

        compare = ttk.LabelFrame(
            self,
            text="Independent FPGA vs GUI Reference",
            padding=10
        )
        compare.grid(row=1, column=0, sticky="ew", pady=(0, 8))

        for c in range(6):
            compare.columnconfigure(c, weight=1)

        labels = [
            ("FPGA Frequency", "fpga_freq_lbl", "StatusGood.TLabel"),
            ("Waveform Ref. Frequency", "gui_freq_lbl", None),
            ("FPGA THD-V", "fpga_thdv_lbl", "StatusGood.TLabel"),
            ("GUI Ref. THD-V", "gui_thdv_lbl", None),
            ("FPGA THD-I", "fpga_thdi_lbl", "StatusGood.TLabel"),
            ("GUI Ref. THD-I", "gui_thdi_lbl", None),
        ]

        for col, (title, attr, style) in enumerate(labels):
            ttk.Label(compare, text=title).grid(row=0, column=col, sticky="w")
            lbl = ttk.Label(compare, text="--", style=style if style else "TLabel")
            lbl.grid(row=1, column=col, sticky="w")
            setattr(self, attr, lbl)

        if MATPLOTLIB_OK:
            fig = Figure(figsize=(9, 7), dpi=100)
            self.ax_v = fig.add_subplot(211)
            self.ax_i = fig.add_subplot(212)
            fig.subplots_adjust(hspace=0.55, top=0.94, bottom=0.10)
            self.canvas = FigureCanvasTkAgg(fig, master=self)
            self.canvas.get_tk_widget().grid(row=2, column=0, sticky="nsew")
        else:
            self.ax_v = None
            self.ax_i = None

    def refresh(self):
        if (
            self.ax_v is None
            or self.ax_i is None
            or not self.model.voltage_samples
            or not self.model.current_samples
        ):
            return

        reference_f0 = estimate_fundamental_frequency(
            self.model.voltage_samples,
            self.model.fs,
            45.0,
            55.0
        )

        h_v, v_pct, gui_thdv = harmonic_least_squares(
            self.model.voltage_samples,
            self.model.fs,
            reference_f0,
            25
        )

        h_i, i_pct, gui_thdi = harmonic_least_squares(
            self.model.current_samples,
            self.model.fs,
            reference_f0,
            25
        )

        self.fpga_freq_lbl.configure(text=f"{self.model.freq:.3f} Hz")
        self.gui_freq_lbl.configure(text=f"{reference_f0:.3f} Hz")
        self.fpga_thdv_lbl.configure(text=f"{self.model.thd_v:.3f} %")
        self.gui_thdv_lbl.configure(text=f"{gui_thdv:.3f} %")
        self.fpga_thdi_lbl.configure(text=f"{self.model.thd_i:.3f} %")
        self.gui_thdi_lbl.configure(text=f"{gui_thdi:.3f} %")

        self.info.configure(
            text=(
                f"Independent waveform analysis · "
                f"{len(self.model.voltage_samples)} samples at "
                f"{self.model.fs:,} S/s · "
                f"source: {self.model.source}"
            )
        )

        self.ax_v.clear()
        self.ax_i.clear()

        self.ax_v.bar(h_v, v_pct)
        self.ax_v.set_ylabel("% of Fundamental")
        self.ax_v.set_title(
            "Voltage Harmonics — Independent Analysis of FPGA AA56 Samples"
        )
        self.ax_v.grid(True, axis="y", alpha=0.25)

        self.ax_i.bar(h_i, i_pct)
        self.ax_i.set_xlabel("Harmonic Number")
        self.ax_i.set_ylabel("% of Fundamental")
        self.ax_i.set_title(
            "Current Harmonics — Independent Analysis of FPGA AA56 Samples"
        )
        self.ax_i.grid(True, axis="y", alpha=0.25)

        ticks = [h for h in h_v if h == 1 or h % 2 == 1]
        if ticks:
            self.ax_v.set_xticks(ticks)
            self.ax_i.set_xticks(ticks)

        self.canvas.draw_idle()



class LoadAnalysisPage(ttk.Frame):
    def __init__(self, parent, model):
        super().__init__(parent, padding=12)
        self.model = model

        self.columnconfigure(0, weight=1)
        self.rowconfigure(2, weight=1)

        header = ttk.LabelFrame(
            self,
            text="Selected Load Test",
            padding=12
        )
        header.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        header.columnconfigure(1, weight=1)

        ttk.Label(header, text="Load type").grid(
            row=0, column=0, sticky="w", padx=(0, 8)
        )

        self.load_var = tk.StringVar(value=self.model.load_type)

        load_box = ttk.Combobox(
            header,
            textvariable=self.load_var,
            values=["Resistive", "Inductive / RL", "Nonlinear"],
            state="readonly",
            width=20
        )
        load_box.grid(row=0, column=1, sticky="w")
        load_box.bind("<<ComboboxSelected>>", self._load_changed)

        self.example_lbl = ttk.Label(
            header,
            text="",
            justify="left"
        )
        self.example_lbl.grid(
            row=1, column=0, columnspan=2,
            sticky="w", pady=(8, 0)
        )

        self.profile_note = ttk.Label(
            header,
            text=(
                "This page interprets the measured behaviour of the selected load. "
                "It does not change the FPGA measurement data."
            ),
            justify="left",
            wraplength=1200
        )
        self.profile_note.grid(
            row=2, column=0, columnspan=2,
            sticky="w", pady=(6, 0)
        )

        # ----------------------------------------------------------
        # Diagnostic summary: only metrics that distinguish load type
        # ----------------------------------------------------------
        diag = ttk.LabelFrame(
            self,
            text="Load Behaviour Diagnostics",
            padding=10
        )
        diag.grid(row=1, column=0, sticky="ew", pady=(0, 8))

        for c in range(4):
            diag.columnconfigure(c, weight=1)

        self.metric_labels = {}

        diagnostic_names = [
            ("Phase relation", ""),
            ("Displacement PF", ""),
            ("Reactive power Q", "VAR"),
            ("P vs S difference", "VA"),
            ("THD-I vs THD-V", ""),
            ("Dominant I harmonic", ""),
            ("Load verdict", ""),
            ("Confidence note", ""),
        ]

        for idx, (name, unit) in enumerate(diagnostic_names):
            card = ttk.Frame(diag, padding=8, style="Card.TFrame")
            card.grid(
                row=idx // 4,
                column=idx % 4,
                sticky="nsew",
                padx=4,
                pady=4
            )

            ttk.Label(
                card,
                text=name,
                style="CardTitle.TLabel"
            ).pack(anchor="w")

            value = ttk.Label(
                card,
                text="--",
                style="CardValue.TLabel",
                wraplength=250,
                justify="left"
            )
            value.pack(anchor="w", pady=(2, 0))

            if unit:
                ttk.Label(
                    card,
                    text=unit,
                    style="CardUnit.TLabel"
                ).pack(anchor="w")

            self.metric_labels[name] = value

        lower = ttk.Frame(self)
        lower.grid(row=2, column=0, sticky="nsew")
        lower.columnconfigure(0, weight=1)
        lower.columnconfigure(1, weight=1)
        lower.rowconfigure(0, weight=1)

        interpretation = ttk.LabelFrame(
            lower,
            text="Interpretation",
            padding=12
        )
        interpretation.grid(
            row=0, column=0,
            sticky="nsew",
            padx=(0, 5)
        )

        self.behavior_lbl = ttk.Label(
            interpretation,
            text="",
            justify="left",
            wraplength=540
        )
        self.behavior_lbl.pack(anchor="nw", fill="x")

        checks = ttk.LabelFrame(
            lower,
            text="What to Check During the Real-PCB Test",
            padding=12
        )
        checks.grid(
            row=0, column=1,
            sticky="nsew",
            padx=(5, 0)
        )

        self.focus_lbl = ttk.Label(
            checks,
            text="",
            justify="left",
            wraplength=540
        )
        self.focus_lbl.pack(anchor="nw", fill="x")

    def _load_changed(self, _=None):
        self.model.load_type = self.load_var.get()

    @staticmethod
    def _dominant_harmonic(samples, fs, f0, significance_floor=0.10):
        harmonics, percentages, _ = harmonic_least_squares(
            samples, fs, f0, 25
        )

        candidates = [
            (h, p)
            for h, p in zip(harmonics, percentages)
            if h > 1
        ]

        if not candidates:
            return "None significant"

        h, pct = max(candidates, key=lambda item: item[1])

        if pct < significance_floor:
            return "None significant"

        return f"H{h} · {pct:.2f}%"

    def refresh(self):
        m = self.model

        if self.load_var.get() != m.load_type:
            self.load_var.set(m.load_type)

        phase_deg = None
        displacement_pf = None
        relation = "Waiting for waveform frame"
        dominant_i = "None significant"

        if m.voltage_samples and m.current_samples:
            waveform_f0 = estimate_fundamental_frequency(
                m.voltage_samples,
                m.fs,
                45.0,
                55.0
            )

            phase_deg, displacement_pf, relation = waveform_phase_analysis(
                m.voltage_samples,
                m.current_samples,
                m.fs,
                waveform_f0
            )

            dominant_i = self._dominant_harmonic(
                m.current_samples,
                m.fs,
                waveform_f0
            )

        p_vs_s = abs(float(m.s) - abs(float(m.p)))
        thd_gap = float(m.thd_i) - float(m.thd_v)

        self.metric_labels["Phase relation"].configure(
            text=relation
        )

        self.metric_labels["Displacement PF"].configure(
            text="—" if displacement_pf is None else f"{displacement_pf:.3f}"
        )

        self.metric_labels["Reactive power Q"].configure(
            text=f"{m.q:.2f}"
        )

        self.metric_labels["P vs S difference"].configure(
            text=f"{p_vs_s:.2f}"
        )

        self.metric_labels["THD-I vs THD-V"].configure(
            text=f"{m.thd_i:.2f}% vs {m.thd_v:.2f}%"
        )

        self.metric_labels["Dominant I harmonic"].configure(
            text=dominant_i
        )

        selected = m.load_type

        if selected == "Resistive":
            self.example_lbl.configure(
                text=(
                    "Suggested real load: 25–60 W incandescent lamp, "
                    "power resistor, rheostat, or laboratory R load bank."
                )
            )

            verdict_checks = []
            if displacement_pf is not None:
                verdict_checks.append(abs(phase_deg) <= 5.0)
                verdict_checks.append(displacement_pf >= 0.95)
            verdict_checks.append(abs(float(m.q)) <= max(5.0, 0.05 * max(float(m.s), 1.0)))
            verdict_checks.append(p_vs_s <= max(5.0, 0.05 * max(float(m.s), 1.0)))

            consistent = all(verdict_checks) if verdict_checks else False

            verdict = (
                "Consistent with resistive behaviour"
                if consistent
                else "Check resistive-load assumptions"
            )

            confidence = (
                "Good agreement" if consistent
                else "Look for phase shift, Q, or distortion"
            )

            self.behavior_lbl.configure(
                text=(
                    "A resistive load should show voltage and current almost in phase, "
                    "PF close to 1, Q close to 0, and P close to S.\n\n"
                    f"Measured phase behaviour: {relation}\n"
                    f"FPGA PF: {m.pf:.3f}\n"
                    f"Reactive power: {m.q:.2f} VAR\n"
                    f"|S − |P||: {p_vs_s:.2f} VA"
                )
            )

            self.focus_lbl.configure(
                text=(
                    "During the experiment, confirm:\n"
                    "• voltage and current peaks align closely\n"
                    "• PF remains near unity\n"
                    "• Q remains small\n"
                    "• P and S are approximately equal\n"
                    "• current changes proportionally with voltage for a fixed resistance"
                )
            )

        elif selected == "Inductive / RL":
            self.example_lbl.configure(
                text=(
                    "Suggested real load: small AC fan, transformer, "
                    "or laboratory R–L load bank."
                )
            )

            lagging = phase_deg is not None and phase_deg < -2.0
            reactive = float(m.q) > max(2.0, 0.02 * max(float(m.s), 1.0))
            pf_below_one = float(m.pf) < 0.98

            consistent = lagging and reactive and pf_below_one

            verdict = (
                "Consistent with inductive behaviour"
                if consistent
                else "Inductive behaviour not yet clear"
            )

            confidence = (
                "Lag, Q and PF agree"
                if consistent
                else "Check current lag, positive Q and PF"
            )

            self.behavior_lbl.configure(
                text=(
                    "An inductive/RL load should normally make current lag voltage, "
                    "produce positive reactive power, and reduce PF below 1.\n\n"
                    f"Measured phase behaviour: {relation}\n"
                    f"Displacement PF: "
                    f"{'—' if displacement_pf is None else f'{displacement_pf:.3f}'}\n"
                    f"FPGA PF: {m.pf:.3f}\n"
                    f"Reactive power: {m.q:.2f} VAR"
                )
            )

            self.focus_lbl.configure(
                text=(
                    "During the experiment, confirm:\n"
                    "• current visibly lags voltage\n"
                    "• Q is positive for the inductive case\n"
                    "• S is greater than P\n"
                    "• total PF is below 1\n"
                    "• waveform-derived displacement PF is sensible"
                )
            )

        else:
            self.example_lbl.configure(
                text=(
                    "Suggested real load: 5–20 W LED lamp, phone charger, "
                    "or another small switch-mode AC/DC supply."
                )
            )

            nonlinear = (
                float(m.thd_i) >= 5.0
                or thd_gap >= 3.0
                or dominant_i != "None significant"
            )

            verdict = (
                "Consistent with nonlinear behaviour"
                if nonlinear
                else "Nonlinear behaviour not yet clear"
            )

            confidence = (
                "Current distortion is evident"
                if nonlinear
                else "Check THD-I and current harmonics"
            )

            self.behavior_lbl.configure(
                text=(
                    "A nonlinear load typically produces a distorted current waveform "
                    "even when the supply voltage remains nearly sinusoidal.\n\n"
                    f"THD-V: {m.thd_v:.2f}%\n"
                    f"THD-I: {m.thd_i:.2f}%\n"
                    f"THD-I − THD-V: {thd_gap:+.2f}%\n"
                    f"Dominant current harmonic: {dominant_i}\n"
                    f"FPGA total PF: {m.pf:.3f}"
                )
            )

            self.focus_lbl.configure(
                text=(
                    "During the experiment, confirm:\n"
                    "• THD-I is appreciably higher than THD-V\n"
                    "• current waveform is visibly distorted\n"
                    "• H3/H5/H7 components appear in the current spectrum\n"
                    "• total PF can be lower even when phase displacement is small\n"
                    "• voltage remains comparatively clean"
                )
            )

        self.metric_labels["Load verdict"].configure(
            text=verdict
        )

        self.metric_labels["Confidence note"].configure(
            text=confidence
        )


class EventsPage(ttk.Frame):
    def __init__(self, parent, model):
        super().__init__(parent, padding=12)
        self.model = model

        self.columnconfigure(0, weight=1)
        self.rowconfigure(1, weight=1)

        summary = ttk.LabelFrame(
            self,
            text="Configured Thresholds",
            padding=10
        )
        summary.grid(row=0, column=0, sticky="ew", pady=(0, 8))

        self.threshold_summary = ttk.Label(
            summary,
            text="",
            justify="left"
        )
        self.threshold_summary.pack(anchor="w")

        cols = ("Time", "Event", "Measured", "Threshold")
        self.tree = ttk.Treeview(
            self,
            columns=cols,
            show="headings"
        )

        for c in cols:
            self.tree.heading(c, text=c)
            self.tree.column(c, width=210, anchor="center")

        self.tree.grid(row=1, column=0, sticky="nsew")

    def refresh(self):
        sag_v = self.model.thresholds["Sag"] * self.model.nominal_vrms
        swell_v = self.model.thresholds["Swell"] * self.model.nominal_vrms

        self.threshold_summary.configure(
            text=(
                f"Sag: < {sag_v:.1f} V "
                f"({self.model.thresholds['Sag']:.2f} pu)     "
                f"Swell: > {swell_v:.1f} V "
                f"({self.model.thresholds['Swell']:.2f} pu)     "
                f"Under-frequency: < "
                f"{self.model.thresholds['Under-frequency']:.2f} Hz     "
                f"Over-frequency: > "
                f"{self.model.thresholds['Over-frequency']:.2f} Hz     "
                f"THD-V: > "
                f"{self.model.thresholds['High THD-V']:.2f}%     "
                f"THD-I: > "
                f"{self.model.thresholds['High THD-I']:.2f}%"
            )
        )

        for iid in self.tree.get_children():
            self.tree.delete(iid)

        for row in self.model.events[:50]:
            self.tree.insert("", "end", values=row)


class ValidationPage(ttk.Frame):
    def __init__(self, parent, model):
        super().__init__(parent, padding=12)
        self.model = model
        self.columnconfigure(0, weight=1)
        self.rowconfigure(1, weight=1)

        refs = ttk.LabelFrame(self, text="Reference / Expected Values", padding=10)
        refs.grid(row=0, column=0, sticky="ew", pady=(0, 8))

        self.vars = {
            "Vrms": tk.DoubleVar(value=230.0),
            "Irms": tk.DoubleVar(value=1.0),
            "Frequency": tk.DoubleVar(value=50.0),
            "THD-V": tk.DoubleVar(value=0.0),
            "PF": tk.DoubleVar(value=1.0),
        }

        for idx, (name, var) in enumerate(self.vars.items()):
            ttk.Label(refs, text=name).grid(row=0, column=idx, padx=4, sticky="w")
            ttk.Entry(refs, textvariable=var, width=11).grid(row=1, column=idx, padx=4)

        cols = ("Quantity", "Reference", "FPGA", "Error", "Error %")
        self.tree = ttk.Treeview(self, columns=cols, show="headings")
        for c in cols:
            self.tree.heading(c, text=c)
            self.tree.column(c, width=150, anchor="center")
        self.tree.grid(row=1, column=0, sticky="nsew")

    def refresh(self):
        m = self.model
        rows = [
            ("Vrms", self.vars["Vrms"].get(), m.vrms, "V"),
            ("Irms", self.vars["Irms"].get(), m.irms, "A"),
            ("Frequency", self.vars["Frequency"].get(), m.freq, "Hz"),
            ("THD-V", self.vars["THD-V"].get(), m.thd_v, "%"),
            ("PF", self.vars["PF"].get(), m.pf, ""),
        ]

        for iid in self.tree.get_children():
            self.tree.delete(iid)

        for name, ref, measured, unit in rows:
            err = measured - ref

            if ref == 0:
                err_pct_text = "—"
            else:
                err_pct = 100 * err / ref
                err_pct_text = f"{err_pct:+.3f}%"

            self.tree.insert("", "end", values=(
                name,
                f"{ref:.4f} {unit}",
                f"{measured:.4f} {unit}",
                f"{err:+.4f} {unit}",
                err_pct_text
            ))


class SettingsPage(ttk.Frame):
    def __init__(self, parent, model, app):
        super().__init__(parent, padding=12)
        self.model = model
        self.app = app
        self.columnconfigure(0, weight=1)

        uart = ttk.LabelFrame(self, text="FPGA UART", padding=12)
        uart.grid(row=0, column=0, sticky="ew")

        ttk.Label(uart, text="Port").grid(row=0, column=0, sticky="w")
        self.port_var = tk.StringVar(value=DEFAULT_PORT)
        self.port_box = ttk.Combobox(uart, textvariable=self.port_var, width=16)
        self.port_box.grid(row=0, column=1, padx=8)

        ttk.Button(uart, text="Refresh Ports", command=self.refresh_ports).grid(row=0, column=2, padx=4)

        ttk.Label(uart, text="Baud").grid(row=1, column=0, sticky="w", pady=(8,0))
        self.baud_var = tk.StringVar(value=str(DEFAULT_BAUD))
        ttk.Entry(uart, textvariable=self.baud_var, width=16).grid(row=1, column=1, padx=8, pady=(8,0))

        row = ttk.Frame(uart)
        row.grid(row=2, column=0, columnspan=3, sticky="w", pady=(12,0))
        ttk.Button(row, text="Connect", command=self.connect).pack(side="left")
        ttk.Button(row, text="Disconnect", command=app.disconnect_uart).pack(side="left", padx=6)

        note = "pyserial available" if SERIAL_AVAILABLE else "Install pyserial: pip install pyserial"
        ttk.Label(uart, text=note).grid(row=3, column=0, columnspan=3, sticky="w", pady=(10,0))

        proto = ttk.LabelFrame(self, text="Dual Packet Protocol", padding=12)
        proto.grid(row=1, column=0, sticky="ew", pady=(10,0))
        ttk.Label(
            proto,
            justify="left",
            text=(
                "AA 55: existing 28-byte metric packet (unchanged)\n"
                "AA 56 v2: frame header + raw 16-bit ADC codes + signed scaled V/I samples\n"
                "Raw ADC page displays the codes and records complete frames to CSV.\n"
                "Both FPGA Internal Test and Real PCB use exactly the same PC parser."
            )
        ).pack(anchor="w")

        self.refresh_ports()

    def refresh_ports(self):
        ports = available_ports()
        self.port_box["values"] = ports
        if ports and self.port_var.get() not in ports:
            self.port_var.set(ports[0])

    def connect(self):
        if not self.port_var.get():
            messagebox.showerror("UART", "Choose a COM port.")
            return
        try:
            self.app.connect_uart(self.port_var.get(), int(self.baud_var.get()))
        except Exception as exc:
            messagebox.showerror("UART", str(exc))

    def refresh(self):
        pass


class PQMonitorApp(tk.Tk):
    def __init__(self):
        super().__init__()

        self.title(APP_TITLE)
        self.geometry("1280x820")
        self.minsize(1050, 700)

        self.model = DataModel()
        self.raw_log_file = None
        self.raw_log_writer = None
        self.raw_log_path = None

        self.receiver = SerialReceiver(
            on_metrics=self._metrics_thread,
            on_samples=self._samples_thread,
            on_state=self._state_thread,
            on_error=self._error_thread,
        )

        self.protocol("WM_DELETE_WINDOW", self._close)

        self._styles()
        self._header()
        self._body()
        self._statusbar()

        self.after(500, self.refresh_all)

    def _styles(self):
        s = ttk.Style(self)
        try:
            s.theme_use("clam")
        except tk.TclError:
            pass

        self.configure(bg="#171a1f")
        s.configure(".", font=("Segoe UI", 10))
        s.configure("TFrame", background="#171a1f")
        s.configure("TLabel", background="#171a1f", foreground="#e5e7eb")
        s.configure("TLabelframe", background="#171a1f", foreground="#e5e7eb")
        s.configure("TLabelframe.Label", background="#171a1f", foreground="#e5e7eb")
        s.configure("Header.TFrame", background="#101318")
        s.configure("Header.TLabel", background="#101318", foreground="#f9fafb")
        s.configure("Title.TLabel", background="#101318", foreground="#f9fafb",
                    font=("Segoe UI Semibold", 18))
        s.configure("Card.TFrame", background="#22262d")
        s.configure("CardTitle.TLabel", background="#22262d", foreground="#aeb6c2")
        s.configure("CardValue.TLabel", background="#22262d", foreground="#ffffff",
                    font=("Segoe UI Semibold", 24))
        s.configure("CardUnit.TLabel", background="#22262d", foreground="#9ca3af")
        s.configure("StatusGood.TLabel", foreground="#45d483", font=("Segoe UI Semibold", 10))
        s.configure("StatusWarn.TLabel", foreground="#f7c948", font=("Segoe UI Semibold", 10))
        s.configure("StatusBad.TLabel", foreground="#ff6b6b", font=("Segoe UI Semibold", 10))
        s.configure("TNotebook.Tab", padding=(14, 8))
        s.configure("Treeview", rowheight=28)

    def _header(self):
        h = ttk.Frame(self, style="Header.TFrame", padding=(16,12))
        h.pack(fill="x")

        ttk.Label(h, text=APP_TITLE, style="Title.TLabel").pack(side="left")

        right = ttk.Frame(h, style="Header.TFrame")
        right.pack(side="right")

        ttk.Label(right, text="Data Source:", style="Header.TLabel").pack(side="left", padx=(0,5))
        self.source_var = tk.StringVar(value=self.model.source)
        box = ttk.Combobox(
            right,
            textvariable=self.source_var,
            values=["FPGA Internal Test", "Real PCB"],
            state="readonly",
            width=18
        )
        box.pack(side="left", padx=(0,12))
        box.bind("<<ComboboxSelected>>", self._source_changed)

        ttk.Label(right, text="Load Test:", style="Header.TLabel").pack(side="left", padx=(0,5))
        self.load_var = tk.StringVar(value=self.model.load_type)
        load_box = ttk.Combobox(
            right,
            textvariable=self.load_var,
            values=["Resistive", "Inductive / RL", "Nonlinear"],
            state="readonly",
            width=15
        )
        load_box.pack(side="left", padx=(0,12))
        load_box.bind("<<ComboboxSelected>>", self._load_changed)

        self.conn = ttk.Label(right, text="● OFFLINE", style="StatusWarn.TLabel")
        self.conn.pack(side="left")

    def _body(self):
        nb = ttk.Notebook(self)
        nb.pack(fill="both", expand=True, padx=10, pady=10)

        self.pages = [
            ("Dashboard", DashboardPage(nb, self.model)),
            ("Raw ADC", RawADCPage(nb, self.model, self)),
            ("Waveforms", WaveformsPage(nb, self.model)),
            ("Load Analysis", LoadAnalysisPage(nb, self.model)),
            ("Spectrum", SpectrumPage(nb, self.model)),
            ("Events", EventsPage(nb, self.model)),
            ("Validation", ValidationPage(nb, self.model)),
            ("Settings", SettingsPage(nb, self.model, self)),
        ]

        for name, page in self.pages:
            nb.add(page, text=name)

    def _statusbar(self):
        b = ttk.Frame(self, padding=(12,6))
        b.pack(fill="x")
        self.status = ttk.Label(b, text="")
        self.status.pack(side="left")

    def _source_changed(self, _=None):
        self.model.source = self.source_var.get()
        # Source selection is descriptive. The FPGA TEST_MODE generic decides
        # whether transmitted samples originated internally or from the ADC.

    def _load_changed(self, _=None):
        self.model.load_type = self.load_var.get()

    def connect_uart(self, port, baud):
        self.receiver.connect(port, baud)

    def disconnect_uart(self):
        self.receiver.disconnect()

    def start_raw_recording(self):
        initial_name = datetime.now().strftime("raw_adc_%Y%m%d_%H%M%S.csv")
        path = filedialog.asksaveasfilename(
            title="Save raw ADC recording",
            defaultextension=".csv",
            filetypes=[("CSV files", "*.csv"), ("All files", "*.*")],
            initialfile=initial_name,
        )
        if not path:
            return None

        self.stop_raw_recording()
        try:
            self.raw_log_file = open(path, "w", newline="", encoding="utf-8")
            self.raw_log_writer = csv.writer(self.raw_log_file)
            self.raw_log_writer.writerow([
                "timestamp_utc",
                "frame_sequence",
                "sample_index",
                "sample_time_s",
                "sample_rate_hz",
                "voltage_raw_code",
                "current_raw_code",
                "scaled_voltage_v",
                "scaled_current_a",
            ])
            self.raw_log_file.flush()
            self.raw_log_path = path
            return path
        except OSError as exc:
            self.raw_log_file = None
            self.raw_log_writer = None
            self.raw_log_path = None
            messagebox.showerror("Raw ADC recording", str(exc))
            return None

    def stop_raw_recording(self):
        if self.raw_log_file is not None:
            try:
                self.raw_log_file.close()
            except OSError:
                pass
        self.raw_log_file = None
        self.raw_log_writer = None
        self.raw_log_path = None

    def _apply_samples(self, frame):
        self.model.update_samples(frame)

        if self.raw_log_writer is None or not frame.voltage_raw or not frame.current_raw:
            return

        timestamp = datetime.now(timezone.utc).isoformat()
        count = min(
            len(frame.voltage_raw),
            len(frame.current_raw),
            len(frame.voltage_v),
            len(frame.current_a),
        )
        for index in range(count):
            self.raw_log_writer.writerow([
                timestamp,
                frame.sequence,
                index,
                f"{index / frame.sample_rate_hz:.9f}",
                frame.sample_rate_hz,
                frame.voltage_raw[index],
                frame.current_raw[index],
                f"{frame.voltage_v[index]:.9f}",
                f"{frame.current_a[index]:.12f}",
            ])
        self.raw_log_file.flush()

    def _metrics_thread(self, metrics):
        self.after(0, lambda m=metrics: self.model.update_metrics(m))

    def _samples_thread(self, frame):
        self.after(0, lambda f=frame: self._apply_samples(f))

    def _state_thread(self, connected, message):
        self.after(0, lambda: self._set_state(connected))

    def _set_state(self, connected):
        self.model.connected = connected
        if connected:
            self.conn.configure(text="● UART CONNECTED", style="StatusGood.TLabel")
        else:
            self.conn.configure(text="● OFFLINE", style="StatusWarn.TLabel")

    def _error_thread(self, message):
        self.after(0, lambda: self.conn.configure(text="● UART ERROR", style="StatusBad.TLabel"))

    def refresh_all(self):
        self.model.sync_losses = self.receiver.framer.sync_losses

        if hasattr(self, "load_var") and self.load_var.get() != self.model.load_type:
            self.load_var.set(self.model.load_type)

        for _, page in self.pages:
            try:
                page.refresh()
            except Exception:
                pass

        self.status.configure(
            text=(
                f"Source: {self.model.source}    "
                f"Load test: {self.model.load_type}    "
                f"Metric packets: {self.model.metric_packets:,}    "
                f"Sample frames: {self.model.sample_packets:,}    "
                f"Sync losses: {self.model.sync_losses:,}"
            )
        )

        self.after(750, self.refresh_all)

    def _close(self):
        try:
            self.stop_raw_recording()
            self.receiver.disconnect()
        finally:
            self.destroy()
