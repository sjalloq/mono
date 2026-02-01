// SPDX-License-Identifier: BSD-2-Clause
// ibex_soc register definitions
// For use by both C and assembly

#ifndef IBEX_SOC_REGS_H
#define IBEX_SOC_REGS_H

// Memory regions
#define ITCM_BASE       0x00010000
#define ITCM_SIZE       0x00004000  // 16KB

#define DTCM_BASE       0x00020000
#define DTCM_SIZE       0x00004000  // 16KB

// Timer peripheral (RISC-V mtime)
#define TIMER_BASE      0x10000000
#define TIMER_MTIME     0x00
#define TIMER_MTIMEH    0x04
#define TIMER_MTIMECMP  0x08
#define TIMER_MTIMECMPH 0x0C

// Simulation control peripheral
#define SIM_CTRL_BASE   0x10001000
#define SIM_CTRL_OUT    0x00    // Write ASCII char [7:0]
#define SIM_CTRL_CTRL   0x08    // Write 1 to halt simulation

// USB UART peripheral
#define USB_UART_BASE       0x10002000
#define USB_UART_TX_DATA    0x00    // Write 32-bit word to TX FIFO
#define USB_UART_RX_DATA    0x04    // Read 32-bit word from RX FIFO (pops)
#define USB_UART_RX_LEN     0x08    // Byte count of current RX packet (peek)
#define USB_UART_STATUS     0x0C    // Status: tx_empty[0], tx_full[1], rx_valid[2], rx_full[3], tx_level[7:4], rx_packets[11:8]
#define USB_UART_CTRL       0x10    // Control: tx_en[0], rx_en[1], char_flush_en[2], timeout_flush_en[3], thresh_flush_en[4], tx_flush[5], rx_flush[6], tx_clear[7]

// USB UART STATUS register bits
#define USB_UART_STATUS_TX_EMPTY    (1 << 0)
#define USB_UART_STATUS_TX_FULL     (1 << 1)
#define USB_UART_STATUS_RX_VALID    (1 << 2)
#define USB_UART_STATUS_RX_FULL     (1 << 3)

// USB UART CTRL register bits
#define USB_UART_CTRL_TX_EN             (1 << 0)
#define USB_UART_CTRL_RX_EN             (1 << 1)
#define USB_UART_CTRL_CHAR_FLUSH_EN     (1 << 2)
#define USB_UART_CTRL_TIMEOUT_FLUSH_EN  (1 << 3)
#define USB_UART_CTRL_THRESH_FLUSH_EN   (1 << 4)
#define USB_UART_CTRL_TX_FLUSH          (1 << 5)
#define USB_UART_CTRL_RX_FLUSH          (1 << 6)
#define USB_UART_CTRL_TX_CLEAR          (1 << 7)

#endif // IBEX_SOC_REGS_H
