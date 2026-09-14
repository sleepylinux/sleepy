import tempfile
import unittest
from pathlib import Path

from filter_firmware import copy_network_firmware


class FirmwareSelectionTests(unittest.TestCase):
    def test_retains_network_bytes_and_relative_aliases_without_gpu_blobs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root / "source", root / "output"
            for name in ("intel/iwlwifi/test.ucode.zst", "rtl_nic/test.fw.zst",
                         "ath11k/test.bin.zst", "brcm/test.bin.zst", "amdgpu/large.bin.zst",
                         "nvidia/large.bin.zst", "mrvl/prestera/large.bin.zst",
                         "mediatek/mt8195/video.bin.zst", "LICENSE.test"):
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(name.encode())
            (source / "iwlwifi-test.ucode.zst").symlink_to("intel/iwlwifi/test.ucode.zst")
            (source / "cypress").mkdir()
            (source / "cypress/test.bin.zst").symlink_to("../brcm/test.bin.zst")
            copy_network_firmware(source, output)
            self.assertEqual((output / "iwlwifi-test.ucode.zst").read_bytes(), b"intel/iwlwifi/test.ucode.zst")
            self.assertEqual((output / "cypress/test.bin.zst").read_bytes(), b"brcm/test.bin.zst")
            self.assertTrue((output / "rtl_nic/test.fw.zst").is_file())
            self.assertTrue((output / "ath11k/test.bin.zst").is_file())
            self.assertTrue((output / "LICENSE.test").is_file())
            for name in ("amdgpu", "nvidia", "mrvl/prestera", "mediatek/mt8195"):
                self.assertFalse((output / name).exists())
            self.assertFalse((output / "iwlwifi-test.ucode.zst").readlink().is_absolute())

    def test_rejects_links_outside_the_firmware_tree(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            (source / "rtl_nic").mkdir(parents=True)
            (root / "external").write_bytes(b"outside")
            (source / "rtl_nic/bad.fw.zst").symlink_to(root / "external")
            with self.assertRaises(ValueError):
                copy_network_firmware(source, root / "output")


if __name__ == "__main__":
    unittest.main()
