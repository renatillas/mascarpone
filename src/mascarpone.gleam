import filepath
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import operating_system
import shellout
import shore
import shore/key
import shore/style
import shore/ui
import simplifile
import snag.{type Result as SnagResult}
import tom

pub fn main() {
  let exit = process.new_subject()

  case get_project_name() {
    Ok(project_name) -> {
      let assert Ok(_actor) =
        shore.spec(
          init: fn() { init(project_name) },
          update: update,
          view: view,
          exit: exit,
          keybinds: shore.default_keybinds(),
          redraw: shore.on_update(),
        )
        |> shore.start

      exit |> process.receive_forever
    }
    Error(err) -> {
      io.println_error("\n❌ Error: " <> snag.pretty_print(err))
    }
  }
}

// Model types

type Step {
  Welcome
  LustreChoice
  TemplateChoice
  DesktopBundleChoice
  Generating(List(GenerationStep))
  Complete
  Failed(String)
}

type GenerationStep {
  StepPending(String)
  StepInProgress(String)
  StepComplete(String)
  StepFailed(String, String)
}

type Template {
  TwoDGame
  ThreeDGame
  PhysicsDemo
}

type Model {
  Model(
    step: Step,
    project_name: String,
    include_lustre: Bool,
    include_physics: Bool,
    template: option.Option(Template),
    bundle_desktop: Bool,
  )
}

type Msg {
  NextStep
  SetLustre(Bool)
  SetTemplate(Template)
  SkipTemplate
  SetDesktopBundle(Bool)
  StartGeneration
  InstallLustreDevTools
  UpdateGleamToml
  InstallNpmPackages
  CreateGitignore
  CreateMainFile
  DetectPlatform(Platform)
  DownloadNwjsSdk(Platform)
  SetupDesktopBundle
  GenerationComplete
  GenerationFailed(String)
}

// Shore Application

fn init(project_name: String) -> #(Model, List(fn() -> Msg)) {
  #(
    Model(
      step: Welcome,
      project_name: project_name,
      include_lustre: True,
      include_physics: False,
      template: None,
      bundle_desktop: False,
    ),
    [],
  )
}

