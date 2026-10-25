//! The NOVA-1 APU: CPU + PRISM GPU + system controller on one bus.
//!
//! Memory map
//! ```text
//!   0x0000_0000  ROM     cartridge, up to 1 MiB, read-only
//!   0x1000_0000  RAM     256 KiB work RAM (stack grows down from the top)
//!   0x2000_0000  PRISM   GPU registers, palette, OAM, raster tables, maps, tiles
//!   0x3000_0000  SYS     vsync, frame counter, buttons, debug port, RNG, halt
//! ```

use crate::cpu::{Bus, Cpu, Trap};
use crate::gpu::{self, Gpu};

pub const ROM_BASE: u32 = 0x0000_0000;
pub const ROM_SIZE: usize = 1 << 20;
pub const RAM_BASE: u32 = 0x1000_0000;
pub const RAM_SIZE: usize = 256 * 1024;
pub const GPU_BASE: u32 = 0x2000_0000;
pub const SYS_BASE: u32 = 0x3000_0000;

/// Instruction budget per video frame: a "60 MHz" CPU at one instruction per cycle.
pub const CYCLES_PER_FRAME: u64 = 1_000_000;

pub mod sys {
    pub const VSYNC: u32 = 0x00; // W: sleep until next frame
    pub const FRAME: u32 = 0x04; // R: frame counter
    pub const BUTTONS: u32 = 0x08; // R: button bitmask
    pub const DEBUG_PUTC: u32 = 0x0C; // W: write a byte to the debug console
    pub const HALT: u32 = 0x10; // W: power off with exit code
    pub const RANDOM: u32 = 0x14; // R: hardware random number
    pub const LAST_CYCLES: u32 = 0x18; // R: instructions used by the previous frame
}

pub mod buttons {
    pub const UP: u32 = 1 << 0;
    pub const DOWN: u32 = 1 << 1;
    pub const LEFT: u32 = 1 << 2;
    pub const RIGHT: u32 = 1 << 3;
    pub const A: u32 = 1 << 4;
    pub const B: u32 = 1 << 5;
    pub const START: u32 = 1 << 6;
}

pub struct CartHeader {
    pub entry: u32,
    pub title: String,
}

pub fn parse_header(rom: &[u8]) -> Result<CartHeader, String> {
    if rom.len() < 32 || &rom[0..4] != b"NOVA" {
        return Err("not a NOVA-1 cartridge (missing 'NOVA' magic)".into());
    }
    let entry = u32::from_le_bytes(rom[4..8].try_into().unwrap());
    let title: String = rom[8..32]
        .iter()
        .take_while(|&&c| c != 0)
        .map(|&c| c as char)
        .collect();
    Ok(CartHeader { entry, title })
}

pub struct Memory {
    pub rom: Vec<u8>,
    pub ram: Vec<u8>,
    pub gpu: Gpu,
    pub frame: u32,
    pub buttons: u32,
    pub last_cycles: u32,
    pub debug_out: Vec<u8>,
    rng: u32,
}

enum Region {
    Rom(usize),
    Ram(usize),
    Gpu(usize),
    Sys(u32),
}

impl Memory {
    fn decode(&self, addr: u32, len: u32) -> Option<Region> {
        let end = addr.checked_add(len - 1)?;
        match addr >> 28 {
            0x0 if (end as usize) < self.rom.len() => Some(Region::Rom(addr as usize)),
            0x1 if ((end - RAM_BASE) as usize) < RAM_SIZE => {
                Some(Region::Ram((addr - RAM_BASE) as usize))
            }
            0x2 if ((end - GPU_BASE) as usize) < gpu::GPU_SPACE => {
                Some(Region::Gpu((addr - GPU_BASE) as usize))
            }
            0x3 if end - SYS_BASE < 0x100 => Some(Region::Sys(addr - SYS_BASE)),
            _ => None,
        }
    }

    fn next_random(&mut self) -> u32 {
        // xorshift32
        let mut x = self.rng;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.rng = x;
        x
    }

    fn sys_read(&mut self, reg: u32) -> u32 {
        match reg {
            sys::FRAME => self.frame,
            sys::BUTTONS => self.buttons,
            sys::RANDOM => self.next_random(),
            sys::LAST_CYCLES => self.last_cycles,
            _ => 0,
        }
    }

    fn sys_write(&mut self, reg: u32, v: u32) -> Result<(), Trap> {
        match reg {
            sys::VSYNC => Err(Trap::VSync),
            sys::DEBUG_PUTC => {
                self.debug_out.push(v as u8);
                Ok(())
            }
            sys::HALT => Err(Trap::Halt(v)),
            _ => Ok(()),
        }
    }

