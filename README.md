# CaddieTools

Window tiling, title-bar fixes, and mouse tweaks for macOS, written as
[Hammerspoon](https://www.hammerspoon.org) Spoons. One call in your Hammerspoon
config loads the ones you want.

```lua
dofile(hs.configdir .. "/CaddieTools/Spoons/CaddieTools.spoon/init.lua").use({
  "AutoReload", "TileManager", "TitleBarTweaks", "EdgeSnap", "MouseTweaks",
})
```

It's all Lua. Nothing is compiled and nothing else has to be installed, with one
exception noted under [SidecarUSB](#sidecarusb).

## What's in it

| Spoon | What it does |
|---|---|
| TileManager | Tiles the focused window from the keyboard: halves, quarters, thirds, two thirds, and maximize. Pressing a tile again sends the window to the next monitor. |
| TitleBarTweaks | The green button and a double-click on the title bar maximize a window, and restore it to the size it had before when clicked again. Option-click still enters full screen. |
| EdgeSnap | Drag a window to a screen edge or corner to tile it. A preview shows where it will go, and a small panel beside the cursor offers the other placements for that edge. |
| MouseTweaks | Reverses the scroll direction of a mouse wheel and leaves trackpads on Natural Scrolling. Wheel notches glide instead of jumping. |
| AutoReload | Reloads Hammerspoon when you save a Lua file, and skips the reload while any file has a syntax error. |
| SidecarUSB | Starts Sidecar when an iPad is plugged in by USB and ends it on unplug. Needs [sidecarctl](https://github.com/tsilenzio/sidecarctl). |

CaddieCore, the runtime they share, loads by itself. However a window gets
placed, by hotkey, green button, or edge drag, the same memory applies, so a
window you tiled with the keyboard restores with the green button and
Ctrl+Opt+Cmd+Z undoes any of them.

## Requirements

Hammerspoon, with Accessibility access granted in System Settings > Privacy &
Security. Developed on macOS 27.0 with Hammerspoon 1.1.1, and untested on
anything older.

## Install

Clone the repository into your Hammerspoon config directory:

```sh
git clone https://github.com/tsilenzio/caddietools.git ~/.hammerspoon/CaddieTools
```

Then add this to `~/.hammerspoon/init.lua`, listing the Spoons you want:

```lua
dofile(hs.configdir .. "/CaddieTools/Spoons/CaddieTools.spoon/init.lua").use({
  "AutoReload", "TileManager", "TitleBarTweaks", "EdgeSnap", "MouseTweaks",
})
```

Reload Hammerspoon. With AutoReload in the list, an alert says the config
loaded.

There's a sixth Spoon, SidecarUSB, which starts Sidecar when you plug in an
iPad. It needs an external tool installed first, so it has
[its own section](#sidecarusb).

The clone can live anywhere. Point the line at it:

```lua
dofile("/path/to/clone/Spoons/CaddieTools.spoon/init.lua").use({
  "TileManager", "EdgeSnap",
})
```

### As regular Spoons

If you'd rather load them the way other Spoons load, `install.sh` links them into
`~/.hammerspoon/Spoons`:

```sh
./install.sh                 # every Spoon
./install.sh EdgeSnap        # only this one, plus CaddieCore and CaddieTools
./install.sh --uninstall     # remove the links this clone made
```

```lua
hs.loadSpoon("CaddieTools").use({
  "TileManager", "TitleBarTweaks", "EdgeSnap", "MouseTweaks",
})
```

They're links, so `git pull` updates them. The script never overwrites a Spoon
already there under the same name.

## Keyboard shortcuts

All on Ctrl+Opt+Cmd, laid out like Rectangle's.

| Key | Placement |
|---|---|
| Left, Right, Up, Down | That half of the screen |
| Return | Maximize |
| U, I, J, K | Top left, top right, bottom left, bottom right quarter |
| D, F, G | First, center, last third |
| E, R, T | First, center, last two thirds |
| Z | Undo the last placement |

Press the same key again and the window moves to that tile on the next monitor.
Hold Space as well and an arrow moves the window to the next monitor without
changing its layout.

## Settings

A Spoon listed by name gets its defaults, hotkeys included. To change something,
name it with a table instead:

```lua
dofile(hs.configdir .. "/CaddieTools/Spoons/CaddieTools.spoon/init.lua").use({
  "AutoReload", "TitleBarTweaks", "EdgeSnap",
  TileManager = { hotkeys = "default" },
  MouseTweaks = { config = { smooth = { enabled = false } } },
  WindowState = { config = { gap = 4 } },
})
```

`config` sets values on the Spoon before it starts. `hotkeys` takes `"default"`
or your own mapping, and a Spoon named this way binds none unless you ask.
`start = false` loads a Spoon without starting it. Each Spoon's settings are
listed with comments at the top of its `init.lua`.

`WindowState` isn't a Spoon. It's where the placement rules live, shared by
everything that moves a window. Its defaults are in
`Spoons/CaddieCore.spoon/window/defaults.lua`:

| Setting | Default | Effect |
|---|---|---|
| `gap` | 1 | Points between a tiled window and its neighbors. Sides against the screen edge get none. |
| `minSize` | 400 × 300 | A tile smaller than this isn't applied. |
| `excluded` | System Settings | Apps whose windows are never placed. |
| `centerSmall` | Calculator, 80% | Apps that take a fraction of their tile, centered in it. |
| `presets` | Terminal, 60% × 70% | Apps that maximize to a fraction of the screen. |

Edit that file to change them for every config, or override one in `use()` as
above.

## Notes on individual Spoons

### EdgeSnap

Turn off macOS's own edge tiling under System Settings > Desktop & Dock, or both
will act on the same drag.

### SidecarUSB

SidecarUSB depends on an external command line tool,
[sidecarctl](https://github.com/tsilenzio/sidecarctl), since macOS has no public
way to start Sidecar. Install it with Homebrew:

```sh
brew install tsilenzio/tap/sidecarctl
```

Then add `"SidecarUSB"` to your list:

```lua
dofile(hs.configdir .. "/CaddieTools/Spoons/CaddieTools.spoon/init.lua").use({
  "AutoReload", "TileManager", "TitleBarTweaks", "EdgeSnap", "MouseTweaks",
  "SidecarUSB",
})
```

Plug an iPad in by USB and Sidecar starts over the cable. Unplug it and Sidecar
ends. Without sidecarctl installed, SidecarUSB shows an alert each time the
config loads and stays off. The rest of your config loads as usual.

### AutoReload

Watches your Hammerspoon config directory, and the clone too when it lives
somewhere else. A file with a syntax error leaves the running config alone, and
the next save tries again.

## Tests

The tests run against a stub of Hammerspoon's API, so they need only `lua`:

```sh
for f in test/test_*.lua; do lua "$f"; done
```

Each suite ends with `ALL PASS`.

## License

MIT. See [LICENSE](LICENSE).
