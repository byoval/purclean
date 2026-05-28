#!/usr/bin/env python3

import os
import subprocess

prefix    = os.environ.get('MESON_INSTALL_PREFIX', '/usr')
schemadir = os.path.join(prefix, 'share', 'glib-2.0', 'schemas')

if os.path.exists(schemadir):
    print('Compiling GSettings schemas...')
    subprocess.call(['glib-compile-schemas', schemadir])
