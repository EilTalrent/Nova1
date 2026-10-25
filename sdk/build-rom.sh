#!/bin/sh
# Build a NOVA-1 cartridge from an Ada main procedure.
#
#   sdk/build-rom.sh roms/starfall/starfall.adb "STARFALL" roms/starfall/starfall.n1
#
# Needs a GNAT RISC-V cross compiler (riscv64-elf-gnatmake etc.) on PATH;
# `alr toolchain` or the gnat_riscv64_elf crate from Alire provides one.
set -e

if [ $# -ne 3 ]; then
    echo "usage: $0 <main.adb> <TITLE> <out.n1>" >&2
    exit 2
fi

SDK=$(cd "$(dirname "$0")" && pwd)
MAIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TITLE=$2
OUT=$(cd "$(dirname "$3")" && pwd)/$(basename "$3")
SRC_DIR=$(dirname "$MAIN")
NAME=$(basename "$MAIN" .adb)
BUILD=$SRC_DIR/build
CROSS=${CROSS:-riscv64-elf-}
ARCH="-march=rv32im -mabi=ilp32"

mkdir -p "$BUILD"
cd "$BUILD"

# 1. Runtime (System, Ada, Interfaces, System.Storage_Elements), compiled once
if [ ! -f "$SDK/rts/adalib/s-assert.ali" ]; then
    (cd "$SDK/rts/adalib" && for u in system.ads ada.ads interfac.ads s-stoele.adb s-assert.adb; do
        ${CROSS}gcc $ARCH -O2 -gnatpg -gnatyN --RTS="$SDK/rts" -c "../adainclude/$u"
    done
    chmod a-w ./*.ali)
fi

# 2. Startup code and memory routines
${CROSS}gcc $ARCH -x assembler-with-cpp -DCART_TITLE="\"$TITLE\"" \
    -c "$SDK/startup/crt0.S" -o crt0.o
${CROSS}gcc $ARCH -O2 -fno-builtin -fno-tree-loop-distribute-patterns \
    -c "$SDK/startup/mem.c" -o mem.o

# 3. The game and the Nova SDK. -gnata turns contracts (Pre/Post) into
#    run-time checks; failed checks land on the crash screen.
${CROSS}gnatmake --RTS="$SDK/rts" -q -c -aI"$SDK/nova" -aI"$SRC_DIR" "$MAIN" \
    -cargs $ARCH -O2 -gnatn -gnat2022 -gnata -gnatwa.X \
           -ffunction-sections -fdata-sections

# 4. Binder: generates main(), which elaborates packages and calls the game
${CROSS}gnatbind --RTS="$SDK/rts" -aI"$SDK/nova" -aI"$SRC_DIR" "$NAME.ali"
${CROSS}gcc $ARCH -O2 --RTS="$SDK/rts" -c "b~$NAME.adb" -o "b~$NAME.o"

# 5. Link against the cartridge memory map and flatten to a ROM image
OBJS=$(ls *.o | grep -v -e '^crt0.o$')
${CROSS}gcc $ARCH -nostdlib -nostartfiles -T "$SDK/startup/nova1.ld" \
    -Wl,--gc-sections -Wl,-Map="$NAME.map" \
    crt0.o $OBJS "$SDK"/rts/adalib/*.o -lgcc -o "$NAME.elf"
${CROSS}objcopy -O binary "$NAME.elf" "$OUT"

SIZE=$(wc -c < "$OUT")
echo "built $OUT ($SIZE bytes)"
