##############
Firmware Build
##############

Tests running on an embedded processor DUT need firmware compiled before
simulation starts. This page covers patterns for managing firmware builds
in pytest, from simple inline builds to xdist-safe caching.


The Challenge
=============

.. code-block:: text

   ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
   │  Firmware       │      │  Compile        │      │  Simulator      │
   │  Source (.c)    │─────►│  (make/gcc)     │─────►│  ($readmemh)    │
   └─────────────────┘      └─────────────────┘      └─────────────────┘
                                   │
                                   ▼
                            ┌─────────────────┐
                            │  .hex / .vmem   │
                            └─────────────────┘

Requirements:

1. Firmware compiled before simulation starts
2. ``.vmem`` file in a location the simulator can find
3. Potentially different firmware per test
4. Efficient sharing when multiple tests use the same firmware


Simple Approach: Dataclass Helper
=================================

Start simple. A dataclass that builds firmware and copies it to the test
directory:

.. code-block:: python

   # conftest.py
   import shutil
   import subprocess
   from dataclasses import dataclass
   from pathlib import Path

   REPO_ROOT = Path(__file__).resolve().parents[5]
   FIRMWARE_ROOT = REPO_ROOT / "sw" / "device" / "project" / "firmware"


   @dataclass
   class FirmwareBuild:
       """Build firmware and copy .vmem into a test directory."""
       name: str
       src_dir: Path

       def build_into(self, test_dir: Path) -> None:
           """Build firmware and copy .vmem to test_dir/firmware.vmem."""
           subprocess.run(["make"], cwd=self.src_dir, check=True)
           vmem = self.src_dir / f"{self.name}.vmem"
           shutil.copy2(vmem, test_dir / "firmware.vmem")

Usage in tests:

.. code-block:: python

   # test_core.py
   from conftest import FirmwareBuild, FIRMWARE_ROOT

   def test_run_boot_heartbeat(test_session):
       FirmwareBuild("hello", FIRMWARE_ROOT / "hello").build_into(
           test_session.directory
       )
       test_session.run(testcase="test_boot_heartbeat")

   # test_usb_uart.py
   def test_run_usb_uart_tx(test_session):
       FirmwareBuild("usb_echo", FIRMWARE_ROOT / "usb_echo").build_into(
           test_session.directory
       )
       test_session.run(testcase="test_usb_uart_tx")

**Pros**: Simple, explicit, no magic.

**Cons**: Rebuilds firmware every test, even when shared.


Marker-Based Approach
=====================

Use pytest markers for cleaner test code:

.. code-block:: python

   # conftest.py
   import pytest

   def pytest_configure(config):
       config.addinivalue_line(
           "markers",
           "firmware(name): specify firmware to build and load"
       )

   @pytest.fixture
   def firmware(request, test_session):
       """Build and copy firmware based on marker."""
       marker = request.node.get_closest_marker("firmware")
       if marker is None:
           return None

       name = marker.args[0]
       src_dir = FIRMWARE_ROOT / name

       subprocess.run(["make"], cwd=src_dir, check=True)
       vmem = src_dir / f"{name}.vmem"
       shutil.copy2(vmem, test_session.directory / "firmware.vmem")

       return vmem

Usage:

.. code-block:: python

   @pytest.mark.firmware("hello")
   def test_run_boot_heartbeat(test_session, firmware):
       test_session.run(testcase="test_boot_heartbeat")

   @pytest.mark.firmware("usb_echo")
   def test_run_usb_uart_tx(test_session, firmware):
       test_session.run(testcase="test_usb_uart_tx")

**Pros**: Clean test code, dependency declared at top.

**Cons**: Still rebuilds every test.


Cached Factory (xdist-Safe)
===========================

For efficient sharing across tests and xdist workers:

