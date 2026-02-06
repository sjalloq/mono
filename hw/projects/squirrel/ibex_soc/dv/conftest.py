import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[5]
FIRMWARE_ROOT = REPO_ROOT / "sw" / "device" / "squirrel" / "ibex_soc"


@dataclass
class FirmwareBuild:
    """Build firmware and copy .vmem into a test directory."""
    name: str
    src_dir: Path

    def build_into(self, test_dir: Path) -> None:
        """Build firmware and copy .vmem to test_dir/firmware.vmem."""
        subprocess.run(["make"], cwd=self.src_dir, check=True)
        vmem = self.src_dir / f"{self.name}.vmem"
        shutil.copy2(vmem, test_dir / "firmware.vmem")