fn update(model: Model, msg: Msg) -> #(Model, List(fn() -> Msg)) {
  case msg {
    NextStep -> {
      let next_step = case model.step {
        Welcome -> LustreChoice
        LustreChoice -> TemplateChoice
        TemplateChoice -> DesktopBundleChoice
        DesktopBundleChoice -> Complete
        Generating(_) -> Complete
        Complete -> Complete
        Failed(_) -> Complete
      }

      #(Model(..model, step: next_step), [])
    }

    SetLustre(value) -> {
      #(Model(..model, include_lustre: value, step: TemplateChoice), [])
    }

    SetTemplate(template) -> {
      #(Model(..model, template: Some(template), step: DesktopBundleChoice), [])
    }

    SkipTemplate -> {
      #(Model(..model, template: None, step: DesktopBundleChoice), [])
    }

    SetDesktopBundle(value) -> {
      let updated_model = Model(..model, bundle_desktop: value)
      let steps = generate_steps_list(updated_model)
      #(Model(..updated_model, step: Generating(steps)), [
        fn() { StartGeneration },
      ])
    }

    StartGeneration -> #(model, [fn() { UpdateGleamToml }])

    InstallLustreDevTools -> {
      let updated_model =
        update_step_status(
          model,
          "Installing Lustre dev tools",
          StatusInProgress,
        )
      case install_lustre_dev_tools() {
        Ok(_) -> #(
          update_step_status(
            updated_model,
            "Installing Lustre dev tools",
            StatusComplete,
          ),
          [fn() { InstallNpmPackages }],
        )
        Error(err) -> #(
          update_step_status(
            updated_model,
            "Installing Lustre dev tools",
            StatusFailed(snag.pretty_print(err)),
          ),
          [fn() { GenerationFailed(snag.pretty_print(err)) }],
        )
      }
    }

    UpdateGleamToml -> {
      let updated_model =
        update_step_status(model, "Updating gleam.toml", StatusInProgress)
      case update_gleam_toml(model.project_name, model.include_lustre) {
        Ok(_) -> #(
          update_step_status(
            updated_model,
            "Updating gleam.toml",
            StatusComplete,
          ),
          [fn() { InstallLustreDevTools }],
        )
        Error(err) -> #(
          update_step_status(
            updated_model,
            "Updating gleam.toml",
            StatusFailed(snag.pretty_print(err)),
          ),
          [fn() { GenerationFailed(snag.pretty_print(err)) }],
        )
      }
    }

    InstallNpmPackages -> {
      let updated_model =
        update_step_status(
          model,
          "Installing Three.js and Rapier3D",
          StatusInProgress,
        )
      case install_npm_packages() {
        Ok(_) -> #(
          update_step_status(
            updated_model,
            "Installing Three.js and Rapier3D",
            StatusComplete,
          ),
          [fn() { CreateGitignore }],
        )
        Error(err) -> #(
          update_step_status(
            updated_model,
            "Installing Three.js and Rapier3D",
            StatusFailed(snag.pretty_print(err)),
          ),
          [fn() { GenerationFailed(snag.pretty_print(err)) }],
        )
      }
    }

    CreateGitignore -> {
      let updated_model =
        update_step_status(model, "Creating .gitignore", StatusInProgress)
      case create_gitignore() {
        Ok(_) -> {
          let next_msg = case model.template {
            Some(_) -> fn() { CreateMainFile }
            None ->
              case model.bundle_desktop {
                True ->
                  case detect_platform() {
                    Ok(platform) -> fn() { DetectPlatform(platform) }
                    Error(_) -> fn() { GenerationComplete }
                  }
                False -> fn() { GenerationComplete }
              }
          }
          #(
            update_step_status(
              updated_model,
              "Creating .gitignore",
              StatusComplete,
            ),
            [next_msg],
          )
        }
        Error(err) -> #(
          update_step_status(
            updated_model,
            "Creating .gitignore",
            StatusFailed(snag.pretty_print(err)),
          ),
          [fn() { GenerationFailed(snag.pretty_print(err)) }],
        )
      }
    }

    CreateMainFile -> {
      let updated_model =
        update_step_status(model, "Creating main game file", StatusInProgress)
      case
        create_main_file(
          model.project_name,
          option.unwrap(model.template, ThreeDGame),
        )
      {
        Ok(_) ->
          case model.bundle_desktop {
            True -> {
              case detect_platform() {
                Ok(platform) -> #(
                  update_step_status(
                    updated_model,
                    "Creating main game file",
                    StatusComplete,
                  ),
                  [fn() { DetectPlatform(platform) }],
                )
                Error(err) -> #(
                  update_step_status(
                    updated_model,
                    "Creating main game file",
                    StatusFailed(snag.pretty_print(err)),
                  ),
                  [fn() { GenerationFailed(snag.pretty_print(err)) }],
                )
              }
            }
            False -> #(
              update_step_status(
                updated_model,
                "Creating main game file",
                StatusComplete,
              ),
              [fn() { GenerationComplete }],
            )
          }
        Error(err) -> #(
          update_step_status(
            updated_model,
            "Creating main game file",
            StatusFailed(snag.pretty_print(err)),
          ),
          [fn() { GenerationFailed(snag.pretty_print(err)) }],
        )
      }
    }

    DetectPlatform(platform) -> {
      let updated_model =
        update_step_status(model, "Detecting platform", StatusInProgress)
      #(
        update_step_status(updated_model, "Detecting platform", StatusComplete),
        [fn() { DownloadNwjsSdk(platform) }],
      )
    }

    DownloadNwjsSdk(platform) -> {
      let updated_model =
        update_step_status(model, "Downloading NW.js SDK", StatusInProgress)
      case download_nwjs_sdk(platform) {
        Ok(_) -> #(
          update_step_status(
            updated_model,
            "Downloading NW.js SDK",
            StatusComplete,
          ),
          [fn() { SetupDesktopBundle }],
        )
        Error(err) -> #(
          update_step_status(
            updated_model,
            "Downloading NW.js SDK",
            StatusFailed(snag.pretty_print(err)),
          ),
          [fn() { GenerationFailed(snag.pretty_print(err)) }],
        )
      }
    }

    SetupDesktopBundle -> {
      let updated_model =
        update_step_status(
          model,
          "Setting up platform distributions",
          StatusInProgress,
        )
      case setup_desktop_bundle(model.project_name) {
        Ok(_) -> #(
          update_step_status(
            updated_model,
            "Setting up platform distributions",
            StatusComplete,
          ),
          [fn() { GenerationComplete }],
        )
        Error(err) -> #(
          update_step_status(
            updated_model,
            "Setting up platform distributions",
            StatusFailed(snag.pretty_print(err)),
          ),
          [fn() { GenerationFailed(snag.pretty_print(err)) }],
        )
      }
    }

    GenerationComplete -> #(Model(..model, step: Complete), [])

    GenerationFailed(err) -> #(Model(..model, step: Failed(err)), [])
  }
}

type StepStatus {
  StatusPending
  StatusInProgress
  StatusComplete
  StatusFailed(String)
}

fn generate_steps_list(model: Model) -> List(GenerationStep) {
  let base_steps = [
    StepPending("Installing Lustre dev tools"),
    StepPending("Updating gleam.toml"),
    StepPending("Installing Three.js and Rapier3D"),
    StepPending("Creating .gitignore"),
  ]

  let with_template = case model.template {
    Some(_) -> list.append(base_steps, [StepPending("Creating main game file")])
    None -> base_steps
  }

  case model.bundle_desktop {
    True ->
      list.append(with_template, [
        StepPending("Detecting platform"),
        StepPending("Downloading NW.js SDK"),
        StepPending("Setting up platform distributions"),
      ])
    False -> with_template
  }
}

fn update_step_status(
  model: Model,
  step_name: String,
  status: StepStatus,
) -> Model {
  case model.step {
    Generating(steps) -> {
      let updated_steps =
        list.map(steps, fn(step) {
          case step {
            StepPending(name) if name == step_name ->
              case status {
                StatusInProgress -> StepInProgress(name)
                StatusComplete -> StepComplete(name)
                StatusFailed(err) -> StepFailed(name, err)
                StatusPending -> step
              }
            StepInProgress(name) if name == step_name ->
              case status {
                StatusComplete -> StepComplete(name)
                StatusFailed(err) -> StepFailed(name, err)
                _ -> step
              }
            _ -> step
          }
        })
      Model(..model, step: Generating(updated_steps))
    }
    _ -> model
  }
}

fn view(model: Model) -> shore.Node(Msg) {
  case model.step {
    Welcome -> view_welcome()
    LustreChoice -> view_lustre_choice()
    TemplateChoice -> view_template_choice()
    DesktopBundleChoice -> view_desktop_bundle_choice()
    Generating(steps) -> view_generating(steps)
    Complete -> view_complete(model)
    Failed(msg) -> view_error(msg)
  }
}

// Views

