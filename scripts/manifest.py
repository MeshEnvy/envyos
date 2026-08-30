#!/usr/bin/env python3
"""Read/write EnvyOS MANIFEST.json (releases.next bench head + shipped snapshots)."""

from __future__ import annotations

import argparse
import copy
import json
from datetime import date
from pathlib import Path
from typing import Any

BENCH_TAG = "next"
# Lookup aliases only. Do not rewrite stored keys on save — shipped tags keep
# "bootloader"; releases.next uses "adafruit-nrf52-bootloader".
ALIASES = {
    "firmware": "meshcore",
    "bootloader": "adafruit-nrf52-bootloader",
    "bl": "adafruit-nrf52-bootloader",
}
CORE_PACKAGES = ("meshcore", "adafruit-nrf52-bootloader", "motatool")


def canonical_name(name: str) -> str:
    return ALIASES.get(name, name)


def stored_package_key(packages: dict[str, Any], name: str) -> str | None:
    """Key as stored on this release. Does not rewrite shipped snapshots."""
    canon = canonical_name(name)
    if canon in packages:
        return canon
    if name in packages:
        return name
    for alias, target in ALIASES.items():
        if target == canon and alias in packages:
            return alias
    return None


def lookup_package(packages: dict[str, Any], name: str) -> dict[str, str] | None:
    key = stored_package_key(packages, name)
    if key is None:
        return None
    return packages[key]


def parse_tag(tag: str) -> str:
    tag = tag.strip()
    if tag == BENCH_TAG:
        return BENCH_TAG
    if not tag.startswith("v"):
        tag = f"v{tag.lstrip('v')}"
    return tag


def fork_repo(packages_meta: Path | None, name: str) -> str:
    if packages_meta is None:
        return ""
    pkg_file = packages_meta / canonical_name(name) / "PACKAGE"
    if not pkg_file.is_file():
        return ""
    for line in pkg_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        if key in ("fork_repo", "repo"):
            return val.strip()
    return ""


def normalize_packages(raw: Any) -> dict[str, dict[str, str]]:
    if not isinstance(raw, dict):
        raise SystemExit("error: packages must be an object")
    out: dict[str, dict[str, str]] = {}
    for key, row in raw.items():
        name = str(key)
        if not isinstance(row, dict):
            continue
        out[name] = {
            "repo": str(row.get("repo", "")),
            "version": str(row.get("version", "")),
            "sha": str(row.get("sha", "")),
        }
    return out


def normalize_release_entry(raw: Any, *, bench: bool = False) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise SystemExit("error: release entry must be an object")
    packages = normalize_packages(raw.get("packages", {}))
    entry: dict[str, Any] = {"packages": packages}
    published = str(raw.get("published", ""))
    if published and not bench:
        entry["published"] = published
    return entry


def normalize_releases(raw: Any) -> dict[str, dict[str, Any]]:
    if not isinstance(raw, dict):
        raise SystemExit("error: releases must be an object keyed by tag")
    out: dict[str, dict[str, Any]] = {}
    for key, entry in raw.items():
        tag = parse_tag(str(key))
        out[tag] = normalize_release_entry(entry, bench=(tag == BENCH_TAG))
    return out


def version_sort_key(tag: str) -> tuple[int, int, int]:
    body = parse_tag(tag)[1:]
    parts = body.split(".")
    while len(parts) < 3:
        parts.append("0")
    return tuple(int(p) for p in parts[:3])


def shipped_tags(releases: dict[str, dict[str, Any]]) -> list[str]:
    return [tag for tag in releases if tag != BENCH_TAG]


def ensure_next_release(
    releases: dict[str, dict[str, Any]], packages_meta: Path | None
) -> None:
    if BENCH_TAG not in releases:
        releases[BENCH_TAG] = {"packages": {}}
    packages = releases[BENCH_TAG]["packages"]
    if "bootloader" in packages and "adafruit-nrf52-bootloader" not in packages:
        packages["adafruit-nrf52-bootloader"] = packages.pop("bootloader")
    for name in CORE_PACKAGES:
        if name not in packages:
            packages[name] = {
                "repo": fork_repo(packages_meta, name),
                "version": "",
                "sha": "",
            }
        elif packages_meta and not packages[name].get("repo"):
            packages[name]["repo"] = fork_repo(packages_meta, name)


