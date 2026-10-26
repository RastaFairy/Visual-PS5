import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "toolchains/PS5_VulkanTemplate/ps5/tools/new-title.py"
SPEC = importlib.util.spec_from_file_location("ps5_vulkan_new_title", GENERATOR)
NEW_TITLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NEW_TITLE)


class VendoredGeneratorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ps5hs-vulkan-vendored-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "PS5_VulkanTemplate"
        self.root.mkdir()
        NEW_TITLE.ROOT = self.root
        (self.root / ".ps5hs-source.json").write_text(json.dumps({
            "repository": "mihawk-99/PS5_VulkanTemplate",
            "commit": "",
            "vendoredSnapshot": True,
            "vendorRepository": "RastaFairy/Visual-PS5",
            "vendoredAt": "2026-10-20T15:43:39Z",
            "sourceRevisionRecorded": False,
        }))
        self.files = {
            "base/foundation.hpp": "foundation",
            "external/library.hpp": "library",
            "external/glm/glm.hpp": "vendored glm",
            "ps5/main.cpp": "PS5 main",
            "ps5/tools/new-title.py": "do not copy the generator",
            "ps5/README.md": "do not copy the template README",
            "ps5/sce_sys/param.json": "do not copy template identity",
            "ps5/ui/kit.hpp": "optional UI module",
            "ps5/licenses/GPL-3.0.txt": "optional UI license",
            "examples/starter/starter.cpp": "3D starter",
            "examples/uiscreen/uiscreen.cpp": "UI starter",
            "shaders/glsl/base/base.vert": "base shader",
            "shaders/glsl/starter/starter.vert": "starter shader",
            "LICENSE.md": "MIT license",
            ".gitignore": "build/",
        }
        for relative, contents in self.files.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents)

    def test_exports_starter_and_glm_from_a_vendored_snapshot_without_git(self):
        target = Path(self.temp.name) / "NativeTitle"
        target.mkdir()

        revision = NEW_TITLE.export(target, False)

        self.assertEqual(revision, "vendored snapshot 2026-10-20 (upstream revision not recorded)")
        self.assertEqual((target / "base/foundation.hpp").read_text(), "foundation")
        self.assertEqual((target / "external/glm/glm.hpp").read_text(), "vendored glm")
        self.assertEqual((target / "examples/starter/starter.cpp").read_text(), "3D starter")
        self.assertTrue((target / "shaders/glsl/base/base.vert").is_file())
        self.assertFalse((target / "examples/uiscreen/uiscreen.cpp").exists())
        self.assertFalse((target / "ps5/ui/kit.hpp").exists())
        self.assertFalse((target / "ps5/tools/new-title.py").exists())
        self.assertFalse((target / "ps5/README.md").exists())
        self.assertFalse((target / "ps5/sce_sys/param.json").exists())

    def test_exports_ui_starter_and_ui_module_from_a_vendored_snapshot(self):
        target = Path(self.temp.name) / "NativeUITitle"
        target.mkdir()

        revision = NEW_TITLE.export(target, True)

        self.assertEqual(revision, "vendored snapshot 2026-10-20 (upstream revision not recorded)")
        self.assertEqual((target / "examples/uiscreen/uiscreen.cpp").read_text(), "UI starter")
        self.assertEqual((target / "ps5/ui/kit.hpp").read_text(), "optional UI module")
        self.assertTrue((target / "ps5/licenses/GPL-3.0.txt").is_file())
        self.assertEqual((target / "external/glm/glm.hpp").read_text(), "vendored glm")
        self.assertFalse((target / "examples/starter/starter.cpp").exists())
        self.assertFalse((target / "ps5/tools/new-title.py").exists())

    def test_missing_git_identity_skips_only_the_initial_commit(self):
        calls = []

        def run(command, **kwargs):
            calls.append(command)
            if command[-2:] == ["var", "GIT_AUTHOR_IDENT"]:
                return CompletedProcess(command, 128, stderr="empty ident name")
            self.fail(f"Unexpected Git command without an identity: {command}")

        output = io.StringIO()
        with patch.object(NEW_TITLE.subprocess, "run", side_effect=run):
            with redirect_stdout(output):
                committed = NEW_TITLE.create_initial_commit(self.root, "title: generated")

        self.assertFalse(committed)
        self.assertEqual(len(calls), 1)
        self.assertIn("without an initial commit", output.getvalue())


if __name__ == "__main__":
    unittest.main()
