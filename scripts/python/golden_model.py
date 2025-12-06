"""
Golden Model: 2D Convolution Reference Implementation
Generates test vectors and computes expected outputs for hardware verification.

Features:
- Configurable matrix sizes (N: 16-64) and kernel sizes (K: 2-16)
- 8-bit unsigned integer arithmetic
- Exports input matrix, kernel, and expected output to text files
- Supports multiple test case generation
"""

import numpy as np
import os
import sys

class ConvolutionGoldenModel:
    """Reference implementation for 2D convolution accelerator verification"""
    
    def __init__(self, N, K, seed=None):
        """
        Initialize the golden model.
        
        Args:
            N (int): Input matrix dimension (N×N), range [16, 64]
            K (int): Kernel dimension (K×K), range [2, 16]
            seed (int, optional): Random seed for reproducibility
        """
        # Validate parameters
        if not (16 <= N <= 64):
            raise ValueError(f"N must be in range [16, 64], got {N}")
        if not (2 <= K <= 16):
            raise ValueError(f"K must be in range [2, 16], got {K}")
        
        self.N = N
        self.K = K
        self.stride = 1  # Fixed per spec
        self.padding = 0  # Fixed per spec
        
        # Set random seed for reproducibility
        if seed is not None:
            np.random.seed(seed)
        
        # Calculate output dimensions
        self.output_N = (N - K) // self.stride + 1
        
        # Generate random test data (8-bit unsigned)
        self.input_matrix = np.random.randint(0, 256, size=(N, N), dtype=np.uint8)
        self.kernel = np.random.randint(0, 256, size=(K, K), dtype=np.uint8)
        self.output_matrix = None
    
    def compute_convolution(self):
        """
        Perform 2D convolution operation.
        
        Returns:
            np.ndarray: Output matrix with computed convolution results
        """
        output = np.zeros((self.output_N, self.output_N), dtype=np.uint32)
        
        print(f"Computing convolution: Input {self.N}×{self.N}, Kernel {self.K}×{self.K}")
        print(f"Output dimensions: {self.output_N}×{self.output_N}")
        
        # Slide kernel across input matrix
        for out_y in range(self.output_N):
            for out_x in range(self.output_N):
                # Calculate starting position in input
                in_y = out_y * self.stride
                in_x = out_x * self.stride
                
                # Extract window and compute MAC
                window = self.input_matrix[in_y:in_y+self.K, in_x:in_x+self.K]
                
                # Perform multiply-accumulate (32-bit accumulation)
                accumulator = 0
                for ky in range(self.K):
                    for kx in range(self.K):
                        pixel = int(window[ky, kx])
                        weight = int(self.kernel[ky, kx])
                        accumulator += pixel * weight
                
                output[out_y, out_x] = accumulator
        
        # Truncate to 8-bit (saturate if needed)
        self.output_matrix = np.clip(output, 0, 255).astype(np.uint8)
        
        print(f"✓ Convolution completed")
        print(f"  Accumulator range: [{output.min()}, {output.max()}]")
        print(f"  Output range after truncation: [{self.output_matrix.min()}, {self.output_matrix.max()}]")
        
        return self.output_matrix
    
    def save_to_files(self, output_dir="sim/data"):
        """
        Save input matrix, kernel, and expected output to text files.
        
        Args:
            output_dir (str): Directory to save files (relative to project root)
        """
        # Create output directories
        input_dir = os.path.join(output_dir, "inputs")
        expected_dir = os.path.join(output_dir, "expected")
        
        os.makedirs(input_dir, exist_ok=True)
        os.makedirs(expected_dir, exist_ok=True)
        
        # Save input matrix
        input_file = os.path.join(input_dir, "input_matrix.txt")
        np.savetxt(input_file, self.input_matrix, fmt='%3d', delimiter=' ')
        print(f"✓ Saved input matrix to: {input_file}")
        
        # Save kernel
        kernel_file = os.path.join(input_dir, "kernel.txt")
        np.savetxt(kernel_file, self.kernel, fmt='%3d', delimiter=' ')
        print(f"✓ Saved kernel to: {kernel_file}")
        
        # Save expected output
        expected_file = os.path.join(expected_dir, "expected_out.txt")
        np.savetxt(expected_file, self.output_matrix, fmt='%3d', delimiter=' ')
        print(f"✓ Saved expected output to: {expected_file}")
        
        # Save metadata
        metadata_file = os.path.join(output_dir, "test_config.txt")
        with open(metadata_file, 'w') as f:
            f.write(f"N={self.N}\n")
            f.write(f"K={self.K}\n")
            f.write(f"OUTPUT_N={self.output_N}\n")
            f.write(f"STRIDE={self.stride}\n")
            f.write(f"PADDING={self.padding}\n")
        print(f"✓ Saved test configuration to: {metadata_file}")
    
    def print_summary(self):
        """Print a summary of the test case"""
        print("\n" + "="*60)
        print("GOLDEN MODEL SUMMARY")
        print("="*60)
        print(f"Configuration:")
        print(f"  Input Matrix:  {self.N} × {self.N}")
        print(f"  Kernel:        {self.K} × {self.K}")
        print(f"  Output Matrix: {self.output_N} × {self.output_N}")
        print(f"  Stride:        {self.stride}")
        print(f"  Padding:       {self.padding}")
        print(f"\nData Statistics:")
        print(f"  Input range:   [{self.input_matrix.min()}, {self.input_matrix.max()}]")
        print(f"  Kernel range:  [{self.kernel.min()}, {self.kernel.max()}]")
        print(f"  Output range:  [{self.output_matrix.min()}, {self.output_matrix.max()}]")
        
        # Show sample corner values
        print(f"\nSample Values (for manual verification):")
        print(f"  Input[0,0] = {self.input_matrix[0,0]}")
        print(f"  Kernel[0,0] = {self.kernel[0,0]}")
        print(f"  Output[0,0] = {self.output_matrix[0,0]}")
        print("="*60 + "\n")


