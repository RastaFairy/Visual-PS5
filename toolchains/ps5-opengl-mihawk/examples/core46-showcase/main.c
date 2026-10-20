// PS5 OpenGL - OpenGL implementation for PlayStation 5.
// Copyright (C) 2026 BlackBearReloaded
// SPDX-License-Identifier: GPL-3.0-or-later

/* OpenGL 4.6 showcase: a GPU-driven scene rendered at up to 3840x2160.
 *
 *  - 262,144 compute-shader particles (SSBO) streaming off a torus knot
 *  - compute frustum culling of 8,192 instances into one
 *    glMultiDrawElementsIndirectCount, materials chosen with gl_DrawID
 *  - GGX lighting, a procedural aurora sky, a 16x anisotropic floor grid
 *  - HDR (RGBA16F) with a compute-shader bloom chain (image load/store)
 *  - ACES tone mapping, vignette, grain and an in-shader bitmap-font HUD
 *  - direct state access everywhere; runtime 4K display mode when the SDK
 *    offers eglSetDisplayModePS5 (ps5-opengl 0.5.0 and later)
 *
 * The demo runs until the application is closed and logs its frame rate. */
#define _POSIX_C_SOURCE 200809L
#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#define GL_GLEXT_PROTOTYPES 1
#include <GL/gl.h>
#include <GL/glext.h>

#ifndef SHOWCASE_WIDTH
#define SHOWCASE_WIDTH 3840
#endif
#ifndef SHOWCASE_HEIGHT
#define SHOWCASE_HEIGHT 2160
#endif
#ifndef SHOWCASE_REFRESH
#define SHOWCASE_REFRESH 120 /* falls back to 60 Hz on displays without 120 Hz */
#endif
#ifndef SHOWCASE_PARTICLES
#define SHOWCASE_PARTICLES 262144
#endif
#ifndef SHOWCASE_COMPUTE_BLOOM
#define SHOWCASE_COMPUTE_BLOOM 0 /* 1: 11 compute dispatches instead of fullscreen passes */
#endif
#ifndef SHOWCASE_SECONDS
#define SHOWCASE_SECONDS 0 /* 0 runs until the application is closed */
#endif
#ifndef SHOWCASE_CAPTURE_FRAME
#define SHOWCASE_CAPTURE_FRAME 0 /* validation: write this frame to SHOWCASE_CAPTURE_PATH */
#endif
#ifndef SHOWCASE_CAPTURE_PATH
#define SHOWCASE_CAPTURE_PATH "/app0/showcase.ppm"
#endif

enum {
   PARTICLES = SHOWCASE_PARTICLES,
   GEMS = 6144,
   CUBES = 2048,
   INSTANCES = GEMS + CUBES,
   BLOOM_LEVELS = 6,
   TEXT_LINES = 4,
   TEXT_COLUMNS = 48,
   KNOT_SEGMENTS = 768,
   KNOT_SIDES = 48,
};

#define TAG "[ps5-gl46-showcase]"

/* Console log output (klog); weak so host previews link without it. */
int sceKernelDebugOutText(int channel, const char *text) __attribute__((weak));

#include <stdarg.h>
static void
say(const char *format, ...)
{
   char line[512];
   va_list arguments;
   va_start(arguments, format);
   vsnprintf(line, sizeof(line) - 1, format, arguments);
   va_end(arguments);
   strcat(line, "\n");
   fputs(line, stdout);
   if (sceKernelDebugOutText)
      sceKernelDebugOutText(0, line);
}

/* Validation builds: the rendered frame, before it is presented, as a PPM. */
static void
capture_frame(int width, int height)
{
   unsigned char *rgb = malloc((size_t)width * height * 3);
   FILE *ppm = fopen(SHOWCASE_CAPTURE_PATH, "wb");
   if (rgb && ppm) {
      glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
      glPixelStorei(GL_PACK_ALIGNMENT, 1);
      glReadPixels(0, 0, width, height, GL_RGB, GL_UNSIGNED_BYTE, rgb);
      fprintf(ppm, "P6 %d %d 255\n", width, height);
      for (int y = height - 1; y >= 0; --y)
         fwrite(rgb + (size_t)y * width * 3, 1, (size_t)width * 3, ppm);
   }
   say(TAG " capture %s gl=%x", rgb && ppm ? SHOWCASE_CAPTURE_PATH : "failed", glGetError());
   if (ppm)
      fclose(ppm);
   free(rgb);
}

/* ps5-opengl 0.5.0 runtime display modes; absent (NULL) in fixed-profile SDKs. */
EGLBoolean eglSetDisplayModePS5(EGLDisplay, EGLint, EGLint) __attribute__((weak));
EGLBoolean eglSetDisplayRefreshPS5(EGLDisplay, EGLint) __attribute__((weak));
EGLBoolean eglGetDisplayModePS5(EGLDisplay, EGLint *, EGLint *, EGLint *) __attribute__((weak));

struct vertex {
   float position[3];
   float normal[3];
   float uv[2];
};

struct draw_elements_indirect {
   uint32_t count, instance_count, first_index;
   int32_t base_vertex;
   uint32_t base_instance;
};

/* std140 per-frame block shared by every program (binding 0). */
struct frame_block {
   float view_proj[16];
   float inv_view_proj[16];
   float camera[4];    /* xyz position, w time */
   float cam_right[4]; /* xyz, w particle size */
   float cam_up[4];
   float light_pos[3][4];
   float light_color[3][4]; /* rgb, w intensity */
   float params[4];         /* width, height, aspect, frame */
};

static int64_t
now_ns(void)
{
   struct timespec value;
   return clock_gettime(CLOCK_MONOTONIC, &value) == 0
             ? (int64_t)value.tv_sec * 1000000000 + value.tv_nsec
             : 0;
}

static int
check(int condition, const char *stage)
{
   if (!condition)
      say(TAG " FAIL stage=%s gl=%x egl=%x", stage, glGetError(), eglGetError());
   return condition;
}

/* ---------------------------------------------------------------- shaders */

#define GLSL_HEADER \
   "#version 460 core\n" \
   "layout(std140,binding=0) uniform Frame{mat4 view_proj;mat4 inv_view_proj;" \
   "vec4 camera;vec4 cam_right;vec4 cam_up;vec4 light_pos[3];vec4 light_color[3];" \
   "vec4 params;};\n"

/* Torus knot (2,3) centre line, shared by the mesh and the particle emitter. */
#define GLSL_KNOT \
   "vec3 knot(float u){float r=cos(3.0*u)+2.2;" \
   "return vec3(r*cos(2.0*u),r*sin(2.0*u),-sin(3.0*u)*1.3)*vec3(1.45,1.45,1.45)" \
   "+vec3(0.0,4.2,0.0);}\n"

#define GLSL_LIGHTING \
   "const float PI=3.14159265;\n" \
   "vec3 sky(vec3 d){float t=clamp(d.y*0.5+0.5,0.0,1.0);" \
   "vec3 c=mix(vec3(0.05,0.03,0.09),vec3(0.004,0.008,0.03),pow(t,0.6));" \
   "float band=sin(d.x*3.1+camera.w*0.23)*0.5+sin(d.z*4.7-camera.w*0.17)*0.5;" \
   "float aur=smoothstep(0.15,0.55,d.y)*smoothstep(0.95,0.35,d.y)*" \
   "pow(max(0.0,sin(d.y*9.0+band*2.3+camera.w*0.11)),6.0);" \
   "c+=aur*mix(vec3(0.05,0.9,0.55),vec3(0.55,0.2,1.0),smoothstep(0.3,0.8,d.y))*1.6;" \
   "return c;}\n" \
   "vec3 shade(vec3 p,vec3 n,vec3 albedo,float rough,float metal,vec3 emissive){" \
   "vec3 v=normalize(camera.xyz-p);float ndv=max(dot(n,v),1e-3);" \
   "vec3 f0=mix(vec3(0.04),albedo,metal);float a=rough*rough;float a2=a*a;" \
   "vec3 col=sky(reflect(-v,n))*mix(vec3(0.08),f0,metal)*(1.0-rough*0.7)" \
   "+albedo*(1.0-metal)*mix(vec3(0.015,0.018,0.035),vec3(0.05,0.035,0.08),n.y*0.5+0.5);" \
   "for(int i=0;i<3;++i){vec3 l=light_pos[i].xyz-p;float d2=dot(l,l);l*=inversesqrt(d2);" \
   "vec3 h=normalize(v+l);float ndl=max(dot(n,l),0.0);float ndh=max(dot(n,h),0.0);" \
   "float dd=ndh*ndh*(a2-1.0)+1.0;float D=a2/(PI*dd*dd);" \
   "vec3 F=f0+(1.0-f0)*pow(1.0-max(dot(h,v),0.0),5.0);" \
   "float k=(rough+1.0)*(rough+1.0)/8.0;" \
   "float G=ndv/(ndv*(1.0-k)+k)*ndl/(ndl*(1.0-k)+k);" \
   "vec3 spec=D*F*G/max(4.0*ndv*ndl,1e-3);" \
   "vec3 diff=(1.0-F)*(1.0-metal)*albedo/PI;" \
   "col+=(diff+spec)*light_color[i].rgb*light_color[i].w*ndl/(1.0+d2*0.06);}" \
   "return col+emissive;}\n"

