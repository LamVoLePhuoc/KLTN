# Dual Core Simulation Guide

## Requirements
- Operating System: **Linux**
- Simulation Tool: **Cadence Xcelium**

> **Note:** You must use **Cadence Xcelium** to run this project. Other simulators are not supported.

## How to Run

1. Move to the `run` directory:
   ```bash
   cd Dual_core/run
2. Enter your assembly instructions into:
    ```bash
    instr_input.txt
3. Run the simulation script from the terminal:
    ```bash
    ./run.sh
4. If you do not want debug signals to be enabled, remove the following flag from run.sh:
    ```diff
    +define+DEBUG_EN

## Output
- After the simulation finishes, the waveform dump file will be generated at:
    ```arduino
    Dual_core/run/my_work_dir/dump.vcd

## Notes
- Make sure run.sh has execute permission:
    ```bash
    chmod +x run.sh
- Ensure the Cadence Xcelium environment is properly set up before running the simulation.