.. code-block:: python

   # conftest.py
   import shutil
   import subprocess
   from pathlib import Path

   import pytest
   from pytest_cocotb.guard import CallOnce

   REPO_ROOT = Path(__file__).resolve().parents[5]
   FIRMWARE_ROOT = REPO_ROOT / "sw" / "device" / "project" / "firmware"


   @pytest.fixture(scope="session")
   def firmware_cache(tmp_path_factory):
       """Build each firmware once, share across all tests/workers."""
       shared = tmp_path_factory.getbasetemp().parent
       cache = {}

       def _get(name: str) -> Path:
           if name not in cache:
               src_dir = FIRMWARE_ROOT / name

               # NFS-safe, xdist-safe: runs once across all workers
               CallOnce(
                   path=shared,
                   name=f"firmware_{name}",
                   fn=lambda src=src_dir: subprocess.run(
                       ["make"], cwd=src, check=True
                   ),
               ).ensure_done()

               cache[name] = src_dir / f"{name}.vmem"
           return cache[name]

       return _get


   @pytest.fixture
   def firmware(request, test_session, firmware_cache):
       """Copy cached firmware to test directory based on marker."""
       marker = request.node.get_closest_marker("firmware")
       if marker is None:
           return None

       name = marker.args[0]
       vmem = firmware_cache(name)
       shutil.copy2(vmem, test_session.directory / "firmware.vmem")
       return vmem

Timeline with 4 xdist workers, all needing ``usb_echo``:

.. code-block:: text

   Worker 0: firmware_cache("usb_echo") → CallOnce acquires lock → runs make
   Worker 1: firmware_cache("usb_echo") → CallOnce blocks on lock...
   Worker 2: firmware_cache("usb_echo") → CallOnce blocks on lock...
   Worker 3: firmware_cache("usb_echo") → CallOnce blocks on lock...

   Worker 0: make finishes → .done marker created → lock released
   Worker 1: sees .done → returns cached path → copies to test_dir
   Worker 2: sees .done → returns cached path → copies to test_dir
   Worker 3: sees .done → returns cached path → copies to test_dir

The ``make`` runs **once**. All workers share the result.


Complete Example
================

Putting it all together for the ibex_soc testbench:

.. code-block:: python

   # hw/projects/squirrel/ibex_soc/dv/conftest.py
   import shutil
   import subprocess
   from pathlib import Path

   import pytest
   from pytest_cocotb.guard import CallOnce

   REPO_ROOT = Path(__file__).resolve().parents[5]
   FIRMWARE_ROOT = REPO_ROOT / "sw" / "device" / "squirrel" / "ibex_soc"


   def pytest_configure(config):
       config.addinivalue_line(
           "markers",
           "firmware(name): specify firmware to build and load"
       )


   @pytest.fixture(scope="session")
   def firmware_cache(tmp_path_factory):
       """Build each firmware once, share across tests/workers."""
       shared = tmp_path_factory.getbasetemp().parent
       cache = {}

       def _get(name: str) -> Path:
           if name not in cache:
               src_dir = FIRMWARE_ROOT / name
               CallOnce(
                   path=shared,
                   name=f"firmware_{name}",
                   fn=lambda src=src_dir: subprocess.run(
                       ["make"], cwd=src, check=True
                   ),
               ).ensure_done()
               cache[name] = src_dir / f"{name}.vmem"
           return cache[name]

       return _get


   @pytest.fixture
   def firmware(request, test_session, firmware_cache):
       """Copy cached firmware to test directory based on marker."""
       marker = request.node.get_closest_marker("firmware")
       if marker is None:
           return None

       name = marker.args[0]
       vmem = firmware_cache(name)
       shutil.copy2(vmem, test_session.directory / "firmware.vmem")
       return vmem

.. code-block:: python

   # hw/projects/squirrel/ibex_soc/dv/test_core.py

   @pytest.mark.firmware("hello")
   def test_run_boot_heartbeat(test_session, firmware):
       test_session.run(testcase="test_boot_heartbeat")

