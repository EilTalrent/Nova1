# NOVA-1: build the emulator and every cartridge.
#
#   make            emulator + ROMs
#   make run        record STARFALL to starfall.gif
#   make test       CPU torture test (host vs. emulator) + crash-screen check
#
# ROMs need the GNAT RISC-V cross compiler (riscv64-elf-gnatmake) on PATH.

EMU := apu/target/release/nova1

.PHONY: all emulator roms run test clean

all: emulator roms

emulator:
	cd apu && cargo build --release

roms:
	sdk/build-rom.sh roms/starfall/starfall.adb   "STARFALL"   roms/starfall/starfall.n1
	sdk/build-rom.sh roms/hello/hello.adb         "HELLO"      roms/hello/hello.n1
	sdk/build-rom.sh roms/crashtest/crashtest.adb "CRASH TEST" roms/crashtest/crashtest.n1

run: emulator
	$(EMU) roms/starfall/starfall.n1 --frames 720 --gif starfall.gif

test: emulator
	cd apu/tests/isa && \
	  riscv64-elf-gcc -march=rv32im -mabi=ilp32 -O2 -DNOVA -nostdlib -nostartfiles \
	    -ffreestanding -T ../../../sdk/startup/nova1.ld start.S isatest.c -lgcc -o isatest.elf && \
	  riscv64-elf-objcopy -O binary isatest.elf isatest.n1 && \
	  cc -O2 isatest.c -o host_isatest && ./host_isatest > host.txt && \
	  ../../target/release/nova1 isatest.n1 --frames 50 | grep -v '^\[nova1\]' > nova.txt && \
	  diff host.txt nova.txt && echo "ISA test: emulator matches host"
	! $(EMU) roms/crashtest/crashtest.n1 --frames 60 > /dev/null 2>&1 && echo "crash test: halted as expected"

clean:
	cd apu && cargo clean
	rm -rf roms/*/build apu/tests/isa/*.elf apu/tests/isa/*.n1 apu/tests/isa/host_isatest apu/tests/isa/*.txt
