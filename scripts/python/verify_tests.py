#!/usr/bin/env python3
"""
Verify test outputs match expected results
"""

def parse_log(filename):
    """Extract test results from log file"""
    passes = 0
    fails = 0
    with open(filename, 'r') as f:
        for line in f:
            if '✓ PASS' in line:
                passes += 1
            elif '✗ FAIL' in line:
                fails += 1
    return passes, fails

if __name__ == "__main__":
    print("Verifying PE tests...")
    pe_pass, pe_fail = parse_log('sim/results/pe_test.log')
    print(f"  PE: {pe_pass} passed, {pe_fail} failed")
    
    print("Verifying Array tests...")
    arr_pass, arr_fail = parse_log('sim/results/array_test.log')
    print(f"  Array: {arr_pass} passed, {arr_fail} failed")
    
    if pe_fail == 0 and arr_fail == 0:
        print("\n✅ ALL TESTS PASSED!")
        exit(0)
    else:
        print("\n❌ SOME TESTS FAILED")
        exit(1)