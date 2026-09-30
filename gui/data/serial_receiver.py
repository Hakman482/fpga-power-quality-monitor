import threading

try:
    import serial
    from serial.tools import list_ports
    SERIAL_AVAILABLE = True
except ImportError:
    serial = None
    list_ports = None
    SERIAL_AVAILABLE = False

from .protocol import StreamFramer, parse_metric_packet, parse_sample_packet


def available_ports():
    if not SERIAL_AVAILABLE:
        return []
    return [p.device for p in list_ports.comports()]


class SerialReceiver:
    def __init__(self, on_metrics, on_samples, on_state=None, on_error=None):
        self.on_metrics = on_metrics
        self.on_samples = on_samples
        self.on_state = on_state
        self.on_error = on_error

        self._ser = None
        self._thread = None
        self._stop = threading.Event()
        self.framer = StreamFramer()

        self.metric_packets = 0
        self.sample_packets = 0

    @property
    def connected(self):
        return bool(self._ser and self._ser.is_open)

    def connect(self, port, baudrate=115200):
        if not SERIAL_AVAILABLE:
            raise RuntimeError("pyserial is not installed. Run: pip install pyserial")

        self.disconnect()

        self._ser = serial.Serial(
            port=port,
            baudrate=int(baudrate),
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.10,
        )

        self.framer = StreamFramer()
        self.metric_packets = 0
        self.sample_packets = 0
        self._stop.clear()

        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

        if self.on_state:
            self.on_state(True, f"Connected to {port}")

    def disconnect(self):
        self._stop.set()
        ser = self._ser
        self._ser = None
        if ser:
            try:
                ser.close()
            except Exception:
                pass
        if self.on_state:
            self.on_state(False, "Disconnected")

    def _run(self):
        try:
            while not self._stop.is_set():
                ser = self._ser
                if not ser or not ser.is_open:
                    break

                chunk = ser.read(512)
                if not chunk:
                    continue

                for kind, packet in self.framer.feed(chunk):
                    if kind == "metrics":
                        self.metric_packets += 1
                        self.on_metrics(parse_metric_packet(packet))
                    else:
                        self.sample_packets += 1
                        self.on_samples(parse_sample_packet(packet))

        except Exception as exc:
            if self.on_error:
                self.on_error(str(exc))
        finally:
            ser = self._ser
            self._ser = None
            if ser:
                try:
                    ser.close()
                except Exception:
                    pass
            if self.on_state:
                self.on_state(False, "UART stopped")
