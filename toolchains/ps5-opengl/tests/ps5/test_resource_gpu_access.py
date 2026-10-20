"""GPU borrowing is queue-ordered: it neither waits nor disables publication reuse."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[2] / 'src/gallium/ps5/ps5_screen.c').read_text()
start = source.index('static int\nps5_resource_get_info(')
end = source.index('\n}', source.index('\nps5_resource_gpu_info(', start)) + 2
code = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#define PIPE_BIND_DISPLAY_TARGET 1
struct pipe_resource { unsigned bind; };
struct ps5_resource { struct pipe_resource base; bool external_cpu_access;
                     void *data; size_t size, allocation_size; };
static unsigned global_waits, resource_waits, invalidations;
static void ps5_draw_batch_drain(void) { ++global_waits; }
static void ps5_draw_batch_drain_buffer(struct pipe_resource *r) { (void)r; ++resource_waits; }
static void ps5_invalidate_gpu_writes(struct ps5_resource *r) { (void)r; ++invalidations; }
''' + source[start:end] + r'''
int main(void) {
    char memory[64]; void *address=0; size_t logical=0, allocated=0;
    struct ps5_resource r={.data=memory,.size=32,.allocation_size=64};
    assert(!ps5_resource_gpu_info(&r.base,&address,&logical,&allocated));
    assert(address==memory && logical==32 && allocated==64);
    assert(!resource_waits && !global_waits && !invalidations && !r.external_cpu_access);
    assert(!ps5_resource_gpu_info(&r.base,0,0,0) && !r.external_cpu_access);
    assert(ps5_resource_gpu_info(0,0,0,0)==-1 && !resource_waits);
    assert(!ps5_resource_info(&r.base,0,0,0) && !r.external_cpu_access);
    assert(global_waits==1 && invalidations==1);
    assert(!ps5_resource_info(&r.base,&address,0,0) && r.external_cpu_access);
    assert(global_waits==2);
    assert(!ps5_resource_gpu_info(&r.base,0,0,0) && r.external_cpu_access);
    r.base.bind=PIPE_BIND_DISPLAY_TARGET;
    assert(!ps5_resource_info(&r.base,0,0,0));
    assert(global_waits==3 && resource_waits==1 && invalidations==3);
    assert(ps5_resource_info(0,0,0,0)==-1 && global_waits==4);
}
'''
with tempfile.TemporaryDirectory() as temporary:
    exe = str(Path(temporary) / 'resource-access')
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror',
                    '-fsanitize=address,undefined', '-x', 'c', '-', '-o', exe],
                   input=code, text=True, check=True)
    subprocess.run([exe], check=True)
print('PASS: GPU access neither waits nor invalidates; CPU export waits and invalidates; flags and display/null handling retained')