def generate_test_suite():
    """Generate multiple test cases covering edge cases and typical scenarios"""
    
    test_cases = [
        # (N, K, description)
        (16, 2, "Minimum dimensions"),
        (16, 8, "Small input, medium kernel"),
        (32, 3, "Typical CNN layer (32×32, 3×3)"),
        (32, 5, "Medium input, medium kernel"),
        (64, 3, "Large input, small kernel"),
        (64, 8, "Large input, medium kernel"),
        (64, 16, "Maximum dimensions"),
    ]
    
    print("="*60)
    print("GENERATING TEST SUITE")
    print("="*60)
    
    for idx, (N, K, desc) in enumerate(test_cases, 1):
        print(f"\nTest Case {idx}: {desc}")
        print(f"  Parameters: N={N}, K={K}")
        
        # Create output directory for this test case
        test_dir = f"sim/data/test_{idx}_N{N}_K{K}"
        
        # Generate and save
        model = ConvolutionGoldenModel(N, K, seed=42+idx)
        model.compute_convolution()
        model.save_to_files(output_dir=test_dir)
        model.print_summary()
    
    print("\n" + "="*60)
    print(f"✓ Generated {len(test_cases)} test cases")
    print("="*60)


def main():
    """Main entry point for golden model generation"""
    
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python golden_model.py <N> <K> [seed]        # Generate single test")
        print("  python golden_model.py --suite                # Generate full test suite")
        print("\nExamples:")
        print("  python golden_model.py 32 3                   # 32×32 input, 3×3 kernel")
        print("  python golden_model.py 64 8 42                # With specific seed")
        print("  python golden_model.py --suite                # Generate all test cases")
        sys.exit(1)
    
    if sys.argv[1] == "--suite":
        generate_test_suite()
    else:
        # Single test case
        N = int(sys.argv[1])
        K = int(sys.argv[2])
        seed = int(sys.argv[3]) if len(sys.argv) > 3 else 42
        
        print(f"Generating single test case: N={N}, K={K}, seed={seed}\n")
        
        model = ConvolutionGoldenModel(N, K, seed=seed)
        model.compute_convolution()
        model.save_to_files()
        model.print_summary()


if __name__ == "__main__":
    main()
