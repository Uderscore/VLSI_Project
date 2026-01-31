# Convolution Accelerator - VLSI Hardware Design Project

## 📋 Project Overview

This repository contains a complete hardware implementation of a **2D Convolution Accelerator** designed for high-performance image processing and deep learning applications. The accelerator is built using an **8×8 Systolic Array** architecture and implements a streaming coprocessor model for efficient matrix convolution operations.

**Course**: CMP3020 - VLSI Design  
**Institution**: Cairo University Faculty of Engineering (CUFE), Computer Engineering Department  
**Architecture**: Domain-Specific Accelerator for 2D Convolution  
**Target Technology**: Sky130 PDK (130nm)

---

## 🎯 Key Features

### Hardware Capabilities
- **8×8 Systolic Array** with 64 Processing Elements (PEs)
- **32KB On-Chip SRAM** with ping-pong buffering for continuous operation
- **Configurable Matrix Sizes**: 16×16 to 64×64 input matrices
- **Flexible Kernel Support**: 2×2 to 16×16 convolution kernels
- **8-bit Unsigned Integer** arithmetic with 32-bit internal accumulation
- **AXI-Stream-like Interface** with Valid/Ready handshake protocol
- **Weight Stationary Dataflow** for optimal energy efficiency

### Design Highlights
- ✅ **Modular Architecture**: Separate control, memory, and compute subsystems
- ✅ **Memory Efficiency**: Ping-pong buffering hides DRAM access latency
- ✅ **Address Generation Unit (AGU)**: Handles 2D-to-1D address mapping with sliding windows
- ✅ **Tiling Support**: Processes large matrices in hardware-sized blocks
- ✅ **Handshake Protocols**: Backpressure-aware data streaming
- ✅ **Comprehensive Testbenches**: Self-checking verification environment
- ✅ **Golden Model**: Python reference implementation for validation

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Convolution Accelerator Top                  │
│                                                                 │
│  ┌──────────────┐      ┌──────────────┐      ┌─────────────┐  │
│  │   Control    │      │    Memory    │      │  Systolic   │  │
│  │     Unit     │◄────►│  Controller  │◄────►│   Array     │  │
│  │    (FSM)     │      │  (Ping-Pong) │      │   (8×8)     │  │
│  └──────┬───────┘      └──────┬───────┘      └─────┬───────┘  │
│         │                     │                     │          │
│         │                     │                     │          │
│  ┌──────▼─────────────────────▼─────────────────────▼───────┐  │
│  │        Data Loader & Address Generation Unit (AGU)       │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              SRAM Buffer (32KB Max)                      │  │
│  │         (Sky130 1rw1r Pseudo-Dual Port SRAM)            │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────┬─────────────────────────────────┬───────────────────┘
          │                                 │
    rx_data (8-bit input)            tx_data (8-bit output)
    rx_valid/rx_ready              tx_valid/tx_ready
