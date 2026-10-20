/*
 * Dusklight for the PlayStation 5 - stage 1: one triangle through Dawn on RADV.
 *
 * What Aurora asks of Dawn, at its smallest: an instance, the Vulkan adapter,
 * a device, the console's surface, a WGSL shader through Tint to SPIR-V, a
 * render pipeline and a present a frame. It runs until OPTIONS or its frame
 * budget, and reports each step to klog.
 *
 * SPDX-License-Identifier: MIT
 */
#include <webgpu/webgpu_cpp.h>

#include <cmath>
#include <cstdint>
#include <cstdlib>

#include "platform.h"

static const char kShader[] = R"(
struct Frame { angle: f32 };
@group(0) @binding(0) var<uniform> frame: Frame;
struct Out { @builtin(position) position: vec4f, @location(0) colour: vec3f };
@vertex fn vs(@builtin(vertex_index) i: u32) -> Out {
  var corners = array<vec2f, 3>(vec2f(0.0, 0.7), vec2f(-0.7, -0.6), vec2f(0.7, -0.6));
  var colours = array<vec3f, 3>(vec3f(1.0, 0.2, 0.2), vec3f(0.2, 1.0, 0.2), vec3f(0.2, 0.4, 1.0));
  let c = cos(frame.angle);
  let s = sin(frame.angle);
  let p = corners[i];
  var out: Out;
  // 16:9: keep the triangle's shape
  out.position = vec4f((p.x * c - p.y * s) * 9.0 / 16.0, p.x * s + p.y * c, 0.0, 1.0);
  out.colour = colours[i];
  return out;
}
@fragment fn fs(in: Out) -> @location(0) vec4f { return vec4f(in.colour, 1.0); }
)";

static void
fail(const char *what)
{
   say("FAILED: %s", what);
   say("ends: status 1");
   exit(1);
}

