# Mascarpone 🧀

**Interactive CLI tool for scaffolding Tiramisu game projects**

Named after the Italian cream cheese used in tiramisu, Mascarpone provides a delightful TUI experience for creating new game projects with the Tiramisu game engine.

## Installation

```bash
gleam add mascarpone
```

## Usage

Run the interactive project creator:

```bash
gleam run -m mascarpone
```

The TUI will guide you through:

1. **Lustre Integration**: Choose whether to include Lustre for UI overlays (menus, HUDs, etc.)
2. **Project Template**: Select from:
   - **2D Game** - Orthographic camera and sprite setup
   - **3D Game** - Perspective camera with lighting
   - **Physics Demo** - Physics-enabled objects

## What It Creates

Mascarpone generates a fully-configured Tiramisu project with:

- `gleam.toml` with all necessary dependencies
- `.gitignore` for Gleam projects
- Main source file with a working game example
- Lustre dev tools configuration (if selected)
- Three.js and Rapier3D CDN imports (via import maps)

## Example

```bash
$ gleam run -m mascarpone

╔═══════════════════════════════════╗
║   🎮 Tiramisu Project Creator 🎮  ║
║   Gleam 3D Game Engine            ║
╚═══════════════════════════════════╝

Welcome to Tiramisu! 🍰

This wizard will help you create a new game project.

Press [Enter] to continue
```

## Features

- 🎨 Beautiful TUI powered by [Shore](https://hexdocs.pm/shore/)
- 🚀 Quick project setup with sensible defaults
- 🎮 Multiple game templates to start from
- 📦 Automatic dependency management
- ⚙️ Configurable options for Lustre UI and Rapier3D physics

## After Creation

Once your project is created, run the dev server:

```bash
gleam run -m lustre/dev start
```

Then open http://localhost:1234 in your browser to see your game!


## License

MIT

## Related

- [Tiramisu](https://github.com/renatillas/tiramisu) - Gleam 3D game engine
- [Shore](https://hexdocs.pm/shore/) - Terminal UI framework for Gleam