```

### Component Breakdown

#### 1. **Systolic Array (8×8 Core)**
- 64 identical Processing Elements (PEs)
- Each PE performs Multiply-Accumulate (MAC) operations
- Weight Stationary dataflow: weights preloaded, pixels stream through
- Pipeline depth: 15 cycles (ROWS + COLS - 1)
- Location: `rtl/core/systolic_array.v`, `rtl/core/processing_element.v`

#### 2. **Memory Controller**
- Manages 32KB on-chip SRAM (configurable: 4KB-32KB)
- Ping-pong buffering: simultaneous read from one buffer, write to another
- 3-cycle read latency handling
- Integrates Sky130 SRAM hard macros (1rw1r configuration)
- Location: `rtl/mem/memory_controller.v`

#### 3. **Control Unit**
- Main FSM orchestrator with states: IDLE, LOAD_INPUT, LOAD_WEIGHT, COMPUTE, DRAIN, DONE
- Configuration management (matrix size N, kernel size K)
- Handshake protocol controller
- Coordinates between memory, AGU, and systolic array
- Location: `rtl/control/control_unit.v`

#### 4. **Address Generation Unit (AGU)**
- Converts 2D coordinates (x, y) to linear memory addresses
- Implements sliding window patterns for convolution tiling
- Handles "halo" pixels for edge cases: `Input Size = Array Size + (K-1)`
- Generates non-sequential access patterns efficiently
- Location: `rtl/control/address_generator.v`

#### 5. **Data Loader**
- Manages data movement between external DRAM and on-chip buffers
- Implements Valid/Ready handshake protocol
- Handles format conversions (8-bit ↔ 32-bit)
- Location: `rtl/control/data_loader.v`

---

## 📁 Repository Structure

```
VLSI_Project/
├── README.md                          # This file - comprehensive project description
├── QUICK_START.md                     # Quick setup and simulation guide
├── BUGFIX_SUMMARY.md                  # Integration bug fixes documentation
├── project.txt                        # Full project specification document
├── project_doc.pdf                    # Project documentation (PDF)
│
├── rtl/                               # RTL source files (Verilog)
│   ├── convolution_accelerator_top.v  # Top-level module
│   ├── accelerator_integration.v      # Memory + Systolic array integration
│   ├── core/                          # Compute core modules
│   │   ├── systolic_array.v           # 8×8 systolic array
│   │   ├── processing_element.v       # Single PE (MAC unit)
│   │   ├── README.md                  # Core architecture documentation
│   │   ├── Stage1_IOs.md             # Stage 1 I/O specifications
│   │   └── systolic_array_handshake.md # Handshake protocol details
│   ├── control/                       # Control and data management
│   │   ├── control_unit.v             # Main FSM controller
│   │   ├── address_generator.v        # AGU for 2D→1D mapping
│   │   ├── data_loader.v              # Data streaming controller
│   │   └── README.md                  # Control subsystem docs
│   ├── mem/                           # Memory subsystem
│   │   ├── memory_controller.v        # Ping-pong buffer controller
│   │   └── README.md                  # Memory architecture docs
│   ├── tb/                            # Testbenches
│   │   ├── tb_processing_element.v    # PE unit tests
│   │   ├── tb_systolic_array.v        # Array tests
│   │   ├── tb_memory_controller.v     # Memory tests
│   │   ├── tb_control_unit.v          # FSM tests
│   │   ├── tb_accelerator_integration.v # Integration tests
│   │   └── tb_full_system.v           # Full system tests
│   ├── INTEGRATION_README.md          # Integration guide
│   └── README.md                      # RTL directory overview
│
├── scripts/                           # Automation scripts
│   ├── golden_model_conv2d.py         # Python reference model
│   ├── python/                        # Python utilities
│   │   ├── expected_out.txt           # Expected outputs
│   │   ├── results_hw.txt             # Hardware results
│   │   └── README.md
│   ├── sim/                           # Simulation scripts
│   │   └── README.md
│   └── utils/                         # Utility scripts
│       └── README.md
│
├── sim/                               # Simulation working directory
│   └── run_integration.do             # ModelSim/QuestaSim script
│
├── third_party/                       # Third-party IP
│   ├── sram_macros/                   # Sky130 SRAM models
│   │   ├── sky130_sram_1kbyte_1rw1r_32x256_8.v
│   │   └── README.md
│   └── README.md
│
├── test_cases/                        # Golden test vectors
│   ├── 01_Basic_Minimal_*.hex         # Basic 2×2 kernel test
│   ├── 02_Basic_Identity_*.hex        # Identity kernel test
│   ├── 03_Basic_AllOnes_*.hex         # All-ones kernel test
│   ├── 04_Regular_Standard_*.hex      # Standard 3×3 kernel
│   ├── 05_Regular_LargeHalo_*.hex     # Large kernel test
│   ├── 06_Regular_PingPong_*.hex      # Ping-pong buffer test
│   ├── 07_Adv_MaxSpec_*.hex           # Maximum size (64×64)
│   ├── 08_Adv_Throughput_*.hex        # Throughput test
│   ├── 09_Pro_PartialTile_*.hex       # Partial tile handling
│   └── 10_Pro_Saturation_*.hex        # Output saturation test
│
├── config/                            # OpenLane configuration
│   └── openlane/                      # Synthesis configs
│       └── README.md
│
└── final/                             # Final implementation outputs
    └── README.md                      # Final deliverables info
```

---

## 🚀 Getting Started

### Prerequisites

**Hardware Simulation**:
- ModelSim/QuestaSim (for Verilog simulation)
- Icarus Verilog (alternative simulator)

**Software Reference**:
- Python 3.7+ with NumPy

**Physical Design** (Optional):
- OpenLane flow
- Sky130 PDK

### Quick Start

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/Uderscore/VLSI_Project.git
   cd VLSI_Project
   ```

