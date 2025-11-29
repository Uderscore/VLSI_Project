# scripts/generate_vectors.py
import numpy as np
import sys


# Config
N = 16 # change to 32 or 64 to stress test
K = 3


np.random.seed(1)
image = np.random.randint(0,256,size=(N,N),dtype=np.uint8)
kernel = np.random.randint(0,256,size=(K,K),dtype=np.uint8)


# Write image
with open('sim/data/inputs/input_matrix.txt','w') as f:
    f.write(f"# N {N}\n")
    for r in range(N):
        f.write(' '.join(map(str,image[r,:])) + '\n')


# Write kernel
with open('sim/data/inputs/kernel.txt','w') as f:
    f.write(f"# K {K}\n")
    for r in range(K):
        f.write(' '.join(map(str,kernel[r,:])) + '\n')


# Golden convolution (valid, no padding, stride 1) producing (N-K+1)x(N-K+1)
out_h = N - K + 1
out = np.zeros((out_h,out_h),dtype=np.int32)
for y in range(out_h):
    for x in range(out_h):
        patch = image[y:y+K, x:x+K].astype(np.int32)
        out[y,x] = np.sum(patch * kernel.astype(np.int32))


with open('sim/data/expected/expected_out.txt','w') as f:
    for r in range(out_h):
        f.write(' '.join(map(str,out[r,:])) + '\n')


print('Generated sim/data/inputs/input_matrix.txt, sim/data/inputs/kernel.txt, sim/data/expected/expected_out.txt')