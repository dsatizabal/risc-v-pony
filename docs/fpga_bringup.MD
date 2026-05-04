# Testing RiscV Pony on FPGA

The first physical test of the RisdV Pony CPU was made on a [TangNano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html) FPGA using [Gowin EDA](https://www.gowinsemi.com/en/support/download_eda/) and [openFPGALoader](https://github.com/trabucayre/openFPGALoader) from WSL.

## Get setup

- Gowin EDA: You must create an account to download the software, also you must request a license with your machine's MAC address and that may take some 24h.
- For the openFPGALoader you can install it directly in WSL (Ubuntu 24 was used)

Note that to use the openFPGALoader in WSL you must redirect the USB from Windows to WSL, proceed as follows:

- Connect the TangNano to the USB port
- Open a PowerShell console (must be running with elevated privileges) and run the following command:

```bash
usbipd list
```
<img src="../img/usbipd-list.jpg" width=800 />

We see the device USB Serial Converter, that's our TangNano, we must share that one, then open the WSL terminal and run the following commands:

```bash
usbipd bind --busid 1-1
usbipd attach --wsl --busid 1-1
```

<img src="../img/usbipd-attach.jpg" width=800 />

Then go to the WSL console and run:

```bash
lsusb
openFPGALoader --detect
```
<img src="../img/lsusb.jpg" width=800 />

we're now ready to upload to the FPGA

## Create the Gowin project

Create a Gowin project, then you can add all the files you need.

For the first tests there are some modified version created to use a direct ROM access instead of using the SPI interface, you can find different versions of that first test in the [tangnano20kROM folder](../src/tangnano20kROM/). See that every folder inside of it has a RTL, Firmware and constraints sub folder.

- Ther RTL folder contains the top module, the rom fetcher that substitutes the SPI fetcher and some modified RTL files from the original implementation (core.v), the rest of the RTL files from the [src](../src/) must be added to the project.

- The constraints folder contains physical pin assignments definition that usually are made using the Gowin's EDA Floor Planner.

- The firmware folder contains assembly or C code (or both) used particularly for the given test, this is an independent folder, you must compile and get the hex file (a Makefile is provided for each version) and place the result within the project files

Observe that the RTL and constraints files vary from folder to folder so stick to each version every time.

Observe that the rom fetcher has this block of code:

```verilog
    initial begin
        $readmemh("firmware.hex", rom);
    end
```

So, the .hex file for the firmware you want to run must exists in the project's root directory

<img src="../img/gowin.jpg" width=800 />

Run the entire process, if it succeeds you're ready to upload the file into the FGPA, use the following command:

```bash
openFPGALoader -b tangnano20k /mnt/c/Gowin/Gowin_V1.9.12.02_SP2_x64/IDE/bin/Documents/rv-pony-first/impl/pnr/rv-pony-first.fs
```

Change of course the .fs file path to yours.

Observe that the provided command loads the created bitstream into a volatile memory, you can test but changes get lost if you disconnect the FPGA.

TODO: Test with SPI
TODO: Test flash bitstream upload