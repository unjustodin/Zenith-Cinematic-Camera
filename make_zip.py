"""Packs the add-on as dist/cinematic-camera_<version>.zip, ready to drop into Zenith's add-ons
folder as it is (Zenith reads zips; no unpacking). The zip holds a cinematic-camera/ folder, as
Factorio's mod zips do.

    python make_zip.py
"""
import json
import os
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
KEEP = (".gd", ".json", ".md", ".png", ".svg", ".tres", ".gdshader")
EXTRA = ("LICENSE",)


def main() -> None:
    manifest = json.load(open(os.path.join(HERE, "addon.json"), encoding="utf-8"))
    name = "%s_%s.zip" % (manifest["id"], manifest["version"])
    out_dir = os.path.join(HERE, "dist")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, name)
    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(HERE):
            dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d != "dist")
            for f in sorted(files):
                if not (f.endswith(KEEP) or f in EXTRA) or f == os.path.basename(__file__):
                    continue
                full = os.path.join(root, f)
                rel = os.path.relpath(full, HERE).replace(os.sep, "/")
                z.write(full, manifest["id"] + "/" + rel)
                count += 1
    print("%s: %d files" % (out, count))


if __name__ == "__main__":
    main()
