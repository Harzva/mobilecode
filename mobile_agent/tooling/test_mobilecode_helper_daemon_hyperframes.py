#!/usr/bin/env python3
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent))
from mobilecode_helper_daemon import hyperframes_command_args


class HyperFramesCommandArgsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.cwd = Path("/workspace/project")

    def test_check_is_fixed_and_supports_bounded_flags(self) -> None:
        self.assertEqual(
            hyperframes_command_args(
                "hyperframes_check",
                {"snapshots": True, "strict": True, "samples": 3},
                self.cwd,
            ),
            [
                "hyperframes",
                "check",
                ".",
                "--json",
                "--snapshots",
                "--strict",
                "--samples",
                "3",
            ],
        )

    def test_render_rejects_escape_and_shell_like_values(self) -> None:
        with self.assertRaises(ValueError):
            hyperframes_command_args(
                "hyperframes_render",
                {"output": "../escape.mp4"},
                self.cwd,
            )
        with self.assertRaises(ValueError):
            hyperframes_command_args(
                "hyperframes_render",
                {"output": "movie.mp4", "composition": "main;rm"},
                self.cwd,
            )

    def test_render_returns_argv_without_shell_interpolation(self) -> None:
        self.assertEqual(
            hyperframes_command_args(
                "hyperframes_render",
                {"output": "exports/movie.mp4", "composition": "Main"},
                self.cwd,
            ),
            ["hyperframes", "render", ".", "-o", "exports/movie.mp4", "-c", "Main"],
        )


if __name__ == "__main__":
    unittest.main()
