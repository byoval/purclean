project('purclean', 'vala', 'c',
  version: '0.1.0',
  meson_version: '>= 0.60.0',
  license: 'GPL-3.0-or-later'
)

gnome = import('gnome')
i18n  = import('i18n')

# Generate config.h so that _() / gettext works in Vala-generated C code
conf = configuration_data()
conf.set_quoted('GETTEXT_PACKAGE', meson.project_name())
conf.set_quoted('VERSION', meson.project_version())
configure_file(output: 'config.h', configuration: conf)
add_project_arguments('-include', 'config.h', language: 'c')

# Generate config.vala — exposes GETTEXT_PACKAGE, LOCALEDIR, APP_VERSION
# as proper Vala string constants (C macros are not visible to Vala directly)
localedir   = get_option('prefix') / get_option('localedir')
conf_vala   = configuration_data()
conf_vala.set('GETTEXT_PACKAGE', meson.project_name())
conf_vala.set('LOCALEDIR',       localedir)
conf_vala.set('APP_VERSION',     meson.project_version())
config_vala = configure_file(
  input:         'src/config.vala.in',
  output:        'config.vala',
  configuration: conf_vala,
)

dependencies = [
  dependency('gtk4'),
  dependency('libadwaita-1'),
  dependency('gio-2.0'),
  dependency('cairo'),
]

sources = files(
  'src/purclean.vala',
  'src/window.vala',
  'src/cleaner.vala',
  'src/utils.vala',
  'src/settings.vala',
  'src/history.vala',
) + [config_vala]

resources = gnome.compile_resources(
  'purclean-resources',
  'data/purclean.gresource.xml',
  source_dir: 'data'
)

executable('purclean',
  sources + resources,
  dependencies: dependencies,
  install: true,
)

# GSettings schema
install_data(
  'data/com.github.byoval.purclean.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

install_data(
  'data/purclean.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data(
  'data/com.github.byoval.purclean.metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo'
)

install_data(
  'data/com.github.byoval.purclean.policy',
  install_dir: get_option('datadir') / 'polkit-1/actions'
)

# Application icon
install_data(
  'data/icons/com.github.byoval.purclean.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)

# Flatpak manifest (not installed — just kept alongside source for reference)
# Build with: flatpak-builder build-dir com.github.byoval.purclean.yml --force-clean

# Translations
subdir('po')

# Post-install: compile schemas, update icon cache, update desktop db
gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)

meson.add_install_script('data/meson_post_install.py')