fn view_welcome() -> shore.Node(Msg) {
  ui.col([
    ui.text_styled(
      "╔═══════════════════════════════════╗",
      Some(style.Cyan),
      None,
    ),
    ui.text_styled(
      "║   🎮 Tiramisu Project Creator 🎮  ║",
      Some(style.Cyan),
      None,
    ),
    ui.text_styled(
      "║   Gleam 3D Game Engine            ║",
      Some(style.Cyan),
      None,
    ),
    ui.text_styled(
      "╚═══════════════════════════════════╝",
      Some(style.Cyan),
      None,
    ),
    ui.text(""),
    ui.text("Welcome to Tiramisu! 🍰"),
    ui.text(""),
    ui.text("This wizard will help you set up Tiramisu for your game project."),
    ui.text(""),
    ui.hr(),
    ui.text(""),
    ui.button("Continue", key.Enter, NextStep),
  ])
}

fn view_lustre_choice() -> shore.Node(Msg) {
  ui.col([
    ui.text_styled("Lustre Integration", Some(style.Cyan), None),
    ui.text(""),
    ui.text("Lustre allows you to create UI overlays for your game"),
    ui.text("(menus, HUDs, dialogs, etc.) using a reactive framework."),
    ui.text(""),
    ui.hr(),
    ui.text(""),
    ui.text("Include Lustre?"),
    ui.text(""),
    ui.button("[Y] Yes (recommended)", key.Char("y"), SetLustre(True)),
    ui.button("[N] No", key.Char("n"), SetLustre(False)),
  ])
}

fn view_template_choice() -> shore.Node(Msg) {
  ui.col([
    ui.text_styled("Project Template", Some(style.Cyan), None),
    ui.text(""),
    ui.text_styled(
      "⚠️  WARNING: Selecting a template is DESTRUCTIVE!",
      Some(style.Red),
      None,
    ),
    ui.text_styled(
      "It will OVERWRITE your existing game code in src/",
      Some(style.Red),
      None,
    ),
    ui.text(""),
    ui.text("If you're setting up NW.js for an existing project,"),
    ui.text("press [S] to skip template selection."),
    ui.text(""),
    ui.hr(),
    ui.text(""),
    ui.button(
      "[1] 2D Game - Orthographic camera and sprite setup",
      key.Char("1"),
      SetTemplate(TwoDGame),
    ),
    ui.button(
      "[2] 3D Game - Perspective camera with lighting",
      key.Char("2"),
      SetTemplate(ThreeDGame),
    ),
    ui.button(
      "[3] Physics Demo - Physics-enabled objects",
      key.Char("3"),
      SetTemplate(PhysicsDemo),
    ),
    ui.text(""),
    ui.button(
      "[S] Skip - Don't create/overwrite game files",
      key.Char("s"),
      SkipTemplate,
    ),
  ])
}

fn view_desktop_bundle_choice() -> shore.Node(Msg) {
  ui.col([
    ui.text_styled("Desktop Bundle for NW.js", Some(style.Cyan), None),
    ui.text(""),
    ui.text("Bundle for desktop will:"),
    ui.text("  • Download NW.js SDK for your current platform"),
    ui.text("  • Create dist folders for Linux, Windows, and macOS"),
    ui.text("  • Download NW.js executables for each platform"),
    ui.text("  • Copy your game files and package.json to each dist folder"),
    ui.text(""),
    ui.hr(),
    ui.text(""),
    ui.text("Bundle for desktop?"),
    ui.text(""),
    ui.button("[Y] Yes", key.Char("y"), SetDesktopBundle(True)),
    ui.button("[N] No", key.Char("n"), SetDesktopBundle(False)),
  ])
}

fn view_generating(steps: List(GenerationStep)) -> shore.Node(Msg) {
  let header = [
    ui.text_styled(
      "╔═══════════════════════════════════╗",
      Some(style.Cyan),
      None,
    ),
    ui.text_styled(
      "║     Setting up your project...    ║",
      Some(style.Cyan),
      None,
    ),
    ui.text_styled(
      "╚═══════════════════════════════════╝",
      Some(style.Cyan),
      None,
    ),
    ui.text(""),
  ]

  let step_views =
    list.map(steps, fn(step) {
      case step {
        StepPending(name) ->
          ui.text_styled("  ⏸  " <> name, Some(style.White), None)
        StepInProgress(name) ->
          ui.text_styled("  ⏳ " <> name <> "...", Some(style.Yellow), None)
        StepComplete(name) ->
          ui.text_styled("  ✓  " <> name, Some(style.Green), None)
        StepFailed(name, _err) ->
          ui.text_styled("  ✗  " <> name, Some(style.Red), None)
      }
    })

  ui.col(list.append(header, step_views))
}