2. **Run Basic Simulation**:
   ```bash
   cd sim
   vsim -do run_integration.do
   ```

3. **Generate Golden Model**:
   ```bash
   cd scripts
   python golden_model_conv2d.py
   ```

For detailed setup instructions, see [QUICK_START.md](QUICK_START.md).

---

## 🔧 Technical Specifications

### Operational Parameters

| Parameter | Min | Max | Type |
|-----------|-----|-----|------|
| Input Matrix (N×N) | 16×16 | 64×64 | Variable |
| Kernel Size (K×K) | 2×2 | 16×16 | Variable |
| Stride | 1 | 1 | Fixed |
| Padding | 0 | 0 | Fixed |
| Input/Weight Precision | 8-bit | 8-bit | Unsigned |
| Internal Accumulation | 32-bit | 32-bit | Fixed Point |
| Output Precision | 8-bit | 8-bit | Unsigned (Truncated) |

### Hardware Constraints

| Resource | Min | Max | Notes |
|----------|-----|-----|-------|
| On-Chip Memory | 4 KB | 32 KB | Total SRAM |
| Systolic Array | 4×4 | 8×8 | Processing Elements |
| Register Size | 8-bit | 32-bit | Datapath registers |
| External Bus | 8-bit | 32-bit | DRAM interface |
| Internal Bus | 8-bit | 128-bit | SRAM ↔ Array |

### Interface Signals

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `rst_n` | Input | 1 | Active-low async reset |
| `start` | Input | 1 | Begin computation pulse |
| `cfg_N` | Input | 7 | Input matrix dimension N |
| `cfg_K` | Input | 5 | Kernel dimension K |
| `done` | Output | 1 | Computation complete |
| `rx_data` | Input | 8-32 | Input data stream |
| `rx_valid` | Input | 1 | Input data valid |
| `rx_ready` | Output | 1 | Ready to accept input |
| `tx_data` | Output | 8-32 | Output data stream |
| `tx_valid` | Output | 1 | Output data valid |
| `tx_ready` | Input | 1 | Ready to accept output |

---

## ✅ Verification & Testing

### Test Coverage

The project includes **10 comprehensive test cases** covering:

1. **Basic Tests** (01-03): Minimal kernels, identity operations, edge cases
2. **Regular Tests** (04-06): Standard convolutions, large halos, ping-pong buffering
3. **Advanced Tests** (07-08): Maximum specifications, throughput validation
4. **Professional Tests** (09-10): Partial tiles, saturation handling

### Golden Model

A Python reference implementation generates expected outputs:
```bash
python scripts/golden_model_conv2d.py
```

Results are compared with hardware outputs with a tolerance of ±1 LSB to account for fixed-point rounding.

### Running Tests

```bash
# Run integration testbench
cd sim
vsim -do run_integration.do

# Run full system test
vsim -do run_full_system.do

# Run specific module tests
cd rtl/tb
vsim tb_systolic_array -do "run -all"
```

---

## 📊 Performance Metrics

### Design Goals

- **Throughput**: 8 MACs per cycle (64 PEs × 1 MAC/cycle)
- **Latency**: ~15 cycles (pipeline fill) + N²/64 cycles (computation)
- **Memory Bandwidth**: Up to 128 bits/cycle internal
- **Power**: Clock gating for idle PEs

### Optimization Areas

1. **Area Optimization**:
   - Counter bit-width reduction
   - Resource sharing between PEs
   - Minimal state machine complexity

2. **Power Optimization**:
   - Clock gating for idle PEs during halo loading
   - Efficient memory access patterns
   - Reduced switching activity

3. **Timing Optimization**:
   - Pipeline balancing
   - Critical path analysis
   - Maximum operating frequency tuning

---

## 🐛 Known Issues & Fixes

See [BUGFIX_SUMMARY.md](BUGFIX_SUMMARY.md) for detailed bug reports and resolutions, including:

- ✅ Multiple driver conflicts resolved
- ✅ Ping-pong buffer switching corrected
- ✅ Handshake protocol timing fixed
- ✅ Testbench timeout protection added

---

## 📚 Documentation

