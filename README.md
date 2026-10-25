# NOVA-1

A fantasy game console that never existed. The **APU** (CPU and GPU on one
chip) is emulated in **Rust**; its cartridges are written in **Ada**.

```
 ┌──────────── cartridge (Ada) ─────────────┐      ┌─────────── NOVA-1 APU (Rust) ───────────┐
 │ starfall.adb, scenery.adb, ship.adb ...  │      │  RV32IM CPU core      cpu.rs            │
 │ Nova SDK: typed registers, video, math   │ ───► │  PRISM GPU            gpu.rs            │
 │ zero-footprint Ada runtime + crt0        │ .n1  │  bus + system ctrl    apu.rs            │
 │ GNAT → RISC-V → flat ROM image           │      │  GIF / PNG output     imgout.rs         │
 └──────────────────────────────────────────┘      └─────────────────────────────────────────┘
```

The CPU runs the real RV32IM instruction set, so a stock GNAT cross compiler can
target it. Everything around the CPU is invented: the PRISM graphics unit, the
memory map, the cartridge format, the character ROM, the crash screen.

## Quick start

```sh
# Emulator (no dependencies)
cd apu && cargo build --release

# Record the demo cartridge to a GIF, or take PNG snapshots
./target/release/nova1 ../roms/starfall/starfall.n1 --frames 720 --gif starfall.gif
./target/release/nova1 ../roms/starfall/starfall.n1 --snap 300:shot.png

# Fly the ship from a script: frames 100-200 hold right + A (boost)
./target/release/nova1 ../roms/starfall/starfall.n1 --input 100-200:right+a --gif fly.gif

# Play it in a real window (pulls in the minifb crate)
cd ../window && cargo run --release -- ../roms/starfall/starfall.n1
```

Window controls: arrows = d-pad, **Z** = A (boost), **X** = B, **Enter** = Start,
**Esc** = power off. Leave the pad alone for two seconds and STARFALL flies itself.

The `.n1` ROMs are included prebuilt, so you only need the Ada toolchain to
change them.

## The hardware

| Address       | What                                                        |
|---------------|-------------------------------------------------------------|
| `0x0000_0000` | Cartridge ROM, up to 1 MiB, read-only                       |
| `0x1000_0000` | 256 KiB work RAM (stack at the top)                         |
| `0x2000_0000` | PRISM GPU: registers, palette, OAM, raster tables, maps, tiles |
| `0x3000_0000` | System: vsync, frame counter, buttons, debug port, RNG, halt |

**CPU:** RV32IM, 1,000,000 instructions per frame (a "60 MHz" part). Writing to
`VSYNC` ends the frame; burning the whole budget counts as a lagged frame.

**PRISM GPU:** 256x192, 256 colours from 24-bit RGB, 8bpp 8x8 tiles.
- Two scrolling tile layers (BG0, BG1) with 32x32 wrapping maps and per-tile flip and palette bank
- 64 sprites, 8 to 64 px, flip, palette bank, "behind BG0" priority
- **Raster tables:** per-scanline BG0 horizontal offset, and per-scanline backdrop colour
- **Sprite window:** sprites flagged *windowed* only draw between two scanlines
- Master brightness for fades
- Character ROM: an original 5x7 font preloaded into tiles 0..127

The full register map is in the doc comment at the top of `apu/src/gpu.rs`, and
as Ada declarations in `sdk/nova/nova-hardware.ads`.

**Cartridge format (`.n1`):** a flat binary. Bytes 0..3 are `NOVA`, 4..7 the entry
point, 8..31 the title, followed by code.

## Writing a cartridge in Ada

```ada
with Nova.Hardware; use Nova.Hardware;
with Nova.Console;  use Nova.Console;
with Nova.Video;    use Nova.Video;

procedure Hello is
begin
   Palette (0) := Make_RGB (16, 24, 64);
   Palette (Bank_Color (15, 1)) := Make_RGB (255, 220, 120);
   Clear (BG1);
   Put_Text (BG1, 10, 6, "HELLO FROM ADA!");
   Control := (BG1 => True, others => False);
   loop
      Wait_VSync;
   end loop;
end Hello;
```

```sh
sdk/build-rom.sh roms/hello/hello.adb "HELLO" roms/hello/hello.n1
```

The SDK:

- `Nova.Hardware` declares every register as a typed Ada object at its bus
  address. Representation clauses pin each bit field, so
  `OAM (3).Attr.Flip_H := True` sets exactly one bit of sprite 3.
- `Nova.Console`: `Wait_VSync`, `Is_Pressed`, `Random`, `Debug`, `CPU_Load_Percent`.
- `Nova.Video`: palette helpers, text, `Place_Sprite`.
- `Nova.Math`: `Fixed`, a real Ada fixed-point type (24.8 in one register), plus
  a modular `Angle` type with a sine table.
- `Nova.Crash`: when any Ada check fails (range, overflow, index, broken
  contract), the cartridge stops on a red **CARTRIDGE FAULT** screen naming the
  file and line, instead of corrupting memory. Try `roms/crashtest`.

### Toolchain

You need GNAT for `riscv64-elf` (it builds RV32 code with `-march=rv32im -mabi=ilp32`).
The easiest source is Alire's prebuilt GNAT FSF compilers: the
`gnat_riscv64_elf` crate, or the `gnat-riscv64-elf-*` archives on the
alire-project/GNAT-FSF-builds GitHub releases page. Put its `bin/` on `PATH`.
Built and tested with GNAT 16.1.0.

GNAT ships without a bare-metal runtime for this target, so `sdk/rts` is a
tiny zero-footprint one: `System`, `Interfaces`, `System.Storage_Elements`,
`System.Assertions`. That means no heap, no tasking and no exception
propagation; failed checks call the crash handler directly.

## Tests

```sh
make test
```

- `apu/tests/isa`: a C torture test of every RV32IM ALU, multiply, divide and
  load path over 400 operand pairs, compiled for both the host and NOVA-1. The
  outputs must be identical.
- `roms/crashtest`: an Ada range error must halt the machine on the crash screen.

## Layout

```
apu/        Rust emulator (library + headless CLI, zero dependencies)
window/     Rust windowed frontend (minifb)
sdk/        Ada SDK: runtime, startup code, linker script, Nova packages, build script
roms/       starfall (the demo), hello, crashtest
```

## Ideas for what's next

- A sound chip (a few wavetable voices with envelopes, mixed by the APU)
- Battery-backed save RAM on the cartridge
- A per-scanline BG1 table, or mid-frame palette changes (a full "copper")
- A WebAssembly build of `apu/` so cartridges run in a browser
- A real game in STARFALL: catch the falling stars before they hit the water
