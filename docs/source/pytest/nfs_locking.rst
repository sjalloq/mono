###########
NFS Locking
###########

When running tests across multiple machines with shared NFS storage, standard
file locking (``flock``, ``fcntl``) often fails. This page explains the problem
and the solution used in pytest-cocotb.


The Problem with flock on NFS
=============================

The standard Python ``filelock`` package uses ``fcntl.flock()`` under the hood.
On many NFS configurations, this lock is **local-only** — it prevents other
processes on the same machine from acquiring the lock, but processes on other
machines don't see it.

.. code-block:: python

   from filelock import FileLock

   # UNRELIABLE on NFS!
   with FileLock("/nfs/shared/build.lock"):
       compile_hdl()  # Other nodes may also be compiling

This leads to race conditions when multiple compute nodes try to build the
same resource.


Solution: mkdir Atomicity
=========================

The ``mkdir`` system call is atomic on all NFS versions — it either succeeds
or raises ``FileExistsError``. We can use this as a locking primitive:

.. code-block:: python

   import os

   def acquire_lock(lock_path):
       while True:
           try:
               os.mkdir(lock_path)  # Atomic!
               return
           except FileExistsError:
               time.sleep(0.1)  # Someone else has the lock

   def release_lock(lock_path):
       os.rmdir(lock_path)

pytest-cocotb provides a robust implementation with timeouts and stale lock
detection.


NFSLock
=======

The ``NFSLock`` class provides a context manager for NFS-safe locking:

.. code-block:: python

   from pytest_cocotb.nfs_lock import NFSLock

   with NFSLock("/nfs/shared/.locks/build.lock"):
       compile_hdl()

Parameters
----------

.. list-table::
   :header-rows: 1
   :widths: 20 15 65

   * - Parameter
     - Default
     - Description
   * - ``lock_path``
     - (required)
     - Directory path to use as the lock
   * - ``timeout``
     - 3600
     - Seconds to wait before raising ``NFSLockTimeout``
   * - ``poll_interval``
     - 0.1
     - Seconds between acquisition attempts
   * - ``stale_timeout``
     - 7200
     - Seconds after which a lock from an unreachable host is broken


How It Works
------------

1. **Acquire**: Try ``os.mkdir(lock_path)``. If it fails with
   ``FileExistsError``, someone else has the lock — wait and retry.

2. **Holder info**: Write a ``holder.info`` file inside the lock directory
   containing hostname, PID, and timestamp.

3. **Release**: Delete ``holder.info`` and ``rmdir`` the lock directory.

4. **Stale detection**: If the lock exists but the holder info indicates:

   - Same host, but PID doesn't exist → lock is stale, break it
   - Different host, and timestamp is older than ``stale_timeout`` → break it


Example: Compilation Lock
-------------------------

.. code-block:: python

   from pytest_cocotb.nfs_lock import NFSLock

   @pytest.fixture(scope="session")
   def compiled_design(tmp_path_factory):
       shared = tmp_path_factory.getbasetemp().parent
       build_dir = shared / "build"
       lock_path = shared / ".locks" / "compile.lock"

       build_dir.mkdir(parents=True, exist_ok=True)
       lock_path.parent.mkdir(parents=True, exist_ok=True)

       with NFSLock(lock_path, timeout=1800):  # 30 min timeout
           if not (build_dir / ".done").exists():
               compile_hdl(build_dir)
               (build_dir / ".done").touch()

       return build_dir


CallOnce Guard
==============

``CallOnce`` is a higher-level abstraction that combines locking with
completion tracking. It ensures a callable runs exactly once across all
processes and nodes.

.. code-block:: python

   from pytest_cocotb.guard import CallOnce

   guard = CallOnce(
       path=build_dir,
       name="hdl_compile",
       fn=lambda: runner.build(...),
   )
   guard.ensure_done()

How It Works
------------

1. Create lock directory at ``{path}/.locks/``
2. Acquire ``{name}.lock`` using NFSLock
3. Check for ``{name}.done`` marker — if exists, return immediately
4. Check for ``{name}.failed`` marker — if exists, raise error
5. Execute ``fn()``
6. On success: create ``{name}.done`` marker
7. On failure: create ``{name}.failed`` marker with error message
8. Release lock

Subsequent callers see the ``.done`` marker and skip execution.


Example: Firmware Build Cache
-----------------------------

.. code-block:: python

   from pytest_cocotb.guard import CallOnce

   FIRMWARE_ROOT = Path("/repo/sw/device/firmware")

   @pytest.fixture(scope="session")
   def firmware_cache(tmp_path_factory):
       shared = tmp_path_factory.getbasetemp().parent
       cache = {}

       def _get(name: str) -> Path:
           if name not in cache:
               src_dir = FIRMWARE_ROOT / name

               # Runs make ONCE across all workers/nodes
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


NFS Cache Coherence
===================

NFS clients cache directory entries and file attributes. After another node
creates a file, your node may not see it immediately.

The ``guard.py`` module includes helpers for this:

.. code-block:: python

   from pytest_cocotb.guard import _nfs_file_exists

   # Forces NFS client to revalidate cache before checking
   if _nfs_file_exists(path / "marker.done"):
       print("Build complete")

This works by opening the parent directory (forces dentry revalidation), then
opening the file itself (bypasses stat cache).


Marker Files and fsync
======================

Creating a marker file requires careful ordering on NFS:

.. code-block:: python

   from pytest_cocotb.guard import _create_marker

   # Writes content, fsyncs file, fsyncs parent directory
   _create_marker(path / "build.done", content="")

The ``fsync`` on the parent directory ensures the directory entry is flushed
to the server, not just cached locally.


Cleaning Up for Rebuild
=======================

To force a rebuild, remove the marker files:

.. code-block:: python

   guard = CallOnce(path=build_dir, name="compile", fn=compile_fn)

   # Force rebuild
   guard.clean()  # Removes .done and .failed markers

   # Next call will re-execute fn()
   guard.ensure_done()


Debugging Lock Issues
=====================

If a build hangs waiting for a lock, check the holder info:

.. code-block:: bash

   cat /nfs/shared/.locks/compile.lock/holder.info
   # {"hostname": "node42", "pid": 12345, "timestamp": 1706123456.789}

If the holder process crashed:

.. code-block:: bash

   # On node42:
   ps -p 12345  # Check if PID exists

   # If not, the lock will be automatically broken after stale_timeout
   # Or manually remove:
   rm -rf /nfs/shared/.locks/compile.lock/


Comparison: filelock vs NFSLock
===============================

.. list-table::
   :header-rows: 1
   :widths: 25 35 40

   * - Aspect
     - ``filelock.FileLock``
     - ``pytest_cocotb.NFSLock``
   * - Mechanism
     - ``fcntl.flock()``
     - ``os.mkdir()``
   * - NFS safe
     - No (often local-only)
     - Yes (mkdir is atomic)
   * - Cross-node
     - No
     - Yes
   * - Stale detection
     - Limited
     - PID check + timeout
   * - Holder info
     - No
     - Yes (hostname, PID, time)
   * - Dependencies
     - ``filelock`` package
     - Standard library only