static const char *sky_vs =
   GLSL_HEADER
   "out vec2 v_ndc;"
   "void main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2)*2.0-1.0;"
   "v_ndc=p;gl_Position=vec4(p,1.0,1.0);}\n";

static const char *sky_fs =
   GLSL_HEADER GLSL_LIGHTING
   "in vec2 v_ndc;layout(location=0) out vec4 out_color;"
   "float hash(vec3 p){p=fract(p*0.3183099+0.1);p*=17.0;return fract(p.x*p.y*p.z*(p.x+p.y+p.z));}"
   "void main(){vec4 w=inv_view_proj*vec4(v_ndc,1.0,1.0);vec3 d=normalize(w.xyz/w.w-camera.xyz);"
   "vec3 c=sky(d);vec3 q=floor(d*420.0);float s=hash(q);"
   "float tw=0.6+0.4*sin(camera.w*2.0+s*40.0);"
   "c+=vec3(0.9,0.95,1.0)*step(0.9965,s)*tw*smoothstep(0.0,0.25,d.y)*3.0;"
   "out_color=vec4(c,1.0);}\n";

static const char *mesh_vs =
   GLSL_HEADER
   "layout(location=0) in vec3 in_position;layout(location=1) in vec3 in_normal;"
   "layout(location=2) in vec2 in_uv;"
   "uniform mat4 u_model;out vec3 v_world;out vec3 v_normal;out vec2 v_uv;"
   "void main(){vec4 w=u_model*vec4(in_position,1.0);v_world=w.xyz;"
   "v_normal=mat3(u_model)*in_normal;v_uv=in_uv;gl_Position=view_proj*w;}\n";

/* The knot: an iridescent metal tube with pulses of light running along it. */
static const char *knot_fs =
   GLSL_HEADER GLSL_LIGHTING
   "in vec3 v_world;in vec3 v_normal;in vec2 v_uv;layout(location=0) out vec4 out_color;"
   "void main(){vec3 n=normalize(v_normal);vec3 v=normalize(camera.xyz-v_world);"
   "float film=dot(n,v);vec3 iri=0.55+0.45*cos(6.2831*(film*1.3+vec3(0.0,0.33,0.67)+v_uv.x*2.0));"
   "float pulse=pow(max(0.0,sin(v_uv.x*6.2831*7.0-camera.w*2.6)),10.0);"
   "float seam=smoothstep(0.30,0.48,abs(v_uv.y-0.5));"
   "vec3 emissive=mix(vec3(0.1,0.9,1.0),vec3(1.0,0.25,0.8),0.5+0.5*sin(v_uv.x*12.566+camera.w*0.4))"
   "*(pulse*14.0*seam+0.35*seam);"
   "out_color=vec4(shade(v_world,n,iri*0.95,0.22,0.92,emissive),1.0);}\n";

/* The floor: a mipmapped grid sampled with 16x anisotropic filtering. */
static const char *floor_fs =
   GLSL_HEADER GLSL_LIGHTING
   "in vec3 v_world;in vec3 v_normal;in vec2 v_uv;layout(location=0) out vec4 out_color;"
   "layout(binding=0) uniform sampler2D u_grid;"
   "void main(){vec3 g=texture(u_grid,v_world.xz*0.125).rgb;"
   "float dist=length(v_world.xz-camera.xz);"
   "float ripple=0.5+0.5*sin(length(v_world.xz)*0.9-camera.w*1.6);"
   "vec3 glow=g*g*vec3(0.25,0.55,1.2)*(0.6+0.8*ripple)*2.5;"
   "vec3 c=shade(v_world,vec3(0,1,0),vec3(0.03,0.035,0.05)+g*0.2,0.45,0.2,glow);"
   "vec3 fogc=sky(normalize(vec3(v_world.x-camera.x,0.02,v_world.z-camera.z)));"
   "c=mix(c,fogc,smoothstep(18.0,70.0,dist));out_color=vec4(c,1.0);}\n";

/* Instances written by the culling pass; material chosen by gl_DrawID. */
static const char *instance_vs =
   GLSL_HEADER
   "layout(location=0) in vec3 in_position;"
   "struct Instance{vec4 pos_scale;vec4 rotation;vec4 color;};"
   "layout(std430,binding=1) readonly buffer Visible{Instance items[];};"
   "out vec3 v_world;flat out vec4 v_color;flat out int v_kind;"
   "vec3 qrot(vec4 q,vec3 v){return v+2.0*cross(q.xyz,cross(q.xyz,v)+q.w*v);}"
   "void main(){Instance it=items[gl_BaseInstance+gl_InstanceID];"
   "vec3 w=qrot(it.rotation,in_position*it.pos_scale.w)+it.pos_scale.xyz;"
   "v_world=w;v_color=it.color;v_kind=gl_DrawID;gl_Position=view_proj*vec4(w,1.0);}\n";

static const char *instance_fs =
   GLSL_HEADER GLSL_LIGHTING
   "in vec3 v_world;flat in vec4 v_color;flat in int v_kind;layout(location=0) out vec4 out_color;"
   "void main(){vec3 n=normalize(cross(dFdx(v_world),dFdy(v_world)));"
   "if(dot(n,camera.xyz-v_world)<0.0)n=-n;vec3 c;"
   "if(v_kind==0){float edge=pow(1.0-abs(dot(n,normalize(camera.xyz-v_world))),3.0);"
   "c=shade(v_world,n,v_color.rgb*0.35,0.12,0.1,v_color.rgb*(0.55+2.8*edge)*v_color.w);}"
   "else{c=shade(v_world,n,vec3(0.92,0.93,0.97),0.18,1.0,vec3(0.0));}"
   "out_color=vec4(c,1.0);}\n";

/* Compute: animate every instance, cull against the frustum and append the
 * visible ones to their draw command (instance counts rebuilt every frame). */
static const char *cull_cs =
   GLSL_HEADER
   "layout(local_size_x=64) in;"
   "struct Instance{vec4 pos_scale;vec4 rotation;vec4 color;};"
   "struct Command{uint count;uint instance_count;uint first_index;int base_vertex;uint base_instance;};"
   "layout(std430,binding=1) writeonly buffer Visible{Instance items[];};"
   "layout(std430,binding=2) buffer Commands{Command cmds[];};"
   "uniform uint u_gems;uniform uint u_total;"
   "vec3 hue(float h){return clamp(abs(fract(h+vec3(0.0,0.667,0.333))*6.0-3.0)-1.0,0.0,1.0);}"
   "void main(){uint id=gl_GlobalInvocationID.x;if(id>=u_total)return;"
   "uint kind=id<u_gems?0u:1u;float f=float(id);float t=camera.w;"
   "float r=7.0+30.0*sqrt(fract(f*0.61803398));"
   "float ang=f*2.39996323+t*(0.55/(1.0+r*0.09))*(kind==0u?1.0:-0.8);"
   "float y=1.2+fract(f*0.7548776)*9.0*exp(-r*0.035)+sin(ang*2.0+f*0.37)*0.8;"
   "vec3 p=vec3(cos(ang)*r,y,sin(ang)*r);"
   "float s=kind==0u?0.16+0.16*fract(f*0.137):0.12+0.1*fract(f*0.311);"
   "vec4 clip=view_proj*vec4(p,1.0);float m=clip.w+s*6.0;"
   "if(clip.w<2.5||abs(clip.x)>m||abs(clip.y)>m)return;"
   "vec3 axis=normalize(vec3(sin(f*1.3),cos(f*0.7),sin(f*2.1)+0.3));"
   "float a=t*(0.6+fract(f*0.271)*1.4)+f;"
   "vec4 q=vec4(axis*sin(a*0.5),cos(a*0.5));"
   "float h=fract(0.52+0.22*sin(ang*0.5+t*0.05)+0.12*fract(f*0.07));"
   "vec3 col=mix(hue(h),vec3(1.0),0.15);"
   "uint slot=atomicAdd(cmds[kind].instance_count,1u);"
   "items[cmds[kind].base_instance+slot]=Instance(vec4(p,s),q,vec4(col,0.8+0.6*fract(f*0.53)));}\n";

