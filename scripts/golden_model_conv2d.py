#!/usr/bin/env python3
"""
Golden Model for 2D Convolution
================================
Reference implementation for verifying the VLSI Convolution Accelerator.

Features:
- Valid convolution (no padding, stride=1)
- 8-bit unsigned fixed-point arithmetic
- 32-bit accumulation with 8-bit saturated/truncated output
- Generates test input files and expected output files

Usage:
    python golden_model_conv2d.py --N 16 --K 3 [--seed 42]
"""

import argparse
import numpy as np
import os

def conv2d_valid(input_matrix, kernel, verbose=False):
    """
    Perform valid 2D convolution (no padding, stride=1).
    
    Args:
        input_matrix: NxN input matrix (uint8)
        kernel: KxK kernel matrix (uint8)
        verbose: Print computation details
    
    Returns:
        Output matrix of size (N-K+1) x (N-K+1), each value 8-bit (saturated)
    """
    N = input_matrix.shape[0]
    K = kernel.shape[0]
    out_size = N - K + 1
    
    # Create output with 32-bit accumulation
    output = np.zeros((out_size, out_size), dtype=np.uint32)
    
    for oy in range(out_size):
        for ox in range(out_size):
            acc = np.uint32(0)
            for ky in range(K):
                for kx in range(K):
                    # Get input and kernel values as unsigned 8-bit
                    pixel = np.uint32(input_matrix[oy + ky, ox + kx])
                    weight = np.uint32(kernel[ky, kx])
                    # Multiply and accumulate
                    acc += pixel * weight
            output[oy, ox] = acc
            
            if verbose:
                print(f"  Output[{oy},{ox}] = {acc} (0x{acc:08X})")
    
    # Truncate to 8-bit with saturation
    output_8bit = np.clip(output, 0, 255).astype(np.uint8)
    
    return output, output_8bit

def generate_test_data(N, K, seed=None, small=False):
    """Generate random test data."""
    if seed is not None:
        np.random.seed(seed)
    
    if small:
        # Use small range ([0, 4]) to ensure max sum (K=3 => 9 * 4*4 = 144) < 255
        input_matrix = np.random.randint(0, 5, (N, N), dtype=np.uint8)
        kernel = np.random.randint(0, 5, (K, K), dtype=np.uint8)
    else:
        input_matrix = np.random.randint(0, 256, (N, N), dtype=np.uint8)
        kernel = np.random.randint(0, 256, (K, K), dtype=np.uint8)
    
    return input_matrix, kernel

def generate_simple_test_data(N, K):
    """Generate simple sequential test data for debugging."""
    input_matrix = np.zeros((N, N), dtype=np.uint8)
    for i in range(N):
        for j in range(N):
            input_matrix[i, j] = (i * N + j) % 256
    
    # Simple averaging kernel
    kernel = np.ones((K, K), dtype=np.uint8)
    
    return input_matrix, kernel

def save_matrix_hex(filename, matrix, bits=8):
    """Save matrix to file in hex format, one value per line."""
    with open(filename, 'w') as f:
        # Write dimensions first
        f.write(f"// Dimensions: {matrix.shape[0]} x {matrix.shape[1]}\n")
        f.write(f"// Bit width: {bits}\n")
        for row in matrix:
            for val in row:
                if bits == 8:
                    f.write(f"{val:02X}\n")
                else:
                    f.write(f"{val:08X}\n")

def save_matrix_dec(filename, matrix):
    """Save matrix to file in decimal format, one value per line."""
    with open(filename, 'w') as f:
        f.write(f"// Dimensions: {matrix.shape[0]} x {matrix.shape[1]}\n")
        for row in matrix:
            for val in row:
                f.write(f"{val}\n")

def save_verilog_mem(filename, matrix, bits=8):
    """Save matrix in Verilog $readmemh format."""
    with open(filename, 'w') as f:
        for row in matrix:
            for val in row:
                if bits == 8:
                    f.write(f"{val:02x}\n")
                else:
                    f.write(f"{val:08x}\n")

