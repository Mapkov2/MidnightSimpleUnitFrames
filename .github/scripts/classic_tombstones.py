"""tools/classic-addon-tombstones.txt for the Python tools.

The manifest names the Retail addons this tree retired and the Retail files of
the shipped addons that retired with them:

    <retired addon>                  a Retail addon folder this tree omits
    <retired addon><TAB><path>       a file below a shipped addon folder that
                                     retired with that addon

Blank lines and lines that start with '#' are comments. These are the rules of
Import-MsufAddonTombstones in .github/scripts/ClassicGate.Common.psm1, which the
gate and the packagers use; keep the two in step. Readers here: the Retail
source resolver, the override rebase tool and the retirement smoke.
"""
from __future__ import annotations

import subprocess
from dataclasses import dataclass, field
from pathlib import Path

MANIFEST = "tools/classic-addon-tombstones.txt"
SHIPPED_ADDONS = ("MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options")


class TombstoneError(ValueError):
    """The manifest breaks one of its rules."""


@dataclass
class Tombstones:
    addons: list = field(default_factory=list)   # retired addon folders, manifest order
    paths: dict = field(default_factory=dict)    # retired path -> the addon it retired with

    def covers(self, path):
        """True for a retired path, or for a path below a retired addon folder."""
        return path in self.paths or any(path == addon or path.startswith(addon + "/") for addon in self.addons)


def _addon_name_ok(name):
    return bool(name) and all(character.isascii() and (character.isalnum() or character == "_") for character in name)


def _path_ok(path, shipped):
    parts = path.split("/")
    return (not ("\\" in path or path.endswith("/") or "//" in path
                 or any(part in (".", "..") for part in parts)
                 or any(ord(character) < 32 for character in path))
            and any(path.startswith(addon + "/") for addon in shipped))


def parse(text, shipped=SHIPPED_ADDONS, label=MANIFEST):
    if text.startswith("﻿"):
        raise TombstoneError("%s starts with a byte order mark" % label)
    result = Tombstones()
    shipped_folded = {addon.casefold() for addon in shipped}
    seen = set()
    owners = []
    for number, line in enumerate(text.replace("\r\n", "\n").split("\n"), 1):
        if not line or line.startswith("#"):
            continue
        where = "%s line %d" % (label, number)
        fields = line.split("\t")
        if len(fields) > 2 or any(not value or value != value.strip() for value in fields):
            raise TombstoneError("%s must be '<addon>' or '<addon><TAB><path>' without surrounding blanks: %r"
                                 % (where, line))
        addon = fields[0]
        if not _addon_name_ok(addon):
            raise TombstoneError("%s names a malformed addon folder: %r" % (where, addon))
        if addon.casefold() in shipped_folded:
            raise TombstoneError("%s retires a shipped addon: %s" % (where, addon))
        if len(fields) == 1:
            key = ("addon", addon.casefold())
            if key in seen:
                raise TombstoneError("%s repeats the addon %s" % (where, addon))
            seen.add(key)
            result.addons.append(addon)
            continue
        path = fields[1]
        if not _path_ok(path, shipped):
            raise TombstoneError("%s names a path that is not a normalized file path below a shipped addon "
                                 "folder: %r" % (where, path))
        key = ("path", path.casefold())
        if key in seen:
            raise TombstoneError("%s repeats the path %s" % (where, path))
        seen.add(key)
        result.paths[path] = addon
        owners.append(addon)
    for addon in owners:
        if addon not in result.addons:
            raise TombstoneError("%s ties a path to %s, which no addon line retires" % (label, addon))
    return result


def read(root, shipped=SHIPPED_ADDONS):
    path = Path(root) / MANIFEST
    if not path.is_file():
        raise TombstoneError("%s is missing below %s" % (MANIFEST, root))
    return parse(path.read_bytes().decode("utf-8"), shipped)


def _git_lines(root, arguments):
    process = subprocess.run(["git", "-C", str(root)] + list(arguments), stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE)
    if process.returncode != 0:
        raise TombstoneError("git %s failed: %s" % (" ".join(arguments),
                                                   process.stderr.decode("utf-8", "replace").strip()))
    return [line for line in process.stdout.decode("utf-8").split("\0") if line]


def check_tree(root, tombstones, loaded=()):
    """Problems of a working tree against its tombstones, from git's point of view.

    A retired addon folder that `git rm` left behind (empty, or ignored files
    only) is fine; a tracked file below it, or a TOC in it, is not. A retired
    path must be untracked and absent from `loaded`, the repository-relative
    forward-slash paths the shipped TOCs reach.
    """
    root = Path(root)
    problems = []
    for addon in tombstones.addons:
        tracked = _git_lines(root, ["ls-files", "-z", "--", addon])
        if tracked:
            problems.append("retired addon %s still has tracked files: %s" % (addon, ", ".join(tracked[:5])))
        folder = root / addon
        if folder.is_dir():
            tocs = sorted(path.relative_to(root).as_posix() for path in folder.rglob("*")
                          if path.is_file() and path.suffix.lower() == ".toc")
            if tocs:
                problems.append("retired addon folder %s still holds a TOC that WoW would load: %s"
                                % (addon, ", ".join(tocs)))
    loaded_folded = {path.casefold() for path in loaded}
    for path in tombstones.paths:
        if _git_lines(root, ["ls-files", "-z", "--", path]):
            problems.append("retired Retail path is tracked: %s" % path)
        if path.casefold() in loaded_folded:
            problems.append("retired Retail path is still loaded by a TOC or XML manifest: %s" % path)
    return problems