- **[QUICK_START.md](QUICK_START.md)**: Quick setup and simulation guide
- **[BUGFIX_SUMMARY.md](BUGFIX_SUMMARY.md)**: Integration debugging guide
- **[project.txt](project.txt)**: Complete project specification (14 pages)
- **[project_doc.pdf](project_doc.pdf)**: Official project documentation
- **[rtl/INTEGRATION_README.md](rtl/INTEGRATION_README.md)**: Detailed integration guide
- **[rtl/README.md](rtl/README.md)**: RTL architecture overview
- **[rtl/core/README.md](rtl/core/README.md)**: Systolic array details
- **[rtl/control/README.md](rtl/control/README.md)**: Control subsystem docs
- **[rtl/mem/README.md](rtl/mem/README.md)**: Memory controller docs

---

## 🔗 Learning Resources

### Recommended Reading

**Systolic Arrays**:
- [Portland State University - Systolic Arrays (PDF)](https://web.cecs.pdx.edu/~mperkows/)
- [NJIT - Matrix Multiplication Visualization (Video)](https://www.youtube.com/watch?v=cmy7LBaWuZ8)

**Memory Architecture**:
- [Ping-Pong Buffering Discussion (StackExchange)](https://electronics.stackexchange.com/)
- [IIT Madras - Memory Hierarchy (Video)](https://nptel.ac.in/)

**Fixed-Point Arithmetic**:
- [GeeksForGeeks - Fixed Point Representation](https://www.geeksforgeeks.org/fixed-point-representation/)
- [Electronic Design - Fixed vs Floating Point](https://www.electronicdesign.com/)

**TPU Architecture**:
- [Google Cloud - TPU Deep Dive](https://cloud.google.com/tpu/docs/tpus)

### SRAM Integration

**Sky130 SRAM Macros**:
- [VLSIDA Standard Macros Repository](https://github.com/VLSIDA/OpenRAM)
- [OpenRAM Memory Generator](https://github.com/Baungarten-CINVESTAV/SKY130-Macro-Memory-Cell-Generator)

---

## 🤝 Contributing

This is an academic project for CMP3020 - VLSI Design course. Team members are responsible for:

1. **Functional Verification** (10 marks): Golden model matching with ±0.1 precision
2. **Performance Optimization** (5 marks): PPA metrics ranking
3. **Personal Contribution** (5 marks): Individual component ownership

**Team Size**: 7-8 members  
**Deadline**: Week 13

### Workload Division

Each team member should contribute to specific components:
- PE design and verification
- Systolic array assembly
- Memory controller integration
- AGU implementation
- Control FSM development
- Testbench development
- Documentation

---

## 📝 Project Status

### ✅ Completed Components

- [x] Processing Element (PE) design
- [x] 8×8 Systolic Array
- [x] Memory Controller with ping-pong buffering
- [x] SRAM macro integration
- [x] Control Unit FSM
- [x] Address Generation Unit (AGU)
- [x] Data Loader
- [x] Top-level integration
- [x] Comprehensive testbenches
- [x] Golden model (Python)
- [x] 10 test cases with golden vectors
- [x] Bug fixes for integration issues

### 🔄 In Progress / Future Work

- [ ] OpenLane synthesis and place-and-route
- [ ] Power analysis and optimization
- [ ] Clock gating implementation
- [ ] Final GDS-II generation
- [ ] PPA metrics optimization
- [ ] Additional test cases
- [ ] Performance benchmarking

---

## 📧 Contact & Support

**Course**: CMP3020 - VLSI Design  
**Institution**: Cairo University Faculty of Engineering (CUFE)  
**Department**: Computer Engineering  
**Instructor**: Muhammad Sayed

For technical questions or issues:
1. Check existing documentation in the repository
2. Review testbench outputs and waveforms
3. Consult [BUGFIX_SUMMARY.md](BUGFIX_SUMMARY.md) for common issues
4. Contact team members or instructor

---

## 📜 License

This project is part of academic coursework for CMP3020 - VLSI Design at Cairo University Faculty of Engineering. All rights reserved.

---

## 🏆 Project Goals

**Primary Objective**: Design a functional 2D convolution accelerator that matches the golden model output within ±0.1 precision.

**Secondary Objectives**:
- Achieve competitive PPA (Power, Performance, Area) metrics
- Demonstrate modular and extensible architecture
- Implement industry-standard design practices
- Create comprehensive verification environment

**Bonus Opportunities**:
- Advanced dataflow analysis (Input vs Weight Stationary)
- Sophisticated memory banking strategies
- Automated regression testing suite
- Novel architectural optimizations

---

**Last Updated**: January 2026  
**Repository**: https://github.com/Uderscore/VLSI_Project  
**Branch**: copilot/describe-repo-details