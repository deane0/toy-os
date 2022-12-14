TARGET := riscv64gc-unknown-none-elf
MODE := release

OS_NAME := os

TARGET_DIR := target/$(TARGET)/$(MODE)

KERNEL_ELF := $(TARGET_DIR)/$(OS_NAME)
KERNEL_BIN := images/kernel/$(OS_NAME).bin
DISASM_TMP := target/$(TARGET)/$(MODE)/asm

APPS_DIR := user/src/bin
APP_IMAGES_DIR := images/user

APPS := $(wildcard $(APPS_DIR)/*.rs)
APP_ELFS := $(patsubst $(APPS_DIR)/%.rs, $(TARGET_DIR)/%, $(APPS))
APP_BINS := $(patsubst $(APPS_DIR)/%.rs, $(TARGET_DIR)/%.bin, $(APPS))

# Building mode argument
ifeq ($(MODE), release)
	MODE_ARG := --release
endif

# Board
BOARD ?= qemu
SBI ?= rustsbi
BOOTLOADER := ./bootloader/$(SBI)-$(BOARD).bin
K210_BOOTLOADER_SIZE := 131072

# KERNEL ENTRY
ifeq ($(BOARD), qemu)
	KERNEL_ENTRY_PA := 0x80200000
else ifeq ($(BOARD), k210)
	KERNEL_ENTRY_PA := 0x80020000
endif

# Run K210
K210-SERIALPORT	= /dev/ttyUSB0
K210-BURNER = ../tools/kflash.py

# Binutils
OBJDUMP := rust-objdump --arch-name=riscv64
OBJCOPY := rust-objcopy --binary-architecture=riscv64

# Disassembly
DISASM ?= -x

app_elf:
	@export RUSTFLAGS="-Clink-arg=-Tuser/src/linker.ld" && \
	cargo build --package user --release
	@echo $(APPS)
	@echo $(APP_ELFS)
	@echo $(APP_BINS)

build-apps: app_elf
	$(foreach elf, $(APP_ELFS), $(OBJCOPY) $(elf) --strip-all -O binary $(patsubst $(TARGET_DIR)/%, $(APP_IMAGES_DIR)/%.bin, $(elf));)

# Build OS
build-os: switch-check $(KERNEL_BIN)

switch-check:
ifeq ($(BOARD), qemu)
	(which last-qemu) || (rm -f last-k210 && touch last-qemu && make clean)
else ifeq ($(BOARD), k210)
	(which last-k210) || (rm -f last-qemu && touch last-k210 && make clean)
endif

env:
	(rustup target list | grep "riscv64gc-unknown-none-elf (installed)") || rustup target add $(TARGET)
	cargo install cargo-binutils
	rustup component add rust-src
	rustup component add llvm-tools-preview

$(KERNEL_BIN): kernel
	@$(OBJCOPY) $(KERNEL_ELF) --strip-all -O binary $@

kernel:
	@echo Platform: $(BOARD)
	@cp os/src/linker-$(BOARD).ld os/src/linker.ld
	@export RUSTFLAGS="-Clink-arg=-Tos/src/linker.ld -Cforce-frame-pointers=yes" && \
	cargo build --package os $(MODE_ARG) --features "board_$(BOARD)"
	@rm os/src/linker.ld

clean:
	@cargo clean

disasm: kernel
	@$(OBJDUMP) $(DISASM) $(KERNEL_ELF) | less

disasm-vim: kernel
	@$(OBJDUMP) $(DISASM) $(KERNEL_ELF) > $(DISASM_TMP)
	@vim $(DISASM_TMP)
	@rm $(DISASM_TMP)

run: run-inner

run-inner: build-os
ifeq ($(BOARD),qemu)
	@qemu-system-riscv64 \
		-machine virt \
		-nographic \
		-bios $(BOOTLOADER) \
		-device loader,file=$(KERNEL_BIN),addr=$(KERNEL_ENTRY_PA)
else
	(which $(K210-BURNER)) || (cd .. && git clone https://github.com/sipeed/kflash.py.git && mv kflash.py tools)
	@cp $(BOOTLOADER) $(BOOTLOADER).copy
	@dd if=$(KERNEL_BIN) of=$(BOOTLOADER).copy bs=$(K210_BOOTLOADER_SIZE) seek=1
	@mv $(BOOTLOADER).copy $(KERNEL_BIN)
	@sudo chmod 777 $(K210-SERIALPORT)
	python3 $(K210-BURNER) -p $(K210-SERIALPORT) -b 1500000 $(KERNEL_BIN)
	python3 -m serial.tools.miniterm --eol LF --dtr 0 --rts 0 --filter direct $(K210-SERIALPORT) 115200
endif

debug: build-os
	@tmux new-session -d \
		"qemu-system-riscv64 -machine virt -nographic -bios $(BOOTLOADER) -device loader,file=$(KERNEL_BIN),addr=$(KERNEL_ENTRY_PA) -s -S" && \
		tmux split-window -h "riscv64-unknown-elf-gdb -ex 'file $(KERNEL_ELF)' -ex 'set arch riscv:rv64' -ex 'target remote localhost:1234'" && \
		tmux -2 attach-session -d

gdbserver: build-os
	@qemu-system-riscv64 -machine virt -nographic -bios $(BOOTLOADER) -device loader,file=$(KERNEL_BIN),addr=$(KERNEL_ENTRY_PA) -s -S

gdbclient:
	@riscv64-unknown-elf-gdb -ex 'file $(KERNEL_ELF)' -ex 'set arch riscv:rv64' -ex 'target remote localhost:1234'

.PHONY: build-os env kernel clean disasm disasm-vim run-inner switch-check gdbserver gdbclient