def load(path: Path, packages_meta: Path | None = None) -> dict[str, Any]:
    data = json.loads(path.read_text())
    releases = normalize_releases(data.get("releases", {}))
    ensure_next_release(releases, packages_meta)
    return {"releases": releases}


def save(path: Path, data: dict[str, Any], packages_meta: Path | None = None) -> None:
    releases = normalize_releases(data.get("releases", {}))
    ensure_next_release(releases, packages_meta)
    ordered: dict[str, Any] = {}
    if BENCH_TAG in releases:
        ordered[BENCH_TAG] = releases[BENCH_TAG]
    for tag in sorted(shipped_tags(releases), key=version_sort_key):
        ordered[tag] = releases[tag]
    path.write_text(json.dumps({"releases": ordered}, indent=2) + "\n")


def bench_packages(data: dict[str, Any]) -> dict[str, dict[str, str]]:
    release = data["releases"].get(BENCH_TAG)
    if release is None:
        return {}
    return release["packages"]


def bench_package(data: dict[str, Any], name: str) -> dict[str, str] | None:
    return lookup_package(bench_packages(data), name)


def release_package(data: dict[str, Any], tag: str, name: str) -> dict[str, str] | None:
    release = data["releases"].get(parse_tag(tag))
    if release is None:
        return None
    return lookup_package(release["packages"], name)


def ensure_bench_package(
    data: dict[str, Any], name: str, packages_meta: Path | None
) -> dict[str, str]:
    ensure_next_release(data["releases"], packages_meta)
    name = canonical_name(name)
    packages = data["releases"][BENCH_TAG]["packages"]
    row = packages.get(name)
    if row is None:
        row = {"repo": fork_repo(packages_meta, name), "version": "", "sha": ""}
        packages[name] = row
    elif packages_meta and not row.get("repo"):
        row["repo"] = fork_repo(packages_meta, name)
    return row


def cmd_get(args: argparse.Namespace) -> None:
    row = bench_package(load(args.path, args.packages_meta), args.name)
    if row is None:
        raise SystemExit(1)
    val = row.get(args.field, "")
    if not val:
        raise SystemExit(1)
    print(val)


def cmd_has(args: argparse.Namespace) -> None:
    row = bench_package(load(args.path, args.packages_meta), args.name)
    if row is None:
        raise SystemExit(1)
    if args.field == "version" and not row.get("version"):
        raise SystemExit(1)
    if args.field == "sha" and not row.get("sha"):
        raise SystemExit(1)


def cmd_list(args: argparse.Namespace) -> None:
    data = load(args.path, args.packages_meta)
    for name in sorted(bench_packages(data)):
        ver = bench_packages(data)[name].get("version")
        if ver:
            print(f"{name}={ver}")


def cmd_set_version(args: argparse.Namespace) -> None:
    path = args.path
    data = load(path, args.packages_meta)
    row = ensure_bench_package(data, args.name, args.packages_meta)
    row["version"] = args.version
    save(path, data, args.packages_meta)


def cmd_set_sha(args: argparse.Namespace) -> None:
    path = args.path
    data = load(path, args.packages_meta)
    name = canonical_name(args.name)
    packages = bench_packages(data)
    key = stored_package_key(packages, name)
    if key is None:
        raise SystemExit(f"error: unknown package {name!r} in {path}")
    packages[key]["sha"] = args.sha
    save(path, data, args.packages_meta)


def cmd_lock(args: argparse.Namespace) -> None:
    path = args.path
    data = load(path, args.packages_meta)
    for spec in args.spec:
        if "=" not in spec:
            raise SystemExit(f"error: lock spec must be name=sha (got {spec!r})")
        name, sha = spec.split("=", 1)
        row = ensure_bench_package(data, name, args.packages_meta)
        row["sha"] = sha
    save(path, data, args.packages_meta)


def cmd_releases_list(args: argparse.Namespace) -> None:
    releases = load(args.path, args.packages_meta)["releases"]
    for tag in sorted(shipped_tags(releases), key=version_sort_key):
        print(tag)


