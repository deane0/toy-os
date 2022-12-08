#![allow(unused)]

use core::arch::asm;

const SBI_CONSOLE_PUT_CHAR: usize = 1;
const SBI_CONSOLE_GET_CHAR: usize = 2;
const SBI_SHUTDOWN: usize = 8;

#[inline(always)]
fn sbi_call(which: usize, arg0: usize, arg1: usize, arg2: usize) -> usize {
    let mut ret;
    unsafe {
        asm!("li x16, 0",
            "ecall",
            inlateout("x10") arg0 => ret,
            in("x11") arg1 ,
            in("x12") arg2 ,
            in("x17") which ,
        );
    }
    ret
}

/// use sbi call to put char in console (qemu uart handler)
pub fn console_put_char(c: usize) {
    sbi_call(SBI_CONSOLE_PUT_CHAR, c, 0, 0);
}

/// use sbi call to get char from console (qemu uart handler)
pub fn console_get_char() -> usize {
    sbi_call(SBI_CONSOLE_GET_CHAR, 0, 0, 0)
}

#[cfg(feature = "board_qemu")]
use crate::board::QEMUExit;
/// use sbi call to shutdown the kernel
pub fn shutdown() -> ! {
    #[cfg(feature = "board_k210")]
    sbi_call(SBI_SHUTDOWN, 0, 0, 0);

    #[cfg(feature = "board_qemu")]
    crate::board::QEMU_EXIT_HANDLE.exit_failure();

    panic!("It should shutdown!");
}
