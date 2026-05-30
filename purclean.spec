Name:           purclean
Version:        0.1.0
Release:        1%{?dist}
Summary:        Disk cleaning utility for Fedora Linux

License:        GPL-3.0-or-later
URL:            https://github.com/byoval/purclean
Source0:        https://github.com/byoval/purclean/archive/refs/tags/v%{version}.tar.gz

BuildRequires:  meson >= 0.60.0
BuildRequires:  vala
BuildRequires:  gcc
BuildRequires:  pkgconfig(gtk4)
BuildRequires:  pkgconfig(libadwaita-1)
BuildRequires:  pkgconfig(gio-2.0)
BuildRequires:  pkgconfig(cairo)
BuildRequires:  gettext
BuildRequires:  python3

Requires:       polkit
Requires:       gtk4
Requires:       libadwaita

%description
Purclean is a GTK4 application for cleaning disk space on Fedora Linux.
It removes old kernels, DNF cache, Flatpak leftovers, systemd journal
logs, orphaned packages, browser caches, and duplicate files.

%prep
%autosetup

%build
%meson
%meson_build

%install
%meson_install
%find_lang %{name}

%files -f %{name}.lang
%license COPYING
%{_bindir}/purclean
%{_datadir}/applications/com.github.byoval.purclean.desktop
%{_datadir}/metainfo/com.github.byoval.purclean.metainfo.xml
%{_datadir}/glib-2.0/schemas/com.github.byoval.purclean.gschema.xml
%{_datadir}/icons/hicolor/256x256/apps/com.github.byoval.purclean.png
%{_datadir}/polkit-1/actions/com.github.byoval.purclean.policy

%changelog
* Sat May 30 2026 Nikita <byoval> - 0.1.0-1
- Initial package
