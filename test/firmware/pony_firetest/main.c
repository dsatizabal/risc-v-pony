/*
 * RiscV Pony Firetest - C version
 *
 * Goals:
 *   - verify a real RV32E C build can boot on Pony
 *   - exercise function calls
 *   - exercise loops and branches
 *   - exercise stack locals
 *   - exercise MMIO input/output
 *
 * This deliberately avoids:
 *   - libc
 *   - printf/syscalls
 *   - multiplication/division
 *   - initialized global variables
 */

#define MMIO_OUT_ADDR 128u
#define MMIO_IN_ADDR  132u
#define SENTINEL      255u

static inline void mmio_write(unsigned int addr, unsigned int value)
{
    *(volatile unsigned int *)addr = value;
}

static inline unsigned int mmio_read(unsigned int addr)
{
    return *(volatile unsigned int *)addr;
}

static inline void emit(unsigned int value)
{
    mmio_write(MMIO_OUT_ADDR, SENTINEL);
    mmio_write(MMIO_OUT_ADDR, value);
}

__attribute__((noinline))
unsigned int sum_to(unsigned int n)
{
    unsigned int i;
    unsigned int acc = 0u;

    for (i = 1u; i <= n; i++) {
        acc += i;
    }

    return acc;
}

__attribute__((noinline))
unsigned int mix_value(unsigned int a, unsigned int b)
{
    unsigned int i;
    unsigned int acc = 0u;

    for (i = 0u; i < 2u; i++) {
        acc += a;
    }

    return acc + b + 3u;
}

int main(void)
{
    volatile unsigned int scratch[2];
    unsigned int input;
    unsigned int branch_value;

    emit(0x11u);

    input = mmio_read(MMIO_IN_ADDR);
    emit(input + 1u);

    emit(sum_to(5u));
    emit(mix_value(7u, 4u));

    scratch[0] = 0x33u;
    scratch[1] = scratch[0] + 0x0Fu;
    emit(scratch[1]);

    if (3u < 9u) {
        branch_value = 0xAAu;
    } else {
        branch_value = 0xEEu;
    }

    emit(branch_value);

    while (1) {
    }

    return 0;
}