fn view_complete(model: Model) -> shore.Node(Msg) {
  let template_text = case model.template {
    Some(t) -> template_name(t)
    None -> "None (skipped)"
  }

  let base_items = [
    ui.text_styled("✅ Project setup complete!", Some(style.Green), None),
    ui.text(""),
    ui.text("Project: " <> model.project_name),
    ui.text("Template: " <> template_text),
    ui.text(
      "Lustre: "
      <> case model.include_lustre {
        True -> "Yes"
        False -> "No"
      },
    ),
    ui.text(
      "Physics: "
      <> case model.include_physics {
        True -> "Yes"
        False -> "No"
      },
    ),
    ui.text(
      "Desktop Bundle: "
      <> case model.bundle_desktop {
        True -> "Yes"
        False -> "No"
      },
    ),
    ui.text(""),
    ui.hr(),
    ui.text(""),
    ui.text("Next steps:"),
    ui.text(""),
  ]

  let next_steps = case model.bundle_desktop {
    True -> [
      ui.text("1. Build your project:"),
      ui.text_styled(
        "   gleam run -m lustre/dev build --outdir=\"dist/<your-platform>\"",
        Some(style.Cyan),
        None,
      ),
      ui.text(""),
      ui.text("2. Run the desktop app using NW.js SDK in the project folder"),
      ui.text_styled(
        "   /dist/<your-platform>/path/to/nw .",
        Some(style.Cyan),
        None,
      ),
      ui.text(""),
      ui.text("3. Distribute using platform-specific builds in:"),
      ui.text("   • dist/linux/"),
      ui.text("   • dist/windows/"),
      ui.text("   • dist/macos/"),
    ]
    False -> [
      ui.text("1. Start the dev server:"),
      ui.text_styled("   gleam run -m lustre/dev start", Some(style.Cyan), None),
      ui.text(""),
      ui.text("2. Open http://localhost:1234 in your browser"),
    ]
  }

  let footer = [
    ui.text(""),
    ui.text("Happy game development! 🎮"),
    ui.text(""),
    ui.text("Press Ctrl + X to leave"),
  ]

  ui.col(list.flatten([base_items, next_steps, footer]))
}

fn view_error(msg: String) -> shore.Node(Msg) {
  ui.col([
    ui.text_styled("❌ Error occurred", Some(style.Red), None),
    ui.text(""),
    ui.text(msg),
  ])
}

fn template_name(template: Template) -> String {
  case template {
    TwoDGame -> "2D Game"
    ThreeDGame -> "3D Game"
    PhysicsDemo -> "Physics Demo"
  }
}

// Utility functions

fn install_lustre_dev_tools() -> SnagResult(Nil) {
  let root = find_root(".")

  shellout.command(
    run: "gleam",
    with: ["run", "-m", "lustre/dev", "add", "bun"],
    in: root,
    opt: [],
  )
  |> result.replace_error(snag.new("Failed to install Lustre dev tools"))
  |> result.replace(Nil)
}

fn get_project_name() -> SnagResult(String) {
  let root = find_root(".")
  let toml_path = filepath.join(root, "gleam.toml")

  use content <- result.try(
    simplifile.read(toml_path)
    |> snag.map_error(fn(_) { "Could not read gleam.toml" }),
  )

  use toml <- result.try(
    tom.parse(content)
    |> snag.map_error(fn(_) { "Could not parse gleam.toml" }),
  )

  use name <- result.try(
    tom.get_string(toml, ["name"])
    |> snag.map_error(fn(_) { "Could not find project name in gleam.toml" }),
  )

  Ok(name)
}

fn find_root(path: String) -> String {
  let toml = filepath.join(path, "gleam.toml")

  case simplifile.is_file(toml) {
    Ok(False) | Error(_) -> find_root(filepath.join(path, ".."))
    Ok(True) -> path
  }
}

