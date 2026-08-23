import Quickshell
import "." as Shell
import "modules/panel" as PanelModule
import "services" as Services

ShellRoot {
    Shell.Theme {
        id: theme
    }

    Services.ClockService {
        id: clockService
    }

    Services.NiriService {
        id: niriService
    }

    PanelModule.Panel {
        theme: theme
        clockService: clockService
        niriService: niriService
        brandingSource: "@sleepyBrandingLogo@"
    }
}
