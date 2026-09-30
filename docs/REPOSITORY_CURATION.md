# Repository curation notes

The original working archive contained 884 items, including source files, generated build artefacts, backups, research literature, component datasheets, repeated photographs and laboratory captures.

This GitHub package intentionally keeps the engineering outputs that are useful for review and reproduction while excluding unrelated or redundant material.

## Included

- final active VHDL implementation;
- VHDL simulation/testbench sources;
- earlier auto-disabled VHDL modules under `fpga/legacy/`;
- final Nexys A7 constraints;
- Python GUI and UART protocol code;
- editable KiCad schematic/PCB files;
- custom KiCad symbols, footprints and 3D models;
- Gerber/drill/BOM/placement manufacturing outputs;
- raw voltage/current validation CSV files;
- final dissertation and defence presentation;
- selected photographs/screenshots that document the system.

## Excluded

- Vivado cache, synthesis/implementation run folders, checkpoints, logs and generated bitstream;
- KiCad automatic backups;
- duplicate/near-duplicate photographs;
- exploratory screenshots that do not add useful documentation;
- downloaded research papers;
- vendor datasheets;
- temporary notes and miscellaneous debugging artefacts.

Research papers and vendor datasheets are deliberately not republished here because they are third-party material and are not required to understand the implementation.