/* Compute: particles advected by a flow field, respawned on the knot. */
static const char *particle_cs =
   GLSL_HEADER GLSL_KNOT
   "layout(local_size_x=256) in;"
   "struct Particle{vec4 pos_life;vec4 vel_seed;};"
   "layout(std430,binding=3) buffer Particles{Particle ps[];};"
   "uniform float u_dt;"
   "float hash(float n){return fract(sin(n)*43758.5453);}"
   "void main(){uint id=gl_GlobalInvocationID.x;if(id>=uint(ps.length()))return;"
   "Particle p=ps[id];float t=camera.w;vec3 x=p.pos_life.xyz;vec3 v=p.vel_seed.xyz;"
   "vec3 flow=vec3(sin(x.y*0.61+t*0.31)+cos(x.z*0.37),"
   "sin(x.z*0.53-t*0.23)+cos(x.x*0.41)*0.6+0.35,"
   "sin(x.x*0.47+t*0.27)+cos(x.y*0.29));"
   "vec3 toward=vec3(0.0,4.2,0.0)-x;float d=length(toward);"
   "vec3 swirl=cross(vec3(0.0,1.0,0.0),toward)/max(d,0.5);"
   "v=v*0.982+(flow*0.9+swirl*0.6+toward*0.02)*u_dt*2.2;"
   "x+=v*u_dt;float life=p.pos_life.w-u_dt*(0.09+0.08*hash(p.vel_seed.w));"
   "if(life<=0.0){float seed=p.vel_seed.w+t;"
   "float u=hash(seed*1.7)*6.2831853;x=knot(u);"
   "vec3 tangent=normalize(knot(u+0.01)-x);"
   "vec3 side=normalize(cross(tangent,vec3(hash(seed),hash(seed+3.1),hash(seed+7.7))-0.5));"
   "x+=side*0.55;v=side*(0.6+hash(seed*2.3)*1.4)+tangent*0.5;life=1.0;}"
   "ps[id]=Particle(vec4(x,life),vec4(v,p.vel_seed.w));}\n";

static const char *particle_vs =
   GLSL_HEADER
   "struct Particle{vec4 pos_life;vec4 vel_seed;};"
   "layout(std430,binding=3) readonly buffer Particles{Particle ps[];};"
   "out vec2 v_corner;out vec3 v_color;"
   "void main(){uint id=uint(gl_VertexID)/6u;uint c=uint(gl_VertexID)%6u;"
   "vec2 corner=vec2((c==1u||c==2u||c==4u)?1.0:-1.0,(c==2u||c==4u||c==5u)?1.0:-1.0);"
   "Particle p=ps[id];float life=p.pos_life.w;float speed=length(p.vel_seed.xyz);"
   "float size=cam_right.w*(0.3+life*0.7);"
   "vec3 w=p.pos_life.xyz+(cam_right.xyz*corner.x+cam_up.xyz*corner.y)*size;"
   "v_corner=corner;"
   "v_color=mix(vec3(1.0,0.2,0.7),vec3(0.15,0.85,1.0),clamp(speed*0.4,0.0,1.0))"
   "*(0.15+1.4*life*life)*cam_up.w;gl_Position=view_proj*vec4(w,1.0);}\n";

static const char *particle_fs =
   "#version 460 core\n"
   "in vec2 v_corner;in vec3 v_color;layout(location=0) out vec4 out_color;"
   "void main(){float d=dot(v_corner,v_corner);if(d>1.0)discard;"
   "out_color=vec4(v_color*exp(-d*4.0)*0.9,1.0);}\n";

/* Bloom: soft-threshold prefilter, then downsample and tent upsample, each a
 * fullscreen pass into the next level's framebuffer (or, with
 * SHOWCASE_COMPUTE_BLOOM, a compute dispatch writing the level as an image). */
#define BLOOM_FILTER(OUTPUT, POSITION, STORE) \
   "#version 460 core\n" OUTPUT \
   "layout(binding=0) uniform sampler2D u_src;layout(binding=1) uniform sampler2D u_add;" \
   "uniform int u_mode;uniform vec2 u_dst_size;" \
   "vec3 box(vec2 uv,vec2 px){return(texture(u_src,uv+px*vec2(-1,-1)).rgb+" \
   "texture(u_src,uv+px*vec2(1,-1)).rgb+texture(u_src,uv+px*vec2(-1,1)).rgb+" \
   "texture(u_src,uv+px*vec2(1,1)).rgb)*0.25;}" \
   "vec3 tent(vec2 uv,vec2 px){vec3 s=texture(u_src,uv).rgb*4.0;" \
   "s+=(texture(u_src,uv+vec2(px.x,0)).rgb+texture(u_src,uv-vec2(px.x,0)).rgb+" \
   "texture(u_src,uv+vec2(0,px.y)).rgb+texture(u_src,uv-vec2(0,px.y)).rgb)*2.0;" \
   "s+=texture(u_src,uv+px).rgb+texture(u_src,uv-px).rgb+" \
   "texture(u_src,uv+vec2(px.x,-px.y)).rgb+texture(u_src,uv+vec2(-px.x,px.y)).rgb;" \
   "return s/16.0;}" \
   "void main(){" POSITION "vec2 uv=xy/u_dst_size;" \
   "vec2 px=1.0/vec2(textureSize(u_src,0));vec3 c;" \
   "if(u_mode==0){c=box(uv,px);float b=max(c.r,max(c.g,c.b));" \
   "float soft=clamp(b-0.7,0.0,1.0);soft=soft*soft/2.0;" \
   "c*=max(soft,b-1.2)/max(b,1e-4);c=min(c,vec3(60.0));}" \
   "else if(u_mode==1){c=box(uv,px);}" \
   "else{c=tent(uv,px)+texture(u_add,uv).rgb;}" \
   STORE "}\n"

#if SHOWCASE_COMPUTE_BLOOM
static const char *bloom_cs = BLOOM_FILTER(
   "layout(local_size_x=8,local_size_y=8) in;"
   "layout(rgba16f,binding=0) writeonly uniform image2D u_dst;",
   "ivec2 p=ivec2(gl_GlobalInvocationID.xy);"
   "if(any(greaterThanEqual(vec2(p),u_dst_size)))return;vec2 xy=vec2(p)+0.5;",
   "imageStore(u_dst,p,vec4(c,1.0));");
#else
static const char *bloom_fs = BLOOM_FILTER(
   "layout(location=0) out vec4 out_color;",
   "vec2 xy=gl_FragCoord.xy;",
   "out_color=vec4(c,1.0);");
#endif

/* Final image: bloom, ACES, vignette, grain and the HUD text. */
static const char *composite_fs =
   GLSL_HEADER
   "layout(location=0) out vec4 out_color;"
   "layout(binding=0) uniform sampler2D u_scene;layout(binding=1) uniform sampler2D u_bloom;"
   "layout(binding=2) uniform sampler2D u_font;"
   "uniform uint u_text[" "192" "];uniform float u_hud_scale;"
   "vec3 aces(vec3 x){return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),0.0,1.0);}"
   "float glyph(vec2 px){vec2 origin=vec2(params.x*0.045,params.y*0.06);"
   "vec2 cell=vec2(6.0,11.0)*u_hud_scale;vec2 q=(px-origin)/cell;"
   "if(q.x<0.0||q.y<0.0||q.x>=48.0||q.y>=4.0)return 0.0;"
   "uint ch=u_text[uint(q.y)*48u+uint(q.x)];vec2 in_cell=fract(q)*vec2(6.0,11.0);"
   "if(in_cell.x>=5.0||in_cell.y>=7.0)return 0.0;"
   "return texelFetch(u_font,ivec2(int(ch)*6+int(in_cell.x),int(in_cell.y)),0).r;}"
   "void main(){vec2 uv=gl_FragCoord.xy/params.xy;"
   "vec3 hdr=texture(u_scene,uv).rgb+texture(u_bloom,uv).rgb*0.75;"
   "vec3 c=aces(hdr*1.1);float vig=smoothstep(1.25,0.35,length((uv-0.5)*vec2(params.z,1.0)));"
   "c*=mix(0.55,1.0,vig);c=pow(c,vec3(1.0/2.2));"
   "float grain=fract(sin(dot(gl_FragCoord.xy+params.w,vec2(12.9898,78.233)))*43758.5453);"
   "c+=(grain-0.5)/255.0*2.0;"
   "vec2 px=vec2(gl_FragCoord.x,params.y-gl_FragCoord.y);"
   "vec2 panel0=vec2(params.x*0.045,params.y*0.06)-vec2(18.0)*u_hud_scale*0.5;"
   "vec2 panel1=panel0+vec2(48.0*6.0,4.0*11.0)*u_hud_scale+vec2(18.0)*u_hud_scale*0.5;"
   "if(all(greaterThan(px,panel0))&&all(lessThan(px,panel1)))c*=0.45;"
   "float g=glyph(px);float line=floor((px.y-params.y*0.06)/(11.0*u_hud_scale));"
   "vec3 ink=line<0.5?vec3(0.35,0.95,1.0):vec3(0.93,0.95,1.0);"
   "c=mix(c,ink,g);out_color=vec4(c,1.0);}\n";

