#ifndef _KLTN_RVMODEL_MACROS_H
#define _KLTN_RVMODEL_MACROS_H

// The RTL enters M-mode directly and this first integration intentionally
// excludes privileged ACTs.  No platform boot sequence is required.
#define RVMODEL_DATA_SECTION
#define STANDARD_SM_SUPPORTED

#define RVMODEL_BOOT

#define RVMODEL_HALT_PASS       \
  li t0, 0xC0000200            ;\
  li x1, 1                     ;\
  sw x1, 0(t0)                 ;\
1: j 1b                        ;

#define RVMODEL_HALT_FAIL       \
  li t0, 0xC0000200            ;\
  li x1, 3                     ;\
  sw x1, 0(t0)                 ;\
1: j 1b                        ;

#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR) \
1:                           ;                        \
  lbu  _R1, 0(_STR_PTR)      ;                        \
  beqz _R1, 3f               ;                        \
  li   _R2, 0xC0000204       ;                        \
  sw   _R1, 0(_R2)           ;                        \
  addi _STR_PTR, _STR_PTR, 1 ;                        \
  j 1b                       ;                        \
3:

#define RVMODEL_INTERRUPT_LATENCY 10
#define RVMODEL_TIMER_INT_SOON_DELAY 10000

#endif
