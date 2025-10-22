/// 3D Game Example - Perspective Camera with Lighting
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
    scene.camera(
      id: "camera",
      camera: cam,
      transform: transform.at(position: vec3.Vec3(0.0, 5.0, 10.0)),
      look_at: option.Some(vec3.Vec3(0.0, 0.0, 0.0)),
      active: True,
      viewport: option.None,
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
        let assert Ok(light) = light.directional(color: 0xffffff, intensity: 0.8)
        light
      },
      transform: transform.at(position: vec3.Vec3(10.0, 10.0, 10.0)),
    ),
    scene.mesh(
      id: "sphere",
      geometry: sphere_geom,
      material: sphere_mat,
      transform: transform.at(position: vec3.Vec3(0.0, 0.0, 0.0)),
      physics: option.None,
    ),
    scene.mesh(
      id: "ground",
      geometry: ground_geom,
      material: ground_mat,
      transform: 
        transform.at(position: vec3.Vec3(0.0, -2.0, 0.0)) 
        |> transform.with_euler_rotation(vec3.Vec3(-1.57, 0.0, 0.0)),
      physics: option.None,
    ),
  ]
}