fn update_gleam_toml(
  project_name: String,
  include_lustre: Bool,
) -> SnagResult(Nil) {
  let root = find_root(".")
  let toml_path = filepath.join(root, "gleam.toml")

  // Read existing gleam.toml
  use content <- result.try(
    simplifile.read(toml_path)
    |> snag.map_error(fn(_) { "Could not read gleam.toml" }),
  )

  // Add target = "javascript" if not present
  let content = case string.contains(content, "target =") {
    True -> content
    False -> {
      // Add after name line
      string.replace(
        content,
        "name = \"" <> project_name <> "\"",
        "name = \"" <> project_name <> "\"\ntarget = \"javascript\"",
      )
    }
  }

  // Write back the updated target
  use _ <- result.try(
    simplifile.write(toml_path, content)
    |> snag.map_error(fn(_) { "Could not write gleam.toml" }),
  )

  // Add dependencies using gleam add
  use _ <- result.try(
    shellout.command(run: "gleam", with: ["add", "tiramisu"], in: root, opt: [])
    |> result.replace_error(snag.new("Failed to add tiramisu dependency")),
  )

  use _ <- result.try(
    shellout.command(run: "gleam", with: ["add", "vec"], in: root, opt: [])
    |> result.replace_error(snag.new("Failed to add vec dependency")),
  )

  use _ <- result.try(
    shellout.command(
      run: "gleam",
      with: ["add", "--dev", "lustre_dev_tools"],
      in: root,
      opt: [],
    )
    |> result.replace_error(snag.new(
      "Failed to add lustre_dev_tools dependency",
    )),
  )

  // Add lustre if requested
  use _ <- result.try(case include_lustre {
    True ->
      shellout.command(run: "gleam", with: ["add", "lustre"], in: root, opt: [])
      |> result.replace_error(snag.new("Failed to add lustre dependency"))
    False -> Ok("")
  })

  // Read the updated gleam.toml to add lustre HTML config
  use content <- result.try(
    simplifile.read(toml_path)
    |> snag.map_error(fn(_) { "Could not read gleam.toml" }),
  )

  // Add lustre HTML config if not already present
  let lustre_config =
    "\n\n[tools.lustre.html]
scripts = [
  { type = \"importmap\", content = \"{ \\\"imports\\\": { \\\"three\\\": \\\"https://cdn.jsdelivr.net/npm/three@0.180.0/build/three.module.js\\\", \\\"three/addons/\\\": \\\"https://cdn.jsdelivr.net/npm/three@0.180.0/examples/jsm/\\\", \\\"@dimforge/rapier3d-compat\\\": \\\"https://cdn.jsdelivr.net/npm/@dimforge/rapier3d-compat@0.11.2/+esm\\\" } }\" }
]
stylesheets = [
  { content = \"body { margin: 0; padding: 0; overflow: hidden; }\" }
]
"

  let final_content = case string.contains(content, "[tools.lustre.html]") {
    True -> content
    False -> content <> lustre_config
  }

  simplifile.write(toml_path, final_content)
  |> snag.map_error(fn(_) { "Could not write gleam.toml" })
}

fn create_gitignore() -> SnagResult(Nil) {
  let root = find_root(".")
  let gitignore_path = filepath.join(root, ".gitignore")

  let content =
    "*.beam
*.ez
/build
erl_crash.dump
/priv
.DS_Store
node_modules/
dist/
.lustre/"

  simplifile.write(gitignore_path, content)
  |> snag.map_error(fn(_) { "Could not write .gitignore" })
}

fn create_main_file(project_name: String, template: Template) -> SnagResult(Nil) {
  let root = find_root(".")
  let src_dir = filepath.join(root, "src")
  let main_path = filepath.join(src_dir, project_name <> ".gleam")

  let content = case template {
    TwoDGame -> generate_2d_template()
    ThreeDGame -> generate_3d_template()
    PhysicsDemo -> generate_physics_template()
  }

  simplifile.write(main_path, content)
  |> snag.map_error(fn(_) { "Could not write main file" })
}

// Template generators

fn generate_2d_template() -> String {
  "/// 2D Game Example - Orthographic Camera
import gleam/float
import gleam/option
import tiramisu
import tiramisu/background
import tiramisu/camera
import tiramisu/effect.{type Effect}
import tiramisu/geometry
import tiramisu/light
import tiramisu/material
import tiramisu/scene
import tiramisu/transform
import vec/vec3

pub type Model {
  Model(time: Float)
}

pub type Msg {
  Tick
}

pub fn main() -> Nil {
  tiramisu.run(
    dimensions: option.None,
    background: background.Color(0x1a1a2e),
    init: init,
    update: update,
    view: view,
  )
}

fn init(_ctx: tiramisu.Context(String)) -> #(Model, Effect(Msg), option.Option(_)) {
  #(Model(time: 0.0), effect.tick(Tick), option.None)
}

fn update(
  model: Model,
  msg: Msg,
  ctx: tiramisu.Context(String),
) -> #(Model, Effect(Msg), option.Option(_)) {
  case msg {
    Tick -> {
      let new_time = model.time +. ctx.delta_time
      #(Model(time: new_time), effect.tick(Tick), option.None)
    }
  }
}

fn view(model: Model, ctx: tiramisu.Context(String)) -> List(scene.Node(String)) {
  let cam = camera.camera_2d(
    width: float.round(ctx.canvas_width),
    height: float.round(ctx.canvas_height),
  )
  let assert Ok(sprite_geom) = geometry.plane(width: 50.0, height: 50.0)
  let assert Ok(sprite_mat) = material.basic(color: 0xff0066, transparent: False, opacity: 1.0, map: option.None)

  [
    scene.Camera(
      id: \"camera\",
      camera: cam,
      transform: transform.at(position: vec3.Vec3(0.0, 0.0, 20.0)),
      look_at: option.None,
      active: True,
      viewport: option.None,
    ),
    scene.Light(
      id: \"ambient\",
      light: {
        let assert Ok(light) = light.ambient(color: 0xffffff, intensity: 1.0)
        light
      },
      transform: transform.identity,
    ),
    scene.Mesh(
      id: \"sprite\",
      geometry: sprite_geom,
      material: sprite_mat,
      transform: transform.Transform(
        position: vec3.Vec3(0.0, 0.0, 0.0),
        rotation: vec3.Vec3(0.0, 0.0, model.time),
        scale: vec3.Vec3(1.0, 1.0, 1.0),
      ),
      physics: option.None,
    ),
  ]
}
"
}

fn generate_3d_template() -> String {
  "/// 3D Game Example - Perspective Camera with Lighting
import gleam/option
import tiramisu
import tiramisu/background
import tiramisu/camera
import tiramisu/effect.{type Effect}
import tiramisu/geometry
import tiramisu/light
import tiramisu/material
import tiramisu/scene
import tiramisu/transform
import vec/vec3

pub type Model {
  Model(time: Float)
}

pub type Msg {
  Tick
}

pub fn main() -> Nil {
  tiramisu.run(
    dimensions: option.None,
    background: background.Color(0x1a1a2e),
    init: init,
    update: update,
    view: view,
  )
}

fn init(_ctx: tiramisu.Context(String)) -> #(Model, Effect(Msg), option.Option(_)) {
  #(Model(time: 0.0), effect.tick(Tick), option.None)
}

fn update(
  model: Model,
  msg: Msg,
  ctx: tiramisu.Context(String),
) -> #(Model, Effect(Msg), option.Option(_)) {
  case msg {
    Tick -> {
      let new_time = model.time +. ctx.delta_time
      #(Model(time: new_time), effect.tick(Tick), option.None)
    }
  }
}

