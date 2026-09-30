# Hardware and PCB

Editable KiCad design files and manufacturing outputs for the custom measurement PCB.

## Design source

Open:

```text
kicad/myProject.kicad_pro
```

The project includes:

- top-level schematic and hierarchical sheets,
- 4-layer PCB layout,
- custom symbols,
- custom footprints,
- 3D component models.

The board implements the voltage/current sensing and conditioning chains, ADC interfaces, reference/power circuitry and FPGA interconnect used by the prototype.

## Manufacturing outputs

`manufacturing/` contains:

- Gerber files,
- plated/non-plated drill files,
- component-placement files,
- BOM,
- JLC assembly placement/CPL export.

These are retained separately from the editable KiCad design so it is clear which files are source and which are generated fabrication outputs.

## Safety and fabrication warning

This board was built and tested as an academic prototype. Manufacturing files are provided for project traceability, not as a statement that the design is certified or suitable for direct deployment on a mains installation.

Before reproducing or energising the board, independently review at least:

- insulation/isolation ratings,
- creepage and clearance,
- fuse/protection coordination,
- earthing and oscilloscope-grounding strategy,
- component voltage/current ratings,
- PCB material and manufacturing tolerances,
- enclosure and touch protection.

Do not infer regulatory compliance from the presence of Gerbers or a successful prototype build.
