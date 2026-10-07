"""Unit tests for hyprtk_isocreator.core (no GTK, no root needed)."""

import re
import unittest

from hyprtk_isocreator import core


class BuilderArgsTests(unittest.TestCase):
    def test_defaults_only_name_the_iso(self):
        # iso_name defaults to "hyprtk" (the builder's own default), so the only
        # flag is the explicit --iso-name.
        self.assertEqual(core.builder_args(core.Options()), ["--iso-name", "hyprtk"])

    def test_no_name_means_no_flag(self):
        self.assertEqual(core.builder_args(core.Options(iso_name="")), [])

    def test_values_and_negations(self):
        opts = core.Options(
            hyprtk_dir="/src/hyprtk",
            iso_name="custom",
            iso_label="MYLABEL",
            out_dir="/out",
            build_root="/work",
            aur=False,
            matuwall=False,
            profile_only=True,
            keep_work=True,
        )
        self.assertEqual(
            core.builder_args(opts),
            [
                "--hyprtk-dir", "/src/hyprtk",
                "--iso-name", "custom",
                "--iso-label", "MYLABEL",
                "--out-dir", "/out",
                "--build-root", "/work",
                "--no-aur", "--no-matuwall",
                "--profile-only", "--keep-work",
            ],
        )

    def test_blank_strings_are_omitted(self):
        opts = core.Options(iso_name="", hyprtk_dir="   ", out_dir="", build_root="\t")
        self.assertEqual(core.builder_args(opts), [])


class ValidateTests(unittest.TestCase):
    def test_ok(self):
        self.assertEqual(core.validate(core.Options()), [])

    def test_empty_name(self):
        errs = core.validate(core.Options(iso_name="  "))
        self.assertTrue(any("name" in e.lower() for e in errs))

    def test_long_label(self):
        errs = core.validate(core.Options(iso_label="X" * 33))
        self.assertTrue(any("32" in e for e in errs))
        self.assertEqual(core.validate(core.Options(iso_label="X" * 32)), [])

    def test_default_label_shape(self):
        self.assertRegex(core.default_label(), r"^HYPRTK_\d{6}$")


class LogParsingTests(unittest.TestCase):
    def test_strip_ansi(self):
        self.assertEqual(core.strip_ansi("\x1b[35m+\x1b[0m"), "+")

    def test_classify_levels(self):
        self.assertEqual(core.classify_level("\x1b[1;31m  \u2717 bad\x1b[0m"), "err")
        self.assertEqual(core.classify_level("  ! warn"), "warn")
        self.assertEqual(core.classify_level("  \u2713 ok"), "ok")
        self.assertEqual(core.classify_level("  \u2192 info"), "info")
        self.assertEqual(core.classify_level("+====+"), "title")
        self.assertEqual(core.classify_level("plain text"), "text")

    def test_detect_stage(self):
        cases = {
            core.strip_ansi("+==========================================================+"): None,
            "  \u2192 Assembling archiso profile from releng: /tmp/x": "profile",
            "  \u2713 Added 12 hyprtk package(s) to releng's package list": "packages",
            "  \u2192 Building matuwall from source": "matuwall",
            "  \u2192 Building 3 AUR package(s) as kori (best-effort)": "aur",
            "  \u2192 Running mkarchiso (this takes a while)...": "iso",
            "  \u2713 hyprtk source: /home/kori/hyprtk": "source",
        }
        for line, expected in cases.items():
            self.assertEqual(core.detect_stage(line), expected, line)

    def test_parse_results(self):
        self.assertEqual(core.parse_iso_path("  \u2713 ISO:  /home/k/hyprtk-x.iso"),
                         "/home/k/hyprtk-x.iso")
        self.assertEqual(core.parse_size("  \u2713 Size: 2.1G"), "2.1G")
        self.assertEqual(core.parse_profile_path("  \u2713 Profile: /tmp/hyprtk-iso-build/profile"),
                         "/tmp/hyprtk-iso-build/profile")
        self.assertIsNone(core.parse_iso_path("not an iso line"))


class StageTests(unittest.TestCase):
    def test_fraction_is_ordered(self):
        fracs = [core.stage_fraction(key) for key, _ in core.STAGES]
        self.assertEqual(fracs, sorted(fracs))
        self.assertEqual(core.stage_fraction("host"), 0.0)
        self.assertLess(core.stage_fraction("iso"), 1.0)
        self.assertGreater(core.stage_fraction("iso"), 0.5)


if __name__ == "__main__":
    unittest.main()