fn view(model: Model, _ctx: tiramisu.Context(String)) -> List(scene.Node(String)) {
  let assert Ok(cam) = camera.perspective(field_of_view: 75.0, near: 0.1, far: 1000.0)
  let assert Ok(sphere_geom) = geometry.sphere(radius: 1.0, width_segments: 32, height_segments: 32)
  let assert Ok(sphere_mat) = material.new() |> material.with_color(0x0066ff) |> material.build
  let assert Ok(ground_geom) = geometry.plane(width: 20.0, height: 20.0)
  let assert Ok(ground_mat) = material.new() |> material.with_color(0x808080) |> material.build

  [
    scene.Camera(
      id: \"camera\",
      camera: cam,
      transform: transform.at(position: vec3.Vec3(0.0, 5.0, 10.0)),
      look_at: option.Some(vec3.Vec3(0.0, 0.0, 0.0)),
      active: True,
      viewport: option.None,
    ),
    scene.Light(
      id: \"ambient\",
      light: {
        let assert Ok(light) = light.ambient(color: 0xffffff, intensity: 0.5)
        light
      },
      transform: transform.identity,
    ),
    scene.Light(
      id: \"directional\",
      light: {
        let assert Ok(light) = light.directional(color: 0xffffff, intensity: 0.8)
        light
      },
      transform: transform.at(position: vec3.Vec3(10.0, 10.0, 10.0)),
    ),
    scene.Mesh(
      id: \"sphere\",
      geometry: sphere_geom,
      material: sphere_mat,
      transform: transform.at(position: vec3.Vec3(0.0, 0.0, 0.0)),
      physics: option.None,
    ),
    scene.Mesh(
      id: \"ground\",
      geometry: ground_geom,
      material: ground_mat,
      transform: transform.Transform(
        position: vec3.Vec3(0.0, -2.0, 0.0),
        rotation: vec3.Vec3(-1.57, 0.0, 0.0),
        scale: vec3.Vec3(1.0, 1.0, 1.0),
      ),
      physics: option.None,
    ),
  ]
}
"
}

fn generate_physics_template() -> String {
  "/// Physics Demo - Falling Cubes
/// Demonstrates physics simulation with Rapier3D
import gleam/option
import tiramisu
import tiramisu/background
import tiramisu/camera
import tiramisu/effect.{type Effect}
import tiramisu/geometry
import tiramisu/light
import tiramisu/material
import tiramisu/physics
import tiramisu/scene
import tiramisu/transform
import vec/vec3

pub type Id {
  Camera
  Ambient
  Directional
  Ground
  Cube1
  Cube2
}

pub type Model {
  Model
}

pub type Msg {
  Tick
}

pub fn main() -> Nil {
  tiramisu.run(
    dimensions: option.None,
    background: background.Color(0x1a1a2e),
    init: init,
    update: update,
    view: view,
  )
}

fn init(_ctx: tiramisu.Context(Id)) -> #(Model, Effect(Msg), option.Option(_)) {
  // Initialize physics world with gravity
  let physics_world =
    physics.new_world(
      physics.WorldConfig(gravity: vec3.Vec3(0.0, -9.81, 0.0), correspondances: [
        #(Cube1, \"cube-1\"),
        #(Cube2, \"cube-2\"),
        #(Ground, \"ground\"),
      ]),
    )

  #(Model, effect.tick(Tick), option.Some(physics_world))
}

fn update(
  model: Model,
  msg: Msg,
  ctx: tiramisu.Context(Id),
) -> #(Model, Effect(Msg), option.Option(_)) {
  let assert option.Some(physics_world) = ctx.physics_world
  case msg {
    Tick -> {
      let new_physics_world = physics.step(physics_world)
      #(model, effect.tick(Tick), option.Some(new_physics_world))
    }
  }
}

fn view(_model: Model, ctx: tiramisu.Context(Id)) -> List(scene.Node(Id)) {
  let assert option.Some(physics_world) = ctx.physics_world
  let assert Ok(cam) = camera.perspective(field_of_view: 75.0, near: 0.1, far: 1000.0)

  let assert Ok(cube_geom) = geometry.box(width: 1.0, height: 1.0, depth: 1.0)
  let assert Ok(cube1_mat) = material.new() |> material.with_color(0xff4444) |> material.build
  let assert Ok(cube2_mat) = material.new() |> material.with_color(0x44ff44) |> material.build

  let assert Ok(ground_geom) = geometry.box(width: 20.0, height: 0.2, depth: 20.0)
  let assert Ok(ground_mat) = material.new() |> material.with_color(0x808080) |> material.build

  [
    scene.Camera(
      id: Camera,
      camera: cam,
      transform: transform.at(position: vec3.Vec3(0.0, 10.0, 15.0)),
      look_at: option.Some(vec3.Vec3(0.0, 0.0, 0.0)),
      active: True,
      viewport: option.None,
    ),
    scene.Light(
      id: Ambient,
      light: {
        let assert Ok(light) = light.ambient(color: 0xffffff, intensity: 0.5)
        light
      },
      transform: transform.identity,
    ),
    scene.Light(
      id: Directional,
      light: {
        let assert Ok(light) = light.directional(color: 0xffffff, intensity: 2.0)
        light
      },
      transform: transform.at(position: vec3.Vec3(5.0, 10.0, 7.5)),
    ),
    // Ground (static physics body)
    scene.Mesh(
      id: Ground,
      geometry: ground_geom,
      material: ground_mat,
      transform: transform.at(position: vec3.Vec3(0.0, 0.0, 0.0)),
      physics: option.Some(
        physics.new_rigid_body(physics.Fixed)
        |> physics.with_collider(physics.Box(20.0, 0.2, 20.0))
        |> physics.with_restitution(0.0)
        |> physics.build(),
      ),
    ),
    // Falling cube 1 (dynamic physics body)
    scene.Mesh(
      id: Cube1,
      geometry: cube_geom,
      material: cube1_mat,
      transform: case physics.get_transform(physics_world, Cube1) {
        Ok(t) -> t
        Error(Nil) -> transform.at(position: vec3.Vec3(-2.0, 5.0, 0.0))
      },
      physics: option.Some(
        physics.new_rigid_body(physics.Dynamic)
        |> physics.with_collider(physics.Box(1.0, 1.0, 1.0))
        |> physics.with_mass(1.0)
        |> physics.with_restitution(0.5)
        |> physics.with_friction(0.5)
        |> physics.build(),
      ),
    ),
    // Falling cube 2 (dynamic physics body)
    scene.Mesh(
      id: Cube2,
      geometry: cube_geom,
      material: cube2_mat,
      transform: case physics.get_transform(physics_world, Cube2) {
        Ok(t) -> t
        Error(Nil) -> transform.at(position: vec3.Vec3(2.0, 7.0, 0.0))
      },
      physics: option.Some(
        physics.new_rigid_body(physics.Dynamic)
        |> physics.with_collider(physics.Box(1.0, 1.0, 1.0))
        |> physics.with_mass(1.0)
        |> physics.with_restitution(0.6)
        |> physics.with_friction(0.3)
        |> physics.build(),
      ),
    ),
  ]
}
"
}

