# ZadOS

ZadOS is a toy operating system for ARM64, RISC-V, and x86_64 architectures, designed to run on QEMU or real hardware.

Based on work done by the ZsystemOS/pluto project: https://github.com/ZystemOS/pluto

## Project Structure

```
ZadOS/
├── build.zig           # Zig build script
├── build.zig.zon       # Zig build dependencies
├── docs/               # Documentation
│   ├── arm64_startup.md
│   ├── debugging.md
│   └── ...
├── src/                # Source code
│   ├── main.zig        # Kernel entry point
│   ├── root.zig        # Root configuration
│   ├── arch/           # Architecture-specific code
│   │   └── aarch64/    # ARM64 specific code
│   │       ├── start.S       # Assembly startup
│   │       ├── linker.ld     # Linker script
│   │       ├── arch.zig      # Arch abstraction
│   │       ├── boot.zig      # Boot logic
│   │       ├── cmos.zig      # CMOS/RTC
│   │       ├── gic.zig       # GIC/interrupt controller
│   │       ├── interrupts.zig
│   │       ├── irq.zig
│   │       ├── isr.zig
│   │       ├── keyboard.zig
│   │       ├── mmio.zig
│   │       ├── multiboot.zig
│   │       ├── paging.zig
│   │       ├── pci.zig
│   │       ├── pit.zig
│   │       ├── rtc.zig
│   │       ├── serial.zig
│   │       ├── syscalls.zig
│   │       ├── tty.zig
│   │       ├── uart.zig
│   │       └── vga.zig
│   ├── drivers/        # Hardware drivers
│   │   ├── uart.zig    # UART driver
│   │   ├── timer.zig   # Timer driver
│   │   └── ...
│   ├── kernel/         # Core kernel components
│   │   ├── arch.zig
│   │   ├── bitmap.zig
│   │   ├── elf.zig
│   │   ├── heap.zig
│   │   ├── keyboard.zig
│   │   ├── log.zig
│   │   ├── mem.zig
│   │   ├── panic.zig
│   │   ├── pmm.zig
│   │   ├── scheduler.zig
│   │   ├── serial.zig
│   │   ├── syscalls.zig
│   │   ├── task.zig
│   │   ├── tty.zig
│   │   ├── vmm.zig
│   │   └── filesystem/
│   │       ├── fat32.zig
│   │       ├── initrd.zig
│   │       └── vfs.zig
│   │   └── lib/
│   │       └── ArrayList.zig
│   ├── lib/            # Common utilities
│   │   ├── debug.zig   # Debugging utilities
│   │   └── ...
│   ├── test/           # Test files
│   └── ...
├── test/               # Test programs and data
│   ├── gen_types.zig
│   ├── ramdisk_test1.txt
│   ├── ramdisk_test2.txt
│   ├── runtime_test.zig
│   ├── user_program_data.s
│   ├── user_program.ld
│   ├── user_program.s
│   └── fat32/
│       └── test_files/
│           ├── ...
├── tmp/                # Temporary files
│   └── syms.log
├── zig-out/            # Build outputs
│   ├── bin/            # Executable outputs
│   │   └── ZadOS       # Kernel binary
│   └── lib/            # Library outputs
│       └── libZadOS.a  # Static library
```

## Building

Build the kernel for the default (AArch64/QEMU):
```fish
zig build
```

### Multi-arch/board builds

You can select the architecture and board at build time:

```fish
zig build -Darch=AArch64 -Dboard=Qemu_Virt
zig build -Darch=AArch64 -Dboard=RaspberryPi4
zig build -Darch=RiscV64 -Dboard=Qemu_Virt
zig build -Darch=X86_64 -Dboard=Qemu_Virt
```

Supported boards: Qemu_Virt, RaspberryPi4, RaspberryPi400, Pine64, OdroidN2, OdroidN2Plus, OdroidC4, RockPro64

### Run in QEMU
```fish
zig build qemu
```

### Debug with GDB/LLDB
```fish
zig build debug
```

## Features

- Bare metal ARM64, RISC-V, and x86_64 support
- QEMU and real hardware board selection
- PL011 UART driver
- Basic kernel initialization
- Debugging support via GDB/LLDB
- Flexible build system (multi-arch/board)

## Development

See [debugging.md](docs/debugging.md) for information about debugging the kernel.
