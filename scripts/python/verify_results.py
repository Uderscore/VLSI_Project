"""
Verification Script: Compare Hardware Results Against Golden Model
Performs automated comparison with configurable tolerance for fixed-point arithmetic.

Features:
- Loads expected output from golden model
- Loads hardware simulation results
- Performs element-wise comparison with tolerance
- Generates detailed pass/fail report
- Supports multiple test cases
"""

import numpy as np
import os
import sys
from pathlib import Path


class ResultVerifier:
    """Automated verification tool for hardware vs. golden model comparison"""
    
    def __init__(self, tolerance=1):
        """
        Initialize the verifier.
        
        Args:
            tolerance (int): Maximum allowed difference per pixel (default: ±1)
        """
        self.tolerance = tolerance
        self.results = []
    
    def load_matrix(self, filepath):
        """
        Load a matrix from a text file.
        
        Args:
            filepath (str): Path to the text file
            
        Returns:
            np.ndarray: Loaded matrix, or None if file doesn't exist
        """
        if not os.path.exists(filepath):
            print(f"✗ Error: File not found: {filepath}")
            return None
        
        try:
            matrix = np.loadtxt(filepath, dtype=np.int32)
            print(f"✓ Loaded: {filepath} (shape: {matrix.shape})")
            return matrix
        except Exception as e:
            print(f"✗ Error loading {filepath}: {str(e)}")
            return None
    
    def compare_matrices(self, expected, actual, test_name="Test"):
        """
        Compare two matrices element-wise with tolerance.
        
        Args:
            expected (np.ndarray): Golden model output
            actual (np.ndarray): Hardware simulation output
            test_name (str): Name of the test case
            
        Returns:
            dict: Verification results
        """
        result = {
            'test_name': test_name,
            'passed': False,
            'total_elements': 0,
            'mismatches': 0,
            'max_error': 0,
            'shape_match': False,
            'details': []
        }
        
        # Check if matrices exist
        if expected is None or actual is None:
            result['details'].append("ERROR: One or both matrices could not be loaded")
            return result
        
        # Check shape compatibility
        if expected.shape != actual.shape:
            result['details'].append(f"SHAPE MISMATCH: Expected {expected.shape}, got {actual.shape}")
            return result
        
        result['shape_match'] = True
        result['total_elements'] = expected.size
        
        # Compute element-wise difference
        diff = np.abs(expected.astype(np.int32) - actual.astype(np.int32))
        result['max_error'] = int(np.max(diff))
        
        # Find mismatches exceeding tolerance
        mismatch_mask = diff > self.tolerance
        result['mismatches'] = int(np.sum(mismatch_mask))
        
        # Check if test passed
        result['passed'] = (result['mismatches'] == 0)
        
        # Generate detailed mismatch report (limit to first 10)
        if result['mismatches'] > 0:
            mismatch_indices = np.argwhere(mismatch_mask)
            for idx, (y, x) in enumerate(mismatch_indices[:10]):
                exp_val = expected[y, x]
                act_val = actual[y, x]
                error = diff[y, x]
                result['details'].append(
                    f"  Position [{y},{x}]: Expected={exp_val}, Actual={act_val}, Error={error}"
                )
            
            if result['mismatches'] > 10:
                result['details'].append(f"  ... and {result['mismatches'] - 10} more mismatches")
        
        return result
    
    def print_result(self, result):
        """Print formatted verification result"""
        print("\n" + "="*70)
        print(f"VERIFICATION RESULT: {result['test_name']}")
        print("="*70)
        
        if not result['shape_match']:
            print("❌ FAILED - Shape mismatch")
            for detail in result['details']:
                print(detail)
            print("="*70)
            return
        
        status = "✅ PASSED" if result['passed'] else "❌ FAILED"
        print(f"Status:          {status}")
        print(f"Total Elements:  {result['total_elements']}")
        print(f"Mismatches:      {result['mismatches']} ({result['mismatches']/result['total_elements']*100:.2f}%)")
        print(f"Max Error:       {result['max_error']} (tolerance: ±{self.tolerance})")
        
        if not result['passed']:
            print("\nMismatch Details:")
            for detail in result['details']:
                print(detail)
        
        print("="*70)
    
    def verify_test_case(self, expected_file, actual_file, test_name="Test"):
        """
        Verify a single test case.
        
        Args:
            expected_file (str): Path to expected output file
            actual_file (str): Path to hardware results file
            test_name (str): Name of the test case
            
        Returns:
            dict: Verification results
        """
        print(f"\n--- Verifying: {test_name} ---")
        
        expected = self.load_matrix(expected_file)
        actual = self.load_matrix(actual_file)
        
        result = self.compare_matrices(expected, actual, test_name)
        self.results.append(result)
        self.print_result(result)
        
        return result
    
    def print_summary(self):
        """Print overall verification summary"""
        if not self.results:
            print("\nNo tests were run.")
            return
        
        passed = sum(1 for r in self.results if r['passed'])
        total = len(self.results)
        
        print("\n" + "="*70)
        print("VERIFICATION SUMMARY")
        print("="*70)
        print(f"Total Tests:     {total}")
        print(f"Passed:          {passed}")
        print(f"Failed:          {total - passed}")
        print(f"Pass Rate:       {passed/total*100:.1f}%")
        print("="*70)
        
        if passed == total:
            print("✅ ALL TESTS PASSED - Hardware matches golden model!")
        else:
            print("❌ SOME TESTS FAILED - Review errors above")
            print("\nFailed Tests:")
            for r in self.results:
                if not r['passed']:
                    print(f"  - {r['test_name']}: {r['mismatches']} mismatches, max error = {r['max_error']}")
        
        print("="*70 + "\n")
        
        return passed == total