// Desktop bundling functions

type Platform {
  Linux
  MacOS
  Windows
}

type Architecture {
  X64
  Arm64
  Aarch64
}

fn detect_platform() -> SnagResult(Platform) {
  case operating_system.name() {
    "nt" -> Ok(Windows)
    "darwin" -> Ok(MacOS)
    _ -> Ok(Linux)
  }
}

fn detect_architecture() -> Architecture {
  // Default to aarch64 on macOS (Apple Silicon), x64 elsewhere
  case operating_system.name() {
    "darwin" -> Aarch64
    _ -> X64
  }
}

fn get_bun_platform_string(platform: Platform) -> String {
  case platform {
    Linux -> "linux"
    MacOS -> "darwin"
    Windows -> "windows"
  }
}

fn get_bun_arch_string(arch: Architecture) -> String {
  case arch {
    X64 -> "x64"
    Arm64 -> "arm64"
    Aarch64 -> "aarch64"
  }
}

fn install_npm_packages() -> SnagResult(Nil) {
  let root = find_root(".")

  // Detect platform and architecture for bun path
  use platform <- result.try(detect_platform())
  let arch = detect_architecture()

  let platform_str = get_bun_platform_string(platform)
  let arch_str = get_bun_arch_string(arch)

  let bun_path =
    filepath.join(
      root,
      ".lustre/bin/bun-" <> platform_str <> "-" <> arch_str <> "/bun",
    )

  // Check if bun exists
  use bun_exists <- result.try(
    simplifile.is_file(bun_path)
    |> result.replace_error(snag.new("Could not check for bun executable")),
  )

  case bun_exists {
    False ->
      Error(snag.new(
        "Bun executable not found at "
        <> bun_path
        <> ". Make sure lustre_dev_tools is properly installed.",
      ))
    True -> {
      // Run bun add to install packages
      use _ <- result.try(
        shellout.command(
          run: bun_path,
          with: ["add", "three@^0.180.0"],
          in: root,
          opt: [],
        )
        |> result.replace_error(snag.new("Failed to install three.js")),
      )

      shellout.command(
        run: bun_path,
        with: ["add", "@dimforge/rapier3d-compat@^0.11.2"],
        in: root,
        opt: [],
      )
      |> result.replace_error(snag.new("Failed to install Rapier3D"))
      |> result.replace(Nil)
    }
  }
}

fn platform_to_string(platform: Platform) -> String {
  case platform {
    Linux -> "linux"
    MacOS -> "osx"
    Windows -> "win"
  }
}

fn download_nwjs_sdk(platform: Platform) -> SnagResult(Nil) {
  let root = find_root(".")
  let nwjs_version = "0.104.1"
  let platform_str = platform_to_string(platform)
  let arch = case platform {
    MacOS -> "arm64"
    _ -> "x64"
  }

  let filename =
    "nwjs-sdk-v" <> nwjs_version <> "-" <> platform_str <> "-" <> arch
  let archive_ext = case platform {
    Windows | MacOS -> ".zip"
    _ -> ".tar.gz"
  }

  let url =
    "https://dl.nwjs.io/v" <> nwjs_version <> "/" <> filename <> archive_ext
  let nwjs_dir = filepath.join(root, "nwjs-sdk")

  // Create nwjs-sdk directory if it doesn't exist
  let _ = simplifile.create_directory(nwjs_dir)

  let archive_path = filepath.join(nwjs_dir, filename <> archive_ext)

  // Download using curl with fail flag
  use download_result <- result.try(
    shellout.command(
      run: "curl",
      with: ["-L", "-f", "-o", archive_path, url],
      in: ".",
      opt: [],
    )
    |> result.map_error(fn(error) {
      snag.new("Failed to download NW.js SDK from " <> url <> ": " <> error.1)
    }),
  )

  // Verify the file was downloaded
  use file_exists <- result.try(
    simplifile.is_file(archive_path)
    |> result.replace_error(snag.new("Could not verify downloaded file")),
  )

  use _ <- result.try(case file_exists {
    False -> Error(snag.new("Downloaded file does not exist: " <> archive_path))
    True -> {
      // Extract archive
      use _ <- result.try(case platform {
        Windows ->
          shellout.command(
            run: "unzip",
            with: ["-q", filename <> archive_ext],
            in: nwjs_dir,
            opt: [],
          )
          |> result.map_error(fn(error) {
            snag.new("Failed to extract NW.js SDK: " <> error.1)
          })
        _ ->
          shellout.command(
            run: "tar",
            with: ["-xzf", filename <> archive_ext],
            in: nwjs_dir,
            opt: [],
          )
          |> result.map_error(fn(error) {
            snag.new("Failed to extract NW.js SDK: " <> error.1)
          })
      })

      Ok(download_result)
    }
  })

  // Rename extracted directory to just "nwjs"
  let extracted_dir = filepath.join(nwjs_dir, filename)
  let target_dir = filepath.join(nwjs_dir, "nwjs")
  let _ = simplifile.delete(target_dir)
  use _ <- result.try(
    shellout.command(
      run: "mv",
      with: [extracted_dir, target_dir],
      in: ".",
      opt: [],
    )
    |> result.replace_error(snag.new("Failed to rename NW.js SDK directory")),
  )

  // Remove archive
  let _ = simplifile.delete(archive_path)

  Ok(Nil)
}