static const char *fullscreen_vs =
   "#version 460 core\n"
   "void main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2)*2.0-1.0;"
   "gl_Position=vec4(p,0.0,1.0);}\n";

/* ------------------------------------------------------------------- font */

/* Classic 5x7 glyphs, column-major, bit 0 = top row. */
static const char font_chars[] =
   " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.:/-@+";
static const uint8_t font_columns[][5] = {
   {0x00, 0x00, 0x00, 0x00, 0x00}, {0x3E, 0x51, 0x49, 0x45, 0x3E},
   {0x00, 0x42, 0x7F, 0x40, 0x00}, {0x42, 0x61, 0x51, 0x49, 0x46},
   {0x21, 0x41, 0x45, 0x4B, 0x31}, {0x18, 0x14, 0x12, 0x7F, 0x10},
   {0x27, 0x45, 0x45, 0x45, 0x39}, {0x3C, 0x4A, 0x49, 0x49, 0x30},
   {0x01, 0x71, 0x09, 0x05, 0x03}, {0x36, 0x49, 0x49, 0x49, 0x36},
   {0x06, 0x49, 0x49, 0x29, 0x1E}, {0x7E, 0x11, 0x11, 0x11, 0x7E},
   {0x7F, 0x49, 0x49, 0x49, 0x36}, {0x3E, 0x41, 0x41, 0x41, 0x22},
   {0x7F, 0x41, 0x41, 0x22, 0x1C}, {0x7F, 0x49, 0x49, 0x49, 0x41},
   {0x7F, 0x09, 0x09, 0x09, 0x01}, {0x3E, 0x41, 0x49, 0x49, 0x7A},
   {0x7F, 0x08, 0x08, 0x08, 0x7F}, {0x00, 0x41, 0x7F, 0x41, 0x00},
   {0x20, 0x40, 0x41, 0x3F, 0x01}, {0x7F, 0x08, 0x14, 0x22, 0x41},
   {0x7F, 0x40, 0x40, 0x40, 0x40}, {0x7F, 0x02, 0x0C, 0x02, 0x7F},
   {0x7F, 0x04, 0x08, 0x10, 0x7F}, {0x3E, 0x41, 0x41, 0x41, 0x3E},
   {0x7F, 0x09, 0x09, 0x09, 0x06}, {0x3E, 0x41, 0x51, 0x21, 0x5E},
   {0x7F, 0x09, 0x19, 0x29, 0x46}, {0x46, 0x49, 0x49, 0x49, 0x31},
   {0x01, 0x01, 0x7F, 0x01, 0x01}, {0x3F, 0x40, 0x40, 0x40, 0x3F},
   {0x1F, 0x20, 0x40, 0x20, 0x1F}, {0x3F, 0x40, 0x38, 0x40, 0x3F},
   {0x63, 0x14, 0x08, 0x14, 0x63}, {0x07, 0x08, 0x70, 0x08, 0x07},
   {0x61, 0x51, 0x49, 0x45, 0x43}, {0x00, 0x60, 0x60, 0x00, 0x00},
   {0x00, 0x36, 0x36, 0x00, 0x00}, {0x20, 0x10, 0x08, 0x04, 0x02},
   {0x08, 0x08, 0x08, 0x08, 0x08}, {0x32, 0x49, 0x79, 0x41, 0x3E},
   {0x08, 0x08, 0x3E, 0x08, 0x08},
};

static GLuint
make_font_texture(void)
{
   enum { COUNT = sizeof(font_columns) / sizeof(font_columns[0]) };
   static uint8_t pixels[8][COUNT * 6];
   for (unsigned g = 0; g < COUNT; ++g)
      for (unsigned x = 0; x < 5; ++x)
         for (unsigned y = 0; y < 7; ++y)
            pixels[y][g * 6 + x] = (font_columns[g][x] >> y) & 1u ? 255 : 0;
   GLuint texture = 0;
   glCreateTextures(GL_TEXTURE_2D, 1, &texture);
   glTextureStorage2D(texture, 1, GL_R8, COUNT * 6, 8);
   glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
   glTextureSubImage2D(texture, 0, 0, 0, COUNT * 6, 8, GL_RED, GL_UNSIGNED_BYTE, pixels);
   glTextureParameteri(texture, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
   glTextureParameteri(texture, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
   return texture;
}

/* Upper-cases and maps text into glyph indices; unknown characters are blank. */
static void
set_line(uint32_t *text, unsigned line, const char *value)
{
   for (unsigned c = 0; c < TEXT_COLUMNS; ++c) {
      char ch = value && *value ? *value++ : ' ';
      if (ch >= 'a' && ch <= 'z')
         ch = (char)(ch - 'a' + 'A');
      const char *at = strchr(font_chars, ch);
      text[line * TEXT_COLUMNS + c] = at && ch ? (uint32_t)(at - font_chars) : 0u;
   }
}

/* ------------------------------------------------------------------- math */

static void
mat_mul(float *out, const float *a, const float *b)
{
   float r[16];
   for (int c = 0; c < 4; ++c)
      for (int row = 0; row < 4; ++row)
         r[c * 4 + row] = a[0 * 4 + row] * b[c * 4 + 0] + a[1 * 4 + row] * b[c * 4 + 1] +
                          a[2 * 4 + row] * b[c * 4 + 2] + a[3 * 4 + row] * b[c * 4 + 3];
   memcpy(out, r, sizeof(r));
}

static void
perspective(float *m, float fovy, float aspect, float near_z, float far_z)
{
   const float f = 1.0f / tanf(fovy * 0.5f);
   memset(m, 0, 16 * sizeof(float));
   m[0] = f / aspect;
   m[5] = f;
   m[10] = (far_z + near_z) / (near_z - far_z);
   m[11] = -1.0f;
   m[14] = 2.0f * far_z * near_z / (near_z - far_z);
}

static void
normalize3(float *v)
{
   const float l = sqrtf(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
   v[0] /= l;
   v[1] /= l;
   v[2] /= l;
}

static void
cross3(float *out, const float *a, const float *b)
{
   out[0] = a[1] * b[2] - a[2] * b[1];
   out[1] = a[2] * b[0] - a[0] * b[2];
   out[2] = a[0] * b[1] - a[1] * b[0];
}

static void
look_at(float *m, const float *eye, const float *target, float *right, float *up)
{
   float f[3] = {target[0] - eye[0], target[1] - eye[1], target[2] - eye[2]};
   const float world_up[3] = {0.0f, 1.0f, 0.0f};
   normalize3(f);
   cross3(right, f, world_up);
   normalize3(right);
   cross3(up, right, f);
   const float view[16] = {
      right[0], up[0], -f[0], 0.0f, right[1], up[1], -f[1], 0.0f,
      right[2], up[2], -f[2], 0.0f,
      -(right[0] * eye[0] + right[1] * eye[1] + right[2] * eye[2]),
      -(up[0] * eye[0] + up[1] * eye[1] + up[2] * eye[2]),
      f[0] * eye[0] + f[1] * eye[1] + f[2] * eye[2], 1.0f,
   };
   memcpy(m, view, sizeof(view));
}

static int
invert(float *out, const float *m)
{
   float inv[16];
   inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] +
            m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
   inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] -
            m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
   inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] +
            m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
   inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] -
             m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
   inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] -
            m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
   inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] +
            m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
   inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] -
            m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
   inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] +
             m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
   inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] +
            m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
   inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] -
            m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
   inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] +
             m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
   inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] -
             m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
   inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] -
            m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
   inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] +
            m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
   inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] -
             m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
   inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] +
             m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];
   const float det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
   if (det == 0.0f)
      return 0;
   for (int i = 0; i < 16; ++i)
      out[i] = inv[i] / det;
   return 1;
}

/* ---------------------------------------------------------------- geometry */

/* Deterministic [0, 1) random numbers (xorshift32), identical on every platform. */
static uint32_t random_state = 0x50533553u;

static float
random01(void)
{
   random_state ^= random_state << 13;
   random_state ^= random_state >> 17;
   random_state ^= random_state << 5;
   return (float)(random_state >> 8) * (1.0f / 16777216.0f);
}

static void
knot_point(float u, float *p)
{
   const float r = cosf(3.0f * u) + 2.2f;
   p[0] = r * cosf(2.0f * u) * 1.45f;
   p[1] = r * sinf(2.0f * u) * 1.45f + 4.2f;
   p[2] = -sinf(3.0f * u) * 1.3f * 1.45f;
}

