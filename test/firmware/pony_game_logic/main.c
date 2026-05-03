/*
 * RiscV Pony Game Logic
 *
 * This is a small "pre-VGA" game loop firmware.
 *
 * Goals:
 *   - validate compiled RV32E C for game-style code
 *   - exercise input polling through MMIO
 *   - exercise local state updates
 *   - exercise branches, loops, function calls, and stack locals
 *   - avoid M-extension instructions
 *
 * Input model:
 *   bit 0 -> move left
 *   bit 1 -> move right
 *
 * Output model:
 *   the firmware emits the player X position after each input step.
 *
 * Current simulated MMIO:
 *   0x80 -> out_port
 *   0x84 -> in_port
 */

#define MMIO_OUT_ADDR 128u
#define MMIO_IN_ADDR  132u
#define SENTINEL      255u

#define INPUT_LEFT    1u
#define INPUT_RIGHT   2u

#define MIN_X         0u
#define MAX_X         15u
#define START_X       8u

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
unsigned int clamp_x(unsigned int x)
{
    if (x > MAX_X) {
        return MAX_X;
    }

    return x;
}

__attribute__((noinline))
unsigned int update_player(unsigned int x, unsigned int input)
{
    if ((input & INPUT_LEFT) != 0u) {
        if (x > MIN_X) {
            x--;
        }
    }

    if ((input & INPUT_RIGHT) != 0u) {
        x++;
    }

    return clamp_x(x);
}

__attribute__((noinline))
unsigned int compute_score(unsigned int x)
{
    unsigned int i;
    unsigned int score = 0u;

    /*
     * Small loop that behaves like a cheap software multiply:
     * score = x * 3, without using the M extension.
     */
    for (i = 0u; i < 3u; i++) {
        score += x;
    }

    return score;
}

int main(void)
{
    volatile unsigned int history[4];
    unsigned int x = START_X;
    unsigned int input;
    unsigned int score;
    unsigned int i;

    emit(0x40u);
    emit(x);

    /*
     * For simulation, the Cocotb test changes in_port between polling
     * windows. Each iteration waits for a small delay so the testbench
     * has time to update input before the next read.
     */
    for (i = 0u; i < 4u; i++) {
        volatile unsigned int delay;

        for (delay = 0u; delay < 8u; delay++) {
        }

        input = mmio_read(MMIO_IN_ADDR);
        x = update_player(x, input);
        history[i] = x;
        emit(x);
    }

    /*
     * Read back stack-local history to prove stores and loads are still
     * working in a more realistic compiled-C control flow.
     */
    emit(history[0]);
    emit(history[3]);

    score = compute_score(x);
    emit(score);

    while (1) {
    }

    return 0;
}
