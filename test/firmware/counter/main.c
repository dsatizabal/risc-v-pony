// Define our Memory-Mapped I/O addresses as volatile pointers
#define OUT_PORT (*(volatile unsigned int *)128)
#define IN_PORT  (*(volatile unsigned int *)132)

int main() {
    int counter = 0;

    while (1) {
        // Read the physical input pins
        int sensor_data = IN_PORT;

        // Write the math result directly to the output pins
        OUT_PORT = sensor_data + counter;

        counter++;
    }

    return 0; // We will never reach here
}

