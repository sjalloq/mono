// SPDX-License-Identifier: BSD-2-Clause
// USB UART echo test for ibex_soc
//
// Exercises both directions of the USB UART data path:
//   1. TX: Writes "Hello USB!\n" to USB UART (auto-flushes on newline)
//   2. RX: Polls for incoming data and echoes it back with software flush
//
// Phase markers via SimCtrl:
//   "T\n" - TX phase complete
//   "R\n" - Ready for RX loopback

#include "ibex_soc.h"

// Enable TX and RX with character-based flush (newline triggers flush)
#define USB_UART_ENABLE (USB_UART_CTRL_TX_EN | USB_UART_CTRL_RX_EN | USB_UART_CTRL_CHAR_FLUSH_EN)

static void usb_uart_puts(const char *str) {
    // Pack characters into 32-bit words and write to TX FIFO
    uint32_t word = 0;
    int byte_idx = 0;

    while (*str) {
        word |= ((uint32_t)(unsigned char)*str++) << (byte_idx * 8);
        byte_idx++;
        if (byte_idx == 4) {
            usb_uart_tx_word(word);
            word = 0;
            byte_idx = 0;
        }
    }

    // Write remaining partial word
    if (byte_idx > 0) {
        usb_uart_tx_word(word);
    }
}

int main(void) {
    // Boot message via SimCtrl (so wait_for_cpu_output works)
    puts("USB echo test");

    // Enable the USB UART
    REG_WRITE(USB_UART_BASE + USB_UART_CTRL, USB_UART_ENABLE);

    // TX phase: write "Hello USB!\n" to USB UART
    usb_uart_puts("Hello USB!\n");

    // Signal TX phase complete
    puts("T");

    // Signal ready for RX loopback
    puts("R");

    // RX loopback: poll for incoming data and echo back
    uint32_t idle_count = 0;
    const uint32_t idle_timeout = 50000;

    while (idle_count < idle_timeout) {
        uint32_t status = usb_uart_status();

        if (status & USB_UART_STATUS_RX_VALID) {
            // Read the packet length
            uint32_t rx_len = usb_uart_rx_len();
            uint32_t num_words = (rx_len + 3) / 4;

            // Read and echo each word
            for (uint32_t i = 0; i < num_words; i++) {
                uint32_t word = usb_uart_rx_word();
                usb_uart_tx_word(word);
            }

            // Software flush to send the echoed data
            usb_uart_tx_flush();

            idle_count = 0;  // Reset timeout on activity
        } else {
            idle_count++;
        }
    }

    puts("Done");
    return 0;
}
