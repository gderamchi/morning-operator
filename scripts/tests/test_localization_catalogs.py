"""Catalog resources must exist in both languages for in-process switches."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LocalizationCatalogTests(unittest.TestCase):
    def test_every_translatable_entry_has_both_resource_languages(self):
        catalogs = [ROOT / "Resources" / name for name in
                    ("Localizable.xcstrings", "InfoPlist.xcstrings", "AppShortcuts.xcstrings")]
        catalogs += [ROOT / "Sources" / module / "Resources" / "Localizable.xcstrings"
                     for module in ("MorningCore", "MorningApple")]
        catalogs.append(ROOT / "Sources/MorningActivityWidget/Localizable.xcstrings")
        for path in catalogs:
            catalog = json.loads(path.read_text())
            for key, entry in catalog["strings"].items():
                if not key or entry.get("shouldTranslate") is False:
                    continue
                for language in ("fr", "en"):
                    with self.subTest(catalog=str(path.relative_to(ROOT)), key=key, language=language):
                        self.assertTrue(entry.get("localizations", {}).get(language))
