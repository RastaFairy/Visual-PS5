/* Real process entry point (_start) for a PS5 title launched by the
 * console's own kernel module loader - NOT the payload/elfldr bootstrap.
 * Sequence ported from SharpProspero.Link/CrtEmitter.cs's StartCode
 * (confirmed: _init_env and atexit are real libc.prx exports, present in
 * the ported catalog - not .NET-runtime-specific, so this is a direct,
 * faithful port rather than an approximation).
 *
 * Deliberately minimal for this phase: _init/_fini are empty stubs (no
 * .init_array walking) since PS5SDK has no C++ global constructors or
 * __attribute__((constructor)) functions yet. Add a real init-array walker
 * here if that ever changes - see DynamicWriter.cs's BuildInitWalker for
 * the reference behavior.
 *
 * This is just another object file to ps5link: _init_env/atexit/exit are
 * resolved as catalog imports exactly like any other function a PS5SDK .c
 * file calls; main/_init/_fini are resolved as local symbols within this
 * same link, through the identical code path.
 */
    .text
    .globl _start
    .globl _init
    .globl _fini

_start:
    .cfi_startproc
    /* Some launchers enter with only the small argument area mapped below
     * the initial RSP. Switch before the first push/call so the CRT never
     * writes into that guard page. The private stack is in this image's BSS. */
    mov    %rdi, %r12              /* loader process-parameter block */
    mov    %rsi, %r13              /* loader teardown routine */
    lea    __ps5link_main_stack_top(%rip), %rsp
    and    $-16, %rsp              /* SysV call-site alignment */

    mov    (%r12), %r14d           /* argc, from the loader's parameter block */
    lea    8(%r12), %r15           /* argv */
    mov    %r12, %rdi

    call   _init_env                /* initialize libc before using its services */

    test   %r13, %r13
    jz     1f
    mov    %r13, %rdi
    call   atexit                   /* register the loader's teardown to run at process exit */
1:

    lea    _fini(%rip), %rdi
    call   atexit                   /* register this module's own teardown */

    call   _init                    /* constructors (a no-op stub for now, see file header) */

    mov    %r14d, %edi
    mov    %r15, %rsi
    xor    %edx, %edx
    call   main

    mov    %eax, %edi
    call   exit
    ud2
    .cfi_endproc
    .size _start, . - _start

/* No global constructors/destructors yet - see file header. */
_init:
    ret
_fini:
    ret

/* Keep the initial C runtime stack independent from the loader's transient
 * entry stack. A 1 MiB stack matches the IDE's standard native-thread budget. */
    .section .bss,"aw",@nobits
    .balign 16
    .globl __ps5link_main_stack_top
    .skip 0x100000
__ps5link_main_stack_top:
