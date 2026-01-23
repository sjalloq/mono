// SPDX-License-Identifier: Apache-2.0
// Wishbone Crossbar Package
//
// Copyright (c) 2025 Mono Authors
//
// Shared types and constants for wb_crossbar modules.

package wb_crossbar_pkg;

  typedef enum logic {
    StIdle,
    StBusy
  } arb_state_e;

endpackage