/* Vertices: knot tube, gem (icosahedron), cube, floor; indices follow. */
struct geometry {
   struct vertex *vertices;
   uint32_t *indices;
   uint32_t vertex_count, index_count;
   uint32_t knot_first, knot_count;
   uint32_t gem_first, gem_count, gem_base_vertex;
   uint32_t cube_first, cube_count, cube_base_vertex;
   uint32_t floor_first, floor_count, floor_base_vertex;
};

static void
put_vertex(struct geometry *g, float x, float y, float z, float nx, float ny, float nz,
           float u, float v)
{
   struct vertex *out = &g->vertices[g->vertex_count++];
   out->position[0] = x;
   out->position[1] = y;
   out->position[2] = z;
   out->normal[0] = nx;
   out->normal[1] = ny;
   out->normal[2] = nz;
   out->uv[0] = u;
   out->uv[1] = v;
}

static int
build_geometry(struct geometry *g)
{
   const uint32_t knot_vertices = (KNOT_SEGMENTS + 1) * (KNOT_SIDES + 1);
   g->vertices = calloc(knot_vertices + 12 + 24 + 4, sizeof(struct vertex));
   g->indices = calloc(KNOT_SEGMENTS * KNOT_SIDES * 6 + 60 + 36 + 6, sizeof(uint32_t));
   if (!g->vertices || !g->indices)
      return 0;

   /* Knot tube along the (2,3) torus knot, with a parallel-transport frame. */
   g->knot_first = g->index_count;
   float normal[3] = {0.0f, 0.0f, 1.0f};
   for (uint32_t s = 0; s <= KNOT_SEGMENTS; ++s) {
      const float u = (float)s / KNOT_SEGMENTS * 6.2831853f;
      float p[3], q[3], t[3], b[3];
      knot_point(u, p);
      knot_point(u + 0.001f, q);
      t[0] = q[0] - p[0];
      t[1] = q[1] - p[1];
      t[2] = q[2] - p[2];
      normalize3(t);
      cross3(b, t, normal);
      normalize3(b);
      cross3(normal, b, t);
      for (uint32_t k = 0; k <= KNOT_SIDES; ++k) {
         const float a = (float)k / KNOT_SIDES * 6.2831853f;
         const float c = cosf(a), sn = sinf(a), radius = 0.42f;
         const float n[3] = {normal[0] * c + b[0] * sn, normal[1] * c + b[1] * sn,
                             normal[2] * c + b[2] * sn};
         put_vertex(g, p[0] + n[0] * radius, p[1] + n[1] * radius, p[2] + n[2] * radius,
                    n[0], n[1], n[2], (float)s / KNOT_SEGMENTS, (float)k / KNOT_SIDES);
      }
   }
   for (uint32_t s = 0; s < KNOT_SEGMENTS; ++s)
      for (uint32_t k = 0; k < KNOT_SIDES; ++k) {
         const uint32_t a = s * (KNOT_SIDES + 1) + k, b2 = a + KNOT_SIDES + 1;
         const uint32_t quad[6] = {a, b2, a + 1, a + 1, b2, b2 + 1};
         memcpy(&g->indices[g->index_count], quad, sizeof(quad));
         g->index_count += 6;
      }
   g->knot_count = g->index_count - g->knot_first;

   /* Gem: an icosahedron (flat-shaded from screen-space derivatives). */
   g->gem_base_vertex = g->vertex_count;
   g->gem_first = g->index_count;
   const float gr = 1.6180339f;
   const float ico[12][3] = {
      {-1, gr, 0}, {1, gr, 0}, {-1, -gr, 0}, {1, -gr, 0}, {0, -1, gr}, {0, 1, gr},
      {0, -1, -gr}, {0, 1, -gr}, {gr, 0, -1}, {gr, 0, 1}, {-gr, 0, -1}, {-gr, 0, 1},
   };
   for (int i = 0; i < 12; ++i)
      put_vertex(g, ico[i][0] * 0.6f, ico[i][1] * 0.6f, ico[i][2] * 0.6f, 0, 0, 0, 0, 0);
   static const uint32_t ico_faces[60] = {
      0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2,
      10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4,
      11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
   };
   memcpy(&g->indices[g->index_count], ico_faces, sizeof(ico_faces));
   g->index_count += 60;
   g->gem_count = 60;

   /* Chrome cube. */
   g->cube_base_vertex = g->vertex_count;
   g->cube_first = g->index_count;
   static const float corners[8][3] = {
      {-1, -1, -1}, {1, -1, -1}, {1, 1, -1}, {-1, 1, -1},
      {-1, -1, 1},  {1, -1, 1},  {1, 1, 1},  {-1, 1, 1},
   };
   for (int i = 0; i < 8; ++i)
      put_vertex(g, corners[i][0], corners[i][1], corners[i][2], 0, 0, 0, 0, 0);
   static const uint32_t cube_faces[36] = {
      4, 5, 6, 4, 6, 7, 5, 1, 2, 5, 2, 6, 0, 4, 7, 0, 7, 3,
      7, 6, 2, 7, 2, 3, 0, 1, 5, 0, 5, 4, 1, 0, 3, 1, 3, 2,
   };
   memcpy(&g->indices[g->index_count], cube_faces, sizeof(cube_faces));
   g->index_count += 36;
   g->cube_count = 36;

   /* Floor quad. */
   g->floor_base_vertex = g->vertex_count;
   g->floor_first = g->index_count;
   const float e = 90.0f;
   put_vertex(g, -e, 0, -e, 0, 1, 0, 0, 0);
   put_vertex(g, e, 0, -e, 0, 1, 0, 1, 0);
   put_vertex(g, e, 0, e, 0, 1, 0, 1, 1);
   put_vertex(g, -e, 0, e, 0, 1, 0, 0, 1);
   static const uint32_t floor_quad[6] = {0, 2, 1, 0, 3, 2};
   memcpy(&g->indices[g->index_count], floor_quad, sizeof(floor_quad));
   g->index_count += 6;
   g->floor_count = 6;
   return 1;
}

