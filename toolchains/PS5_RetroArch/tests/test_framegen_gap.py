"""Frame generation's gap between new frames (patches 0121 and 0137) as the port inserts it into
vulkan.c: the clock adds the calls a fast core skipped, never the time a slow core takes."""
import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class FramegenGap(unittest.TestCase):
    def test_the_clock_counts_skipped_calls_not_a_slow_core(self):
        spec = importlib.util.spec_from_file_location('patches', ROOT / 'tools/apply-port-patches.py')
        patches = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(patches)
        # The gap as 0121 inserts it, with every later vulkan.c edit applied in order, as main() does.
        edits = [e for e in patches.EDITS if e[0] == 'gfx/drivers/vulkan.c']
        start = next(i for i, e in enumerate(edits) if e[3].startswith('patches/series, 0121: the gap in core frames'))
        text = edits[start][2]
        for _, anchor, replacement, marker in edits[start + 1:]:
            if marker not in text and anchor in text:
                text = text.replace(anchor, replacement, 1)
        self.assertIn('0137', text)
        source = r'''
#include <assert.h>
#include <stdint.h>
#include <time.h>
struct { unsigned framegen_call; } vk_state, *vk = &vk_state;
float ps5_fg_core_fps = 59.94f;
double ps5_fg_last_core_run_ms;
static uint64_t clock_ns;
#define clock_gettime(id, ts) ((ts)->tv_sec = (time_t)(clock_ns / 1000000000ull), (ts)->tv_nsec = (long)(clock_ns % 1000000000ull))
/* The gap the driver takes for a new frame after calls in the group, ms after the last one,
 * the last call of the core having taken run_ms. */
static unsigned gap(unsigned calls, double ms, double run_ms)
{
   vk->framegen_call = calls - 1;
   ps5_fg_last_core_run_ms = run_ms;
   clock_ns += (uint64_t)(ms * 1e6);
''' + text + r'''
   return fg_gap;
}
int main(void)
{
   clock_ns = 1000000000ull;
   gap(1, 16.7, 2.0); /* the first frame starts the clock */
   /* A fast core that skipped a call (it said "unchanged"): two frames by the clock */
   assert(gap(1, 33.4, 2.0) == 2);
   /* A core slower than real time: each call is a new frame, whatever the clock says */
   assert(gap(1, 27.6, 27.4) == 1);
   assert(gap(1, 33.4, 33.0) == 1);
   /* A full-speed core, its call holding the presents: one frame */
   assert(gap(1, 16.7, 17.3) == 1);
   /* Calls the driver saw count either way */
   assert(gap(2, 33.4, 17.3) == 2);
   return 0;
}
'''
        with tempfile.TemporaryDirectory() as temp:
            path, exe = Path(temp) / 'gap.c', Path(temp) / 'gap'
            path.write_text(source)
            subprocess.run(['cc', '-std=gnu99', str(path), '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)


if __name__ == '__main__':
    unittest.main()
