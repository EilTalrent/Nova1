//! NOVA-1 windowed frontend.
//!
//!   cargo run --release -- ../roms/starfall/starfall.n1
//!
//! Controls: arrows = d-pad, Z = A, X = B, Enter = Start, Esc = power off.

use minifb::{Key, Scale, Window, WindowOptions};
use nova1::apu::{buttons::*, Apu, FrameResult};
use nova1::gpu;

fn main() {
    let path = std::env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: nova1-window <rom.n1>");
        std::process::exit(2);
    });
    let rom = std::fs::read(&path).expect("cannot read ROM");
    let mut apu = Apu::new(rom).unwrap_or_else(|e| {
        eprintln!("{path}: {e}");
        std::process::exit(2);
    });

    let mut win = Window::new(
        &format!("NOVA-1  —  {}", apu.header.title),
        gpu::WIDTH,
        gpu::HEIGHT,
        WindowOptions { scale: Scale::X4, ..WindowOptions::default() },
    )
    .expect("cannot open window");
    win.set_target_fps(60);

    let keymap = [
        (Key::Up, UP),
        (Key::Down, DOWN),
        (Key::Left, LEFT),
        (Key::Right, RIGHT),
        (Key::Z, A),
        (Key::X, B),
        (Key::Enter, START),
    ];

    while win.is_open() && !win.is_key_down(Key::Escape) {
        let pressed = keymap
            .iter()
            .filter(|(k, _)| win.is_key_down(*k))
            .fold(0, |acc, (_, bit)| acc | bit);
        let result = apu.run_frame(pressed);
        print!("{}", apu.take_debug_output());
        win.update_with_buffer(&apu.mem.gpu.frame_rgb(), gpu::WIDTH, gpu::HEIGHT)
            .expect("window update");
        match result {
            FrameResult::Ok | FrameResult::Lagged => {}
            FrameResult::Halted(code) => {
                println!("cartridge powered off (code {code})");
                break;
            }
            FrameResult::Crashed(trap) => {
                eprintln!("CPU crash at pc={:#010x}: {trap:?}", apu.cpu.pc);
                // keep the last frame (the crash screen) on display
                while win.is_open() && !win.is_key_down(Key::Escape) {
                    win.update();
                }
                break;
            }
        }
    }
}
