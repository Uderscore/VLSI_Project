#!/bin/bash
################################################################################
# Automated Verification Script
# Orchestrates the complete verification flow:
#   1. Generate golden model test vectors
#   2. Run hardware simulation (when available)
#   3. Compare results and report
################################################################################

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_DIR="$PROJECT_ROOT/scripts/python"
SIM_DIR="$PROJECT_ROOT/sim"
DATA_DIR="$SIM_DIR/data"

# Default parameters
TOLERANCE=1
RUN_SIMULATION=false
GENERATE_VECTORS=true
TEST_MODE="suite"  # Options: suite, single

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  $1"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════╝${NC}"
}

print_step() {
    echo -e "${YELLOW}► $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_python() {
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 not found. Please install Python 3."
        exit 1
    fi
    print_success "Python 3 found: $(python3 --version)"
}

check_dependencies() {
    print_step "Checking dependencies..."
    
    check_python
    
    # Check for numpy
    if ! python3 -c "import numpy" &> /dev/null; then
        print_error "NumPy not found. Installing..."
        pip3 install numpy
    else
        print_success "NumPy found"
    fi
}

################################################################################
# Main Workflow Functions
################################################################################

generate_golden_model() {
    print_header "STEP 1: Generate Golden Model Test Vectors"
    
    cd "$PROJECT_ROOT"
    
    if [ "$TEST_MODE" = "suite" ]; then
        print_step "Generating full test suite..."
        python3 "$PYTHON_DIR/golden_model.py" --suite
        
        if [ $? -eq 0 ]; then
            print_success "Test suite generated successfully"
        else
            print_error "Failed to generate test suite"
            exit 1
        fi
    else
        # Single test case (default 32x32 input, 3x3 kernel)
        N=${TEST_N:-32}
        K=${TEST_K:-3}
        SEED=${TEST_SEED:-42}
        
        print_step "Generating single test: N=$N, K=$K, seed=$SEED"
        python3 "$PYTHON_DIR/golden_model.py" $N $K $SEED
        
        if [ $? -eq 0 ]; then
            print_success "Single test case generated successfully"
        else
            print_error "Failed to generate test case"
            exit 1
        fi
    fi
    
    echo ""
}

run_hardware_simulation() {
    print_header "STEP 2: Run Hardware Simulation (PLACEHOLDER)"
    
    print_info "Hardware simulation will be integrated here once RTL is complete."
    print_info "Expected simulation steps:"
    echo "  1. Compile Verilog/VHDL sources"
    echo "  2. Load test vectors from sim/data/inputs/"
    echo "  3. Run testbench simulation"
    echo "  4. Export results to sim/data/results/results_hw.txt"
    
    # Placeholder: Check if results already exist
    if [ -f "$DATA_DIR/results/results_hw.txt" ]; then
        print_success "Found existing hardware results"
    elif [ -d "$DATA_DIR/test_1_N32_K3/results" ]; then
        print_success "Found existing test suite results"
    else
        print_info "No hardware results found yet."
        print_info "To run verification, you'll need to:"
        echo "  1. Implement the hardware testbench (rtl/tb/tb_full_system.v)"
        echo "  2. Run ModelSim/QuestaSim simulation"
        echo "  3. Generate results_hw.txt files"
    fi
    
    echo ""
}

verify_results() {
    print_header "STEP 3: Verify Results Against Golden Model"
    
    cd "$PROJECT_ROOT"
    
    print_step "Running verification with tolerance = ±$TOLERANCE"
    
    python3 "$PYTHON_DIR/verify_results.py" --suite $TOLERANCE
    VERIFY_RESULT=$?
    
    echo ""
    
    if [ $VERIFY_RESULT -eq 0 ]; then
        print_success "VERIFICATION PASSED - All tests match golden model!"
        return 0
    else
        print_error "VERIFICATION FAILED - Check errors above"
        return 1
    fi
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Automated verification script for the Convolution Accelerator project.

OPTIONS:
    --suite              Generate full test suite (default)
    --single N K [seed]  Generate single test case
    --sim                Run hardware simulation (when available)
    --verify-only        Skip generation, only verify existing results
    --tolerance N        Set comparison tolerance (default: 1)
    -h, --help           Show this help message

EXAMPLES:
    $0                                    # Generate test suite
    $0 --single 32 3                      # Generate single 32×32, 3×3 test
    $0 --single 64 8 42                   # With specific seed
    $0 --verify-only                      # Only verify existing results
    $0 --verify-only --tolerance 2        # With custom tolerance
    $0 --sim                              # Full flow with simulation

WORKFLOW:
    1. Generate test vectors using Python golden model
    2. (Optional) Run hardware simulation
    3. Compare hardware results against expected output

DIRECTORY STRUCTURE:
    sim/data/inputs/input_matrix.txt      - Input test data
    sim/data/inputs/kernel.txt            - Kernel weights
    sim/data/expected/expected_out.txt    - Golden model output
    sim/data/results/results_hw.txt       - Hardware simulation output

EOF
}

################################################################################
# Main Script
################################################################################

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --suite)
                TEST_MODE="suite"
                shift
                ;;
            --single)
                TEST_MODE="single"
                TEST_N=$2
                TEST_K=$3
                TEST_SEED=${4:-42}
                shift 3
                [ -n "$4" ] && shift
                ;;
            --sim)
                RUN_SIMULATION=true
                shift
                ;;
            --verify-only)
                GENERATE_VECTORS=false
                shift
                ;;
            --tolerance)
                TOLERANCE=$2
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Print configuration
    print_header "Convolution Accelerator - Automated Verification"
    echo "Project Root:  $PROJECT_ROOT"
    echo "Data Directory: $DATA_DIR"
    echo "Test Mode:     $TEST_MODE"
    echo "Tolerance:     ±$TOLERANCE"
    echo ""
    
    # Check dependencies
    check_dependencies
    echo ""
    
    # Execute workflow
    if [ "$GENERATE_VECTORS" = true ]; then
        generate_golden_model
    fi
    
    if [ "$RUN_SIMULATION" = true ]; then
        run_hardware_simulation
    fi
    
    verify_results
    FINAL_RESULT=$?
    
    # Summary
    print_header "Verification Complete"
    if [ $FINAL_RESULT -eq 0 ]; then
        print_success "All checks passed!"
        exit 0
    else
        print_error "Verification failed. Review the output above."
        exit 1
    fi
}

# Run main function
main "$@"
