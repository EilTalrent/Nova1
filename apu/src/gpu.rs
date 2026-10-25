//! PRISM: the NOVA-1 graphics unit.
//!
//! 256x192 pixels, 256-colour palette (24-bit RGB), 8bpp 8x8 tiles.
//!
//! * Two scrolling tile layers (BG0 behind, BG1 in front), 32x32-tile maps that wrap.
//! * 64 hardware sprites, 8/16/32/64 px square, flip, palette bank, and a
//!   "behind BG0" priority bit.
//! * Raster tables, the console's party trick: a per-scanline horizontal
//!   offset for BG0 (waves, heat haze, water) and a per-scanline backdrop
//!   colour (sky gradients without spending a single tile).
//! * A sprite window: sprites with the "windowed" bit are only drawn between
//!   two scanlines, e.g. to let a sun set behind the horizon.
//! * A master brightness register for fades.
//!
//! Colour index 0 is transparent in every tile, sprite and layer. A palette
//! bank adds `bank * 16` to every non-transparent pixel, so one set of tiles
//! can be drawn in 16 colourways.
//!
//! Register map (offsets from 0x2000_0000)
//! ```text
//!   0x0000 CTRL         bit0 BG0, bit1 BG1, bit2 sprites, bit3 line-scroll, bit4 line-backdrop
//!   0x0004 BG0_SCROLL_X  i32     0x0008 BG0_SCROLL_Y  i32
//!   0x000C BG1_SCROLL_X  i32     0x0010 BG1_SCROLL_Y  i32
//!   0x0014 BACKDROP      colour index used when line-backdrop is off
//!   0x0018 BRIGHTNESS    0 (black) .. 256 (full)
//!   0x001C WINDOW_TOP    first scanline of the sprite window
//!   0x0020 WINDOW_BOTTOM scanline just past the sprite window
//!   0x1000 PALETTE       256 x u32 0x00RRGGBB
//!   0x2000 OAM           64 x { x:i16, y:i16, tile:u16, attr:u16 }
//!   0x3000 LINE_SCROLL   192 x i16
//!   0x3200 LINE_BACKDROP 192 x u8
//!   0x4000 BG0_MAP       32x32 x u16 { tile:10, flip_h:1, flip_v:1, bank:4 }
//!   0x4800 BG1_MAP       32x32 x u16
//!   0x10000 TILES        1024 x 64 bytes   (tiles 0..127 hold the built-in font at power-on)
//! ```
//! Sprite attr: bit0 enable, bit1 flip_h, bit2 flip_v, bits3-4 size (8/16/32/64),
//! bit5 behind BG0, bit6 windowed, bits8-11 palette bank. Big sprites use consecutive tiles in
//! row-major order.

pub const WIDTH: usize = 256;
pub const HEIGHT: usize = 192;
pub const GPU_SPACE: usize = 0x2_0000;

pub const REG_CTRL: usize = 0x0000;
pub const REG_BG0_SX: usize = 0x0004;
pub const REG_BG0_SY: usize = 0x0008;
pub const REG_BG1_SX: usize = 0x000C;
pub const REG_BG1_SY: usize = 0x0010;
pub const REG_BACKDROP: usize = 0x0014;
pub const REG_BRIGHTNESS: usize = 0x0018;
pub const REG_WINDOW_TOP: usize = 0x001C;
pub const REG_WINDOW_BOTTOM: usize = 0x0020;
pub const PALETTE: usize = 0x1000;
pub const OAM: usize = 0x2000;
pub const LINE_SCROLL: usize = 0x3000;
pub const LINE_BACKDROP: usize = 0x3200;
pub const BG0_MAP: usize = 0x4000;
pub const BG1_MAP: usize = 0x4800;
pub const TILES: usize = 0x1_0000;
pub const NUM_SPRITES: usize = 64;
pub const NUM_TILES: usize = 1024;

const CTRL_BG0: u32 = 1 << 0;
const CTRL_BG1: u32 = 1 << 1;
const CTRL_SPRITES: u32 = 1 << 2;
const CTRL_LINE_SCROLL: u32 = 1 << 3;
const CTRL_LINE_BACKDROP: u32 = 1 << 4;

pub struct Gpu {
    /// The whole PRISM address space, exactly as the CPU sees it.
    pub mem: Vec<u8>,
    /// Last rendered frame as palette indices.
    pub frame: Vec<u8>,
    /// Palette for the last rendered frame, brightness already applied.
    pub frame_palette: [u32; 256],
}

impl Gpu {
    pub fn power_on() -> Self {
        let mut g = Gpu {
            mem: vec![0; GPU_SPACE],
            frame: vec![0; WIDTH * HEIGHT],
            frame_palette: [0; 256],
        };
        g.w32(REG_BRIGHTNESS, 256);
        g.w32(REG_WINDOW_BOTTOM, HEIGHT as u32);
        g.load_character_rom();
        g
    }

    /// The character ROM: ASCII 0..127 copied into tiles 0..127 at power-on,
    /// glyph pixels set to colour 1.
    fn load_character_rom(&mut self) {
        for (ch, glyph) in crate::font::character_rom().iter().enumerate() {
            self.mem[TILES + ch * 64..TILES + ch * 64 + 64].copy_from_slice(glyph);
        }
    }

