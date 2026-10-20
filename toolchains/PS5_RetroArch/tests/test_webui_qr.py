"""Decode the real runtime QR and RGUI drawing, using controlled network changes."""
import ctypes as C
import hashlib
import json
import runpy
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class QR(C.Structure):
    _fields_ = [('url', C.c_char * 64), ('size', C.c_uint),
                ('modules', C.c_ubyte * (37 * 37)), ('checked', C.c_long)]


class WebUIQR(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        lib = Path(cls.tmp.name) / 'qr.so'
        subprocess.run(['cc', '-shared', '-fPIC', '-std=c11', '-D_DEFAULT_SOURCE', '-Isrc',
                        '-Ithird_party', 'src/ps5_webui_qr.c', 'tests/webui_qr_test.c',
                        '-Wl,--wrap=getifaddrs,--wrap=freeifaddrs,--wrap=time', '-o', str(lib)],
                       cwd=ROOT, check=True)
        cls.lib = C.CDLL(str(lib))
        cls.lib.ps5_webui_qr_encode.argtypes = [C.POINTER(QR), C.c_char_p]
        cls.lib.ps5_webui_qr_encode.restype = C.c_bool
        cls.lib.ps5_webui_qr_refresh.argtypes = [C.POINTER(QR), C.c_bool]
        cls.lib.ps5_webui_qr_current.restype = C.POINTER(QR)
        cls.lib.ps5_webui_qr_visible.restype = C.c_bool
        cls.lib.qr_test_network.argtypes = [C.c_char_p, C.c_uint, C.c_int, C.c_long]
        cls.lib.qr_test_rgui.argtypes = [C.POINTER(C.c_uint16), C.c_uint, C.c_uint]
        cls.lib.qr_test_xmb.argtypes = cls.lib.qr_test_rgui.argtypes

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def decode(self, data, width, height):
        self.assertIsNotNone(shutil.which('zbarimg'), 'QR verification requires zbarimg')
        path = Path(self.tmp.name) / 'qr.pgm'
        path.write_bytes(f'P5\n{width} {height}\n255\n'.encode() + data)
        result = subprocess.run(['zbarimg', '--quiet', '--raw', str(path)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        return result.stdout.strip().decode()

    def test_encoder_decodes_and_preserves_quiet_zone(self):
        qr = QR()
        for address in (b'192.0.2.42', b'198.51.100.123', b'203.0.113.254', b'10.0.0.1'):
            self.assertTrue(self.lib.ps5_webui_qr_encode(C.byref(qr), address))
            self.assertLessEqual(qr.size, 37)
            side = qr.size
            self.assertTrue(all(not qr.modules[y * side + x] for y in range(side) for x in range(side)
                                if min(x, y, side - x - 1, side - y - 1) < 4))
            scale = 8
            pixels = bytes(0 if qr.modules[(y // scale) * side + x // scale] else 255
                           for y in range(side * scale) for x in range(side * scale))
            self.assertEqual(self.decode(pixels, side * scale, side * scale), f'http://{address.decode()}:6769/')
        for address in (b'', b'0.0.0.0', b'127.0.0.1', b'224.0.0.1', b'255.255.255.255', b'1.2.3.999', b'bad/path'):
            self.assertFalse(self.lib.ps5_webui_qr_encode(C.byref(qr), address))
            self.assertEqual(qr.size, 0)
            self.assertEqual(qr.url, b'')

    def test_current_ip_changes_offline_and_modal_lifecycle(self):
        lib = self.lib
        lib.qr_test_network(b'192.0.2.42', 1, 0, 100)
        lib.ps5_webui_qr_open()
        self.assertTrue(lib.ps5_webui_qr_visible())
        self.assertEqual(lib.ps5_webui_qr_current().contents.url, b'http://192.0.2.42:6769/')
        lib.qr_test_network(b'198.51.100.123', 1, 0, 101)
        self.assertEqual(lib.ps5_webui_qr_current().contents.url, b'http://198.51.100.123:6769/')
        lib.qr_test_network(b'198.51.100.123', 0, 0, 102)
        self.assertEqual(lib.ps5_webui_qr_current().contents.size, 0)
        lib.qr_test_network(b'198.51.100.123', 1, 1, 103)
        self.assertEqual(lib.ps5_webui_qr_current().contents.url, b'')
        lib.ps5_webui_qr_close()
        self.assertFalse(lib.ps5_webui_qr_visible())
        lib.qr_test_network(b'203.0.113.2', 1, 0, 104)
        lib.ps5_webui_qr_open()
        self.assertEqual(lib.ps5_webui_qr_current().contents.url, b'http://203.0.113.2:6769/')
        lib.ps5_webui_qr_close()

    def test_rgui_rendered_frame_decodes(self):
        self.lib.qr_test_network(b'192.0.2.42', 1, 0, 200)
        self.lib.ps5_webui_qr_open()
        for width, height in ((320, 240), (640, 480)):
            pixels = (C.c_uint16 * (width * height))()
            self.lib.qr_test_rgui(pixels, width, height)
            self.assertEqual(self.decode(bytes(255 if pixel == 0xffff else 0 for pixel in pixels), width, height),
                             'http://192.0.2.42:6769/')
        self.lib.ps5_webui_qr_close()

    def test_xmb_rendered_frame_decodes(self):
        self.lib.qr_test_network(b'198.51.100.123', 1, 0, 300)
        self.lib.ps5_webui_qr_open()
        for width, height in ((1280, 720), (1920, 1080)):
            pixels = (C.c_uint16 * (width * height))()
            self.lib.qr_test_xmb(pixels, width, height)
            self.assertEqual(self.decode(bytes(255 if pixel == 0xffff else 0 for pixel in pixels), width, height),
                             'http://198.51.100.123:6769/')
        self.lib.ps5_webui_qr_close()

    def test_picker_buttons_consume_input(self):
        source = (ROOT / 'frontends/picker/picker.cpp').read_text()
        block = source.split('// Consume the overlay', 1)[1].split('\n', 1)[1].split('\n\t\tif (input.nav', 1)[0]
        test = r"""
#include <cassert>
namespace hui {
enum class Action { north=1, back=2, confirm=4, west=8 };
struct InputFrame { unsigned bits=0; bool is_pressed(Action a) const { return bits & (unsigned)a; } };
}
bool showWebUI=false; int webuiQR=0;
void ps5_webui_qr_refresh(int*,bool) {}
void update(hui::InputFrame &input) {
""" + block + r"""
}
int main() {
 hui::InputFrame i{1}; update(i); assert(showWebUI && !i.bits);
 i.bits=4|8; update(i); assert(showWebUI && !i.bits);
 i.bits=1; update(i); assert(!showWebUI && !i.bits);
 i.bits=1; update(i); assert(showWebUI && !i.bits);
 i.bits=2; update(i); assert(!showWebUI && !i.bits);
 i.bits=2; update(i); assert(!showWebUI && i.bits==2);
}
"""
        file = Path(self.tmp.name) / 'picker-input.cpp'
        file.write_text(test)
        binary = file.with_suffix('')
        subprocess.run(['c++', '-std=c++17', str(file), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)

    def test_menu_hooks_apply_and_are_idempotent(self):
        edits = runpy.run_path(str(ROOT / 'tools/apply-port-patches.py'))['EDITS']
        files = {}
        for name, anchor, replacement, marker in edits:
            if name not in files:
                files[name] = (ROOT / 'vendor/retroarch' / name).read_text()
            if marker not in files[name]:
                self.assertIn(anchor, files[name], marker)
                files[name] = files[name].replace(anchor, replacement, 1)
        before = files.copy()
        for name, anchor, replacement, marker in edits:
            if any(step in replacement for step in ("0115", "0116")) and marker not in files[name]:
                files[name] = files[name].replace(anchor, replacement, 1)
        self.assertEqual(before, files)
        xmb = files['menu/drivers/xmb.c']
        cache = xmb.split('static void xmb_list_cache', 1)[1]
        self.assertIn('case XMB_SYSTEM_TAB_WEBUI:', cache)
        tabs = xmb.split('static void xmb_refresh_system_tabs_list', 1)[1].split('static ', 1)[0]
        self.assertLess(tabs.index('XMB_SYSTEM_TAB_WEBUI'), tabs.index('XMB_SYSTEM_TAB_SETTINGS'))
        rgui = files['menu/menu_displaylist.c'].split('case DISPLAYLIST_MAIN_MENU:', 1)[1]
        self.assertLess(rgui.index('"ps5_webui"'), rgui.index('RUNLOOP_FLAG_CORE_RUNNING'))

    def test_retroarch_entry_opens_modal_and_cancel_closes(self):
        edits = runpy.run_path(str(ROOT / 'tools/apply-port-patches.py'))['EDITS']
        files = {}
        for name, anchor, replacement, marker in edits:
            if name not in files:
                files[name] = (ROOT / 'vendor/retroarch' / name).read_text()
            if marker not in files[name]:
                self.assertIn(anchor, files[name], marker)
                files[name] = files[name].replace(anchor, replacement, 1)

        def function(source, signature):
            return source[source.index(signature):].split('\n}', 1)[0] + '\n}\n'

        callbacks = files['menu/cbs/menu_cbs_ok.c']
        code = r"""
#include <assert.h>
#include <string.h>
#include "ps5_webui_qr.h"
void qr_test_network(const char *, unsigned, int, long);
typedef int (*ok_cb)(const char *, const char *, unsigned, size_t, size_t);
typedef struct { ok_cb action_ok; } menu_file_list_cbs_t;
#define BIND_ACTION_OK(cbs, name) ((cbs)->action_ok = (name))
#define string_is_equal(a, b) ((a) && (b) && strcmp((a), (b)) == 0)
static int fallback_calls;
static int action_ok_lookup_setting(const char *p, const char *l, unsigned t, size_t i, size_t e)
{ fallback_calls++; return 23; }
static int menu_cbs_init_bind_ok_compare_label(menu_file_list_cbs_t *c, const char *l)
{ return -1; }
static int menu_cbs_init_bind_ok_compare_type(menu_file_list_cbs_t *c, const char *l,
                                             const char *m, unsigned t)
{ return -1; }
/* The frame generation entries (patches/series, 0120) bound beside the WebUI's: none here. */
#include <stdbool.h>
static bool ps5_fg_menu_is_label(const char *l) { return false; }
static bool ps5_fg_menu_is_folder(const char *l) { return false; }
static int action_ok_push_default(const char *p, const char *l, unsigned t, size_t i, size_t e)
{ return 0; }
static int action_ok_ps5_fg(const char *p, const char *l, unsigned t, size_t i, size_t e)
{ return 0; }
"""
        code += function(callbacks, 'static int action_ok_ps5_webui(')
        code += function(callbacks, 'int menu_cbs_init_bind_ok(')
        code += r"""
enum menu_action { MENU_ACTION_NOOP, MENU_ACTION_OK, MENU_ACTION_CANCEL, MENU_ACTION_RIGHT };
typedef struct { menu_file_list_cbs_t cbs; } menu_entry_t;
static int forwarded;
static int entry_action(void *data, menu_entry_t *entry, size_t i, enum menu_action action)
{
    forwarded++;
    if (action == MENU_ACTION_OK)
        return entry->cbs.action_ok("WebUI", "ps5_webui", 0, i, 0);
    return 17;
}
struct driver { int (*entry_action)(void *, menu_entry_t *, size_t, enum menu_action); };
struct menu_state { struct driver *driver_ctx; void *userdata; };
static struct driver driver = {entry_action};
static struct menu_state menu_driver_state = {&driver, NULL};
"""
        code += function(files['menu/menu_driver.c'], 'int menu_entry_action(')
        code += r"""
int main(void)
{
    qr_test_network("192.0.2.42", 1, 0, 500);
    menu_entry_t entry = {0};
    assert(menu_cbs_init_bind_ok(NULL, "", "ps5_webui", 9, 0, 0, "", 0) == -1);
    assert(menu_cbs_init_bind_ok(&entry.cbs, "WebUI", "ps5_webui", 9, 0, 0, "main_menu", 9) == 0);
    assert(entry.cbs.action_ok == action_ok_ps5_webui);
    assert(menu_entry_action(&entry, 0, MENU_ACTION_OK) == 0);
    assert(ps5_webui_qr_visible() && forwarded == 1 && fallback_calls == 0);
    assert(strcmp(ps5_webui_qr_current()->url, "http://192.0.2.42:6769/") == 0);
    assert(menu_entry_action(&entry, 0, MENU_ACTION_RIGHT) == 0);
    assert(ps5_webui_qr_visible() && forwarded == 1);
    assert(menu_entry_action(&entry, 0, MENU_ACTION_CANCEL) == 0);
    assert(!ps5_webui_qr_visible() && forwarded == 1);
    assert(menu_entry_action(&entry, 0, MENU_ACTION_RIGHT) == 17 && forwarded == 2);
    assert(menu_entry_action(&entry, 0, MENU_ACTION_OK) == 0 && ps5_webui_qr_visible());
    assert(menu_entry_action(&entry, 0, MENU_ACTION_OK) == 0 && !ps5_webui_qr_visible());
    assert(menu_cbs_init_bind_ok(&entry.cbs, "", "other", 5, 0, 0, "", 0) == -1);
    assert(entry.cbs.action_ok == action_ok_lookup_setting);
    assert(entry.cbs.action_ok("", "other", 0, 0, 0) == 23 && fallback_calls == 1);
}
"""
        file = Path(self.tmp.name) / 'menu-action.c'
        file.write_text(code)
        binary = file.with_suffix('')
        subprocess.run(['cc', '-std=c11', '-Isrc', str(file), str(Path(self.tmp.name) / 'qr.so'),
                        '-o', str(binary)], cwd=ROOT, check=True)
        subprocess.run([str(binary)], check=True, cwd=self.tmp.name)

    def test_upstream_encoder_is_unmodified(self):
        folder = ROOT / 'third_party/qrcodegen'
        for name, digest in json.loads((folder / 'source.json').read_text())['files'].items():
            self.assertEqual(hashlib.sha256((folder / name).read_bytes()).hexdigest(), digest)


if __name__ == '__main__':
    unittest.main()
