# Windows x64 calling convention version
# First argument is in %rcx (not %rdi)

.global get_context
get_context:
    # Save the return address and stack pointer.
    movq (%rsp), %r8
    movq %r8, 8*0(%rcx)
    leaq 8(%rsp), %r8
    movq %r8, 8*1(%rcx)

    # Save preserved registers.
    movq %rbx, 8*2(%rcx)
    movq %rbp, 8*3(%rcx)
    movq %r12, 8*4(%rcx)
    movq %r13, 8*5(%rcx)
    movq %r14, 8*6(%rcx)
    movq %r15, 8*7(%rcx)

    # return
    xorl %eax, %eax
    ret

.global set_context
set_context:
    # Should return to the address set with {get, swap}_context.
    movq 8*0(%rcx), %r8

    # Load new stack pointer
    movq 8*1(%rcx), %rsp

    # Load preserved registers.
    movq 8*2(%rcx), %rbx
    movq 8*3(%rcx), %rbp
    movq 8*4(%rcx), %r12
    movq 8*5(%rcx), %r13
    movq 8*6(%rcx), %r14
    movq 8*7(%rcx), %r15

    # Push RIP to stack for RET.
    pushq %r8

    # Return.
    xorl %eax, %eax
    ret

.global swap_context
swap_context:
    # Save the return address.
    movq (%rsp), %r8
    movq %r8, 8*0(%rcx)
    leaq 8(%rsp), %r8
    movq %r8, 8*1(%rcx)

    # Save preserved registers
    movq %rbx, 8*2(%rcx)
    movq %rbp, 8*3(%rcx)
    movq %r12, 8*4(%rcx)
    movq %r13, 8*5(%rcx)
    movq %r14, 8*6(%rcx)
    movq %r15, 8*7(%rcx)

    # Should return to the address set with {get, swap}_context.
    # Second argument is in %rdx on Windows
    movq 8*0(%rdx), %r8

    # Load new stack pointer.
    movq 8*1(%rdx), %rsp

    # Load preserved registers
    movq 8*2(%rdx), %rbx
    movq 8*3(%rdx), %rbp
    movq 8*4(%rdx), %r12
    movq 8*5(%rdx), %r13
    movq 8*6(%rdx), %r14
    movq 8*7(%rdx), %r15

    # Push RIP to stack for RET.
    pushq %r8

    # Return.
    xorl %eax, %eax
    ret
