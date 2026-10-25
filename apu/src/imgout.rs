//! Dependency-free image output: an animated GIF encoder (LZW) and a minimal
//! PNG writer (uncompressed deflate). Enough to record what the console shows.

use std::io::{self, Write};

pub struct GifWriter<W: Write> {
    out: W,
    width: u16,
    height: u16,
}

impl<W: Write> GifWriter<W> {
    pub fn new(mut out: W, width: u16, height: u16) -> io::Result<Self> {
        out.write_all(b"GIF89a")?;
        out.write_all(&width.to_le_bytes())?;
        out.write_all(&height.to_le_bytes())?;
        out.write_all(&[0x00, 0, 0])?; // no global colour table
        // NETSCAPE2.0 extension: loop forever
        out.write_all(&[0x21, 0xFF, 0x0B])?;
        out.write_all(b"NETSCAPE2.0")?;
        out.write_all(&[0x03, 0x01, 0x00, 0x00, 0x00])?;
        Ok(GifWriter { out, width, height })
    }

    /// `pixels` are palette indices; `palette` is 256 RGB colours (0x00RRGGBB).
    /// `delay` is in hundredths of a second.
    pub fn frame(&mut self, pixels: &[u8], palette: &[u32; 256], delay: u16) -> io::Result<()> {
        let o = &mut self.out;
        o.write_all(&[0x21, 0xF9, 0x04, 0x00])?; // graphic control, no transparency
        o.write_all(&delay.to_le_bytes())?;
        o.write_all(&[0x00, 0x00])?;
        o.write_all(&[0x2C, 0, 0, 0, 0])?; // image descriptor at 0,0
        o.write_all(&self.width.to_le_bytes())?;
        o.write_all(&self.height.to_le_bytes())?;
        o.write_all(&[0x87])?; // local colour table, 256 entries
        for c in palette {
            o.write_all(&[(c >> 16) as u8, (c >> 8) as u8, *c as u8])?;
        }
        o.write_all(&[8])?; // LZW minimum code size
        let data = lzw_encode(pixels);
        for chunk in data.chunks(255) {
            o.write_all(&[chunk.len() as u8])?;
            o.write_all(chunk)?;
        }
        o.write_all(&[0])
    }

    pub fn finish(mut self) -> io::Result<()> {
        self.out.write_all(&[0x3B])?;
        self.out.flush()
    }
}

fn lzw_encode(pixels: &[u8]) -> Vec<u8> {
    const CLEAR: u16 = 256;
    const EOI: u16 = 257;
    let mut out = Vec::new();
    let mut acc: u32 = 0;
    let mut nbits = 0u32;
    let mut emit = |code: u16, width: u32, out: &mut Vec<u8>| {
        acc |= (code as u32) << nbits;
        nbits += width;
        while nbits >= 8 {
            out.push(acc as u8);
            acc >>= 8;
            nbits -= 8;
        }
    };
    // dictionary: (prefix code, next byte) -> code, as a dense table
    let mut dict = vec![0u16; 4096 * 256];
    let mut next_code = EOI + 1;
    let mut width = 9u32;
    emit(CLEAR, width, &mut out);
    let mut iter = pixels.iter();
    let Some(&first) = iter.next() else {
        emit(EOI, width, &mut out);
        return out;
    };
    let mut prefix = first as u16;
    for &p in iter {
        let key = prefix as usize * 256 + p as usize;
        let hit = dict[key];
        if hit != 0 {
            prefix = hit;
            continue;
        }
        emit(prefix, width, &mut out);
        if next_code < 4096 {
            dict[key] = next_code;
            next_code += 1;
            if next_code > (1 << width) && width < 12 {
                width += 1;
            }
        } else {
            emit(CLEAR, width, &mut out);
            dict.fill(0);
            next_code = EOI + 1;
            width = 9;
        }
        prefix = p as u16;
    }
    emit(prefix, width, &mut out);
    emit(EOI, width, &mut out);
    if nbits > 0 {
        out.push(acc as u8);
    }
    out
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc = !0u32;
    for &b in data {
        crc ^= b as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 { (crc >> 1) ^ 0xEDB8_8320 } else { crc >> 1 };
        }
    }
    !crc
}

/// Write an 8-bit RGB PNG using stored (uncompressed) deflate blocks.
pub fn write_png(path: &str, width: usize, height: usize, rgb: &[u8]) -> io::Result<()> {
    let mut raw = Vec::with_capacity((width * 3 + 1) * height);
    for row in rgb.chunks(width * 3) {
        raw.push(0); // filter: none
        raw.extend_from_slice(row);
    }
    let mut z = vec![0x78, 0x01];
    let blocks: Vec<&[u8]> = raw.chunks(65535).collect();
    for (i, b) in blocks.iter().enumerate() {
        z.push((i + 1 == blocks.len()) as u8);
        let len = b.len() as u16;
        z.extend_from_slice(&len.to_le_bytes());
        z.extend_from_slice(&(!len).to_le_bytes());
        z.extend_from_slice(b);
    }
    let (mut a, mut b) = (1u32, 0u32);
    for &x in &raw {
        a = (a + x as u32) % 65521;
        b = (b + a) % 65521;
    }
    z.extend_from_slice(&((b << 16) | a).to_be_bytes());

    let mut f = io::BufWriter::new(std::fs::File::create(path)?);
    f.write_all(b"\x89PNG\r\n\x1a\n")?;
    let mut chunk = |kind: &[u8], data: &[u8]| -> io::Result<()> {
        f.write_all(&(data.len() as u32).to_be_bytes())?;
        let mut c = kind.to_vec();
        c.extend_from_slice(data);
        f.write_all(&c)?;
        f.write_all(&crc32(&c).to_be_bytes())
    };
    let mut ihdr = Vec::new();
    ihdr.extend_from_slice(&(width as u32).to_be_bytes());
    ihdr.extend_from_slice(&(height as u32).to_be_bytes());
    ihdr.extend_from_slice(&[8, 2, 0, 0, 0]);
    chunk(b"IHDR", &ihdr)?;
    chunk(b"IDAT", &z)?;
    chunk(b"IEND", &[])?;
    f.flush()
}
