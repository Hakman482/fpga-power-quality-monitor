from dataclasses import dataclass
from typing import List, Tuple

METRIC_HEADER = b"\xAA\x55"
SAMPLE_HEADER = b"\xAA\x56"
METRIC_PACKET_SIZE = 28
SAMPLE_FIXED_HEADER_SIZE = 11  # AA56 + ver + count(u16) + fs(u32) + seq(u16)


@dataclass(frozen=True)
class PQMetrics:
    vrms_v: float
    irms_a: float
    frequency_hz: float
    active_power_w: float
    apparent_power_va: float
    power_factor: float
    thd_v_pct: float
    thd_i_pct: float


@dataclass(frozen=True)
class SampleFrame:
    version: int
    sample_rate_hz: int
    sequence: int
    voltage_raw: List[int]
    current_raw: List[int]
    voltage_v: List[float]
    current_a: List[float]


def parse_metric_packet(packet: bytes) -> PQMetrics:
    if len(packet) != METRIC_PACKET_SIZE:
        raise ValueError(f"Metric packet must be {METRIC_PACKET_SIZE} bytes")
    if packet[:2] != METRIC_HEADER:
        raise ValueError("Bad metric header")

    return PQMetrics(
        vrms_v=int.from_bytes(packet[2:6], "big", signed=False) / 1000.0,
        irms_a=int.from_bytes(packet[6:10], "big", signed=False) / 1_000_000.0,
        frequency_hz=int.from_bytes(packet[10:14], "big", signed=False) / 1000.0,
        active_power_w=int.from_bytes(packet[14:18], "big", signed=True) / 1000.0,
        apparent_power_va=int.from_bytes(packet[18:22], "big", signed=False) / 1000.0,
        power_factor=int.from_bytes(packet[22:24], "big", signed=True) / 1000.0,
        thd_v_pct=int.from_bytes(packet[24:26], "big", signed=False) / 100.0,
        thd_i_pct=int.from_bytes(packet[26:28], "big", signed=False) / 100.0,
    )


def parse_sample_packet(packet: bytes) -> SampleFrame:
    if len(packet) < SAMPLE_FIXED_HEADER_SIZE:
        raise ValueError("Sample packet too short")
    if packet[:2] != SAMPLE_HEADER:
        raise ValueError("Bad sample header")

    version = packet[2]
    count = int.from_bytes(packet[3:5], "big", signed=False)
    sample_rate_hz = int.from_bytes(packet[5:9], "big", signed=False)
    sequence = int.from_bytes(packet[9:11], "big", signed=False)

    if version == 1:
        bytes_per_sample = 8
    elif version == 2:
        bytes_per_sample = 12
    else:
        raise ValueError(f"Unsupported sample protocol version {version}")

    expected = SAMPLE_FIXED_HEADER_SIZE + count * bytes_per_sample
    if len(packet) != expected:
        raise ValueError(f"Expected sample packet length {expected}, got {len(packet)}")

    voltage_raw = []
    current_raw = []
    voltage_v = []
    current_a = []

    offset = SAMPLE_FIXED_HEADER_SIZE
    for _ in range(count):
        if version == 2:
            voltage_raw.append(
                int.from_bytes(packet[offset:offset+2], "big", signed=False)
            )
            current_raw.append(
                int.from_bytes(packet[offset+2:offset+4], "big", signed=False)
            )
            offset += 4

        v_mv = int.from_bytes(packet[offset:offset+4], "big", signed=True)
        i_ua = int.from_bytes(packet[offset+4:offset+8], "big", signed=True)
        voltage_v.append(v_mv / 1000.0)
        current_a.append(i_ua / 1_000_000.0)
        offset += 8

    return SampleFrame(
        version=version,
        sample_rate_hz=sample_rate_hz,
        sequence=sequence,
        voltage_raw=voltage_raw,
        current_raw=current_raw,
        voltage_v=voltage_v,
        current_a=current_a,
    )


class StreamFramer:
    """
    Finds both packet types in one UART stream:
      AA55 -> fixed 28-byte metrics packet
      AA56 -> variable sample-frame packet
    """
    def __init__(self, max_samples=2048):
        self.buffer = bytearray()
        self.max_samples = max_samples
        self.sync_losses = 0

    def feed(self, chunk: bytes):
        if chunk:
            self.buffer.extend(chunk)

        out = []

        while True:
            if len(self.buffer) < 2:
                break

            metric_idx = self.buffer.find(METRIC_HEADER)
            sample_idx = self.buffer.find(SAMPLE_HEADER)

            candidates = [x for x in (metric_idx, sample_idx) if x >= 0]
            if not candidates:
                # Preserve a trailing AA as possible next header.
                if self.buffer.endswith(b"\xAA"):
                    self.sync_losses += max(len(self.buffer)-1, 0)
                    self.buffer[:] = b"\xAA"
                else:
                    self.sync_losses += len(self.buffer)
                    self.buffer.clear()
                break

            idx = min(candidates)
            if idx > 0:
                self.sync_losses += idx
                del self.buffer[:idx]

            if len(self.buffer) < 2:
                break

            header = bytes(self.buffer[:2])

            if header == METRIC_HEADER:
                if len(self.buffer) < METRIC_PACKET_SIZE:
                    break
                packet = bytes(self.buffer[:METRIC_PACKET_SIZE])
                del self.buffer[:METRIC_PACKET_SIZE]
                out.append(("metrics", packet))
                continue

            if header == SAMPLE_HEADER:
                if len(self.buffer) < SAMPLE_FIXED_HEADER_SIZE:
                    break

                count = int.from_bytes(self.buffer[3:5], "big", signed=False)
                if count <= 0 or count > self.max_samples:
                    self.sync_losses += 1
                    del self.buffer[0]
                    continue

                version = self.buffer[2]
                if version == 1:
                    bytes_per_sample = 8
                elif version == 2:
                    bytes_per_sample = 12
                else:
                    self.sync_losses += 1
                    del self.buffer[0]
                    continue

                size = SAMPLE_FIXED_HEADER_SIZE + count * bytes_per_sample
                if len(self.buffer) < size:
                    break

                packet = bytes(self.buffer[:size])
                del self.buffer[:size]
                out.append(("samples", packet))
                continue

            self.sync_losses += 1
            del self.buffer[0]

        return out
