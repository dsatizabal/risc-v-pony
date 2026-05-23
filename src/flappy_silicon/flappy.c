// flappy.c
// Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -O2 -T link.ld -o flappy.elf crt0.S flappy.c
// Extract: riscv64-unknown-elf-objcopy -O binary flappy.elf flappy.bin

// --------------------------------------------------------
// 1. HARDWARE MEMORY MAP (Volatile Pointers)
// --------------------------------------------------------
#define VGA_CTRL       (*((volatile unsigned int*)140))
#define VGA_OBJ_INDEX  (*((volatile unsigned int*)148))
#define VGA_OBJ_WORD0  (*((volatile unsigned int*)152))
#define VGA_OBJ_WORD1  (*((volatile unsigned int*)156))
#define VGA_BG_COLOR   (*((volatile unsigned int*)160))
#define VGA_OBJ_WORD2  (*((volatile unsigned int*)164))
#define FRAMES_COUNTER (*((volatile unsigned int*)168))

// --------------------------------------------------------
// 2. FONT ARRAYS (Replaces switch statements to prevent Jump Table bugs)
// --------------------------------------------------------
static const unsigned int FONT_W1[10] = {
    0x3C666666, 0x18381818, 0x3C66060C, 0x3C66061C, 0x0C1C3C6C,
    0x7E607C06, 0x3C66607C, 0x7E06060C, 0x3C66663C, 0x3C666666
};

static const unsigned int FONT_W2[10] = {
    0x6666663C, 0x1818187E, 0x1830607E, 0x0606663C, 0xCCFE0C0C,
    0x0606663C, 0x6666663C, 0x18181818, 0x6666663C, 0x3E06063C
};

// --------------------------------------------------------
// 3. MAIN ENTRY POINT
// --------------------------------------------------------
int main(void) {
    // Setup Background (Blue Sky = 0x03)
    VGA_BG_COLOR = 0x03;

    // Draw Ground Line (Rect 7, Green = 0x0C -> 0x0600 in WORD1)
    VGA_OBJ_INDEX = 7;
    VGA_OBJ_WORD0 = 0x80000000 | (0 << 15) | (220 << 5);
    VGA_OBJ_WORD1 = (320 << 22) | (20 << 13) | 0x0600;

    // Turn on Monitor
    VGA_CTRL = 1;

    // Game State Variables
    int bird_y = 120;
    int bird_v = 0;
    int pipe_x = 320;
    int pipe_gap_y = 80;
    int gap_size = 60;

    int score_ones = 0;
    int score_tens = 0;

    int cloud_x = 320;
    unsigned int last_frame = FRAMES_COUNTER;

    // --------------------------------------------------------
    // 4. INFINITE GAME LOOP
    // --------------------------------------------------------
    while (1) {

        // Wait for VBLANK
        while (FRAMES_COUNTER == last_frame);
        last_frame = FRAMES_COUNTER;

        // --- WORLD PHYSICS ---
        bird_v += 1;
        bird_y += (bird_v >> 1);

        // Move Pipes
        pipe_x -= 2;
        if (pipe_x < -30) {
            pipe_x = 320;
            // Pseudo-random height (0 to 63)
            pipe_gap_y = 40 + (last_frame & 63);

            score_ones++;
            if (score_ones > 9) {
                score_ones = 0;
                score_tens++;
                if (score_tens > 9) score_tens = 0;
            }
        }

        // Move Cloud Background
        if ((last_frame & 3) == 0) cloud_x -= 1;
        if (cloud_x < -64) cloud_x = 320;

        // --- AI AUTO-PILOT ---
        if (bird_y > (pipe_gap_y + 20) && bird_v >= 0) {
            bird_v = -6;
        }

        // --- AABB COLLISION DETECTION ---
        int hit = 0;
        if (bird_y > 212 || bird_y < 0) hit = 1;

        if (88 >= pipe_x && 80 <= pipe_x + 30) {
            if (bird_y <= pipe_gap_y) hit = 1;
            if (bird_y + 8 >= pipe_gap_y + gap_size) hit = 1;
        }

        if (hit) {
            bird_y = 120;
            bird_v = 0;
            pipe_x = 320;
            score_ones = 0;
            score_tens = 0;
        }

        // --- RENDER GRAPHICS ---

        // NEW: Render Background Cloud as Rect 6 (Behind Pipes!)
        // Width = 40, Height = 20, Color = White (0x3F -> 0x1F80 in WORD1)
        VGA_OBJ_INDEX = 6;
        VGA_OBJ_WORD0 = 0x80000000 | (cloud_x << 15) | (40 << 5);
        VGA_OBJ_WORD1 = (40 << 22) | (20 << 13) | 0x1F80;

        // Render Top Pipe (Rect 4, Green)
        VGA_OBJ_INDEX = 4;
        VGA_OBJ_WORD0 = 0x80000000 | (pipe_x << 15) | (0 << 5);
        VGA_OBJ_WORD1 = (30 << 22) | (pipe_gap_y << 13) | 0x0600;

        // Render Bottom Pipe (Rect 5, Green)
        VGA_OBJ_INDEX = 5;
        VGA_OBJ_WORD0 = 0x80000000 | (pipe_x << 15) | ((pipe_gap_y + gap_size) << 5);
        int bottom_h = 240 - (pipe_gap_y + gap_size);
        VGA_OBJ_WORD1 = (30 << 22) | (bottom_h << 13) | 0x0600;

        // Render Bird (Sprite 0, Yellow = 0x3C)
        VGA_OBJ_INDEX = 0;
        VGA_OBJ_WORD0 = 0x80000000 | (0x3C << 25) | (80 << 15) | (bird_y << 5);
        VGA_OBJ_WORD1 = 0x183C7EFF;
        VGA_OBJ_WORD2 = 0xFF7E3C18;

        // Render Score Tens (Sprite 1, White)
        VGA_OBJ_INDEX = 1;
        VGA_OBJ_WORD0 = 0x80000000 | (0x3F << 25) | (150 << 15) | (10 << 5);
        VGA_OBJ_WORD1 = FONT_W1[score_tens];
        VGA_OBJ_WORD2 = FONT_W2[score_tens];

        // Render Score Ones (Sprite 2, White)
        VGA_OBJ_INDEX = 2;
        VGA_OBJ_WORD0 = 0x80000000 | (0x3F << 25) | (158 << 15) | (10 << 5);
        VGA_OBJ_WORD1 = FONT_W1[score_ones];
        VGA_OBJ_WORD2 = FONT_W2[score_ones];
    }
}