def cmd_releases_latest(args: argparse.Namespace) -> None:
    tags = shipped_tags(load(args.path, args.packages_meta)["releases"])
    if not tags:
        raise SystemExit(1)
    print(max(tags, key=version_sort_key))


def cmd_releases_has(args: argparse.Namespace) -> None:
    tag = parse_tag(args.tag)
    if tag == BENCH_TAG:
        raise SystemExit(1)
    if tag not in load(args.path, args.packages_meta)["releases"]:
        raise SystemExit(1)


def cmd_releases_record(args: argparse.Namespace) -> None:
    path = args.path
    data = load(path, args.packages_meta)
    tag = parse_tag(args.tag)
    if tag == BENCH_TAG:
        raise SystemExit(f"error: cannot record bench tag {BENCH_TAG!r}")
    if tag in data["releases"]:
        raise SystemExit(f"error: {tag} is already recorded")
    published = args.published or date.today().isoformat()
    data["releases"][tag] = {
        "published": published,
        "packages": copy.deepcopy(bench_packages(data)),
    }
    save(path, data, args.packages_meta)


def cmd_releases_get(args: argparse.Namespace) -> None:
    data = load(args.path, args.packages_meta)
    tag = parse_tag(args.tag)
    if args.key == "published":
        release = data["releases"].get(tag)
        if release is None or not release.get("published"):
            raise SystemExit(1)
        print(release["published"])
        return
    row = release_package(data, tag, args.key)
    if row is None:
        raise SystemExit(1)
    val = row.get(args.field, "")
    if not val:
        raise SystemExit(1)
    print(val)


def cmd_releases_packages(args: argparse.Namespace) -> None:
    data = load(args.path, args.packages_meta)
    tag = parse_tag(args.tag)
    release = data["releases"].get(tag)
    if release is None:
        raise SystemExit(1)
    for name in sorted(release["packages"]):
        row = release["packages"][name]
        print(f"{name}={row.get('version', '')}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument("--packages-meta", type=Path, default=None)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_get = sub.add_parser("get")
    p_get.add_argument("name")
    p_get.add_argument("field", choices=("version", "sha", "repo"))
    p_get.set_defaults(func=cmd_get)

    p_has = sub.add_parser("has")
    p_has.add_argument("name")
    p_has.add_argument("--field", default="version", choices=("version", "sha"))
    p_has.set_defaults(func=cmd_has)

    p_list = sub.add_parser("list")
    p_list.set_defaults(func=cmd_list)

    p_ver = sub.add_parser("set-version")
    p_ver.add_argument("name")
    p_ver.add_argument("version")
    p_ver.set_defaults(func=cmd_set_version)

    p_sha = sub.add_parser("set-sha")
    p_sha.add_argument("name")
    p_sha.add_argument("sha")
    p_sha.set_defaults(func=cmd_set_sha)

    p_lock = sub.add_parser("lock")
    p_lock.add_argument("spec", nargs="+", help="name=sha pairs")
    p_lock.set_defaults(func=cmd_lock)

    p_rel = sub.add_parser("releases")
    rel_sub = p_rel.add_subparsers(dest="rel_cmd", required=True)

    p_rel_list = rel_sub.add_parser("list")
    p_rel_list.set_defaults(func=cmd_releases_list)

    p_rel_latest = rel_sub.add_parser("latest")
    p_rel_latest.set_defaults(func=cmd_releases_latest)

    p_rel_has = rel_sub.add_parser("has")
    p_rel_has.add_argument("tag")
    p_rel_has.set_defaults(func=cmd_releases_has)

    p_rel_record = rel_sub.add_parser("record")
    p_rel_record.add_argument("tag")
    p_rel_record.add_argument("--published", default="")
    p_rel_record.set_defaults(func=cmd_releases_record)

    p_rel_get = rel_sub.add_parser("get")
    p_rel_get.add_argument("tag")
    p_rel_get.add_argument("key", help="published or package name")
    p_rel_get.add_argument(
        "field",
        nargs="?",
        default="version",
        choices=("version", "sha", "repo"),
    )
    p_rel_get.set_defaults(func=cmd_releases_get)

    p_rel_pkgs = rel_sub.add_parser("packages")
    p_rel_pkgs.add_argument("tag")
    p_rel_pkgs.set_defaults(func=cmd_releases_packages)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
