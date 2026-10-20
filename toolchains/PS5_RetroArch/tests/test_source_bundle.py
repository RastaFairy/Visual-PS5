"""The release's source archives: SHA256SUMS lists every archive tools/source-bundle.py writes."""

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent

spec = importlib.util.spec_from_file_location("source_bundle", ROOT / "tools/source-bundle.py")
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


class SourceBundle(unittest.TestCase):
    def test_every_archive_is_in_the_checksums(self):
        # ICU's sources are downloaded as a .tgz and a .zip, not a .tar.gz: the
        # checksums once listed only *.tar*, so those two shipped without one.
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            downloads = base / "repo/downloads"
            downloads.mkdir(parents=True)
            archives = {"icu-sources.tgz": b"tgz", "icu-data.zip": b"zip", "lib-1.tar.gz": b"gz"}
            for name, data in archives.items():
                (downloads / name).write_bytes(data)
            part = {"id": "lib", "name": "Library", "kind": "code",
                    "source": {"kind": "fixed", "revision": "1",
                               "extra": [{"tarball": f"downloads/{name}"} for name in archives]}}
            table = base / "components.json"
            table.write_text(json.dumps({"components": [part]}))
            title = base / "title"
            (title / "licenses").mkdir(parents=True)
            staged = dict(part, source={"kind": "fixed", "revision": "1"})
            (title / "licenses/components.json").write_text(json.dumps({"components": [staged]}))
            out = base / "source"
            with patch.object(bundle, "ROOT", base / "repo"), patch.object(bundle, "TABLE", table):
                self.assertEqual(bundle.main([str(title), str(out)]), 0)
            sums = dict(reversed(line.split("  ")) for line in
                        (out / "SHA256SUMS").read_text().splitlines())
            self.assertEqual(sums, {name: hashlib.sha256(data).hexdigest()
                                    for name, data in archives.items()})


if __name__ == "__main__":
    unittest.main()
