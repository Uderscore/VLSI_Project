#!/usr/bin/env python3
"""
Generate test vectors for verification
"""
import numpy as np

def generate_matrix(size, max_val=255):
    """Generate random matrix"""
    return np.random.randint(0, max_val, size=(size, size))

def save_matrix(matrix, filename):
    """Save matrix to text file"""
    np.savetxt(filename, matrix, fmt='%d')

if __name__ == "__main__":
    # Generate 8×8 test matrices
    input_matrix = generate_matrix(8)
    weight_matrix = generate_matrix(8)
    
    # Save
    save_matrix(input_matrix, 'input_8x8.txt')
    save_matrix(weight_matrix, 'weights_8x8.txt')
    
    # Calculate expected output (for verification)
    output = np.dot(input_matrix, weight_matrix)
    save_matrix(output, 'expected_output_8x8.txt')
    
    print("Test vectors generated!")