def verify_single_test(expected_file, actual_file, tolerance=1):
    """
    Verify a single test case (convenience function).
    
    Args:
        expected_file (str): Path to expected output
        actual_file (str): Path to hardware results
        tolerance (int): Allowed difference per element
        
    Returns:
        bool: True if test passed
    """
    verifier = ResultVerifier(tolerance=tolerance)
    result = verifier.verify_test_case(expected_file, actual_file, "Single Test")
    return result['passed']


def verify_test_suite(data_dir="sim/data", tolerance=1):
    """
    Verify all test cases in a directory structure.
    
    Args:
        data_dir (str): Base directory containing test cases
        tolerance (int): Allowed difference per element
        
    Returns:
        bool: True if all tests passed
    """
    verifier = ResultVerifier(tolerance=tolerance)
    
    print("="*70)
    print("RUNNING VERIFICATION SUITE")
    print("="*70)
    print(f"Data Directory: {data_dir}")
    print(f"Tolerance: ±{tolerance}")
    
    # Find all test directories
    test_dirs = []
    if os.path.exists(data_dir):
        for item in os.listdir(data_dir):
            test_path = os.path.join(data_dir, item)
            if os.path.isdir(test_path) and item.startswith("test_"):
                test_dirs.append(test_path)
    
    if not test_dirs:
        # Try default single test location
        expected_file = os.path.join(data_dir, "expected", "expected_out.txt")
        actual_file = os.path.join(data_dir, "results", "results_hw.txt")
        
        if os.path.exists(expected_file):
            verifier.verify_test_case(expected_file, actual_file, "Default Test")
        else:
            print(f"\n✗ No test cases found in {data_dir}")
            print("  Expected structure:")
            print("    sim/data/expected/expected_out.txt")
            print("    sim/data/results/results_hw.txt")
            print("  Or:")
            print("    sim/data/test_1_N32_K3/expected/expected_out.txt")
            print("    sim/data/test_1_N32_K3/results/results_hw.txt")
            return False
    else:
        # Verify each test case
        test_dirs.sort()
        for test_dir in test_dirs:
            test_name = os.path.basename(test_dir)
            expected_file = os.path.join(test_dir, "expected", "expected_out.txt")
            actual_file = os.path.join(test_dir, "results", "results_hw.txt")
            
            verifier.verify_test_case(expected_file, actual_file, test_name)
    
    # Print final summary
    all_passed = verifier.print_summary()
    
    return all_passed


def main():
    """Main entry point for verification script"""
    
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python verify_results.py --suite [tolerance]           # Verify all test cases")
        print("  python verify_results.py <expected> <actual> [tol]     # Verify single test")
        print("\nExamples:")
        print("  python verify_results.py --suite")
        print("  python verify_results.py --suite 2")
        print("  python verify_results.py sim/data/expected/expected_out.txt sim/data/results/results_hw.txt")
        print("  python verify_results.py expected.txt actual.txt 1")
        sys.exit(1)
    
    if sys.argv[1] == "--suite":
        tolerance = int(sys.argv[2]) if len(sys.argv) > 2 else 1
        success = verify_test_suite(tolerance=tolerance)
        sys.exit(0 if success else 1)
    else:
        # Single test verification
        expected_file = sys.argv[1]
        actual_file = sys.argv[2]
        tolerance = int(sys.argv[3]) if len(sys.argv) > 3 else 1
        
        success = verify_single_test(expected_file, actual_file, tolerance)
        sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
