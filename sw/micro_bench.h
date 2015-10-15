// ***************************************************************************
//
//        UCLA CDSC Microbenchmark Software
//
// Engineer:            Peng Wei
// Create Date:         Oct 13, 2015
// ***************************************************************************

#ifndef _MICRO_BENCH_H
#define _MICRO_BENCH_H

#ifndef CL
# define CL(x)                     ((x) * 64)
#endif // CL

#ifndef LOG2_CL
# define LOG2_CL                   6
#endif // LOG2_CL

#ifndef MB
# define MB(x)                     ((x) * 1024 * 1024)
#endif // MB

#define CACHELINE_ALIGNED_ADDR(p)  ((p) >> LOG2_CL)

#define DSM_SIZE                   MB(4)

#define CSR_CIPUCTL                0x280

#define CSR_AFU_DSM_BASEL          0x1a00
#define CSR_AFU_DSM_BASEH          0x1a04
#define CSR_SRC_ADDR               0x1a20
#define CSR_DST_ADDR               0x1a24
#define CSR_CTL                    0x1a2c
#define CSR_DATA_SIZE              0x1a30
#define CSR_LOOP_NUM               0x1a34

#define CSR_OFFSET(x)              ((x) / sizeof(bt32bitCSR))

#define DSM_STATUS_COMPLETE	   0x40
#define DSM_STATUS_TEST_ERROR      0x44
#define DSM_STATUS_MODE_ERROR_0    0x60

#define DSM_STATUS_ERROR_REGS      8

#endif
