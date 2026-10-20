"""Run frame generation's plan (patches 0121, 0131 and 0132) as the port inserts it, for each kind of output."""
import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class FramegenPlan(unittest.TestCase):
    def test_the_plan_follows_the_flips_the_output_shows(self):
        spec = importlib.util.spec_from_file_location('patches', ROOT / 'tools/apply-port-patches.py')
        patches = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(patches)
        # The plan as 0121 inserts it, with every later retroarch.c edit applied in order, as main() does.
        edits = [e for e in patches.EDITS if e[0] == 'retroarch.c']
        start = next(i for i, e in enumerate(edits) if e[3] == 'Output Rate Auto: the presents per game frame')
        text = edits[start][2]
        for _, anchor, replacement, marker in edits[start + 1:]:
            if marker not in text and anchor in text:
                text = text.replace(anchor, replacement, 1)
        plan = text[:text.index('   unsigned shader_subframes')]
        source = r'''
#include <assert.h>
#include <math.h>
#include <stdbool.h>
#define RARCH_LOG(...) ((void)0)
typedef struct {
   struct { bool video_framegen, video_framegen_auto; } bools;
   struct { unsigned video_framegen_target, video_shader_subframes; } uints;
   struct { float video_refresh_rate; } floats;
} settings_t;
unsigned vulkan_ps5_display_refresh_x1000, vulkan_ps5_flip_rate_x1000, ps5_fg_dup;
float ps5_fg_core_fps, ps5_fg_target_fps;
/* The presents per game frame, frame generation on or off with what an earlier run left in retroarch.cfg, for a mode
 * and the flips timed in it; refresh: what RetroArch then paces on. */
static unsigned plan_after(bool framegen, unsigned left, unsigned mode, unsigned flips, unsigned target,
                           double input_fps, float *refresh)
{
   settings_t s = {{framegen, true}, {target, left}, {mode / 1000.0f}};
   settings_t *settings = &s;
   float video_refresh_rate = settings->floats.video_refresh_rate;
   vulkan_ps5_display_refresh_x1000 = mode;
   vulkan_ps5_flip_rate_x1000 = flips;
''' + plan + r'''
   (void)video_refresh_rate;
   *refresh = settings->floats.video_refresh_rate;
   return settings->uints.video_shader_subframes;
}
static unsigned plan(unsigned mode, unsigned flips, unsigned target, double input_fps, float *refresh)
{
   return plan_after(true, 1, mode, flips, target, input_fps, refresh);
}
int main(void)
{
   float refresh;
   /* An output without 120 Hz: no picture held for two refreshes, paced at 59.94 */
   assert(plan(59940, 59940, 120, 58.944, &refresh) == 1 && refresh < 60.0f);
   assert(plan(59940, 59940, 120, 60.0, &refresh) == 1 && refresh < 60.0f);
   assert(plan(59940, 59940, 60, 60.0, &refresh) == 1);
   /* ...and a 30 fps game still gets a frame between its frames, at the display's 60 */
   assert(plan(59940, 59940, 120, 30.0, &refresh) == 2 && fabsf(ps5_fg_target_fps - 59.94f) < 0.01f);
   /* VRR: 120 flips a second in the 59.94 Hz mode */
   assert(plan(59940, 119880, 120, 60.0, &refresh) == 2 && refresh > 119.0f && ps5_fg_dup == 1);
   assert(plan(59940, 119880, 60, 60.0, &refresh) == 2 && ps5_fg_dup == 2);
   /* Flips not timed: the mode is believed */
   assert(plan(59940, 0, 120, 60.0, &refresh) == 1 && refresh < 60.0f);
   /* The 119.88 Hz mode itself */
   assert(plan(119880, 0, 120, 60.0, &refresh) == 2 && ps5_fg_dup == 1);
   assert(plan(119880, 0, 60, 60.0, &refresh) == 2 && ps5_fg_dup == 2);
   /* Frame generation turned off: the 2 it left is one present per game frame again, on either output */
   assert(plan_after(false, 2, 59940, 59940, 120, 60.0, &refresh) == 1);
   assert(plan_after(false, 2, 59940, 119880, 120, 60.0, &refresh) == 1);
   return 0;
}
'''
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'plan.c'
            path.write_text(source)
            exe = Path(tmp) / 'plan'
            subprocess.run(['cc', '-std=gnu99', str(path), '-o', str(exe), '-lm'], check=True)
            subprocess.run([str(exe)], check=True)
