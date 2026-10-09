// Desktop widgets — free-floating layer-shell surfaces owned by the shell.
//
// Config is read from the Qt bar's own `widgets` block (data/Widgets.qml);
// all seven widgets are implemented (Clock / Resources / Disk / Network /
// Weather / Visualizer / SysInfo).
import QtQuick
import Quickshell
import "../data"
import "widgets"

Scope {
    ClockWidget {
        visible: Widgets.active("clock")
        block: Widgets.block("clock")
    }
    ResourcesWidget {
        visible: Widgets.active("resources")
        block: Widgets.block("resources")
    }
    DiskWidget {
        visible: Widgets.active("disk")
        block: Widgets.block("disk")
    }
    NetworkWidget {
        visible: Widgets.active("network")
        block: Widgets.block("network")
    }
    WeatherWidget {
        visible: Widgets.active("weather")
        block: Widgets.block("weather")
    }
    SysInfoWidget {
        visible: Widgets.active("sysinfo")
        block: Widgets.block("sysinfo")
    }
    VisualizerWidget {
        visible: Widgets.active("visualizer")
        block: Widgets.block("visualizer")
    }
}