int
main(void)
{
   platform_init(PS5_TITLE_NAME);
   pad_open();

   static const wgpu::InstanceFeatureName instanceFeatures[] = {wgpu::InstanceFeatureName::TimedWaitAny};
   wgpu::InstanceDescriptor instanceDescriptor{};
   instanceDescriptor.requiredFeatureCount = 1;
   instanceDescriptor.requiredFeatures = instanceFeatures;
   wgpu::Instance instance = wgpu::CreateInstance(&instanceDescriptor);
   if (!instance)
      fail("no instance");
   say("instance");

   /* The console has no window: any token names its one output */
   static int output;
   wgpu::SurfaceSourceSwitchNWindow source{};
   source.window = &output;
   wgpu::SurfaceDescriptor surfaceDescriptor{};
   surfaceDescriptor.nextInChain = &source;
   wgpu::Surface surface = instance.CreateSurface(&surfaceDescriptor);
   if (!surface)
      fail("no surface");
   say("surface");

   wgpu::RequestAdapterOptions adapterOptions{};
   adapterOptions.backendType = wgpu::BackendType::Vulkan;
   adapterOptions.compatibleSurface = surface;
   wgpu::Adapter adapter;
   instance.WaitAny(instance.RequestAdapter(
                       &adapterOptions, wgpu::CallbackMode::WaitAnyOnly,
                       [&](wgpu::RequestAdapterStatus status, wgpu::Adapter found, wgpu::StringView message) {
                          if (status != wgpu::RequestAdapterStatus::Success)
                             say("adapter: %.*s", (int)message.length, message.data);
                          adapter = std::move(found);
                       }),
                    UINT64_MAX);
   if (!adapter)
      fail("no adapter");
   wgpu::AdapterInfo info;
   adapter.GetInfo(&info);
   say("adapter: %.*s (%.*s)", (int)info.device.length, info.device.data, (int)info.description.length,
       info.description.data);

   wgpu::DeviceDescriptor deviceDescriptor{};
   deviceDescriptor.SetUncapturedErrorCallback(
      [](const wgpu::Device &, wgpu::ErrorType type, wgpu::StringView message) {
         say("device error %d: %.*s", (int)type, (int)message.length, message.data);
      });
   deviceDescriptor.SetDeviceLostCallback(
      wgpu::CallbackMode::AllowSpontaneous,
      [](const wgpu::Device &, wgpu::DeviceLostReason reason, wgpu::StringView message) {
         say("device lost %d: %.*s", (int)reason, (int)message.length, message.data);
      });
   wgpu::Device device;
   instance.WaitAny(instance ? adapter.RequestDevice(
                                  &deviceDescriptor, wgpu::CallbackMode::WaitAnyOnly,
                                  [&](wgpu::RequestDeviceStatus status, wgpu::Device made, wgpu::StringView message) {
                                     if (status != wgpu::RequestDeviceStatus::Success)
                                        say("device: %.*s", (int)message.length, message.data);
                                     device = std::move(made);
                                  })
                             : wgpu::Future{},
                    UINT64_MAX);
   if (!device)
      fail("no device");
   say("device");

   wgpu::SurfaceCapabilities capabilities;
   surface.GetCapabilities(adapter, &capabilities);
   if (capabilities.formatCount == 0)
      fail("the surface has no format");
   wgpu::SurfaceConfiguration configuration{};
   configuration.device = device;
   configuration.format = capabilities.formats[0];
   configuration.width = 1920;
   configuration.height = 1080;
   configuration.presentMode = wgpu::PresentMode::Fifo;
   surface.Configure(&configuration);
   say("surface configured: format %d of %zu, %zu present modes", (int)configuration.format,
       capabilities.formatCount, capabilities.presentModeCount);

   wgpu::ShaderSourceWGSL wgsl{};
   wgsl.code = kShader;
   wgpu::ShaderModuleDescriptor shaderDescriptor{};
   shaderDescriptor.nextInChain = &wgsl;
   wgpu::ShaderModule shader = device.CreateShaderModule(&shaderDescriptor);

   wgpu::BufferDescriptor bufferDescriptor{};
   bufferDescriptor.size = 16;
   bufferDescriptor.usage = wgpu::BufferUsage::Uniform | wgpu::BufferUsage::CopyDst;
   wgpu::Buffer uniforms = device.CreateBuffer(&bufferDescriptor);

   wgpu::ColorTargetState target{};
   target.format = configuration.format;
   wgpu::FragmentState fragment{};
   fragment.module = shader;
   fragment.entryPoint = "fs";
   fragment.targetCount = 1;
   fragment.targets = &target;
   wgpu::RenderPipelineDescriptor pipelineDescriptor{};
   pipelineDescriptor.vertex.module = shader;
   pipelineDescriptor.vertex.entryPoint = "vs";
   pipelineDescriptor.fragment = &fragment;
   wgpu::RenderPipeline pipeline = device.CreateRenderPipeline(&pipelineDescriptor);
   if (!pipeline)
      fail("no pipeline");
   say("pipeline (WGSL through Tint)");

   wgpu::BindGroupEntry entry{};
   entry.binding = 0;
   entry.buffer = uniforms;
   entry.size = 16;
   wgpu::BindGroupDescriptor groupDescriptor{};
   groupDescriptor.layout = pipeline.GetBindGroupLayout(0);
   groupDescriptor.entryCount = 1;
   groupDescriptor.entries = &entry;
   wgpu::BindGroup group = device.CreateBindGroup(&groupDescriptor);

   const double start = now_seconds();
   double last = start;
   int frames = 0;
   for (; frames < 60 * 60; frames++) {
      struct pad pad;
      pad_poll(&pad);
      if (pad.pressed & PAD_OPTIONS)
         break;

      const float angle[4] = {(float)(now_seconds() - start)};
      device.GetQueue().WriteBuffer(uniforms, 0, angle, sizeof(angle));

      wgpu::SurfaceTexture frame;
      surface.GetCurrentTexture(&frame);
      if (!frame.texture)
         fail("no frame to draw to");

      wgpu::RenderPassColorAttachment attachment{};
      attachment.view = frame.texture.CreateView();
      attachment.loadOp = wgpu::LoadOp::Clear;
      attachment.storeOp = wgpu::StoreOp::Store;
      attachment.clearValue = {0.02, 0.02, 0.06, 1.0};
      wgpu::RenderPassDescriptor passDescriptor{};
      passDescriptor.colorAttachmentCount = 1;
      passDescriptor.colorAttachments = &attachment;

      wgpu::CommandEncoder encoder = device.CreateCommandEncoder();
      wgpu::RenderPassEncoder pass = encoder.BeginRenderPass(&passDescriptor);
      pass.SetPipeline(pipeline);
      pass.SetBindGroup(0, group);
      pass.Draw(3);
      pass.End();
      wgpu::CommandBuffer commands = encoder.Finish();
      device.GetQueue().Submit(1, &commands);
      surface.Present();
      instance.ProcessEvents();

      if (frames == 0)
         say("first frame presented");
      const double now = now_seconds();
      if (now - last >= 5.0) {
         say("%d frames, %.1f fps", frames + 1, (frames + 1) / (now - start));
         last = now;
      }
   }
   say("%d frames in %.1f s", frames, now_seconds() - start);
   say("ends: status 0");
   return 0;
}
