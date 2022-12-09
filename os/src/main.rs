#![no_std]
#![no_main]
#![feature(panic_info_message)]

use core::arch::global_asm;

pub mod batch;
#[macro_use]
mod console;
mod lang_items;
mod sbi;
mod sync;
mod syscall;
mod trap;

#[cfg(feature = "board_qemu")]
#[path = "boards/qemu.rs"]
mod board;

global_asm!(include_str!("entry.asm"));
global_asm!(include_str!("link_app.S"));

/// clear BSS segment
pub fn clear_bss() {
    extern "C" {
        fn sbss();
        fn ebss();
    }
    (sbss as usize..ebss as usize).for_each(|a| unsafe { (a as *mut u8).write_volatile(0) });
}

/// the rust entry-point of os
#[no_mangle]
pub fn main() -> ! {
    clear_bss();
    println!("[kernel] Hello, world!");
    trap::init();
    batch::init();
    batch::run_next_app();
}
