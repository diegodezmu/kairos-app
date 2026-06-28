# dmgbuild settings for the Kairos installer DMG.
# Invoked by scripts/release-dmg.sh as:
#   dmgbuild -s scripts/dmg-settings.py -D app=<Kairos.app> -D bg=<background.tiff> Kairos <out.dmg>
#
# Layout matches the Figma "Drag to install" frame: app on the left, the
# Applications drop target on the right, both at the height of the arrow.

import os.path

application = defines["app"]
appname = os.path.basename(application)

# Disk image
format = defines.get("format", "UDZO")

# Contents
files = [application]
symlinks = {"Applications": "/Applications"}

# Window / icon-view styling
background = defines["bg"]
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
icon_locations = {
    appname: (120, 185),
    "Applications": (540, 185),
}
