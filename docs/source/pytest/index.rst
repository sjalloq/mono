######
Pytest
######

Pytest patterns and fixtures for HDL verification with cocotb.

This section documents pytest infrastructure used across the mono repository,
with particular focus on patterns that enable:

- Parallel test execution with pytest-xdist
- NFS-safe resource sharing across compute nodes
- Efficient firmware compilation caching
- Clean fixture composition

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   fixtures
   xdist
   nfs_locking
   firmware


Quick Reference
===============

Factory Fixture Pattern
-----------------------

Return a function from a fixture to defer execution or allow parameterisation:

.. code-block:: python

   @pytest.fixture(scope="session")
   def firmware_cache(tmp_path_factory):
       cache = {}

       def _get(name):
           if name not in cache:
               # Build firmware...
               cache[name] = result
           return cache[name]

       return _get  # Return the function

   def test_boot(firmware_cache):
       fw = firmware_cache("hello")  # Call the returned function


xdist Worker Coordination
-------------------------

Use ``tmp_path_factory.getbasetemp().parent`` to get a directory shared across
all xdist workers:

.. code-block:: python

   @pytest.fixture(scope="session")
   def shared_resource(tmp_path_factory):
       # Shared across ALL workers
       base = tmp_path_factory.getbasetemp().parent
       lock_dir = base / ".locks"
       lock_dir.mkdir(exist_ok=True)
       # ...


NFS-Safe Locking
----------------

Use ``mkdir`` atomicity instead of ``flock`` for NFS filesystems:

.. code-block:: python

   from pytest_cocotb.nfs_lock import NFSLock
   from pytest_cocotb.guard import CallOnce

   # Ensure something runs exactly once across all workers/nodes
   CallOnce(
       path=build_dir,
       name="compile_hdl",
       fn=lambda: runner.build(...),
   ).ensure_done()