    fn read_n(&mut self, addr: u32, n: u32) -> Result<u32, Trap> {
        let fault = Trap::BusFault { addr, write: false };
        let bytes: &[u8] = match self.decode(addr, n).ok_or(fault)? {
            Region::Rom(o) => &self.rom[o..o + n as usize],
            Region::Ram(o) => &self.ram[o..o + n as usize],
            Region::Gpu(o) => &self.gpu.mem[o..o + n as usize],
            Region::Sys(r) => return Ok(self.sys_read(r)),
        };
        let mut v = 0u32;
        for (i, b) in bytes.iter().enumerate() {
            v |= (*b as u32) << (8 * i);
        }
        Ok(v)
    }

    fn write_n(&mut self, addr: u32, n: u32, v: u32) -> Result<(), Trap> {
        let fault = Trap::BusFault { addr, write: true };
        let dst: &mut [u8] = match self.decode(addr, n).ok_or(fault)? {
            Region::Rom(_) => return Err(fault), // cartridge ROM is read-only
            Region::Ram(o) => &mut self.ram[o..o + n as usize],
            Region::Gpu(o) => &mut self.gpu.mem[o..o + n as usize],
            Region::Sys(r) => return self.sys_write(r, v),
        };
        for (i, b) in dst.iter_mut().enumerate() {
            *b = (v >> (8 * i)) as u8;
        }
        Ok(())
    }
}

impl Bus for Memory {
    fn read8(&mut self, a: u32) -> Result<u8, Trap> {
        self.read_n(a, 1).map(|v| v as u8)
    }
    fn read16(&mut self, a: u32) -> Result<u16, Trap> {
        self.read_n(a, 2).map(|v| v as u16)
    }
    fn read32(&mut self, a: u32) -> Result<u32, Trap> {
        // Fast path for instruction fetch from ROM.
        if a < self.rom.len() as u32 - 3 {
            let o = a as usize;
            return Ok(u32::from_le_bytes(self.rom[o..o + 4].try_into().unwrap()));
        }
        self.read_n(a, 4)
    }
    fn write8(&mut self, a: u32, v: u8) -> Result<(), Trap> {
        self.write_n(a, 1, v as u32)
    }
    fn write16(&mut self, a: u32, v: u16) -> Result<(), Trap> {
        self.write_n(a, 2, v as u32)
    }
    fn write32(&mut self, a: u32, v: u32) -> Result<(), Trap> {
        self.write_n(a, 4, v)
    }
}

pub enum FrameResult {
    /// Frame finished normally (the program waited for vsync).
    Ok,
    /// The program used its whole cycle budget without waiting for vsync.
    Lagged,
    /// The machine powered off with an exit code.
    Halted(u32),
    /// The CPU hit a fatal trap.
    Crashed(Trap),
}

pub struct Apu {
    pub cpu: Cpu,
    pub mem: Memory,
    pub header: CartHeader,
}

impl Apu {
    pub fn new(rom_image: Vec<u8>) -> Result<Self, String> {
        if rom_image.len() > ROM_SIZE {
            return Err(format!("ROM is {} bytes; the cartridge slot holds 1 MiB", rom_image.len()));
        }
        let header = parse_header(&rom_image)?;
        let mut rom = rom_image;
        // Pad so instruction fetch near the end never reads out of bounds.
        rom.resize(rom.len().max(64) + 4, 0);
        let mem = Memory {
            rom,
            ram: vec![0; RAM_SIZE],
            gpu: Gpu::power_on(),
            frame: 0,
            buttons: 0,
            last_cycles: 0,
            debug_out: Vec::new(),
            rng: 0x2545_F491,
        };
        let cpu = Cpu::new(header.entry, RAM_BASE + RAM_SIZE as u32);
        Ok(Apu { cpu, mem, header })
    }

    /// Run the CPU until it waits for vsync (or runs out of budget), then
    /// let PRISM draw the frame.
    pub fn run_frame(&mut self, buttons: u32) -> FrameResult {
        self.mem.buttons = buttons;
        let start = self.cpu.retired;
        let mut result = FrameResult::Lagged;
        while self.cpu.retired - start < CYCLES_PER_FRAME {
            match self.cpu.step(&mut self.mem) {
                Ok(()) => {}
                Err(Trap::VSync) => {
                    result = FrameResult::Ok;
                    break;
                }
                Err(Trap::Halt(code)) => {
                    result = FrameResult::Halted(code);
                    break;
                }
                Err(t) => {
                    result = FrameResult::Crashed(t);
                    break;
                }
            }
        }
        self.mem.last_cycles = (self.cpu.retired - start) as u32;
        self.mem.gpu.render();
        self.mem.frame = self.mem.frame.wrapping_add(1);
        result
    }

    pub fn take_debug_output(&mut self) -> String {
        let s = String::from_utf8_lossy(&self.mem.debug_out).into_owned();
        self.mem.debug_out.clear();
        s
    }
}
