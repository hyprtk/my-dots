import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw

from .app import ThemeGuiApp


def main():
    app = ThemeGuiApp()
    app.run(sys.argv)


if __name__ == "__main__":
    main()