static GLuint
make_grid_texture(void)
{
   enum { SIZE = 1024 };
   uint8_t *pixels = malloc(SIZE * SIZE * 4);
   if (!pixels)
      return 0;
   for (int y = 0; y < SIZE; ++y)
      for (int x = 0; x < SIZE; ++x) {
         const int major = (x % 256 < 5 || y % 256 < 5);
         const int minor = (x % 64 < 2 || y % 64 < 2);
         const float v = major ? 1.0f : minor ? 0.35f : 0.0f;
         uint8_t *p = &pixels[(y * SIZE + x) * 4];
         p[0] = (uint8_t)(v * 120.0f);
         p[1] = (uint8_t)(v * 200.0f);
         p[2] = (uint8_t)(v * 255.0f);
         p[3] = 255;
      }
   GLuint texture = 0;
   int levels = 1;
   while ((SIZE >> levels) > 0)
      ++levels;
   glCreateTextures(GL_TEXTURE_2D, 1, &texture);
   glTextureStorage2D(texture, levels, GL_RGBA8, SIZE, SIZE);
   glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
   glTextureSubImage2D(texture, 0, 0, 0, SIZE, SIZE, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
   glGenerateTextureMipmap(texture);
   glTextureParameteri(texture, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
   glTextureParameteri(texture, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
   glTextureParameteri(texture, GL_TEXTURE_WRAP_S, GL_REPEAT);
   glTextureParameteri(texture, GL_TEXTURE_WRAP_T, GL_REPEAT);
   GLfloat max_anisotropy = 1.0f;
   glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY, &max_anisotropy);
   glTextureParameterf(texture, GL_TEXTURE_MAX_ANISOTROPY,
                       max_anisotropy < 16.0f ? max_anisotropy : 16.0f);
   free(pixels);
   return texture;
}

/* ---------------------------------------------------------------- programs */

static GLuint
compile(GLenum type, const char *source, const char *name)
{
   GLuint shader = glCreateShader(type);
   GLint ok = GL_FALSE;
   glShaderSource(shader, 1, &source, NULL);
   glCompileShader(shader);
   glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
   if (!ok) {
      char log[4096] = {0};
      GLsizei length = 0;
      glGetShaderInfoLog(shader, sizeof(log), &length, log);
      say(TAG " shader=%s log=%.*s", name, length, log);
      glDeleteShader(shader);
      return 0;
   }
   return shader;
}

static GLuint
program(const char *name, const char *first, GLenum first_type, const char *second)
{
   GLuint a = compile(first_type, first, name);
   GLuint b = second ? compile(GL_FRAGMENT_SHADER, second, name) : 0;
   GLuint linked = 0;
   GLint ok = GL_FALSE;
   if (!a || (second && !b))
      goto done;
   linked = glCreateProgram();
   glAttachShader(linked, a);
   if (b)
      glAttachShader(linked, b);
   glLinkProgram(linked);
   glGetProgramiv(linked, GL_LINK_STATUS, &ok);
   if (!ok) {
      char log[4096] = {0};
      GLsizei length = 0;
      glGetProgramInfoLog(linked, sizeof(log), &length, log);
      say(TAG " program=%s link=%.*s", name, length, log);
      glDeleteProgram(linked);
      linked = 0;
   }
done:
   if (a)
      glDeleteShader(a);
   if (b)
      glDeleteShader(b);
   return linked;
}

static GLuint
float_texture(GLsizei width, GLsizei height)
{
   GLuint texture = 0;
   glCreateTextures(GL_TEXTURE_2D, 1, &texture);
   glTextureStorage2D(texture, 1, GL_RGBA16F, width, height);
   glTextureParameteri(texture, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
   glTextureParameteri(texture, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
   glTextureParameteri(texture, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
   glTextureParameteri(texture, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
   return texture;
}

/* --------------------------------------------------------------------- run */

#ifdef SHOWCASE_HOST_PREVIEW
static void GLAPIENTRY
debug_message(GLenum source, GLenum type, GLuint id, GLenum severity, GLsizei length,
              const GLchar *message, const void *user)
{
   (void)source;
   (void)id;
   (void)user;
   if (type == GL_DEBUG_TYPE_ERROR || severity == GL_DEBUG_SEVERITY_HIGH)
      say(TAG " gl-debug: %.*s", (int)length, message);
}
#endif

struct scene {
   GLuint sky, knot, floor, instances, cull, particles_update, particles_draw, bloom, composite;
   GLint model_knot, model_floor, cull_gems, cull_total, particle_dt, bloom_mode, text,
      hud_scale, bloom_size_uniform;
   GLuint vao, vertex_buffer, index_buffer, frame_buffer, visible_buffer, command_buffer,
      count_buffer, particle_buffer;
   GLuint grid, font, hdr, depth, framebuffer;
   GLuint bloom_down[BLOOM_LEVELS], bloom_up[BLOOM_LEVELS];
   GLuint bloom_down_fb[BLOOM_LEVELS], bloom_up_fb[BLOOM_LEVELS];
   GLsizei bloom_size[BLOOM_LEVELS][2];
   struct draw_elements_indirect commands[2];
   uint32_t floor_first, floor_base_vertex;
};

static void
bloom_pass(struct scene *s, GLuint src, GLuint add, int level, bool up, int mode, GLsizei w,
           GLsizei h)
{
   glUniform1i(s->bloom_mode, mode);
   glUniform2f(s->bloom_size_uniform, (float)w, (float)h);
   glBindTextureUnit(0, src);
   glBindTextureUnit(1, add ? add : src);
#if SHOWCASE_COMPUTE_BLOOM
   glBindImageTexture(0, up ? s->bloom_up[level] : s->bloom_down[level], 0, GL_FALSE, 0,
                      GL_WRITE_ONLY, GL_RGBA16F);
   glDispatchCompute((GLuint)(w + 7) / 8, (GLuint)(h + 7) / 8, 1);
   glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT | GL_TEXTURE_FETCH_BARRIER_BIT);
#else
   glBindFramebuffer(GL_FRAMEBUFFER, up ? s->bloom_up_fb[level] : s->bloom_down_fb[level]);
   glViewport(0, 0, w, h);
   glDrawArrays(GL_TRIANGLES, 0, 3);
#endif
}

static int
setup(struct scene *s, GLsizei width, GLsizei height)
{
   s->sky = program("sky", sky_vs, GL_VERTEX_SHADER, sky_fs);
   s->knot = program("knot", mesh_vs, GL_VERTEX_SHADER, knot_fs);
   s->floor = program("floor", mesh_vs, GL_VERTEX_SHADER, floor_fs);
   s->instances = program("instances", instance_vs, GL_VERTEX_SHADER, instance_fs);
   s->cull = program("cull", cull_cs, GL_COMPUTE_SHADER, NULL);
   s->particles_update = program("particles", particle_cs, GL_COMPUTE_SHADER, NULL);
   s->particles_draw = program("sparks", particle_vs, GL_VERTEX_SHADER, particle_fs);
#if SHOWCASE_COMPUTE_BLOOM
   s->bloom = program("bloom", bloom_cs, GL_COMPUTE_SHADER, NULL);
#else
   s->bloom = program("bloom", fullscreen_vs, GL_VERTEX_SHADER, bloom_fs);
#endif
   s->composite = program("composite", fullscreen_vs, GL_VERTEX_SHADER, composite_fs);
   if (!check(s->sky && s->knot && s->floor && s->instances && s->cull &&
                 s->particles_update && s->particles_draw && s->bloom && s->composite,
              "programs"))
      return 0;
   s->model_knot = glGetUniformLocation(s->knot, "u_model");
   s->model_floor = glGetUniformLocation(s->floor, "u_model");
   s->cull_gems = glGetUniformLocation(s->cull, "u_gems");
   s->cull_total = glGetUniformLocation(s->cull, "u_total");
   s->particle_dt = glGetUniformLocation(s->particles_update, "u_dt");
   s->bloom_mode = glGetUniformLocation(s->bloom, "u_mode");
   s->bloom_size_uniform = glGetUniformLocation(s->bloom, "u_dst_size");
   s->text = glGetUniformLocation(s->composite, "u_text");
   s->hud_scale = glGetUniformLocation(s->composite, "u_hud_scale");

   struct geometry g = {0};
   if (!check(build_geometry(&g), "geometry"))
      return 0;
   glCreateBuffers(1, &s->vertex_buffer);
   glNamedBufferStorage(s->vertex_buffer, g.vertex_count * sizeof(struct vertex), g.vertices, 0);
   glCreateBuffers(1, &s->index_buffer);
   glNamedBufferStorage(s->index_buffer, g.index_count * sizeof(uint32_t), g.indices, 0);
   s->floor_first = g.floor_first;
   s->floor_base_vertex = g.floor_base_vertex;
   free(g.vertices);
   free(g.indices);
   glCreateVertexArrays(1, &s->vao);
   glVertexArrayVertexBuffer(s->vao, 0, s->vertex_buffer, 0, sizeof(struct vertex));
   glVertexArrayElementBuffer(s->vao, s->index_buffer);
   for (GLuint a = 0; a < 3; ++a) {
      glEnableVertexArrayAttrib(s->vao, a);
      glVertexArrayAttribBinding(s->vao, a, 0);
   }
   glVertexArrayAttribFormat(s->vao, 0, 3, GL_FLOAT, GL_FALSE, offsetof(struct vertex, position));
   glVertexArrayAttribFormat(s->vao, 1, 3, GL_FLOAT, GL_FALSE, offsetof(struct vertex, normal));
   glVertexArrayAttribFormat(s->vao, 2, 2, GL_FLOAT, GL_FALSE, offsetof(struct vertex, uv));

   /* Two indirect commands (gems, cubes); the count comes from a buffer. */
   s->commands[0] = (struct draw_elements_indirect){g.gem_count, 0, g.gem_first,
                                                    (int32_t)g.gem_base_vertex, 0};
   s->commands[1] = (struct draw_elements_indirect){g.cube_count, 0, g.cube_first,
                                                    (int32_t)g.cube_base_vertex, GEMS};
   const uint32_t draw_count = 2;
   glCreateBuffers(1, &s->command_buffer);
   glNamedBufferStorage(s->command_buffer, sizeof(s->commands), s->commands,
                        GL_DYNAMIC_STORAGE_BIT);
   glCreateBuffers(1, &s->count_buffer);
   glNamedBufferStorage(s->count_buffer, sizeof(draw_count), &draw_count, 0);
   glCreateBuffers(1, &s->visible_buffer);
   glNamedBufferStorage(s->visible_buffer, INSTANCES * 12 * sizeof(float), NULL, 0);
   glCreateBuffers(1, &s->frame_buffer);
   glNamedBufferStorage(s->frame_buffer, sizeof(struct frame_block), NULL, GL_DYNAMIC_STORAGE_BIT);

   /* Particles start scattered around the knot with staggered lifetimes. */
   float *particles = malloc((size_t)PARTICLES * 8 * sizeof(float));
   if (!check(particles != NULL, "particle memory"))
      return 0;
   for (uint32_t i = 0; i < PARTICLES; ++i) {
      float p[3];
      knot_point(random01() * 6.2831853f, p);
      float *out = &particles[i * 8];
      for (int k = 0; k < 3; ++k)
         out[k] = p[k] + (random01() - 0.5f) * 3.0f;
      out[3] = random01();
      out[4] = out[5] = out[6] = 0.0f;
      out[7] = (float)i * 0.618034f;
   }
   glCreateBuffers(1, &s->particle_buffer);
   glNamedBufferStorage(s->particle_buffer, (GLsizeiptr)PARTICLES * 8 * sizeof(float),
                        particles, 0);
   free(particles);

   s->grid = make_grid_texture();
   s->font = make_font_texture();
   s->hdr = float_texture(width, height);
   glCreateRenderbuffers(1, &s->depth);
   glNamedRenderbufferStorage(s->depth, GL_DEPTH_COMPONENT24, width, height);
   glCreateFramebuffers(1, &s->framebuffer);
   glNamedFramebufferTexture(s->framebuffer, GL_COLOR_ATTACHMENT0, s->hdr, 0);
   glNamedFramebufferRenderbuffer(s->framebuffer, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, s->depth);
   if (!check(glCheckNamedFramebufferStatus(s->framebuffer, GL_FRAMEBUFFER) ==
                 GL_FRAMEBUFFER_COMPLETE,
              "HDR framebuffer"))
      return 0;
   GLsizei w = width / 2, h = height / 2;
   for (int i = 0; i < BLOOM_LEVELS; ++i) {
      s->bloom_size[i][0] = w > 1 ? w : 1;
      s->bloom_size[i][1] = h > 1 ? h : 1;
      s->bloom_down[i] = float_texture(s->bloom_size[i][0], s->bloom_size[i][1]);
      s->bloom_up[i] = float_texture(s->bloom_size[i][0], s->bloom_size[i][1]);
      glCreateFramebuffers(1, &s->bloom_down_fb[i]);
      glNamedFramebufferTexture(s->bloom_down_fb[i], GL_COLOR_ATTACHMENT0, s->bloom_down[i], 0);
      glCreateFramebuffers(1, &s->bloom_up_fb[i]);
      glNamedFramebufferTexture(s->bloom_up_fb[i], GL_COLOR_ATTACHMENT0, s->bloom_up[i], 0);
      w /= 2;
      h /= 2;
   }
   glBindBufferBase(GL_UNIFORM_BUFFER, 0, s->frame_buffer);
   glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, s->visible_buffer);
   glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, s->command_buffer);
   glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 3, s->particle_buffer);
   glProgramUniform1ui(s->cull, s->cull_gems, GEMS);
   glProgramUniform1ui(s->cull, s->cull_total, INSTANCES);
   return check(glGetError() == GL_NO_ERROR, "resource setup");
}

static void
update_frame(struct scene *s, float t, GLsizei width, GLsizei height, unsigned frame)
{
   struct frame_block block;
   const float aspect = (float)width / (float)height;
   const float orbit = t * 0.085f;
   const float radius = 17.0f + 3.0f * sinf(t * 0.13f);
   const float eye[3] = {cosf(orbit) * radius, 5.2f + 2.4f * sinf(t * 0.21f),
                         sinf(orbit) * radius};
   const float target[3] = {0.0f, 3.6f, 0.0f};
   float view[16], proj[16], right[3], up[3];
   look_at(view, eye, target, right, up);
   perspective(proj, 0.95f, aspect, 0.1f, 220.0f);
   mat_mul(block.view_proj, proj, view);
   invert(block.inv_view_proj, block.view_proj);
   memcpy(block.camera, eye, sizeof(eye));
   block.camera[3] = t;
   memcpy(block.cam_right, right, sizeof(right));
   block.cam_right[3] = 0.032f;
   memcpy(block.cam_up, up, sizeof(up));
   /* Keep the additive glow constant whatever the particle count. */
   block.cam_up[3] = 0.55f * sqrtf(65536.0f / (float)PARTICLES);
   static const float colors[3][4] = {
      {0.25f, 0.9f, 1.0f, 22.0f}, {1.0f, 0.3f, 0.85f, 20.0f}, {1.0f, 0.78f, 0.35f, 18.0f},
   };
   for (int i = 0; i < 3; ++i) {
      const float a = t * (0.35f + 0.12f * i) + i * 2.094f;
      block.light_pos[i][0] = cosf(a) * (7.0f + i * 2.0f);
      block.light_pos[i][1] = 3.0f + 2.5f * sinf(a * 1.3f + i);
      block.light_pos[i][2] = sinf(a) * (7.0f + i * 2.0f);
      block.light_pos[i][3] = 1.0f;
      memcpy(block.light_color[i], colors[i], sizeof(colors[i]));
   }
   block.params[0] = (float)width;
   block.params[1] = (float)height;
   block.params[2] = aspect;
   block.params[3] = (float)(frame % 1024u);
   glNamedBufferSubData(s->frame_buffer, 0, sizeof(block), &block);
}

/* CPU time spent issuing each stage (synchronous driver work shows up here). */
enum { STAGE_COMPUTE, STAGE_SCENE, STAGE_BLOOM, STAGE_COMPOSITE, STAGE_PRESENT, STAGE_COUNT };
static const char *const stage_names[STAGE_COUNT] = {"compute", "scene", "bloom", "composite",
                                                     "present"};
static double stage_ms[STAGE_COUNT];
static int64_t stage_mark;

static void
stage_end(int stage)
{
   const int64_t now = now_ns();
   stage_ms[stage] += (double)(now - stage_mark) / 1e6;
   stage_mark = now;
}

static void
render(struct scene *s, float dt, GLsizei width, GLsizei height)
{
   stage_mark = now_ns();
   static const float identity[16] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};

   /* GPU work first: particles and instance culling. */
   glUseProgram(s->particles_update);
   glUniform1f(s->particle_dt, dt);
   glDispatchCompute((PARTICLES + 255) / 256, 1, 1);
   glNamedBufferSubData(s->command_buffer, 0, sizeof(s->commands), s->commands);
   glUseProgram(s->cull);
   glDispatchCompute((INSTANCES + 63) / 64, 1, 1);
   glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT | GL_COMMAND_BARRIER_BIT);
   stage_end(STAGE_COMPUTE);

   /* HDR scene. */
   glBindFramebuffer(GL_FRAMEBUFFER, s->framebuffer);
   glViewport(0, 0, width, height);
   glDisable(GL_BLEND);
   glDepthMask(GL_TRUE);
   glClear(GL_DEPTH_BUFFER_BIT);
   glDisable(GL_DEPTH_TEST);
   glBindVertexArray(s->vao); /* Core profile draws always need a VAO. */
   glUseProgram(s->sky);
   glDrawArrays(GL_TRIANGLES, 0, 3);

   glEnable(GL_DEPTH_TEST);
   glDepthFunc(GL_LESS);
   glUseProgram(s->floor);
   glUniformMatrix4fv(s->model_floor, 1, GL_FALSE, identity);
   glBindTextureUnit(0, s->grid);
   glDrawElementsBaseVertex(GL_TRIANGLES, 6, GL_UNSIGNED_INT,
                            (const void *)(uintptr_t)(s->floor_first * sizeof(uint32_t)),
                            (GLint)s->floor_base_vertex);
   glUseProgram(s->knot);
   glUniformMatrix4fv(s->model_knot, 1, GL_FALSE, identity);
   glDrawElements(GL_TRIANGLES, KNOT_SEGMENTS * KNOT_SIDES * 6, GL_UNSIGNED_INT, NULL);

   glUseProgram(s->instances);
   glBindBuffer(GL_DRAW_INDIRECT_BUFFER, s->command_buffer);
   glBindBuffer(GL_PARAMETER_BUFFER, s->count_buffer);
   glMultiDrawElementsIndirectCount(GL_TRIANGLES, GL_UNSIGNED_INT, NULL, 0, 2,
                                    sizeof(struct draw_elements_indirect));

   glEnable(GL_BLEND);
   glBlendFunc(GL_ONE, GL_ONE);
   glDepthMask(GL_FALSE);
   glUseProgram(s->particles_draw);
   glDrawArrays(GL_TRIANGLES, 0, PARTICLES * 6);
   glDepthMask(GL_TRUE);
   glDisable(GL_BLEND);
   glBindFramebuffer(GL_FRAMEBUFFER, 0);
   stage_end(STAGE_SCENE);

   /* Bloom chain: prefilter, downsample, tent upsample. */
   glDisable(GL_DEPTH_TEST);
   glUseProgram(s->bloom);
   bloom_pass(s, s->hdr, 0, 0, false, 0, s->bloom_size[0][0], s->bloom_size[0][1]);
   for (int i = 1; i < BLOOM_LEVELS; ++i)
      bloom_pass(s, s->bloom_down[i - 1], 0, i, false, 1, s->bloom_size[i][0],
                 s->bloom_size[i][1]);
   for (int i = BLOOM_LEVELS - 2; i >= 0; --i)
      bloom_pass(s, i == BLOOM_LEVELS - 2 ? s->bloom_down[i + 1] : s->bloom_up[i + 1],
                 s->bloom_down[i], i, true, 2, s->bloom_size[i][0], s->bloom_size[i][1]);
   glBindFramebuffer(GL_FRAMEBUFFER, 0);

   stage_end(STAGE_BLOOM);

   /* Composite to the window. */
   glViewport(0, 0, width, height);
   glDisable(GL_DEPTH_TEST);
   glUseProgram(s->composite);
   glBindTextureUnit(0, s->hdr);
   glBindTextureUnit(1, s->bloom_up[0]);
   glBindTextureUnit(2, s->font);
   glDrawArrays(GL_TRIANGLES, 0, 3);
   stage_end(STAGE_COMPOSITE);
}

