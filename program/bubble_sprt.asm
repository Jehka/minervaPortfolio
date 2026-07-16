.data
.word 5, 3, 8, 1, 9, 2, 7, 4, 6, 0

.text
main:
    addi a0, x0, 0x200    # base address of array (word 128 = byte 0x200)
    addi a1, x0, 10       # n = 10 elements

bubble_sort:
    addi t0, x0, 0        # i = 0
outer:
    addi t1, x0, 0        # j = 0
    addi t6, a1, -1       # t6 = n-1
    sub  t6, t6, t0       # t6 = n-1-i (inner loop limit)
inner:
    slli t2, t1, 2        # t2 = j*4
    add  t3, a0, t2       # t3 = &A[j]
    lw   t4, 0(t3)        # t4 = A[j]
    lw   t5, 4(t3)        # t5 = A[j+1]
    bge  t4, t5, swap     # if A[j] >= A[j+1], swap
    jal  x0, no_swap
swap:
    sw   t5, 0(t3)
    sw   t4, 4(t3)
no_swap:
    addi t1, t1, 1        # j++
    blt  t1, t6, inner    # if j < n-1-i, continue inner
    addi t0, t0, 1        # i++
    blt  t0, a1, outer    # if i < n, continue outer
done:
    lw   a0, 0x200(x0)    # load first element of sorted array into a0
    jal  x0, done         # halt — spin forever