fn download_nwjs_for_platform(
  platform: Platform,
  dist_platform_dir: String,
) -> SnagResult(Nil) {
  let nwjs_version = "0.104.1"
  let platform_str = platform_to_string(platform)
  let arch = case platform {
    MacOS -> "arm64"
    _ -> "x64"
  }

  let filename = "nwjs-v" <> nwjs_version <> "-" <> platform_str <> "-" <> arch
  let archive_ext = case platform {
    MacOS | Windows -> ".zip"
    _ -> ".tar.gz"
  }

  let url =
    "https://dl.nwjs.io/v" <> nwjs_version <> "/" <> filename <> archive_ext
  let archive_path = filepath.join(dist_platform_dir, filename <> archive_ext)

  // Download using curl with fail flag
  use download_result <- result.try(
    shellout.command(
      run: "curl",
      with: ["-L", "-f", "-o", archive_path, url],
      in: ".",
      opt: [],
    )
    |> result.map_error(fn(error) {
      snag.new(
        "Failed to download NW.js for "
        <> platform_str
        <> " from "
        <> url
        <> ": "
        <> error.1,
      )
    }),
  )

  // Verify the file was downloaded
  use file_exists <- result.try(
    simplifile.is_file(archive_path)
    |> result.replace_error(snag.new("Could not verify downloaded file")),
  )

  use _ <- result.try(case file_exists {
    False ->
      Error(snag.new(
        "Downloaded file does not exist for "
        <> platform_str
        <> ": "
        <> archive_path,
      ))
    True -> {
      // Extract archive
      use _ <- result.try(case platform {
        Windows ->
          shellout.command(
            run: "unzip",
            with: ["-q", filename <> archive_ext],
            in: dist_platform_dir,
            opt: [],
          )
          |> result.map_error(fn(error) {
            snag.new(
              "Failed to extract NW.js for " <> platform_str <> ": " <> error.1,
            )
          })
        _ ->
          shellout.command(
            run: "tar",
            with: ["-xzf", filename <> archive_ext],
            in: dist_platform_dir,
            opt: [],
          )
          |> result.map_error(fn(error) {
            snag.new(
              "Failed to extract NW.js for " <> platform_str <> ": " <> error.1,
            )
          })
      })

      Ok(download_result)
    }
  })

  // Rename extracted directory to just "nwjs"
  let extracted_dir = filepath.join(dist_platform_dir, filename)
  let target_dir = filepath.join(dist_platform_dir, "nwjs")
  let _ = simplifile.delete(target_dir)
  use _ <- result.try(
    shellout.command(
      run: "mv",
      with: [extracted_dir, target_dir],
      in: ".",
      opt: [],
    )
    |> result.replace_error(snag.new(
      "Failed to rename NW.js directory for " <> platform_str,
    )),
  )

  // Remove archive
  let _ = simplifile.delete(archive_path)

  Ok(Nil)
}

fn create_package_json(project_name: String, with_nwjs: Bool) -> String {
  let nwjs_config = case with_nwjs {
    True -> ",
  \"main\": \"index.html\",
  \"window\": {
    \"title\": \"" <> project_name <> "\",
    \"width\": 1920,
    \"height\": 1080
  }"
    False -> ""
  }

  "{
  \"name\": \"" <> project_name <> "\",
  \"version\": \"1.0.0\"" <> nwjs_config <> ",
  \"dependencies\": {
    \"three\": \"^0.180.0\",
    \"@dimforge/rapier3d-compat\": \"^0.11.2\"
  }
}"
}

fn setup_desktop_bundle(project_name: String) -> SnagResult(Nil) {
  let root = find_root(".")
  let dist_dir = filepath.join(root, "dist")

  // Create dist directory
  let _ = simplifile.create_directory(dist_dir)

  // Update package.json with NW.js configuration
  let package_json_path = filepath.join(root, "package.json")
  let package_json_content = create_package_json(project_name, True)
  use _ <- result.try(
    simplifile.write(package_json_path, package_json_content)
    |> snag.map_error(fn(_) { "Could not write package.json" }),
  )

  // Create platform-specific directories and download NW.js for each
  let platforms = [
    #(Linux, "linux"),
    #(MacOS, "macos"),
    #(Windows, "windows"),
  ]

  use _ <- result.try(
    list.try_each(platforms, fn(platform_tuple) {
      let #(platform, dir_name) = platform_tuple
      let platform_dir = filepath.join(dist_dir, dir_name)

      // Create platform directory
      let _ = simplifile.create_directory(platform_dir)

      // Download NW.js for this platform
      use _ <- result.try(download_nwjs_for_platform(platform, platform_dir))

      // Copy package.json to platform directory
      let package_json_src = filepath.join(root, "package.json")
      let package_json_dest = filepath.join(platform_dir, "package.json")
      use _ <- result.try(
        simplifile.copy_file(package_json_src, package_json_dest)
        |> snag.map_error(fn(_) {
          "Could not copy package.json to " <> dir_name
        }),
      )

      Ok(Nil)
    }),
  )

  Ok(Nil)
}
