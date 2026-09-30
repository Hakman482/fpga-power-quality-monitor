# Python GUI

Desktop interface for the FPGA power-quality monitor.

## Features

- FPGA metrics dashboard
- raw 16-bit voltage/current ADC display
- waveform plotting
- spectrum/harmonic view
- event/status table
- validation page
- serial-port settings
- raw CSV recording

No Python-generated measurement source is used in the final application. The selectable data modes refer to whether the FPGA itself is running its internal test source or the physical PCB input path.

## Requirements

```bash
python -m pip install -r requirements.txt
```

Dependencies:

- NumPy
- Matplotlib
- PySerial
- Tkinter (normally provided with desktop Python installations)

## Run

```bash
python main.py
```

Connect to the Nexys A7 USB-UART interface at **115200 baud**.

## Packet formats

### `AA55` metric packet

Carries the FPGA-computed measurement metrics.

### `AA56` waveform/raw packet, protocol version 2

Header and metadata are followed by V/I sample pairs.

Each sample pair contains:

- unsigned 16-bit voltage ADC code,
- unsigned 16-bit current ADC code,
- signed 32-bit voltage in millivolts,
- signed 32-bit current in microamps.

Multi-byte fields are MSB-first.

The final FPGA configuration captures 1000 sample pairs at 10 kS/s. This preserves the full 100 µs sample spacing within the 100 ms capture without attempting to stream every sample continuously over the 115200-baud serial link.

## CSV capture

Raw recording keeps both original ADC codes and scaled values. The data in `../validation/` was captured through this path.
