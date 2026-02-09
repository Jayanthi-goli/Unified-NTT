Overview:
This project presents a unified, hardware-efficient implementation of the Number Theoretic Transform (NTT) and Inverse NTT (INTT) targeting CRYSTALS-Kyber post-quantum cryptography.
A single shared datapath is used to support both forward NTT (FNTT) and inverse NTT (INTT) operations, reducing area overhead compared to separate designs.
Architecture Summary:
Control Unit (FSM)

Controls NTT stages, butterfly scheduling, and mode selection (NTT / INTT)

Unified Butterfly Unit (BU)

Performs both CT (forward) and GS (inverse) butterfly operations

Register Banks (RB1, RB2)

Dual memory structure for polynomial storage and intermediate results

Zeta ROM

Stores Kyber twiddle factors

Output Streaming Logic

Sequentially streams output coefficients after computation completes
FPGA Flow

Xilinx Vivado

Synthesis

Implementation

Timing analysis

Power estimation

Target Devices:

Artix-7

Virtex-7

ASIC Flow

Cadence Xcelium – RTL simulation

Cadence Genus – Logic synthesis

Cadence Innovus – Place and Route
Implementation Results (Summary)

Very low LUT and FF utilization due to unified datapath design

Timing closure achieved with positive slack

Reduced area compared to state-of-the-art NTT accelerators

Suitable for resource-constrained PQC hardware
Applications

Post-quantum cryptographic accelerators
Secure hardware for embedded and IoT systems
