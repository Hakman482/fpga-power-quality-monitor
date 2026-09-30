# Laboratory validation data

Raw measurement captures used during the final project validation.

The source CSV files are intentionally preserved rather than overwritten by cleaned/processed versions.

## CSV schema

The GUI recording format contains:

```text
timestamp_utc
frame_sequence
sample_index
sample_time_s
sample_rate_hz
voltage_raw_code
current_raw_code
scaled_voltage_v
scaled_current_a
```

## Voltage data

`voltage/raw/` contains the function-generator tests used to check the voltage measurement chain, including 5 Vpp, 7.5 Vpp and 10 Vpp captures and calibration/zero-input runs.

`voltage/zero_input/` contains additional no-signal recordings.

The lab setup did not provide a variable mains AC source or power amplifier, so these results validate the low-voltage response of the implemented chain rather than a full standards-grade mains calibration.

## Current data

`current/raw/` contains the DC current-calibration captures.

Reference points used during the final test sequence were approximately:

| File | Ammeter reference |
|---|---:|
| `raw_adc_I_zero_A.csv` | ~0 A |
| `raw_adc_0.05A.csv` | 0.051 A |
| `raw_adc_0.10A.csv` | 0.100 A |
| `raw_adc_0.15A.csv` | 0.151 A |
| `raw_adc_0.2A.csv` | 0.200 A |
| `raw_adc_0.25A.csv` | 0.251 A |
| `raw_adc_0.3A.csv` | 0.300 A |
| `raw_adc_20260917_0.35A.csv` | 0.358 A |
| `raw_adc_0.4A.csv` | 0.403 A |
| `raw_adc_0.45A.csv` | 0.459 A |

Testing stopped at the highest point because of resistive-load heating.

## Data cleaning rule

The raw files contain occasional acquisition glitches. Keep the original files unchanged.

For statistical summaries/plots, isolated exact ADC codes such as `24576` and `49152` are excluded when they represent acquisition glitches rather than valid measurements. The helper script in `analysis/` implements this conservative filter.

## Quick summary script

Run:

```bash
python analysis/summarize_adc_csv.py current/raw/raw_adc_0.10A.csv --channel current
```

or:

```bash
python analysis/summarize_adc_csv.py voltage/raw/raw_adc_10pp.csv --channel voltage
```

The script reports sample count, raw-code mean/standard deviation and scaled-value statistics after removing the known isolated glitch codes.
