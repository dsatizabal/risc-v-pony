#define OUT_PORT (*(volatile unsigned int *)128)
#define IN_PORT  (*(volatile unsigned int *)132)

// Using a function with a switch forces the compiler to generate
// instruction logic (ROM) instead of a RAM data array lookup!
unsigned int get_seg7(int num) {
    switch(num) {
        case 0: return 0x3F;
        case 1: return 0x06;
        case 2: return 0x5B;
        case 3: return 0x4F;
        case 4: return 0x66;
        case 5: return 0x6D;
        case 6: return 0x7D;
        case 7: return 0x07;
        case 8: return 0x7F;
        case 9: return 0x6F;
        default: return 0x00;
    }
}

int main() {
    int count = 0;
    int last_button_state = 0;

    // Send the initial '0' to the display
    OUT_PORT = get_seg7(count);

    while (1) {
        // Read the physical input pins
        int current_button_state = IN_PORT & 0x01;

        // EDGE DETECTION: Did the button just go from OFF to ON?
        if (current_button_state == 1 && last_button_state == 0) {

            count++;
            if (count > 9) count = 0;

            // Push the safely decoded graphic to the physical pins!
            OUT_PORT = get_seg7(count);
        }

        last_button_state = current_button_state;
    }

    return 0;
}
