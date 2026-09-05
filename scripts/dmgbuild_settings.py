from pathlib import Path


root = Path(defines["root_dir"]).resolve()
app_path = Path(defines["app_path"]).resolve()

volume_name = defines.get("volume_name", "2分にしてね - Mitene Video Converter")
format = "UDZO"
filesystem = "HFS+"
files = [(str(app_path), "2分にしてね.app")]
symlinks = {"Applications": "/Applications"}
icon_path = root / "Resources" / "AppIcon.icns"
if icon_path.exists():
    icon = str(icon_path)
    badge_icon = str(icon_path)
background = str(root / "assets" / "dmg-background.png")
hide = [".background.png"]
hide_extensions = ["2分にしてね.app"]
window_rect = ((20, 120), (840, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 100
text_size = 16
label_pos = "bottom"
arrange_by = None
icon_locations = {
    "2分にしてね.app": (180, 140),
    "Applications": (480, 140),
}
