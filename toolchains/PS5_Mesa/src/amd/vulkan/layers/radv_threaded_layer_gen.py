COPYRIGHT=u"""
/* Copyright © 2026 Mihawk
 *
 * SPDX-License-Identifier: MIT
 */
"""

# The threaded recording layer's command entrypoints (radv_threaded_layer.c):
# each vkCmd* is queued on the command buffer (the runtime's vk_cmd_queue)
# for the layer's worker to record, or, on the worker itself (a runtime helper
# calling back through the device's dispatch table while it records), passed
# down the layer's own table.

import argparse
import os
import re
import sys

import mako
from mako.template import Template

sys.path.append(os.path.join(sys.path[0], '../../../vulkan/util/'))

from vk_entrypoints import get_entrypoints_from_xml
from vk_cmd_queue_gen import NO_ENQUEUE_COMMANDS

# Commands whose runtime enqueue takes references on pipeline layouts,
# descriptor set layouts or update templates as the runtime's own objects,
# which RADV's are not: the two RPCS3-style ones are queued by the layer
# itself (radv_threaded_layer.c), the rest are recorded directly once the
# command buffer's queued work is done.
LAYER_QUEUED_COMMANDS = [
    'CmdBindDescriptorSets',
    'CmdPushConstants',
]

DIRECT_COMMANDS = [
    'CmdPushDescriptorSet',
    'CmdPushDescriptorSetWithTemplate',
    'CmdSetDescriptorBufferOffsetsEXT',
    'CmdBindDescriptorBufferEmbeddedSamplersEXT',
    'CmdBindDescriptorSets2',
    'CmdPushConstants2',
    'CmdPushDescriptorSet2',
    'CmdPushDescriptorSetWithTemplate2',
    'CmdSetDescriptorBufferOffsets2EXT',
    'CmdBindDescriptorBufferEmbeddedSamplers2EXT',
] + NO_ENQUEUE_COMMANDS

# Destroys and frees the layer implements itself (the command buffer's own).
LAYER_DESTROYS = ['DestroyDevice', 'DestroyCommandPool', 'FreeCommandBuffers']

# Commands after which the layer may hand what is queued to its worker.
KICK_COMMANDS = [
    'CmdDraw', 'CmdDrawIndexed', 'CmdDrawIndirect', 'CmdDrawIndexedIndirect',
    'CmdDrawIndirectCount', 'CmdDrawIndexedIndirectCount', 'CmdDrawMultiEXT',
    'CmdDrawMultiIndexedEXT', 'CmdDrawMeshTasksEXT', 'CmdDispatch',
    'CmdDispatchIndirect', 'CmdDispatchBase', 'CmdCopyBuffer', 'CmdCopyImage',
    'CmdCopyBufferToImage', 'CmdCopyImageToBuffer', 'CmdBlitImage',
    'CmdCopyBuffer2', 'CmdCopyImage2', 'CmdCopyBufferToImage2',
    'CmdCopyImageToBuffer2', 'CmdBlitImage2', 'CmdClearColorImage',
    'CmdClearDepthStencilImage', 'CmdClearAttachments', 'CmdEndRenderPass',
    'CmdEndRenderPass2', 'CmdEndRendering',
]

TEMPLATE = Template(COPYRIGHT + """
/* This file generated from ${filename}, don't edit directly. */

#include "radv_cmd_buffer.h"
#include "radv_device.h"
#include "radv_entrypoints.h"
#include "layers/radv_threaded_layer.h"
#include "vk_cmd_enqueue_entrypoints.h"

% for c in commands:
% if c.guard is not None:
#ifdef ${c.guard}
% endif
VKAPI_ATTR void VKAPI_CALL
threaded_${c.name}(${c.decl_params()})
{
   struct radv_cmd_buffer *cmd_buffer = radv_cmd_buffer_from_handle(commandBuffer);
   struct radv_device *device = radv_cmd_buffer_device(cmd_buffer);

   if (radv_threaded_replaying()) {
      device->layer_dispatch.threaded.${c.name}(${c.call_params()});
      return;
   }

% if c.name in direct_commands:
   radv_threaded_drain(cmd_buffer);
   device->layer_dispatch.threaded.${c.name}(${c.call_params()});
% elif c.name in layer_queued_commands:
   radv_threaded_queue_${c.name}(${c.call_params()});
   radv_threaded_note(cmd_buffer, false);
% else:
   vk_cmd_enqueue_${c.name}(${c.call_params()});
   radv_threaded_note(cmd_buffer, ${'true' if c.name in kick_commands else 'false'});
% endif
}

% if c.guard is not None:
#endif // ${c.guard}
% endif
% endfor

/* Destroys and frees: a batch handed to the worker may name the object. */
% for d in destroys:
% if d.guard is not None:
#ifdef ${d.guard}
% endif
VKAPI_ATTR ${d.return_type} VKAPI_CALL
threaded_${d.name}(${d.decl_params()})
{
   struct radv_device *radv_device = radv_device_from_handle(${d.params[0].name});

   radv_threaded_barrier(radv_device);
   ${'return ' if d.return_type != 'void' else ''}radv_device->layer_dispatch.threaded.${d.name}(${d.call_params()});
}

% if d.guard is not None:
#endif // ${d.guard}
% endif
% endfor
""")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-c", required=True, help="Output C file.")
    parser.add_argument("--beta", required=True, help="Enable beta extensions.")
    parser.add_argument("--xml",
                        help="Vulkan API XML file.",
                        required=True, action="append", dest="xml_files")
    args = parser.parse_args()

    # The commands the runtime's queue knows (vk_cmd_queue_gen.py's choice):
    # every vkCmd* that is not an alias; those returning a value are among
    # NO_ENQUEUE_COMMANDS and are recorded directly.
    commands = []
    destroys = []
    for e in get_entrypoints_from_xml(args.xml_files, args.beta):
        if e.alias:
            continue
        # Every device-level vkDestroy*, vkFree* and vkResetDescriptorPool
        # (which frees the pool's sets).
        if (re.match(r'(Destroy|Free)[A-Z]', e.name) or e.name == 'ResetDescriptorPool') and \
           e.is_device_entrypoint() and e.name not in LAYER_DESTROYS:
            destroys.append(e)
            continue
        if not e.name.startswith('Cmd'):
            continue
        if e.return_type != "void":
            continue
        commands.append(e)

    environment = {
        "filename": os.path.basename(__file__),
        "commands": commands,
        "destroys": destroys,
        "direct_commands": DIRECT_COMMANDS,
        "layer_queued_commands": LAYER_QUEUED_COMMANDS,
        "kick_commands": KICK_COMMANDS,
    }

    try:
        with open(args.out_c, "w", encoding='utf-8') as f:
            f.write(TEMPLATE.render(**environment))
    except Exception:
        print(mako.exceptions.text_error_template().render(), file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
