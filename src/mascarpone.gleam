import filepath
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
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
  Complete
  Failed(String)
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
  )
}

type Msg {
  NextStep
  SetLustre(Bool)
  SetTemplate(Template)
  Generate
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
        TemplateChoice -> Complete
        Complete -> Complete
        Failed(_) -> Complete
      }

      #(Model(..model, step: next_step), [])
    }

    SetLustre(value) -> {
      #(Model(..model, include_lustre: value, step: TemplateChoice), [])
    }

    SetTemplate(template) -> {
      let updated_model = Model(..model, template: Some(template))
      let result = generate_project(updated_model)
      case result {
        Ok(_) -> #(Model(..updated_model, step: Complete), [])
        Error(err) -> #(
          Model(..updated_model, step: Failed(snag.pretty_print(err))),
          [],
        )
      }
    }

    Generate -> {
      let result = generate_project(model)
      case result {
        Ok(_) -> #(Model(..model, step: Complete), [])
        Error(err) -> #(
          Model(..model, step: Failed(snag.pretty_print(err))),
          [],
        )
      }
    }
  }
}

fn view(model: Model) -> shore.Node(Msg) {
  case model.step {
    Welcome -> view_welcome()
    LustreChoice -> view_lustre_choice()
    TemplateChoice -> view_template_choice()
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
  ])
}

fn view_complete(model: Model) -> shore.Node(Msg) {
  ui.col([
    ui.text_styled("✅ Project setup complete!", Some(style.Green), None),
    ui.text(""),
    ui.text("Project: " <> model.project_name),
    ui.text(
      "Template: " <> template_name(option.unwrap(model.template, ThreeDGame)),
    ),
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
    ui.text(""),
    ui.hr(),
    ui.text(""),
    ui.text("Next steps:"),
    ui.text(""),
    ui.text("1. Start the dev server:"),
    ui.text_styled("   gleam run -m lustre/dev start", Some(style.Cyan), None),
    ui.text(""),
    ui.text("2. Open http://localhost:1234 in your browser"),
    ui.text(""),
    ui.text("Happy game development! 🎮"),
    ui.text(""),
    ui.text("Press Ctrl + X to leave"),
  ])
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

// Project generation

fn generate_project(model: Model) -> SnagResult(Nil) {
  use _ <- result.try(update_gleam_toml(
    model.project_name,
    model.include_lustre,
  ))

  use _ <- result.try(create_gitignore())

  use _ <- result.try(create_main_file(
    model.project_name,
    option.unwrap(model.template, ThreeDGame),
  ))

  Ok(Nil)
}

// Utility functions

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

  // Build dependencies
  let deps = [
    "tiramisu = \">= 2.0.0 and < 3.0.0\"",
    "vec = \">= 3.0.1 and < 4.0.0\"",
  ]

  let dev_deps = ["lustre_dev_tools = \">= 2.0.2 and <= 3.0.0\""]

  // Add lustre if requested
  let deps = case include_lustre {
    True -> list.append(deps, ["lustre = \">= 5.0.0 and < 6.0.0\""])
    False -> deps
  }

  let content_with_deps = case string.contains(content, "[dependencies]") {
    True -> {
      list.fold(deps, content, fn(acc, dep) {
        string.replace(acc, "[dependencies]", "[dependencies]\n" <> dep)
      })
    }
    False -> {
      content <> "\n\n[dependencies]\n" <> string.join(deps, "\n")
    }
  }

  let content_with_dev_deps = case
    string.contains(content_with_deps, "[dev-dependencies]")
  {
    True -> {
      list.fold(dev_deps, content_with_deps, fn(acc, dep) {
        string.replace(acc, "[dev-dependencies]", "[dev-dependencies]\n" <> dep)
      })
    }
    False -> {
      content_with_deps
      <> "\n\n[dev-dependencies]\n"
      <> string.join(dev_deps, "\n")
    }
  }

  // Add lustre HTML config
  let lustre_config =
    "\n\n[tools.lustre.html]
scripts = [
  { type = \"importmap\", content = \"{ \\\"imports\\\": { \\\"three\\\": \\\"https://cdn.jsdelivr.net/npm/three@0.180.0/build/three.module.js\\\", \\\"three/addons/\\\": \\\"https://cdn.jsdelivr.net/npm/three@0.180.0/examples/jsm/\\\", \\\"@dimforge/rapier3d-compat\\\": \\\"https://cdn.jsdelivr.net/npm/@dimforge/rapier3d-compat@0.11.2/+esm\\\" } }\" }
]
stylesheets = [
  { content = \"body { margin: 0; padding: 0; overflow: hidden; }\" }
]
"

  let final_content = case
    string.contains(content_with_dev_deps, "[tools.lustre.html]")
  {
    True -> content_with_dev_deps
    False -> content_with_dev_deps <> lustre_config
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
