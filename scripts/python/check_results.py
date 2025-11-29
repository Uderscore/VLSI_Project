# scripts/check_results.py
import numpy as np


exp = np.loadtxt('sim/data/expected/expected_out.txt', dtype=np.int64)
res_stream = np.loadtxt('sim/data/results/results_hw.txt', dtype=np.int64)

# res_stream is a time-series dump from the systolic array (shape e.g. 108x8).
# For comparison with the golden convolution (14x14 for N=16,K=3),
# we flatten the stream and take the first exp.size entries, then
# reshape to exp.shape. This aligns shapes so we can at least see
# value mismatches.
flat = res_stream.reshape(-1)
if flat.size < exp.size:
    print('FAIL: hardware stream too short', flat.size, 'vs needed', exp.size)
    raise SystemExit(1)

res = flat[: exp.size].reshape(exp.shape)


if exp.shape != res.shape:
    print('FAIL: shape mismatch', exp.shape, res.shape)
    raise SystemExit(1)


bad = np.where(exp != res)
if bad[0].size == 0:
    print('PASS: hardware matches golden model')
else:
    print('FAIL: mismatches at', bad[0].size, 'positions')
    for r,c in zip(bad[0][:10], bad[1][:10]):
        print('pos',r,c,'expected',exp[r,c],'got',res[r,c])
    raise SystemExit(2)