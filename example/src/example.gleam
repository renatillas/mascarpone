
/// Physics Demo - Falling Cubes
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

pub type Model {
  Model
}

pub type Msg {
  Tick
  BackgroundSet
}

pub fn main() -> Nil {
  let assert Ok(Nil) = tiramisu.application(init:, update:, view:)
  |> tiramisu.start("#app", tiramisu.FullScreen, option.None)
  Nil
}

fn init(ctx: tiramisu.Context) -> #(Model, Effect(Msg), option.Option(_)) {
  // Initialize physics world with gravity
  let physics_world =
    physics.new_world(
      physics.WorldConfig(gravity: vec3.Vec3(0.0, -9.81, 0.0)),
    )

  let bg_effect = background.set(ctx.scene, background.Color(0x1a1a2e), BackgroundSet, BackgroundSet)
  #(Model, effect.batch([bg_effect, effect.dispatch(Tick)]), option.Some(physics_world))
}

fn update(
  model: Model,
  msg: Msg,
  ctx: tiramisu.Context,
) -> #(Model, Effect(Msg), option.Option(_)) {
  let assert option.Some(physics_world) = ctx.physics_world
  case msg {
    Tick -> {
      let new_physics_world = physics.step(physics_world, ctx.delta_time)
      #(model, effect.dispatch(Tick), option.Some(new_physics_world))
    }
    BackgroundSet -> #(model, effect.none(), option.None)
  }
}

fn view(_model: Model, ctx: tiramisu.Context) -> scene.Node {
  let assert option.Some(physics_world) = ctx.physics_world
  let assert Ok(cam) = camera.perspective(field_of_view: 75.0, near: 0.1, far: 1000.0)

  let assert Ok(cube_geom) = geometry.box(size: vec3.Vec3(1.0, 1.0, 1.0))
  let assert Ok(cube1_mat) = material.new() |> material.with_color(0xff4444) |> material.build
  let assert Ok(cube2_mat) = material.new() |> material.with_color(0x44ff44) |> material.build

  let assert Ok(ground_geom) = geometry.box(size: vec3.Vec3(20.0, 0.2, 20.0))
  let assert Ok(ground_mat) = material.new() |> material.with_color(0x808080) |> material.build

  scene.empty(id: "scene", transform: transform.identity, children: [
    scene.camera(
      id: "camera",
      camera: cam,
      transform: transform.look_at(
        from: transform.at(position: vec3.Vec3(0.0, 10.0, 15.0)),
        to: transform.at(position: vec3.Vec3(0.0, 0.0, 0.0)),
        up: option.None,
      ),
      active: True,
      viewport: option.None,
      postprocessing: option.None,
    ),
    scene.light(
      id: "ambient",
      light: {
        let assert Ok(light) = light.ambient(color: 0xffffff, intensity: 0.5)
        light
      },
      transform: transform.identity,
    ),
    scene.light(
      id: "directional",
      light: {
        let assert Ok(light) = light.directional(color: 0xffffff, intensity: 2.0)
        light
      },
      transform: transform.at(position: vec3.Vec3(5.0, 10.0, 7.5)),
    ),
    // Ground (static physics body)
    scene.mesh(
      id: "ground",
      geometry: ground_geom,
      material: ground_mat,
      transform: transform.at(position: vec3.Vec3(0.0, 0.0, 0.0)),
      physics: option.Some(
        physics.new_rigid_body(physics.Fixed)
        |> physics.with_collider(physics.Box(offset: transform.identity, size: vec3.Vec3(20.0, 0.2, 20.0)))
        |> physics.with_restitution(0.0)
        |> physics.build(),
      ),
    ),
    // Falling cube 1 (dynamic physics body)
    scene.mesh(
      id: "cube1",
      geometry: cube_geom,
      material: cube1_mat,
      transform: case physics.get_transform(physics_world, "cube1") {
        Ok(t) -> t
        Error(Nil) -> transform.at(position: vec3.Vec3(-2.0, 5.0, 0.0))
      },
      physics: option.Some(
        physics.new_rigid_body(physics.Dynamic)
        |> physics.with_collider(physics.Box(offset: transform.identity, size: vec3.Vec3(1.0, 1.0, 1.0)))
        |> physics.with_mass(1.0)
        |> physics.with_restitution(0.5)
        |> physics.with_friction(0.5)
        |> physics.build(),
      ),
    ),
    // Falling cube 2 (dynamic physics body)
    scene.mesh(
      id: "cube2",
      geometry: cube_geom,
      material: cube2_mat,
      transform: case physics.get_transform(physics_world, "cube2") {
        Ok(t) -> t
        Error(Nil) -> transform.at(position: vec3.Vec3(2.0, 7.0, 0.0))
      },
      physics: option.Some(
        physics.new_rigid_body(physics.Dynamic)
        |> physics.with_collider(physics.Box(offset: transform.identity, size: vec3.Vec3(1.0, 1.0, 1.0)))
        |> physics.with_mass(1.0)
        |> physics.with_restitution(0.6)
        |> physics.with_friction(0.3)
        |> physics.build(),
      ),
    ),
  ])
}
