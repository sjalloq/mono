# Configuration file for the Sphinx documentation builder.

import os

project = 'Mono'
copyright = '2026'
author = 'Shareef Jalloq'

extensions = [
    'sphinx.ext.autodoc',
    'sphinx.ext.viewcode',
    'sphinx.ext.todo',
    'sphinx_peakrdl',
]

_repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

peakrdl_input_files = [
    os.path.join(_repo_root, 'hw/ip/usb/uart/rdl/usb_uart_csr.rdl'),
]

templates_path = ['_templates']
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']

html_theme = 'alabaster'
html_static_path = ['_static']

# Todo extension settings
todo_include_todos = True
