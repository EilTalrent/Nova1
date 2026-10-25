//! NOVA-1 fantasy console emulator.
//!
//! Headless:  nova1 rom.n1 --frames 600 --gif out.gif [--snap 300:shot.png]
//!            [--input 100-160:right+a]   (scripted button presses)
//! Windowed:  see ../window (needs the minifb crate)

use nova1::{apu, gpu, imgout};

use apu::{Apu, FrameResult};
use std::io::Write;
use std::process::ExitCode;

struct Options {
    rom: String,
    frames: u32,
    gif: Option<String>,
    gif_every: u32,
    scale: usize,
    snaps: Vec<(u32, String)>,
    inputs: Vec<(u32, u32, u32)>, // first frame, last frame, buttons
}

fn parse_buttons(s: &str) -> u32 {
    use apu::buttons::*;
    s.split('+')
        .map(|b| match b {
            "up" => UP,
            "down" => DOWN,
            "left" => LEFT,
            "right" => RIGHT,
            "a" => A,
            "b" => B,
            "start" => START,
            _ => usage(),
        })
        .fold(0, |acc, b| acc | b)
}

fn usage() -> ! {
    eprintln!(
        "usage: nova1 <rom.n1> [--frames N] [--gif out.gif] [--gif-every K] [--scale S]\n\
         \x20                     [--snap FRAME:file.png]... [--input FIRST-LAST:right+a]...\n\
         buttons: up down left right a b start"
    );
    std::process::exit(2);
}

fn parse_args() -> Options {
    let mut args = std::env::args().skip(1);
    let mut o = Options {
        rom: String::new(),
        frames: 600,
        gif: None,
        gif_every: 2,
        scale: 2,
        snaps: Vec::new(),
        inputs: Vec::new(),
    };
    while let Some(a) = args.next() {
        let mut val = || args.next().unwrap_or_else(|| usage());
        match a.as_str() {
            "--frames" => o.frames = val().parse().unwrap_or_else(|_| usage()),
            "--gif" => {
                o.gif = Some(val());
            }
            "--gif-every" => o.gif_every = val().parse::<u32>().unwrap_or_else(|_| usage()).max(1),
            "--scale" => o.scale = val().parse::<usize>().unwrap_or_else(|_| usage()).clamp(1, 8),
            "--snap" => {
                let v = val();
                let (f, p) = v.split_once(':').unwrap_or_else(|| usage());
                o.snaps.push((f.parse().unwrap_or_else(|_| usage()), p.to_string()));
            }
            "--input" => {
                let v = val();
                let (range, btns) = v.split_once(':').unwrap_or_else(|| usage());
                let (a, b) = range.split_once('-').unwrap_or((range, range));
                let first = a.parse().unwrap_or_else(|_| usage());
                let last = b.parse().unwrap_or_else(|_| usage());
                o.inputs.push((first, last, parse_buttons(btns)));
            }
            "-h" | "--help" => usage(),
            _ if o.rom.is_empty() && !a.starts_with("--") => o.rom = a,
            _ => usage(),
        }
    }
    if o.rom.is_empty() {
        usage();
    }
    o
}

fn report(apu: &mut Apu, r: &FrameResult) -> Option<ExitCode> {
    let out = apu.take_debug_output();
    if !out.is_empty() {
        print!("{out}");
        let _ = std::io::stdout().flush();
    }
    match r {
        FrameResult::Ok | FrameResult::Lagged => None,
        FrameResult::Halted(code) => {
            println!("[nova1] cartridge powered off (code {code}) after frame {}", apu.mem.frame);
            Some(if *code == 0 { ExitCode::SUCCESS } else { ExitCode::from(1) })
        }
        FrameResult::Crashed(t) => {
            eprintln!("[nova1] CPU crash at pc={:#010x}: {t:?}", apu.cpu.pc);
            for (i, r) in apu.cpu.x.iter().enumerate() {
                eprint!("x{i:<2}={r:08x}{}", if i % 4 == 3 { "\n" } else { "  " });
            }
            Some(ExitCode::from(1))
        }
    }
}

fn write_png(path: &str, apu: &Apu, scale: usize) -> std::io::Result<()> {
    let (w, h) = (gpu::WIDTH * scale, gpu::HEIGHT * scale);
    let rgb = apu.mem.gpu.frame_rgb();
    let mut data = Vec::with_capacity(w * h * 3);
    for y in 0..h {
        for x in 0..w {
            let c = rgb[(y / scale) * gpu::WIDTH + x / scale];
            data.extend_from_slice(&[(c >> 16) as u8, (c >> 8) as u8, c as u8]);
        }
    }
    imgout::write_png(path, w, h, &data)
}

fn run_headless(o: &Options, mut apu: Apu) -> ExitCode {
    let (w, h) = (gpu::WIDTH * o.scale, gpu::HEIGHT * o.scale);
    let mut gif_enc = o.gif.as_ref().map(|path| {
        let f = std::fs::File::create(path).expect("cannot create gif");
        imgout::GifWriter::new(std::io::BufWriter::new(f), w as u16, h as u16).expect("gif header")
    });
    // 60 fps console, GIF delays are in 1/100 s.
    let delay = ((o.gif_every as f32 * 100.0 / 60.0).round() as u16).max(2);
    let mut code = ExitCode::SUCCESS;
    let mut lag = 0;
    for _ in 0..o.frames {
        let f = apu.mem.frame;
        let pressed = o
            .inputs
            .iter()
            .filter(|(a, b, _)| (*a..=*b).contains(&f))
            .fold(0, |acc, (_, _, m)| acc | m);
        let r = apu.run_frame(pressed);
        if matches!(r, FrameResult::Lagged) {
            lag += 1;
        }
        let frame_no = apu.mem.frame - 1;
        if let Some(enc) = gif_enc.as_mut() {
            if frame_no % o.gif_every == 0 {
                let g = &apu.mem.gpu;
                let mut pixels = Vec::with_capacity(w * h);
                for y in 0..h {
                    let row = &g.frame[(y / o.scale) * gpu::WIDTH..][..gpu::WIDTH];
                    for x in 0..w {
                        pixels.push(row[x / o.scale]);
                    }
                }
                enc.frame(&pixels, &g.frame_palette, delay).expect("gif frame");
            }
        }
        for (at, path) in &o.snaps {
            if *at == frame_no {
                write_png(path, &apu, o.scale).expect("png");
            }
        }
        if let Some(c) = report(&mut apu, &r) {
            code = c;
            break;
        }
    }
    if let Some(enc) = gif_enc {
        enc.finish().expect("gif trailer");
    }
    println!(
        "[nova1] ran {} frames, {} instructions, {} lagged frames",
        apu.mem.frame, apu.cpu.retired, lag
    );
    code
}

fn main() -> ExitCode {
    let o = parse_args();
    let rom = match std::fs::read(&o.rom) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("cannot read {}: {e}", o.rom);
            return ExitCode::from(2);
        }
    };
    let apu = match Apu::new(rom) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("{}: {e}", o.rom);
            return ExitCode::from(2);
        }
    };
    println!(
        "[nova1] NOVA-1 APU  |  cartridge: \"{}\"  entry {:#x}",
        apu.header.title, apu.header.entry
    );
    run_headless(&o, apu)
}
