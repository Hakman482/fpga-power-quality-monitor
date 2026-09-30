# FPGA implementation

This directory contains the final VHDL implementation for the Nexys A7-100T and the associated simulation sources.

## Active synthesis sources

| Module | Purpose |
|---|---|
| `pq_nexys_top.vhd` | Final top-level integration: acquisition, DSP, packet formatting and UART. |
| `acquisition_pipeline.vhd` | Selects internal-test or real-ADC acquisition and coordinates the measurement pipeline. |
| `adc_if.vhd` | ADS8320 serial-interface building block. |
| `dual_adc_if.vhd` | Simultaneously controls the two ADS8320 channels and returns synchronized 16-bit samples. |
| `sample_preprocess.vhd` | Removes measured channel zero offsets and produces signed, zero-centred ADC counts. |
| `sample_scale_v2.vhd` | Converts zero-centred counts to voltage/current engineering units using measured calibration factors. |
| `dual_rms.vhd` | Cycle-synchronous voltage/current RMS engine. |
| `frequency_meter.vhd` | Frequency measurement from the conditioned voltage waveform. |
| `power_meter_v2.vhd` | Cycle-synchronous active/apparent power and power-factor calculation. |
| `sample_frame_buffer.vhd` | Stores one adaptive electrical cycle for harmonic processing. |
| `harmonic_1_25_extractor.vhd` | Fixed-point Goertzel harmonic engine for the fundamental and harmonics 2–25. |
| `thd_1_25_meter.vhd` | Converts harmonic energy terms into V/I THD results. |
| `test_signal_source.vhd` | Internal deterministic waveform source for FPGA-only validation. |
| `pq_uart_packet_tx.vhd` | Formats metric packets plus raw/scaled V/I sample frames. |
| `uart_tx.vhd` | 115200-baud byte transmitter. |

Earlier modules that were auto-disabled in the submitted Vivado project are retained in `legacy/` for traceability but are not added by the clean build script.

## Final configuration

The supplied `pq_nexys_top.vhd` uses:

```vhdl
TEST_MODE => false
```

so normal synthesis targets the physical PCB/ADS8320 acquisition path.

Important values in the final top level:

```text
SYS_CLK_HZ            = 100,000,000
ADC_DCLOCK_HZ         = 500,000
SAMPLE_RATE_HZ        = 10,000
RMS_WINDOW_SAMPLES    = 200
POWER_WINDOW_SAMPLES  = 200
THD_FRAME_SAMPLES     = 210
SAMPLE_FRAME_SAMPLES  = 1,000
FRAME_PERIOD_SAMPLES  = 20,000
UART_BAUD              = 115,200
```

## Pin mapping

The included XDC targets the Nexys A7-100T:

| Function | Board pin |
|---|---|
| 100 MHz clock | E3 |
| Reset / BTNC | N17 |
| ADC chip select / JA1 | C17 |
| ADC serial clock / JA2 | D18 |
| Voltage ADC data / JA3 | E18 |
| Current ADC data / JA4 | G17 |
| USB-UART TX | D4 |

## Clean Vivado project

Generated Vivado output is deliberately not stored in the repository.

Run the project-generation Tcl script from the repository root:

```tcl
source fpga/scripts/create_project.tcl
```

Then run Synthesis, Implementation and Generate Bitstream.

Target device:

```text
xc7a100tcsg324-1
```

The original project file was created with Vivado 2026.1.

## Simulation

The `sim/` directory contains focused testbenches for the acquisition interface, RMS, frequency, harmonic/THD pipeline, power meter, UART packets and the integrated PQ pipeline.

Some testbenches exercise legacy variants as part of the development record; use the final `*_1_25_*`, `power_meter_v2` and `pq_uart_packet_tx` paths for the final architecture.
