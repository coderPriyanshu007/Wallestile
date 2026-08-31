

# CustomWallpaper

A fullscreen Quickshell wallpaper browser for Hyprland/Caelestia with Grid,
Carousel, and 3D Ring layouts. It searches Wallhaven and MoeWalls, downloads only
the selected image to `$XDG_DATA_HOME/custom-wallpaper`, then applies it through
Caelestia. The selected wallpaper survives logout and reboot. Applying another
wallpaper deletes the previous original first, so the gallery always keeps exactly
one full-resolution wallpaper instead of growing an archive.

Provider filters include Latest and Toplist for Wallhaven, plus Latest, Anime,
Games, and Landscape for MoeWalls. Applying routes through the running Caelestia
shell's native `wallpaper set` IPC service so its live
wallpaper and colour singletons update exactly like Caelestia's own selector. The
CLI is retained as a fallback when the shell is unavailable. MoeWalls blocks Qt
image hotlinking, so its small browse previews
are fetched with the provider helper into `$XDG_RUNTIME_DIR/custom-wallpaper-thumbnails`;
that temporary preview cache disappears at logout or reboot.

## Install

On Arch Linux or CachyOS, clone/download this directory and run:

```sh
chmod +x install.sh
./install.sh
```

The installer checks Python, Hyprland, Quickshell, and `caelestia-cli`; offers to
install missing packages; copies the module; validates it; safely adds managed
Super+B and blur rules; backs up the edited config; and reloads Hyprland. Running
it again updates the installation without duplicating configuration blocks.

To uninstall while retaining the active wallpaper file:

```sh
~/.config/quickshell/CustomWallpaper/uninstall.sh
```

Add `--purge` to also delete the retained wallpaper.

Run it directly:

```sh
qs -c CustomWallpaper
```

Controls: arrow keys navigate, Enter applies, Escape closes, and double-clicking
a card applies it. Add this Hyprland bind to open it with Super+B:

```lua
hl.bind("SUPER + B", hl.dsp.exec_cmd("qs -c CustomWallpaper"))
```

For real background blur, add a layer rule for the `custom-wallpaper` namespace:

```lua
hl.rule("blur", { "layer", "custom-wallpaper" })
```

MoeWalls does not offer a public API. Its provider uses the public search page
and applies the available static preview image; Wallhaven supplies full-resolution
files through its API.
