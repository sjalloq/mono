# Configuration file for the Sphinx documentation builder.

project = 'Mono'
copyright = '2026'
author = 'Shareef Jalloq'

extensions = [
    'sphinx.ext.autodoc',
    'sphinx.ext.viewcode',
    'sphinx.ext.todo',
]

templates_path = ['_templates']
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']

html_theme = 'alabaster'
html_static_path = ['_static']

# Todo extension settings
todo_include_todos = True