int
main(void)
{
   static const EGLint config_attributes[] = {
#ifdef SHOWCASE_HOST_PREVIEW
      EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
#else
      EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
#endif
      EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
      EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
      EGL_DEPTH_SIZE, 24, EGL_NONE,
   };
   static const EGLint context_attributes[] = {
      EGL_CONTEXT_MAJOR_VERSION_KHR, 4, EGL_CONTEXT_MINOR_VERSION_KHR, 6,
      EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR, EGL_NONE,
   };
   static struct scene s;
   static uint32_t text[TEXT_LINES * TEXT_COLUMNS];
   EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
   EGLSurface surface = EGL_NO_SURFACE;
   EGLContext context = EGL_NO_CONTEXT;
   EGLConfig config = NULL;
   EGLint config_count = 0, width = 0, height = 0;
   int ok = 0;

   /* One SDK for every display: ask for 4K before EGL starts. */
   const int display_modes = eglSetDisplayModePS5 != NULL;
   if (display_modes && !eglSetDisplayModePS5(display, SHOWCASE_WIDTH, SHOWCASE_HEIGHT))
      say(TAG " display mode %dx%d unavailable, using the default", SHOWCASE_WIDTH,
             SHOWCASE_HEIGHT);
   if (eglSetDisplayRefreshPS5 && !eglSetDisplayRefreshPS5(display, SHOWCASE_REFRESH))
      say(TAG " refresh %d Hz unavailable, using the default", SHOWCASE_REFRESH);
   if (!check(display != EGL_NO_DISPLAY && eglInitialize(display, NULL, NULL) &&
                 eglBindAPI(EGL_OPENGL_API) &&
                 eglChooseConfig(display, config_attributes, &config, 1, &config_count) &&
                 config_count == 1,
              "EGL init"))
      return 1;
#ifdef SHOWCASE_HOST_PREVIEW
   const EGLint pbuffer_attributes[] = {EGL_WIDTH, SHOWCASE_WIDTH, EGL_HEIGHT,
                                        SHOWCASE_HEIGHT, EGL_NONE};
   surface = eglCreatePbufferSurface(display, config, pbuffer_attributes);
#else
   surface = eglCreateWindowSurface(display, config, 0, NULL);
#endif
   context = eglCreateContext(display, config, EGL_NO_CONTEXT, context_attributes);
   if (!check(surface != EGL_NO_SURFACE && context != EGL_NO_CONTEXT &&
                 eglMakeCurrent(display, surface, surface, context) &&
                 eglQuerySurface(display, surface, EGL_WIDTH, &width) &&
                 eglQuerySurface(display, surface, EGL_HEIGHT, &height) && width > 0 &&
                 height > 0,
              "EGL surface"))
      return 1;
   eglSwapInterval(display, 1);
#ifdef SHOWCASE_HOST_PREVIEW
   glEnable(GL_DEBUG_OUTPUT);
   glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);
   glDebugMessageCallback(debug_message, NULL);
