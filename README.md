# Mascarpone 🧀

**Interactive CLI tool for scaffolding Tiramisu game projects**

Named after the Italian cream cheese used in tiramisu, Mascarpone provides a delightful TUI experience for creating new game projects with the Tiramisu game engine.

## Installation

```bash
gleam add --dev mascarpone
```

## Usage

Run the interactive project creator:

```bash
gleam run -m mascarpone
```

The TUI will guide you through:

1. **Lustre Integration**: Choose whether to include Lustre for UI overlays (menus, HUDs, etc.)
2. **Project Template** (Optional): Select from:
   - **2D Game** - Orthographic camera and sprite setup
   - **3D Game** - Perspective camera with lighting
   - **Physics Demo** - Physics-enabled objects
   - **Skip** - Don't create template files (for existing projects)
3. **Desktop Bundle**: Set up NW.js for desktop distribution

## What It Creates

Mascarpone sets up your Tiramisu project with:

- Lustre dev tools installed to `priv/<project-name>/` with bundled Bun runtime
- `gleam.toml` with all necessary dependencies (tiramisu, vec, lustre_dev_tools, optionally lustre)
- `.gitignore` for Gleam projects
- `package.json` and `node_modules/` with Three.js and Rapier3D installed via Bun
- Main source file with a working game example (if template selected)
- Lustre dev tools configuration with Three.js and Rapier3D import maps


## Features

- 🎨 Beautiful TUI powered by [Shore](https://hexdocs.pm/shore/)
- 🚀 Quick project setup with sensible defaults
- 🎮 Multiple game templates to start from (optional)
- 📦 Automatic dependency management via `gleam add`
- 🖥️ Desktop bundling with NW.js for cross-platform distribution
- ⚙️ Configurable options for Lustre UI and Rapier3D physics
- ♻️ Can be run on existing projects to add NW.js support

## Bun Configuration

By default, Mascarpone will:
1. First try to use bun from your system PATH
2. If not found, download a bundled bun via lustre_dev_tools

You can override this behavior in your `gleam.toml`:

```toml
[tools.lustre.bin]
bun = "system"  # Force using system bun (will error if not found)
# OR
bun = "/path/to/custom/bun"  # Use specific bun executable
```

When a custom bun path is configured, Mascarpone will skip downloading bun entirely.

## After Creation

### For Web Development

Run the dev server:

```bash
gleam run -m lustre/dev start
```

Then open http://localhost:1234 in your browser to see your game!

### For Desktop Development (if NW.js bundling was selected)

#### Building Desktop Distributions

If you set up NW.js bundling during project creation, you can build platform-specific distributions with a single command:

```bash
gleam run -m mascarpone bundle
```

This command:
- Uses the Bun runtime from lustre-dev-tools
- Runs `bun run build` which executes the build script in your `package.json`
- Compiles your Gleam code with `gleam build`
- Creates platform distributions with `nwbuild`

The built distributions will be available in the directory specified in your `package.json` (typically `../<project-name>_build/`).

## Using Mascarpone with Existing Projects

⚠️ **Important**: If you're adding NW.js support to an existing project, make sure to **skip the template selection** when prompted. Selecting a template will overwrite your existing game code in `src/`!


## License

MIT

## Related

- [Tiramisu](https://github.com/renatillas/tiramisu) - Gleam 3D game engine
- [Shore](https://hexdocs.pm/shore/) - Terminal UI framework for Gleam
- [NW.js](https://nwjs.io/) - Terminal UI framework for Gleam
- [nwbuilder](https://github.com/nwutils/nw-builder) - Terminal UI framework for Gleam