.. code-block:: python

   # hw/projects/squirrel/ibex_soc/dv/test_usb_uart.py

   @pytest.mark.firmware("usb_echo")
   def test_run_usb_uart_tx(test_session, firmware):
       test_session.run(testcase="test_usb_uart_tx")

   @pytest.mark.firmware("usb_echo")
   def test_run_usb_uart_rx(test_session, firmware):
       test_session.run(testcase="test_usb_uart_rx")

   @pytest.mark.firmware("usb_echo")
   def test_run_usb_uart_loopback(test_session, firmware):
       test_session.run(testcase="test_usb_uart_loopback")


Advanced: Multiple Firmware Images
==================================

Some tests need multiple firmware images (bootloader + application):

.. code-block:: python

   @pytest.fixture
   def firmwares(request, test_session, firmware_cache):
       """Handle multiple firmware markers."""
       results = {}
       for marker in request.node.iter_markers("firmware"):
           name = marker.args[0]
           # Optional: custom destination name
           dest_name = marker.kwargs.get("dest", f"{name}.vmem")

           vmem = firmware_cache(name)
           shutil.copy2(vmem, test_session.directory / dest_name)
           results[name] = vmem

       return results

Usage:

.. code-block:: python

   @pytest.mark.firmware("bootloader", dest="boot.vmem")
   @pytest.mark.firmware("app_test", dest="app.vmem")
   def test_boot_and_run(test_session, firmwares):
       # Both boot.vmem and app.vmem are in test_session.directory
       test_session.run(testcase="test_boot_sequence")


Advanced: Build Variants
========================

For firmware that needs different build configurations:

.. code-block:: python

   @pytest.fixture(scope="session")
   def firmware_cache(tmp_path_factory):
       shared = tmp_path_factory.getbasetemp().parent
       cache = {}

       def _get(name: str, make_args: tuple = ()) -> Path:
           # Include make_args in cache key
           key = (name, make_args)
           if key not in cache:
               src_dir = FIRMWARE_ROOT / name

               # Unique guard name includes args
               args_hash = hash(make_args)
               guard_name = f"firmware_{name}_{args_hash}"

               def build():
                   cmd = ["make"] + list(make_args)
                   subprocess.run(cmd, cwd=src_dir, check=True)

               CallOnce(path=shared, name=guard_name, fn=build).ensure_done()
               cache[key] = src_dir / f"{name}.vmem"

           return cache[key]

       return _get

Usage:

.. code-block:: python

   def test_debug_mode(test_session, firmware_cache):
       vmem = firmware_cache("app", make_args=("DEBUG=1",))
       shutil.copy(vmem, test_session.directory / "firmware.vmem")
       test_session.run(testcase="test_debug")

   def test_release_mode(test_session, firmware_cache):
       vmem = firmware_cache("app", make_args=("RELEASE=1",))
       shutil.copy(vmem, test_session.directory / "firmware.vmem")
       test_session.run(testcase="test_release")


Troubleshooting
===============

Build Fails But Tests Keep Running
----------------------------------

``CallOnce`` creates a ``.failed`` marker on error. Subsequent tests see this
and fail immediately without re-attempting the build.

To retry after fixing the issue:

.. code-block:: bash

   # Find and remove failed markers
   find sim_build -name "*.failed" -delete

   # Or clean entire sim_build
   rm -rf sim_build/


Wrong Firmware in Test
----------------------

Each test copies firmware to ``test_session.directory / "firmware.vmem"``.
Check that:

1. The marker specifies the correct firmware name
2. The ``firmware`` fixture is included in the test signature
3. The ``.vmem`` exists after the build


Build Hangs with xdist
----------------------

A worker may be waiting on a lock held by a crashed worker. Check:

.. code-block:: bash

   # Find lock directories
   find /tmp/pytest-* -name "*.lock" -type d

   # Check holder info
   cat /tmp/pytest-.../firmware_hello.lock/holder.info

If the holder PID doesn't exist, remove the lock directory to unblock.
