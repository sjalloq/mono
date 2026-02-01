/* SPDX-License-Identifier: BSD-2-Clause */
/* Linker script for serv_soc */
/* Single unified TCM for code + data */

OUTPUT_ARCH(riscv)

MEMORY
{
    /* Unified TCM: code + rodata + data + bss + stack */
    tcm : ORIGIN = 0x00000000, LENGTH = 0x2000  /* 8KB */
}

/* Stack configuration */
_min_stack   = 0x400;   /* 1KB minimum stack */
_stack_start = ORIGIN(tcm) + LENGTH(tcm);

/* Entry point */
ENTRY(_start)

/* Simulation halt address (for Spike compatibility) */
tohost   = 0x10001008;  /* SIM_CTRL_CTRL register */
fromhost = _stack_start + 0x10;

SECTIONS
{
    /* Code at start of TCM */
    .text : {
        . = ALIGN(4);
        *(.text.start)
        *(.text)
        *(.text.*)
    } > tcm

    /* Read-only data (constants, strings) */
    .rodata : {
        . = ALIGN(4);
        *(.srodata)
        *(.srodata.*)
        *(.rodata)
        *(.rodata.*)
    } > tcm

    /* Initialized data */
    .data : {
        . = ALIGN(4);
        _data_start = .;
        *(.sdata)
        *(.sdata.*)
        *(.data)
        *(.data.*)
        _data_end = .;
    } > tcm

    /* Uninitialized data (zeroed at startup) */
    .bss :
    {
        . = ALIGN(4);
        _bss_start = .;
        *(.sbss)
        *(.sbss.*)
        *(.bss)
        *(.bss.*)
        *(COMMON)
        _bss_end = .;
    } > tcm

    /* Stack (grows downward from end of TCM) */
    .stack (NOLOAD) : {
        . = ALIGN(4);
        . = . + _min_stack;
        . = ALIGN(4);
        _stack = .;
    } > tcm
}
