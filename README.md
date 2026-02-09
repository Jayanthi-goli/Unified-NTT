# Unified NTT / INTT Accelerator for CRYSTALS-Kyber

## Overview
This project presents a **unified and hardware-efficient implementation** of the **Number Theoretic Transform (NTT)** and **Inverse NTT (INTT)** targeting **CRYSTALS-Kyber** post-quantum cryptography.

A **single shared datapath** is used to support both **forward NTT (FNTT)** and **inverse NTT (INTT)** operations, significantly reducing **area overhead** compared to separate forward and inverse designs.  
The architecture is optimized for **resource efficiency**, making it suitable for **FPGA and ASIC implementations**.

---

## Architecture Summary

### Control Unit (FSM)
- Controls NTT stages and butterfly scheduling  
- Selects operation mode (**NTT / INTT**)  
- Manages overall computation flow  

### Unified Butterfly Unit (BU)
- Supports both:
  - **Cooley–Tukey (CT)** butterfly for forward NTT  
  - **Gentleman–Sande (GS)** butterfly for inverse NTT  
- Enables hardware reuse across both transforms  

### Register Banks (RB1, RB2)
- Dual memory structure for:
  - Polynomial coefficient storage  
  - Intermediate computation results  
- Supports efficient data access and swapping  

### Zeta ROM
- Stores precomputed **Kyber twiddle factors (zetas)**  
- Provides modular multiplication constants  

### Output Streaming Logic
- Sequentially streams output coefficients  
- Activates after NTT/INTT computation completes  

---

## FPGA Flow

**Tool:** Xilinx Vivado  
- RTL Synthesis  
- Implementation (Place & Route)  
- Timing Analysis  
- Power Estimation  

### Target FPGA Devices
- Artix-7  
- Virtex-7  

---

## ASIC Flow

- **Cadence Xcelium** – RTL functional simulation  
- **Cadence Genus** – Logic synthesis  
- **Cadence Innovus** – Place and Route exploration  

---

## Implementation Results (Summary)

- Very low **LUT and FF utilization** due to unified datapath design  
- **Positive timing slack** achieved across implementation flows  
- Reduced area compared to conventional standalone NTT architectures  
- Suitable for **resource-constrained post-quantum cryptographic hardware**

---

## Applications

- Post-quantum cryptographic accelerators  
- Secure hardware for embedded systems  
- Cryptographic engines for IoT and edge devices  

---

## Keywords
NTT, INTT, CRYSTALS-Kyber, Post-Quantum Cryptography, FPGA, ASIC, RTL Design, SystemVerilog