#endif
   if (!setup(&s, width, height))
      return 1;

   say(TAG " ready GL=%s GLSL=%s size=%dx%d particles=%u instances=%u display_modes=%d",
          glGetString(GL_VERSION), glGetString(GL_SHADING_LANGUAGE_VERSION), width, height,
          PARTICLES, INSTANCES, display_modes);
   char line[80];
   set_line(text, 0, "PS5 OPENGL 4.6 CORE SHOWCASE");
   snprintf(line, sizeof(line), "%dX%d  -- FPS", width, height);
   set_line(text, 1, line);
   snprintf(line, sizeof(line), "%u PARTICLES  %u INSTANCES", PARTICLES, INSTANCES);
   set_line(text, 2, line);
   set_line(text, 3, "COMPUTE SSBO MULTIDRAWINDIRECTCOUNT HDR BLOOM");
   glProgramUniform1uiv(s.composite, s.text, TEXT_LINES * TEXT_COLUMNS, text);
   glProgramUniform1f(s.composite, s.hud_scale, (float)(height / 540 > 1 ? height / 540 : 1) *
                                                   1.0f);

   const int64_t start = now_ns();
   int64_t previous = start, window_start = start, log_start = start;
   unsigned frames = 0, window_frames = 0, profile_frames = 0;
   int settled = 0, refresh_hz = 60;
   for (;;) {
      const int64_t now = now_ns();
      const float t = (float)(now - start) / 1e9f;
      float dt = (float)(now - previous) / 1e9f;
      previous = now;
      if (dt > 0.05f || frames == 0)
         dt = 1.0f / 60.0f;
      update_frame(&s, t, width, height, frames);
      render(&s, dt, width, height);
      if (SHOWCASE_CAPTURE_FRAME > 0 && frames == SHOWCASE_CAPTURE_FRAME)
         capture_frame(width, height);
      stage_mark = now_ns();
      if (!check(eglSwapBuffers(display, surface), "present"))
         break;
      stage_end(STAGE_PRESENT);
      ++frames;
      ++window_frames;
      if (now - window_start >= 500000000) {
         const double fps = window_frames * 1e9 / (double)(now - window_start);
         snprintf(line, sizeof(line), "%dX%d  %d HZ  %.0f FPS  %.1f MS", width, height,
                  refresh_hz, fps, 1000.0 / fps);
         set_line(text, 1, line);
         glProgramUniform1uiv(s.composite, s.text, TEXT_LINES * TEXT_COLUMNS, text);
         if (now - log_start >= 2000000000LL) {
            const unsigned counted = frames - profile_frames;
            char profile[256];
            int used = 0;
            for (int i = 0; i < STAGE_COUNT; ++i) {
               used += snprintf(profile + used, sizeof(profile) - (size_t)used, " %s=%.2f",
                                stage_names[i], stage_ms[i] / (counted ? counted : 1));
               stage_ms[i] = 0.0;
            }
            say(TAG " frames=%u fps=%.2f size=%dx%d gl=%x cpu-ms%s", frames, fps, width, height,
                glGetError(), profile);
            profile_frames = frames;
            log_start = now;
         }
         window_start = now;
         window_frames = 0;
      }
#ifdef SHOWCASE_HOST_PREVIEW
      if (frames == SHOWCASE_HOST_PREVIEW) {
         unsigned char *rgb = malloc((size_t)width * height * 3);
         glPixelStorei(GL_PACK_ALIGNMENT, 1);
         glReadPixels(0, 0, width, height, GL_RGB, GL_UNSIGNED_BYTE, rgb);
         FILE *ppm = fopen("showcase.ppm", "wb");
         fprintf(ppm, "P6 %d %d 255\n", width, height);
         for (int y = height - 1; y >= 0; --y)
            fwrite(rgb + (size_t)y * width * 3, 1, (size_t)width * 3, ppm);
         fclose(ppm);
         free(rgb);
         ok = glGetError() == GL_NO_ERROR;
         break;
      }
#endif
      if (frames == 2 && eglGetDisplayModePS5) {
         EGLint mode_w = 0, mode_h = 0, mode_hz = 0;
         eglGetDisplayModePS5(display, &mode_w, &mode_h, &mode_hz);
         say(TAG " display %dx%d at %d Hz", mode_w, mode_h, mode_hz);
         refresh_hz = mode_hz;
      }
      if (!settled && t >= 20.0f) {
         settled = 1; /* marks a warmed-up measurement window in the log */
         say(TAG " settled frames=%u", frames);
      }
      if (SHOWCASE_SECONDS > 0 && t >= SHOWCASE_SECONDS) {
         ok = glGetError() == GL_NO_ERROR;
         break;
      }
   }
   eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
   eglDestroySurface(display, surface);
   eglDestroyContext(display, context);
   eglTerminate(display);
   say(TAG " frames=%u result=%s", frames, ok ? "PASS" : "FAIL");
   return ok ? 0 : 1;
}
