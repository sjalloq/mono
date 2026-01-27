/* SPDX-License-Identifier: BSD-2-Clause */
/* Linker script for ibex_soc */
/* Based on lowRISC Ibex simple_system */

OUTPUT_ARCH(riscv)

MEMORY
{
    /* ITCM: Instruction memory (code + rodata) */
    itcm : ORIGIN = 0x00010000, LENGTH = 0x4000  /* 16KB */

    /* DTCM: Data memory (data + bss + stack) */
    dtcm : ORIGIN = 0x00020000, LENGTH = 0x4000  /* 16KB */
}

/* Stack configuration */
_min_stack   = 0x800;   /* 2KB minimum stack */
_stack_start = ORIGIN(dtcm) + LENGTH(dtcm);

/* Entry point: reset vector at offset 0x80 from vector table base */
_entry_point = _vectors_start + 0x80;
ENTRY(_entry_point)

/* Simulation halt address (for Spike compatibility) */
tohost   = 0x10001008;  /* SIM_CTRL_CTRL register */
fromhost = _stack_start + 0x10;

SECTIONS
{
    /* Vector table must be at start of ITCM */
    .vectors :
    {
        . = ALIGN(4);
        _vectors_start = .;
        KEEP(*(.vectors))
        _vectors_end = .;
    } > itcm

    /* Code */
    .text : {
        . = ALIGN(4);
        *(.text)
        *(.text.*)
    } > itcm

    /* Read-only data (constants, strings) */
    .rodata : {
        . = ALIGN(4);
        *(.srodata)
        *(.srodata.*)
        *(.rodata)
        *(.rodata.*)
    } > itcm

    /* Initialized data (copied to DTCM at startup) */
    .data : {
        . = ALIGN(4);
        _data_start = .;
        *(.sdata)
        *(.sdata.*)
        *(.data)
        *(.data.*)
        _data_end = .;
    } > dtcm AT > itcm

    _data_load = LOADADDR(.data);

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
    } > dtcm

    /* Stack (grows downward from end of DTCM) */
    .stack (NOLOAD) : {
        . = ALIGN(4);
        . = . + _min_stack;
        . = ALIGN(4);
        _stack = .;
    } > dtcm
}
