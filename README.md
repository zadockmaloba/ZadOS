# ZadOS

ZadOS is a toy operating system for ARM64 architecture, designed to run on QEMU's virtual machine.

Based on work done by the ZsystemOS/pluto project: https://github.com/ZystemOS/pluto

## Project Structure

```
ZadOS/
├── build.zig           # Zig build script
├── build.zig.zon      # Zig build dependencies
├── docs/              # Documentation
│   └── debugging.md   # Debugging guide
├── src/               # Source code
│   ├── main.zig      # Kernel entry point
│   ├── root.zig      # Root configuration
│   ├── arch/         # Architecture-specific code
│   │   └── aarch64/  # ARM64 specific code
│   │       ├── start.S    # Assembly startup
│   │       └── linker.ld  # Linker script
│   ├── drivers/      # Hardware drivers
│   │   ├── uart.zig # UART driver
│   │   └── timer.zig # Timer driver
│   ├── kernel/       # Core kernel components
│   │   ├── memory.zig    # Memory management
│   │   ├── scheduler.zig # Process scheduler
│   │   └── interrupt.zig # Interrupt handling
│   ├── lib/          # Common utilities
│   │   └── debug.zig # Debugging utilities
│   └── test/         # Test files
└── zig-out/          # Build outputs
    ├── bin/          # Executable outputs
    │   └── ZadOS    # Kernel binary
    └── lib/          # Library outputs
        └── libZadOS.a # Static library
```

## Building

Build the kernel:
```fish
zig build
```

Run in QEMU:
```fish
zig build qemu
```

Debug with GDB/LLDB:
```fish
zig build debug
```

## Features

- Bare metal ARM64 support
- PL011 UART driver
- Basic kernel initialization
- Debugging support via GDB/LLDB


## Development

See [debugging.md](docs/debugging.md) for information about debugging the kernel.