    #[inline]
    fn r16(&self, o: usize) -> u16 {
        u16::from_le_bytes([self.mem[o], self.mem[o + 1]])
    }
    #[inline]
    fn r32(&self, o: usize) -> u32 {
        u32::from_le_bytes(self.mem[o..o + 4].try_into().unwrap())
    }
    fn w32(&mut self, o: usize, v: u32) {
        self.mem[o..o + 4].copy_from_slice(&v.to_le_bytes());
    }

    #[inline]
    fn tile_pixel(&self, tile: usize, x: usize, y: usize) -> u8 {
        self.mem[TILES + (tile % NUM_TILES) * 64 + y * 8 + x]
    }

    fn draw_bg(&self, line: &mut [u8; WIDTH], map: usize, sx: i32, sy: i32, y: usize, row_off: i32) {
        let wy = ((y as i32 + sy).rem_euclid(256)) as usize;
        for (x, out) in line.iter_mut().enumerate() {
            let wx = ((x as i32 + sx + row_off).rem_euclid(256)) as usize;
            let e = self.r16(map + ((wy / 8) * 32 + wx / 8) * 2);
            let tile = (e & 0x3ff) as usize;
            let mut px = wx % 8;
            let mut py = wy % 8;
            if e & (1 << 10) != 0 {
                px = 7 - px;
            }
            if e & (1 << 11) != 0 {
                py = 7 - py;
            }
            let c = self.tile_pixel(tile, px, py);
            if c != 0 {
                *out = c.wrapping_add(((e >> 12) as u8) * 16);
            }
        }
    }

    fn draw_sprites(&self, line: &mut [u8; WIDTH], y: usize, behind: bool) {
        let in_window = (self.r32(REG_WINDOW_TOP) as usize..self.r32(REG_WINDOW_BOTTOM) as usize)
            .contains(&y);
        // Lower sprite numbers are drawn on top, so paint from the back.
        for s in (0..NUM_SPRITES).rev() {
            let o = OAM + s * 8;
            let attr = self.r16(o + 6);
            if attr & 1 == 0 || ((attr >> 5) & 1 == 1) != behind {
                continue;
            }
            if attr & (1 << 6) != 0 && !in_window {
                continue;
            }
            let sx = self.r16(o) as i16 as i32;
            let sy = self.r16(o + 2) as i16 as i32;
            let size = 8i32 << ((attr >> 3) & 3);
            let dy = y as i32 - sy;
            if dy < 0 || dy >= size {
                continue;
            }
            let base = self.r16(o + 4) as usize;
            let bank = ((attr >> 8) & 15) as u8 * 16;
            let tiles_across = (size / 8) as usize;
            let ty = if attr & 4 != 0 { size - 1 - dy } else { dy } as usize;
            for dx in 0..size {
                let x = sx + dx;
                if !(0..WIDTH as i32).contains(&x) {
                    continue;
                }
                let tx = if attr & 2 != 0 { size - 1 - dx } else { dx } as usize;
                let tile = base + (ty / 8) * tiles_across + tx / 8;
                let c = self.tile_pixel(tile, tx % 8, ty % 8);
                if c != 0 {
                    line[x as usize] = c.wrapping_add(bank);
                }
            }
        }
    }

    pub fn render(&mut self) {
        let ctrl = self.r32(REG_CTRL);
        let bg0 = (self.r32(REG_BG0_SX) as i32, self.r32(REG_BG0_SY) as i32);
        let bg1 = (self.r32(REG_BG1_SX) as i32, self.r32(REG_BG1_SY) as i32);
        let backdrop = self.r32(REG_BACKDROP) as u8;
        let mut line = [0u8; WIDTH];
        for y in 0..HEIGHT {
            let bd = if ctrl & CTRL_LINE_BACKDROP != 0 {
                self.mem[LINE_BACKDROP + y]
            } else {
                backdrop
            };
            line.fill(bd);
            if ctrl & CTRL_SPRITES != 0 {
                self.draw_sprites(&mut line, y, true);
            }
            if ctrl & CTRL_BG0 != 0 {
                let off = if ctrl & CTRL_LINE_SCROLL != 0 {
                    self.r16(LINE_SCROLL + y * 2) as i16 as i32
                } else {
                    0
                };
                self.draw_bg(&mut line, BG0_MAP, bg0.0, bg0.1, y, off);
            }
            if ctrl & CTRL_SPRITES != 0 {
                self.draw_sprites(&mut line, y, false);
            }
            if ctrl & CTRL_BG1 != 0 {
                self.draw_bg(&mut line, BG1_MAP, bg1.0, bg1.1, y, 0);
            }
            self.frame[y * WIDTH..(y + 1) * WIDTH].copy_from_slice(&line);
        }
        let bright = self.r32(REG_BRIGHTNESS).min(256);
        for i in 0..256 {
            let c = self.r32(PALETTE + i * 4);
            let ch = |shift: u32| ((((c >> shift) & 0xff) * bright) >> 8) << shift;
            self.frame_palette[i] = ch(16) | ch(8) | ch(0);
        }
    }

    /// The last frame as 0x00RRGGBB pixels.
    pub fn frame_rgb(&self) -> Vec<u32> {
        self.frame.iter().map(|&i| self.frame_palette[i as usize]).collect()
    }
}
