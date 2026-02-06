########
Fixtures
########

Pytest fixtures provide dependency injection for tests. This page covers
patterns particularly useful for HDL verification.


Fixture Basics
==============

A fixture is a function decorated with ``@pytest.fixture`` that provides
a value to tests:

.. code-block:: python

   @pytest.fixture
   def clock_period():
       return 10  # ns

   def test_timing(clock_period):
       assert clock_period == 10

Pytest automatically calls ``clock_period()`` and passes the result to any
test that requests it by name.


Fixture Scope
=============

Scope controls how often a fixture is created:

.. list-table::
   :header-rows: 1
   :widths: 20 80

   * - Scope
     - Lifetime
   * - ``function`` (default)
     - Created fresh for each test function
   * - ``class``
     - Shared across all tests in a class
   * - ``module``
     - Shared across all tests in a module (.py file)
   * - ``session``
     - Created once per pytest invocation

For HDL verification, ``session`` scope is common for expensive operations
like compiling the design:

.. code-block:: python

   @pytest.fixture(scope="session")
   def compiled_design(tmp_path_factory):
       """Compile HDL once, share across all tests."""
       build_dir = tmp_path_factory.mktemp("build")
       # ... expensive compilation ...
       return build_dir


Factory Fixtures
================

A factory fixture returns a *function* rather than a value. This allows:

1. Deferred execution until the test actually needs it
2. Parameterised creation with test-specific arguments
3. Multiple calls with different parameters

Basic Factory
-------------

.. code-block:: python

   @pytest.fixture
   def make_packet():
       """Factory for creating test packets."""
       def _make(size: int, payload: bytes = b"") -> Packet:
           return Packet(
               header=Header(size=size),
               payload=payload or bytes(size),
           )
       return _make

   def test_small_packet(make_packet):
       pkt = make_packet(64)
       assert len(pkt.payload) == 64

   def test_large_packet(make_packet):
       pkt = make_packet(1500, payload=b"\xff" * 1500)
       assert pkt.payload == b"\xff" * 1500


Caching Factory
---------------

Combine factory pattern with memoisation for expensive operations:

.. code-block:: python

   @pytest.fixture(scope="session")
   def firmware_cache(tmp_path_factory):
       """Build firmware once per name, cache result."""
       base = tmp_path_factory.getbasetemp()
       cache = {}

       def _get(name: str) -> Path:
           if name not in cache:
               src_dir = FIRMWARE_ROOT / name
               subprocess.run(["make"], cwd=src_dir, check=True)
               cache[name] = src_dir / f"{name}.vmem"
           return cache[name]

       return _get

   def test_boot(firmware_cache, test_session):
       vmem = firmware_cache("hello")
       shutil.copy(vmem, test_session.directory / "firmware.vmem")
       test_session.run(testcase="test_boot")

   def test_uart(firmware_cache, test_session):
       vmem = firmware_cache("uart_echo")  # Different firmware
       shutil.copy(vmem, test_session.directory / "firmware.vmem")
       test_session.run(testcase="test_uart")


Why Factory Over Direct Value?
------------------------------

Consider the difference:

.. code-block:: python

   # Direct value - firmware always built, even if test doesn't need it
   @pytest.fixture
   def firmware():
       subprocess.run(["make"], cwd=FW_DIR, check=True)
       return FW_DIR / "firmware.vmem"

   # Factory - firmware only built when _get() is called
   @pytest.fixture
   def firmware_factory():
       def _get():
           subprocess.run(["make"], cwd=FW_DIR, check=True)
           return FW_DIR / "firmware.vmem"
       return _get

The factory pattern is essential when:

- The fixture is session-scoped but not all tests need it
- Different tests need different variants (e.g., different firmware)
- You want to control *when* the expensive operation happens


Fixture Composition
===================

Fixtures can depend on other fixtures:

.. code-block:: python

   @pytest.fixture(scope="session")
   def build_dir(tmp_path_factory):
       return tmp_path_factory.mktemp("build")

   @pytest.fixture(scope="session")
   def compiled_rtl(build_dir):
       """Depends on build_dir fixture."""
       runner = get_runner("verilator")
       runner.build(
           sources=[...],
           build_dir=build_dir,
       )
       return runner

   @pytest.fixture
   def test_session(compiled_rtl, tmp_path):
       """Depends on compiled_rtl and tmp_path."""
       return TestSession(
           runner=compiled_rtl,
           directory=tmp_path,
       )

Pytest resolves the dependency graph automatically. In this example,
``test_session`` triggers ``compiled_rtl``, which triggers ``build_dir``.


Yield Fixtures (Setup/Teardown)
===============================

Use ``yield`` to run cleanup after the test:

.. code-block:: python

   @pytest.fixture
   def temp_config(tmp_path):
       """Create config file, clean up after test."""
       config_file = tmp_path / "config.yaml"
       config_file.write_text("debug: true")

       yield config_file  # Test runs here

       # Cleanup (runs even if test fails)
       config_file.unlink(missing_ok=True)


Request Object
==============

The special ``request`` fixture provides test metadata:

.. code-block:: python

   @pytest.fixture
   def test_dir(request, tmp_path_factory):
       """Create directory named after the test."""
       # request.node.name = "test_uart_tx"
       safe_name = request.node.name.replace("[", "_").replace("]", "")
       return tmp_path_factory.mktemp(safe_name)

   @pytest.fixture
   def firmware(request, firmware_cache, test_session):
       """Read firmware name from test marker."""
       marker = request.node.get_closest_marker("firmware")
       if marker:
           name = marker.args[0]
           vmem = firmware_cache(name)
           shutil.copy(vmem, test_session.directory / "firmware.vmem")

Useful ``request`` attributes:

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - Attribute
     - Description
   * - ``request.node``
     - The test item (has ``.name``, ``.nodeid``, markers)
   * - ``request.config``
     - Pytest config (command-line options, ini settings)
   * - ``request.module``
     - The test module object
   * - ``request.fspath``
     - Path to the test file


Markers for Fixture Configuration
=================================

Use markers to pass data to fixtures:

.. code-block:: python

   # conftest.py
   def pytest_configure(config):
       config.addinivalue_line(
           "markers",
           "firmware(name): specify firmware to load"
       )

   @pytest.fixture
   def firmware(request, firmware_cache, test_session):
       marker = request.node.get_closest_marker("firmware")
       if marker is None:
           return None

       name = marker.args[0]
       vmem = firmware_cache(name)
       shutil.copy(vmem, test_session.directory / "firmware.vmem")
       return vmem

   # test_core.py
   @pytest.mark.firmware("hello")
   def test_boot(test_session, firmware):
       test_session.run(testcase="test_boot_heartbeat")

   @pytest.mark.firmware("uart_echo")
   def test_uart(test_session, firmware):
       test_session.run(testcase="test_uart_tx")
