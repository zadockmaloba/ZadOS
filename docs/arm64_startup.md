# ARM64 Startup Code Documentation

This document explains the startup assembly code used in ZadOS for ARM64 architecture.

## Overview

The startup code (`start.S`) is responsible for:
1. Initial CPU setup
2. CPU core management
3. Stack initialization
4. BSS section clearing
5. Jumping to the Zig kernel code

## Code Analysis

```arm
.section ".text.boot"              # Place at start of kernel
.global _start                     # Export symbol
```
This places our startup code at the beginning of the kernel binary and makes the `_start` symbol visible to the linker.

### CPU Core Management
```arm
mrs     x0, mpidr_el1         # Read Multiprocessor Affinity Register
and     x0, x0, #3            # Mask to get CPU ID (bits [1:0])
cbz     x0, 2f                # If CPU 0, continue to label 2
```
- `mpidr_el1`: System register containing CPU core information
- Only CPU 0 continues boot process
- Other cores enter low-power state:
  ```arm
  wfe                         # Wait For Event
  b       1b                  # Loop back
  ```

### Stack Setup
```arm
ldr     x0, =stack_top        # Load stack address
mov     sp, x0                # Set stack pointer
```
- Stack address comes from linker script
- Full descending stack (grows downward)
- Must be 16-byte aligned for ARM64

### BSS Initialization
```arm
ldr     x0, =__bss_start      # Start of BSS
ldr     x1, =__bss_end        # End of BSS
sub     x1, x1, x0            # Calculate size
cbz     x1, 4f                # Skip if empty
str     xzr, [x0], #8         # Zero 8 bytes
sub     x1, x1, #8            # Adjust counter
b       3b                    # Loop
```
- Clears uninitialized data section
- Processes 8 bytes at a time
- Uses zero register (`xzr`)
- Post-increment addressing

### Kernel Jump
```arm
bl      kernel_main           # Call kernel
wfe                          # If return, sleep
b       5b                   # Loop forever
```
- `bl` saves return address
- CPU halts if kernel returns

## Register Usage

| Register | Usage |
|----------|-------|
| x0       | Temporary/Arguments |
| x1       | Temporary/Counter |
| sp       | Stack Pointer |
| xzr      | Zero Register |

## Branch Notation

- `Nb`: Branch backward to label N
- `Nf`: Branch forward to label N
- Example: `2f` means "branch forward to label 2"

## Memory Layout

```
+------------------+ 
| .text.boot      | → Entry point code
+------------------+
| .text           | → Kernel code
+------------------+
| .rodata         | → Read-only data
+------------------+
| .data           | → Initialized data
+------------------+
| .bss            | → Uninitialized data (zeroed)
+------------------+
| stack           | → Kernel stack (grows down)
+------------------+
```

## System Registers

- `mpidr_el1`: Multiprocessor Affinity Register
  - Bits [1:0]: CPU core ID
  - Used for core identification

## Important Instructions

| Instruction | Description |
|-------------|-------------|
| mrs         | Move from System Register |
| ldr         | Load Register |
| str         | Store Register |
| cbz         | Compare and Branch if Zero |
| wfe         | Wait For Event |
| bl          | Branch with Link |

## Further Considerations

1. **Exception Level**
   - Kernel typically runs at EL1
   - Boot starts at EL2 or EL3
   - Transition setup needed (future enhancement)

2. **MMU Setup**
   - Currently running with MMU disabled
   - Virtual memory setup needed before C code

3. **Cache Configuration**
   - Caches initially disabled
   - Setup needed for performance

4. **Future Enhancements**
   - FPU/NEON initialization
   - Exception vector setup
   - Page table initialization
   - SMP support
