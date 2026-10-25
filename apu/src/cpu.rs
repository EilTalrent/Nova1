//! The NOVA-1 CPU core: a plain RV32IM interpreter.
//!
//! Base integer ISA plus the M extension (mul/div). No CSRs, no interrupts,
//! no privilege levels: the console is a single-tasking machine and talks to
//! its hardware purely through memory-mapped registers.

/// Everything the CPU can touch goes through the bus.
pub trait Bus {
    fn read8(&mut self, addr: u32) -> Result<u8, Trap>;
    fn read16(&mut self, addr: u32) -> Result<u16, Trap>;
    fn read32(&mut self, addr: u32) -> Result<u32, Trap>;
    fn write8(&mut self, addr: u32, v: u8) -> Result<(), Trap>;
    fn write16(&mut self, addr: u32, v: u16) -> Result<(), Trap>;
    fn write32(&mut self, addr: u32, v: u32) -> Result<(), Trap>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Trap {
    IllegalInstruction { pc: u32, raw: u32 },
    BusFault { addr: u32, write: bool },
    Ecall { pc: u32 },
    Ebreak { pc: u32 },
    /// The program asked the console to go to sleep until the next frame.
    VSync,
    /// The program asked the console to power off (exit code).
    Halt(u32),
}

pub struct Cpu {
    pub x: [u32; 32],
    pub pc: u32,
    pub retired: u64,
}

#[inline(always)]
fn sext(v: u32, bits: u32) -> u32 {
    let s = 32 - bits;
    (((v << s) as i32) >> s) as u32
}

impl Cpu {
    pub fn new(entry: u32, sp: u32) -> Self {
        let mut x = [0u32; 32];
        x[2] = sp;
        Cpu { x, pc: entry, retired: 0 }
    }

    #[inline(always)]
    fn set(&mut self, rd: usize, v: u32) {
        if rd != 0 {
            self.x[rd] = v;
        }
    }

