#####
xdist
#####

pytest-xdist enables parallel test execution across multiple processes or
machines. This page covers patterns for safe resource sharing.


Overview
========

Install and run:

.. code-block:: bash

   pip install pytest-xdist
   pytest -n auto        # Use all CPU cores
   pytest -n 4           # Use 4 workers
   pytest -n 4 --dist=loadfile  # Keep same-file tests together

Each worker (``gw0``, ``gw1``, etc.) is a separate Python process with its own
memory space. Session-scoped fixtures are **per-worker**, not global.


The Problem: Session Scope with xdist
=====================================

Without xdist, ``scope="session"`` means "once per pytest run":

.. code-block:: python

   @pytest.fixture(scope="session")
   def compiled_design():
       print("Compiling...")  # Prints once
       return compile_hdl()

With xdist and 4 workers, this prints **4 times** — each worker has its own
session.

For expensive operations like HDL compilation, we need coordination between
workers.


tmp_path_factory: The Coordination Point
========================================

``tmp_path_factory`` is a built-in pytest fixture that creates temporary
directories. The key insight is how xdist handles it:

.. code-block:: text

   Without xdist:
     getbasetemp() = /tmp/pytest-of-user/pytest-123/

   With xdist (4 workers):
     Worker gw0: getbasetemp() = /tmp/pytest-of-user/pytest-123/worker-gw0/
     Worker gw1: getbasetemp() = /tmp/pytest-of-user/pytest-123/worker-gw1/
     Worker gw2: getbasetemp() = /tmp/pytest-of-user/pytest-123/worker-gw2/
     Worker gw3: getbasetemp() = /tmp/pytest-of-user/pytest-123/worker-gw3/

The **parent** directory is shared across all workers:

.. code-block:: python

   @pytest.fixture(scope="session")
   def shared_dir(tmp_path_factory):
       # Worker-specific
       worker_dir = tmp_path_factory.getbasetemp()
       # e.g., /tmp/pytest-of-user/pytest-123/worker-gw0/

       # Shared across ALL workers
       shared = worker_dir.parent
       # e.g., /tmp/pytest-of-user/pytest-123/

       return shared

Without xdist, ``.parent`` just goes one level up harmlessly — it still works.


Pattern: Coordinated One-Time Execution
=======================================

Use the shared directory for lock files so workers coordinate:

.. code-block:: python

   from pytest_cocotb.guard import CallOnce

   @pytest.fixture(scope="session")
   def compiled_design(tmp_path_factory):
       shared = tmp_path_factory.getbasetemp().parent
       build_dir = shared / "hdl_build"
       build_dir.mkdir(exist_ok=True)

       # Only ONE worker compiles; others wait then reuse
       CallOnce(
           path=build_dir,
           name="hdl_compile",
           fn=lambda: compile_hdl(build_dir),
       ).ensure_done()

       return build_dir

Timeline with 4 workers:

.. code-block:: text

   Worker 0: CallOnce acquires lock → runs compile_hdl()
   Worker 1: CallOnce blocks on lock...
   Worker 2: CallOnce blocks on lock...
   Worker 3: CallOnce blocks on lock...

   Worker 0: Compilation done → .done marker created → lock released
   Worker 1: Lock acquired → sees .done marker → returns immediately
   Worker 2: Lock acquired → sees .done marker → returns immediately
   Worker 3: Lock acquired → sees .done marker → returns immediately


Pattern: Caching Factory
========================

Combine the factory pattern with xdist-safe caching:

.. code-block:: python

   from pytest_cocotb.guard import CallOnce

   FIRMWARE_ROOT = Path("/path/to/firmware")

   @pytest.fixture(scope="session")
   def firmware_cache(tmp_path_factory):
       """Build firmware once across all workers."""
       shared = tmp_path_factory.getbasetemp().parent
       cache = {}  # Local memo for this worker

       def _get(name: str) -> Path:
           if name not in cache:
               src_dir = FIRMWARE_ROOT / name

               # Coordinate across workers
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
       """Copy firmware to test directory."""
       marker = request.node.get_closest_marker("firmware")
       if marker:
           vmem = firmware_cache(marker.args[0])
           shutil.copy(vmem, test_session.directory / "firmware.vmem")


The Lambda Capture Trick
========================

When creating lambdas in a loop or with variables that change, capture the
value explicitly:

.. code-block:: python

   # WRONG - all lambdas capture the same reference
   for name in ["a", "b", "c"]:
       fn = lambda: build(name)  # All will use name="c"!

   # CORRECT - capture value at definition time
   for name in ["a", "b", "c"]:
       fn = lambda n=name: build(n)  # Each captures its own value

In the firmware factory:

.. code-block:: python

   def _get(name: str) -> Path:
       CallOnce(
           path=shared,
           name=f"firmware_{name}",
           # Capture src_dir's VALUE, not reference
           fn=lambda src=src_dir: subprocess.run(["make"], cwd=src, check=True),
       ).ensure_done()


Worker ID Detection
===================

Sometimes you need to know which worker you're on:

.. code-block:: python

   @pytest.fixture(scope="session")
   def worker_id(request):
       """Return xdist worker id, or 'master' if not using xdist."""
       if hasattr(request.config, "workerinput"):
           return request.config.workerinput["workerid"]
       return "master"

   @pytest.fixture(scope="session")
   def is_xdist_master(worker_id):
       """True if this is the master worker (or not using xdist)."""
       return worker_id in ("master", "gw0")


Distributing Tests
==================

xdist supports different distribution modes:

.. code-block:: bash

   pytest -n 4                    # Load balance across workers
   pytest -n 4 --dist=loadfile    # Keep same-file tests on same worker
   pytest -n 4 --dist=loadscope   # Keep same-scope tests together

For HDL tests, ``--dist=loadfile`` often makes sense — tests in the same file
likely share setup and can reuse the same compiled design.


Common Pitfalls
===============

Fixture Assumes Single Process
------------------------------

.. code-block:: python

   # BROKEN with xdist - global variable not shared between workers
   _compiled = None

   @pytest.fixture(scope="session")
   def compiled_design():
       global _compiled
       if _compiled is None:
           _compiled = compile_hdl()  # Each worker compiles!
       return _compiled

   # FIXED - use file-based coordination
   @pytest.fixture(scope="session")
   def compiled_design(tmp_path_factory):
       shared = tmp_path_factory.getbasetemp().parent
       CallOnce(path=shared, name="compile", fn=compile_hdl).ensure_done()
       return shared / "build"


Race Condition on Shared Files
------------------------------

.. code-block:: python

   # BROKEN - multiple workers may write simultaneously
   @pytest.fixture(scope="session")
   def shared_config(tmp_path_factory):
       shared = tmp_path_factory.getbasetemp().parent
       config = shared / "config.json"
       config.write_text('{"debug": true}')  # Race condition!
       return config

   # FIXED - use CallOnce
   @pytest.fixture(scope="session")
   def shared_config(tmp_path_factory):
       shared = tmp_path_factory.getbasetemp().parent
       config = shared / "config.json"

       CallOnce(
           path=shared,
           name="write_config",
           fn=lambda: config.write_text('{"debug": true}'),
       ).ensure_done()

       return config
