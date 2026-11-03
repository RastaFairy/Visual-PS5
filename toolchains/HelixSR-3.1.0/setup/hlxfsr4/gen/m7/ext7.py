# from kernels/m7 (weights, output as arguments)
import numpy as np, sys
I=np.fromfile(sys.argv[1],np.uint8)
i8=lambda o,n: I[o:o+n].view(np.int8).astype(np.int64)
i32=lambda o,n: I[o:o+4*n].view(np.int32).astype(np.int64)
WC=np.array([[i8(13952+16*o+256*t,16) for t in range(9)] for o in range(16)])          # [o,t,i]
BC=i32(16256,16)
W1=np.array([i8(16384+32*o,32) for o in range(64)]); B1=i32(18432,64)                  # [64,32]
W2=np.array([i8(18688+64*o,64) for o in range(32)]); B2=i32(20736,32)                  # [32,64]
WP=np.array([[[i8(20864+1024*py+512*px+32*o,32) for o in range(16)] for px in range(2)] for py in range(2)])  # [py,px,16,32]
BP=i32(22912,16)
np.savez(sys.argv[2],WC=WC,BC=BC,W1=W1,B1=B1,W2=W2,B2=B2,WP=WP,BP=BP)
print('ok',np.abs(WC).max(),BC[:4],B1[:4],B2[:4],BP[:4])
