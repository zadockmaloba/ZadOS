# ARM64 Kernel Entry Point
# This code runs when the kernel first starts up

.section ".text.boot"              // Place this code at the start of the kernel
.global _start                     // Make _start symbol visible to the linker

_start:
    // ---- CPU Core Check ----
    // Only allow CPU 0 to boot, park other cores
    mrs     x0, mpidr_el1         // Read Multiprocessor Affinity Register into x0
    and     x0, x0, #3            // Mask with 3 to get CPU ID (bits [1:0])
    cbz     x0, 2f                // If CPU 0, branch forward to label 2
1:  wfe                           // Other CPUs: Wait For Event (low power state)
    b       1b                    // Infinite loop for non-boot CPUs (b[ack])

    // ---- Stack Setup ----
2:  // CPU 0 continues here
    // Set up EL1 mode
    mrs     x0, CurrentEL         // Read current exception level
    cmp     x0, #(1 << 2)        // Check if we're already at EL1
    b.eq    3f                    // Skip EL adjustment if we are

    // If we're in EL2, set up EL1
    mrs     x0, hcr_el2          // Read Hypervisor Configuration Register
    orr     x0, x0, #(1 << 31)   // Set EL1 execution state to AArch64
    msr     hcr_el2, x0          // Write back to HCR_EL2

    // Set up SCTLR_EL1
    mov     x0, #0x0800          // Enable alignment checking
    movk    x0, #0x30d0, lsl #16 // Standard configuration for EL1
    msr     sctlr_el1, x0

3:  // Set up the stack
    ldr     x0, =stack_top        // Load address of stack_top
    and     x0, x0, #~15          // Ensure 16-byte alignment
    mov     sp, x0                // Set up stack pointer

    // ---- Clear BSS Section ----
    // BSS must be zero-initialized according to C/C++ standard
    ldr     x0, =__bss_start      // Load start address of BSS
    ldr     x1, =__bss_end        // Load end address of BSS
    sub     x1, x1, x0            // Calculate size of BSS section
3:  cbz     x1, 4f                // If size is zero, branch forward to label 4
    str     xzr, [x0], #8         // Store zero and increment address by 8
    sub     x1, x1, #8            // Decrease remaining size by 8 bytes
    b       3b                    // Loop back until BSS is cleared

    // ---- Jump to Kernel ----
4:  // BSS is cleared, ready to run kernel
    bl      kernel_main           // Branch with Link to kernel_main function

    // ---- CPU Halt ----
5:  // If kernel_main returns, halt the CPU
    wfe                           // Wait For Event (low power state)
    b       5b                    // Infinite loop (b[ack])