def generate_pattern_data(N, K, pattern):
    """Generate specific pattern test data."""
    if pattern == 'zeros':
        input_matrix = np.zeros((N, N), dtype=np.uint8)
        kernel = np.zeros((K, K), dtype=np.uint8)
    
    elif pattern == 'max':
        input_matrix = np.full((N, N), 255, dtype=np.uint8)
        kernel = np.full((K, K), 255, dtype=np.uint8)
        
    elif pattern == 'sparse':
        # Identity-like: Input has random sparse points, Kernel is identity (center=1)
        input_matrix = np.zeros((N, N), dtype=np.uint8)
        # Add 5 random points
        for _ in range(5):
            input_matrix[np.random.randint(0, N), np.random.randint(0, N)] = np.random.randint(1, 256)
        
        kernel = np.zeros((K, K), dtype=np.uint8)
        kernel[K//2, K//2] = 1
        
    elif pattern == 'checker':
        input_matrix = np.zeros((N, N), dtype=np.uint8)
        input_matrix[::2, ::2] = 255
        input_matrix[1::2, 1::2] = 255
        
        kernel = np.zeros((K, K), dtype=np.uint8)
        kernel[::2, ::2] = 1
    
    else: # Default or unknown
        return generate_test_data(N, K, seed=42)

    return input_matrix, kernel

def main():
    parser = argparse.ArgumentParser(description='Golden Model for 2D Convolution')
    parser.add_argument('--N', type=int, default=16, help='Input matrix dimension (16-64)')
    parser.add_argument('--K', type=int, default=3, help='Kernel dimension (2-8)')
    parser.add_argument('--seed', type=int, default=42, help='Random seed')
    parser.add_argument('--simple', action='store_true', help='Use simple sequential data')
    parser.add_argument('--small', action='store_true', help='Use small random values to avoid saturation')
    parser.add_argument('--pattern', type=str, default='random', choices=['random', 'zeros', 'max', 'sparse', 'checker'], help='Test pattern')
    parser.add_argument('--outdir', type=str, default='sim/testdata', help='Output directory')
    parser.add_argument('--verbose', action='store_true', help='Print detailed output')
    args = parser.parse_args()
    
    # Validate parameters
    if args.N < 16 or args.N > 64:
        print(f"Error: N must be between 16 and 64, got {args.N}")
        return 1
    if args.K < 2 or args.K > 8:
        print(f"Error: K must be between 2 and 8, got {args.K}")
        return 1
    
    print("="*60)
    print("Golden Model for 2D Convolution")
    print("="*60)
    print(f"Input size:  {args.N} x {args.N}")
    print(f"Kernel size: {args.K} x {args.K}")
    print(f"Output size: {args.N - args.K + 1} x {args.N - args.K + 1}")
    print(f"Pattern:     {args.pattern}")
    print("="*60)
    
    # Create output directory
    os.makedirs(args.outdir, exist_ok=True)
    
    # Generate test data
    if args.simple:
        input_matrix, kernel = generate_simple_test_data(args.N, args.K)
        print("Using simple sequential test data")
    elif args.pattern != 'random':
        input_matrix, kernel = generate_pattern_data(args.N, args.K, args.pattern)
        print(f"Using {args.pattern} test data")
    else:
        input_matrix, kernel = generate_test_data(args.N, args.K, args.seed, small=args.small)
        print("Using random test data")
    
    print(f"\nInput Matrix (first 8x8):")
    print(input_matrix[:min(8, args.N), :min(8, args.N)])
    
    print(f"\nKernel:")
    print(kernel)
    
    # Compute convolution
    print("\nComputing convolution...")
    output_32bit, output_8bit = conv2d_valid(input_matrix, kernel, verbose=args.verbose)
    
    print(f"\nOutput Matrix 32-bit (first 8x8):")
    out_size = min(8, output_32bit.shape[0])
    print(output_32bit[:out_size, :out_size])
    
    print(f"\nOutput Matrix 8-bit truncated (first 8x8):")
    print(output_8bit[:out_size, :out_size])
    
    # Save files
    if args.simple:
        prefix = f"N{args.N}_K{args.K}_simple"
    elif args.pattern != 'random':
        prefix = f"N{args.N}_K{args.K}_{args.pattern}"
    else:
        prefix = f"N{args.N}_K{args.K}" # Keep standard name for random
    
    # Input matrix
    input_file = os.path.join(args.outdir, f"{prefix}_input.hex")
    save_verilog_mem(input_file, input_matrix, bits=8)
    print(f"\nSaved: {input_file}")
    
    # Kernel
    kernel_file = os.path.join(args.outdir, f"{prefix}_kernel.hex")
    save_verilog_mem(kernel_file, kernel, bits=8)
    print(f"Saved: {kernel_file}")
    
    # Expected output (32-bit full precision)
    output32_file = os.path.join(args.outdir, f"{prefix}_expected_32bit.hex")
    save_verilog_mem(output32_file, output_32bit, bits=32)
    print(f"Saved: {output32_file}")
    
    # Expected output (8-bit truncated)
    output8_file = os.path.join(args.outdir, f"{prefix}_expected_8bit.hex")
    save_verilog_mem(output8_file, output_8bit, bits=8)
    print(f"Saved: {output8_file}")
    
    # Save human-readable versions
    save_matrix_dec(os.path.join(args.outdir, f"{prefix}_input.txt"), input_matrix)
    save_matrix_dec(os.path.join(args.outdir, f"{prefix}_kernel.txt"), kernel)
    save_matrix_dec(os.path.join(args.outdir, f"{prefix}_expected.txt"), output_32bit)
    
    print("\n" + "="*60)
    print("Golden model generation complete!")
    print("="*60)
    
    return 0

if __name__ == "__main__":
    exit(main())
