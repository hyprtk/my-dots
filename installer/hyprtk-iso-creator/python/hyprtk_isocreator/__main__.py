"""``python -m hyprtk_isocreator`` — launch the Qt app in place."""

import sys

from .gui import main

if __name__ == "__main__":
    sys.exit(main())
