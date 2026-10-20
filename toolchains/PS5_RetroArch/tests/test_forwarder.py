"""The Game Forwarder's tile app and launch payload (forwarder/), built for the host with the
console's calls stubbed: the tile stamps its title id into the payload and sends it to the
loader; the payload reads that tile's arguments, waits for the tile to close and starts
RetroArch with them."""
import shutil
import socket
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MARKER = b"PS5RA-FORWARDER-TILE-ID-SLOT"

TILE_STUBS = r'''
int sceSystemServiceHideSplashScreen(void) { return 0; }
int sceSystemServiceLoadExec(const char *path, const char *const *argv)
{ (void)path; (void)argv; return -1; }
'''

LAUNCH_DRIVER = r'''
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct { uint32_t size; int user_id; uint32_t app_opt; uint64_t crash_report; uint64_t check_flag; } param_t;
extern char tile_slot[];
int launch_main(void);
static int polls, lnc_result;
static FILE *record;
uint32_t sceLncUtilGetAppIdOfRunningBigApp(void) { return polls-- > 0 ? 0x2018u : 0xffffffffu; }
int sceLncUtilGetAppTitleId(uint32_t app, char *title) { (void)app; strcpy(title, "PPSA99170"); return 0; }
int sceUserServiceInitialize(void *p) { (void)p; return 0; }
int sceUserServiceGetForegroundUser(int *user) { *user = 7; return 0; }
static int launch(const char *call, const char *title, const char *argv[], param_t *param, int result)
{
    fprintf(record, "%s %s user=%d size=%u", call, title, param->user_id, param->size);
    for (int i = 0; argv[i]; i++)
        fprintf(record, " [%s]", argv[i]);
    fprintf(record, "\n");
    return result;
}
int sceLncUtilLaunchApp(const char *title, const char *argv[], param_t *param)
{ return launch("lnc", title, argv, param, lnc_result); }
int sceSystemServiceLaunchApp(const char *title, const char *argv[], param_t *param)
{ return launch("system", title, argv, param, 0); }
/* polls the tile is still running for, the first call's result (hex), the tile id stamped
 * into the slot ("-" leaves the marker), the record file */
int main(int argc, char **argv)
{
    if (argc != 5 || strlen(argv[3]) >= 32)
        return 2;
    polls = atoi(argv[1]);
    lnc_result = (int)strtol(argv[2], NULL, 16);
    if (strcmp(argv[3], "-") != 0)
        memcpy(tile_slot, argv[3], strlen(argv[3]) + 1);
    record = fopen(argv[4], "w");
    const int status = launch_main();
    fclose(record);
    return status;
}
'''


@unittest.skipUnless(shutil.which('cc'), 'requires a host C compiler')
class Forwarder(unittest.TestCase):
    def build(self, folder, name, sources, defines):
        binary = folder / name
        subprocess.run(['cc', '-std=gnu11', '-Wall', '-Wextra', '-Werror', *defines,
                        '-I' + str(ROOT / 'forwarder'), *map(str, sources), '-o', str(binary)], check=True)
        return binary

    def test_the_tile_stamps_its_id_and_sends_the_payload(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            app0 = folder / 'app0'
            (app0 / 'sce_sys').mkdir(parents=True)
            stubs = folder / 'stubs.c'
            stubs.write_text(TILE_STUBS)
            with socket.socket() as server:
                server.bind(('127.0.0.1', 0))
                server.listen(1)
                port = server.getsockname()[1]
                tile = self.build(folder, 'tile', [ROOT / 'forwarder/tile.c', stubs],
                                  [f'-DFORWARDER_APP0="{app0}"', f'-DFORWARDER_LOADER_PORT={port}'])
                payload = b'\x7fELF' + b'\x01' * 100 + MARKER + b'\0' * 4 + b'tail'
                (app0 / 'launch.elf').write_bytes(payload)
                (app0 / 'sce_sys/param.json').write_text('{"contentId": "x", "titleId": "PPSA99170"}')
                received = bytearray()

                def accept():
                    connection, _ = server.accept()
                    with connection:
                        while chunk := connection.recv(4096):
                            received.extend(chunk)
                thread = threading.Thread(target=accept)
                thread.start()
                subprocess.run([str(tile)], check=True, timeout=10)
                thread.join(10)
            expected = payload.replace(MARKER, b'PPSA99170' + b'\0' * (len(MARKER) - 9))
            self.assertEqual(bytes(received), expected)
            log = (app0 / 'tile.log').read_text()
            self.assertIn(f'tile PPSA99170: launch payload {len(payload)} bytes, {len(payload)} sent', log)

            # Nothing is sent without a title id, or without exactly one slot.
            (app0 / 'sce_sys/param.json').write_text('{"titleId": "ppsa99170"}')
            subprocess.run([str(tile)], check=True, timeout=10)
            self.assertIn('no title id in sce_sys/param.json', (app0 / 'tile.log').read_text())
            (app0 / 'sce_sys/param.json').write_text('{"titleId": "PPSA99170"}')
            for bad in (b'\x7fELF no slot', b'\x7fELF' + MARKER + MARKER):
                (app0 / 'launch.elf').write_bytes(bad)
                subprocess.run([str(tile)], check=True, timeout=10)
                self.assertIn('has no slot for the title id', (app0 / 'tile.log').read_text())

    def test_the_payload_waits_and_starts_retroarch_with_the_tiles_arguments(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            homebrew = folder / 'homebrew'
            (homebrew / 'PPSA99170').mkdir(parents=True)
            driver = folder / 'driver.c'
            driver.write_text(LAUNCH_DRIVER)
            payload = folder / 'launch.o'
            subprocess.run(['cc', '-std=gnu11', '-Wall', '-Wextra', '-Werror', '-c', f'-DFORWARDER_HOMEBREW="{homebrew}"',
                            '-DFORWARDER_TARGET="PPSA99169"', '-DFORWARDER_WAIT_STEP_US=1000', '-Dmain=launch_main',
                            '-I' + str(ROOT / 'forwarder'), str(ROOT / 'forwarder/launch.c'), '-o', str(payload)],
                           check=True)
            launch = self.build(folder, 'launch', [driver, payload], [])
            (homebrew / 'PPSA99170/forward.txt').write_bytes(
                b'--rom\r\nsnes/Game (USA).zip\n\n--core\nsnes9x\n--exit-after-game\n')
            record = folder / 'record.txt'
            subprocess.run([str(launch), '3', '4018', 'PPSA99170', str(record)], check=True, timeout=10)
            self.assertEqual(record.read_text(), 'lnc PPSA99169 user=7 size=32 [--rom] [snes/Game (USA).zip] '
                             '[--core] [snes9x] [--exit-after-game]\n')
            log = (homebrew / 'PPSA99170/launch.log').read_text()
            self.assertIn('launch PPSA99170: 5 argument(s) from forward.txt', log)
            self.assertIn("waited 3 step(s) for the tile, running now: ''", log)

            # The first call refused: the second is asked.
            subprocess.run([str(launch), '0', '80940031', 'PPSA99170', str(record)], timeout=10)
            self.assertEqual([line.split(' ')[0] for line in record.read_text().splitlines()], ['lnc', 'system'])

            # Not stamped (the marker is still there): nothing is launched.
            result = subprocess.run([str(launch), '0', '0', '-', str(record)], capture_output=True, text=True,
                                    timeout=10)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(record.read_text(), '')


if __name__ == '__main__':
    unittest.main()