    /// Execute one instruction. On a trap the PC is left pointing at the
    /// instruction *after* the one that trapped for VSync/Halt (they are
    /// "completed" stores), and at the faulting instruction otherwise.
    pub fn step<B: Bus>(&mut self, bus: &mut B) -> Result<(), Trap> {
        let pc = self.pc;
        if pc & 3 != 0 {
            return Err(Trap::BusFault { addr: pc, write: false });
        }
        let ins = bus.read32(pc)?;
        let opcode = ins & 0x7f;
        let rd = ((ins >> 7) & 31) as usize;
        let f3 = (ins >> 12) & 7;
        let rs1 = ((ins >> 15) & 31) as usize;
        let rs2 = ((ins >> 20) & 31) as usize;
        let f7 = ins >> 25;
        let a = self.x[rs1];
        let b = self.x[rs2];
        let imm_i = sext(ins >> 20, 12);
        let mut next = pc.wrapping_add(4);
        let illegal = Trap::IllegalInstruction { pc, raw: ins };

        match opcode {
            0x37 => self.set(rd, ins & 0xffff_f000), // LUI
            0x17 => self.set(rd, pc.wrapping_add(ins & 0xffff_f000)), // AUIPC
            0x6f => {
                // JAL
                let imm = ((ins >> 31) << 20)
                    | (((ins >> 12) & 0xff) << 12)
                    | (((ins >> 20) & 1) << 11)
                    | (((ins >> 21) & 0x3ff) << 1);
                self.set(rd, next);
                next = pc.wrapping_add(sext(imm, 21));
            }
            0x67 => {
                // JALR
                if f3 != 0 {
                    return Err(illegal);
                }
                let t = a.wrapping_add(imm_i) & !1;
                self.set(rd, next);
                next = t;
            }
            0x63 => {
                // Branches
                let imm = ((ins >> 31) << 12)
                    | (((ins >> 7) & 1) << 11)
                    | (((ins >> 25) & 0x3f) << 5)
                    | (((ins >> 8) & 0xf) << 1);
                let take = match f3 {
                    0 => a == b,
                    1 => a != b,
                    4 => (a as i32) < (b as i32),
                    5 => (a as i32) >= (b as i32),
                    6 => a < b,
                    7 => a >= b,
                    _ => return Err(illegal),
                };
                if take {
                    next = pc.wrapping_add(sext(imm, 13));
                }
            }
            0x03 => {
                // Loads
                let addr = a.wrapping_add(imm_i);
                let v = match f3 {
                    0 => sext(bus.read8(addr)? as u32, 8),
                    1 => sext(bus.read16(addr)? as u32, 16),
                    2 => bus.read32(addr)?,
                    4 => bus.read8(addr)? as u32,
                    5 => bus.read16(addr)? as u32,
                    _ => return Err(illegal),
                };
                self.set(rd, v);
            }
            0x23 => {
                // Stores
                let imm = sext(((ins >> 25) << 5) | ((ins >> 7) & 31), 12);
                let addr = a.wrapping_add(imm);
                let r = match f3 {
                    0 => bus.write8(addr, b as u8),
                    1 => bus.write16(addr, b as u16),
                    2 => bus.write32(addr, b),
                    _ => return Err(illegal),
                };
                if let Err(t) = r {
                    // VSync / Halt are side effects of a completed store.
                    if matches!(t, Trap::VSync | Trap::Halt(_)) {
                        self.pc = next;
                        self.retired += 1;
                    }
                    return Err(t);
                }
            }
            0x13 => {
                // ALU immediate
                let sh = (ins >> 20) & 31;
                let v = match f3 {
                    0 => a.wrapping_add(imm_i),
                    1 => {
                        if f7 != 0 {
                            return Err(illegal);
                        }
                        a << sh
                    }
                    2 => ((a as i32) < (imm_i as i32)) as u32,
                    3 => (a < imm_i) as u32,
                    4 => a ^ imm_i,
                    5 => match f7 {
                        0x00 => a >> sh,
                        0x20 => ((a as i32) >> sh) as u32,
                        _ => return Err(illegal),
                    },
                    6 => a | imm_i,
                    7 => a & imm_i,
                    _ => unreachable!(),
                };
                self.set(rd, v);
            }
            0x33 => {
                // ALU register, including the M extension (funct7 = 1)
                let v = match (f7, f3) {
                    (0x00, 0) => a.wrapping_add(b),
                    (0x20, 0) => a.wrapping_sub(b),
                    (0x00, 1) => a << (b & 31),
                    (0x00, 2) => ((a as i32) < (b as i32)) as u32,
                    (0x00, 3) => (a < b) as u32,
                    (0x00, 4) => a ^ b,
                    (0x00, 5) => a >> (b & 31),
                    (0x20, 5) => ((a as i32) >> (b & 31)) as u32,
                    (0x00, 6) => a | b,
                    (0x00, 7) => a & b,
                    // M extension
                    (0x01, 0) => a.wrapping_mul(b),
                    (0x01, 1) => (((a as i32 as i64) * (b as i32 as i64)) >> 32) as u32,
                    (0x01, 2) => (((a as i32 as i64) * (b as u64 as i64)) >> 32) as u32,
                    (0x01, 3) => (((a as u64) * (b as u64)) >> 32) as u32,
                    (0x01, 4) => {
                        let (a, b) = (a as i32, b as i32);
                        if b == 0 {
                            u32::MAX
                        } else {
                            a.wrapping_div(b) as u32
                        }
                    }
                    (0x01, 5) => {
                        if b == 0 {
                            u32::MAX
                        } else {
                            a / b
                        }
                    }
                    (0x01, 6) => {
                        let (a, b) = (a as i32, b as i32);
                        if b == 0 {
                            a as u32
                        } else {
                            a.wrapping_rem(b) as u32
                        }
                    }
                    (0x01, 7) => {
                        if b == 0 {
                            a
                        } else {
                            a % b
                        }
                    }
                    _ => return Err(illegal),
                };
                self.set(rd, v);
            }
            0x0f => {} // FENCE / FENCE.I: memory is always coherent here
            0x73 => {
                return Err(match ins {
                    0x0000_0073 => Trap::Ecall { pc },
                    0x0010_0073 => Trap::Ebreak { pc },
                    _ => illegal,
                })
            }
            _ => return Err(illegal),
        }
        self.pc = next;
        self.retired += 1;
        Ok(())
    }
}
