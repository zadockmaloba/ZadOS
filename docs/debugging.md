# Debugging ZadOS

This guide explains how to debug ZadOS using GDB or LLDB with QEMU.

## Quick Start

1. Start QEMU in debug mode:
```fish
zig build debug
```

2. In another terminal, connect with either GDB or LLDB:

### Using GDB
```fish
aarch64-elf-gdb zig-out/bin/ZadOS -ex "target remote localhost:1234"
```

### Using LLDB
```fish
lldb zig-out/bin/ZadOS
(lldb) gdb-remote 1234
```

## Debugging Commands

### GDB Commands
```gdb
# Set breakpoints
break _start        # Break at assembly entry point
break kernel_main   # Break at kernel main function

# Execution control
continue           # Continue execution
step              # Step into function
next              # Step over function
stepi             # Step single instruction
nexti             # Step over instruction

# Inspection
info registers    # Show all registers
print $x0        # Print register x0
x/10x $sp        # Examine 10 hex words at stack pointer
bt               # Show backtrace
```

### LLDB Commands
```lldb
# Set breakpoints
b _start         # Break at assembly entry point
b kernel_main    # Break at kernel main function

# Execution control
c                # Continue execution
s                # Step into function
n                # Step over function
si               # Step single instruction
ni               # Step over instruction

# Inspection
register read    # Show all registers
p $x0           # Print register x0
x/10x $sp       # Examine 10 hex words at stack pointer
bt              # Show backtrace
```

## QEMU Debug Configuration

The debug configuration includes:
- Debug symbols enabled
- Link Time Optimization (LTO) disabled
- QEMU debug server on port 1234
- CPU starts halted (-S flag)
- Machine type: 'virt'
- CPU type: cortex-a72

## Memory Map

The kernel is loaded at address 0x80000 (defined in linker.ld).

Important memory regions:
- 0x80000: Kernel entry point
- 0x09000000: UART0 (PL011)

## Source Files

Key files for debugging:
- `src/arch/aarch64/start.S`: Assembly entry point
- `src/arch/aarch64/linker.ld`: Memory layout
- `src/main.zig`: Kernel main
- `src/drivers/uart.zig`: UART driver

## Common Issues

1. If GDB can't connect:
   - Check if QEMU is running in debug mode
   - Verify port 1234 is not in use
   - Try restarting QEMU

2. If symbols are not loading:
   - Verify the kernel was built with debug symbols
   - Check the file path is correct

3. If breakpoints don't work:
   - Ensure you're setting breakpoints after connecting
   - Verify symbol names are correct
