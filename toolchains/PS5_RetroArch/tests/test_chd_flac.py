"""The frontend's CHD reader opens a disc that declares CD FLAC (patches/series, 0133).

chdman lists CD FLAC among a CD's codecs by default, and libchdr refuses to open a CHD that
declares a codec it was built without, so RetroAchievements could hash none of those discs.
tests/chd/tone-cdfl.chd is synthetic: tone_pcm() below, written as tone.bin beside a cue
sheet (FILE "tone.bin" BINARY, TRACK 01 AUDIO, INDEX 01 00:00:00) and compressed with
`chdman createcd -c cdfl` (MAME 0.289). Four of its hunks are FLAC, the rest copies.
"""
import math
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TREE = ROOT / 'vendor/retroarch'
FRAMES = 75


def tone_pcm():
    """One second of CD audio: a quarter second of a 440 Hz tone, then silence."""
    pcm = bytearray()
    for i in range(FRAMES * 588):
        value = int(3000 * math.sin(2 * math.pi * 440 * i / 44100)) if i < 44100 // 4 else 0
        pcm += struct.pack('<hh', value, -value)
    return bytes(pcm)


class ChdFlac(unittest.TestCase):
    def test_the_title_configures_builtin_flac(self):
        flags = subprocess.run(['bash', str(ROOT / 'tools/retroarch-sources.sh'), '--config'],
                               capture_output=True, text=True, check=True).stdout.split()
        self.assertIn('--enable-builtinflac', flags)
        self.assertNotIn('--disable-flac', flags)

    def test_a_cd_flac_disc_opens_and_decodes(self):
        if not shutil.which('cc') or not (TREE / 'libretro-common/formats/libchdr').is_dir():
            self.skipTest('requires a host C compiler and vendor/retroarch')
        chdr = TREE / 'libretro-common/formats/libchdr'
        sources = [chdr / f'libchdr_{name}.c' for name in
                   ('bitstream', 'cdrom', 'chd', 'huffman', 'zlib', 'flac', 'flac_codec')]
        sources += sorted((TREE / 'deps/libz').glob('*.c'))
        # As Makefile.common compiles the reader with builtin FLAC (dr_flac decodes);
        # plain stdio stands in for libretro's file streams.
        flags = ['-DHAVE_CHD', '-DHAVE_ZLIB', '-DWANT_SUBCODE', '-DWANT_RAW_DATA_SECTOR',
                 '-DHAVE_FLAC', '-DHAVE_DR_FLAC', '-DSKIP_STDIO_REDEFINES',
                 '-I' + str(TREE / 'libretro-common/include'), '-I' + str(TREE / 'deps'),
                 '-I' + str(TREE / 'libretro-common/include/compat/zlib'), '-I' + str(TREE / 'deps/libz')]
        program = r'''
#include <stdio.h>
#include <stdlib.h>
#include <libchdr/chd.h>
int main(int argc, char **argv)
{
   chd_file *chd = NULL;
   if (chd_open(argv[1], CHD_OPEN_READ, NULL, &chd) != CHDERR_NONE)
      return 2;
   const chd_header *header = chd_get_header(chd);
   unsigned char *hunk = malloc(header->hunkbytes);
   unsigned frames = header->hunkbytes / header->unitbytes, written = 0;
   for (unsigned i = 0; i < header->totalhunks && written < (unsigned)atoi(argv[2]); i++)
   {
      if (chd_read(chd, i, hunk) != CHDERR_NONE)
         return 3;
      for (unsigned f = 0; f < frames && written < (unsigned)atoi(argv[2]); f++, written++)
         fwrite(hunk + f * header->unitbytes, 1, 2352, stdout); /* the audio, not the subcode */
   }
   chd_close(chd);
   return 0;
}
'''
        with tempfile.TemporaryDirectory() as folder:
            work = Path(folder)
            (work / 'read.c').write_text(program)
            subprocess.run(['cc', '-O1', '-w', *flags, str(work / 'read.c'), *map(str, sources),
                            '-lm', '-o', str(work / 'read')], check=True)
            result = subprocess.run([str(work / 'read'), str(ROOT / 'tests/chd/tone-cdfl.chd'),
                                     str(FRAMES)], capture_output=True)
        self.assertEqual(result.returncode, 0, 'the CD FLAC disc did not open or a hunk failed its CRC')
        pcm = tone_pcm()
        # A CHD keeps CD audio big-endian; the .bin it was made from is little-endian.
        swapped = b''.join(pcm[i + 1:i + 2] + pcm[i:i + 1] for i in range(0, len(pcm), 2))
        self.assertEqual(result.stdout, swapped)


if __name__ == '__main__':
    unittest.main()
