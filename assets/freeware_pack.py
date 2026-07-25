# Downloads each freeware title, extracts the needed file from its zip when
# necessary, sanity-checks WAD magics, and writes freeware/<key>.js files
# the page can load with a script tag. Failures are warnings, not fatal:
# the page explains per title if its file is missing.
import base64, io, json, os, subprocess, sys, zipfile

outdir = sys.argv[1]

# (js key, download url, member inside the zip or None for a raw file,
#  filename the page should present to the engine)
PLAN = [
    ("doom1",       "https://distro.ibiblio.org/slitaz/sources/packages/d/doom1.wad",
                    None,            "doom1.wad"),
    ("freedoom1",   "https://github.com/freedoom/freedoom/releases/download/v0.13.0/freedoom-0.13.0.zip",
                    "freedoom-0.13.0/freedoom1.wad", "freedoom1.wad"),
    ("freedoom2",   "https://github.com/freedoom/freedoom/releases/download/v0.13.0/freedoom-0.13.0.zip",
                    "freedoom-0.13.0/freedoom2.wad", "freedoom2.wad"),
    ("hacx",        "https://www.gamers.org/pub/idgames/themes/hacx/hacx12.zip",
                    "HACX.WAD",      "hacx.wad"),
    # Chex Quest 3: Vanilla Edition (Melodic Spaceship, 2024): the whole Chex
    # trilogy backported to the vanilla engine as a self-contained IWAD. The
    # external chex3.deh is the plain-DeHackEd patch its readme prescribes
    # for Chocolate-class engines like this one.
    ("chex3v",      "https://dsdarchive.com/files/wads/doom/4756/chex3v_1_0.zip",
                    "chex3v.wad",    "chex3v.wad"),
    ("chex3v_deh",  "https://dsdarchive.com/files/wads/doom/4756/chex3v_1_0.zip",
                    "chex3.deh",     "chex3.deh"),
    ("chex3v_readme", "https://dsdarchive.com/files/wads/doom/4756/chex3v_1_0.zip",
                    "chex3v_readme.txt", "chex3v-readme.txt"),
    ("harmonyc",    "https://www.gamers.org/pub/idgames/levels/doom2/Ports/g-i/harmonyc.zip",
                    "HarmonyC.wad",  "harmonyc.wad"),
    ("harmony_deh", "https://www.gamers.org/pub/idgames/levels/doom2/Ports/g-i/harmonyc.zip",
                    "HarmonyC.deh",  "harmony.deh"),
    # WolfenDoom: the author's readme explicitly permits distribution as
    # long as the readme is included, so it is installed alongside.
    ("wolfen1",     "https://www.gamers.org/pub/idgames/themes/wolf3d/1st_enc.zip",
                    "1st_enc.wad",   "1st_enc.wad"),
    ("wolfen1_readme", "https://www.gamers.org/pub/idgames/themes/wolf3d/1st_enc.zip",
                    "1st_enc.txt",   "1st_enc-readme.txt"),
    # STRAIN (1997, Alpha Dog Alliance): distribution terms require including
    # the text file and the ENTIRE package unmodified, so besides the loader
    # files the complete original zip is stored as-is alongside.
    ("strain",      "https://www.gamers.org/pub/idgames/levels/doom2/megawads/strain.zip",
                    "STRAIN.WAD",    "strain.wad"),
    ("strain_deh",  "https://www.gamers.org/pub/idgames/levels/doom2/megawads/strain.zip",
                    "STRAIN.DEH",    "strain.deh"),
    ("strain_readme", "https://www.gamers.org/pub/idgames/levels/doom2/megawads/strain.zip",
                    "STRAIN.TXT",    "strain-readme.txt"),
    ("strain_package", "https://www.gamers.org/pub/idgames/levels/doom2/megawads/strain.zip",
                    None,            "strain-package.zip"),
]

downloads = {}   # url -> bytes, so the two-member zips download once

def fetch(url):
    if url not in downloads:
        print("  downloading %s" % url.split("/")[-1])
        data = subprocess.run(["curl", "-sL", "--max-time", "600", url],
                              capture_output=True).stdout
        if not data:
            raise RuntimeError("empty download")
        downloads[url] = data
    return downloads[url]

failed = []
for key, url, member, engine_name in PLAN:
    is_raw = engine_name.endswith(".txt") or engine_name.endswith(".zip")
    outpath = os.path.join(outdir, engine_name if is_raw else key + ".js")
    if os.path.exists(outpath):
        print("  %s: already packed" % key)
        continue
    try:
        raw = fetch(url)
        if member is not None:
            raw = zipfile.ZipFile(io.BytesIO(raw)).read(member)
        if is_raw:
            # Stored as-is, not packed: readmes and complete original
            # packages whose inclusion is a distribution condition.
            with open(outpath, "wb") as f:
                f.write(raw)
            print("  %s: installed (%d bytes)" % (key, len(raw)))
            continue
        if engine_name.endswith(".wad") and raw[:4] not in (b"IWAD", b"PWAD"):
            raise RuntimeError("not a WAD (bad magic)")
        b64 = base64.b64encode(raw).decode("ascii")
        with open(outpath, "w") as f:
            f.write('window.WASM_BUILDER_FREEWARE = window.WASM_BUILDER_FREEWARE || {};\n')
            f.write('window.WASM_BUILDER_FREEWARE[%s] = { name: %s, b64: %s };\n'
                    % (json.dumps(key), json.dumps(engine_name), json.dumps(b64)))
        print("  %s: packed (%.1f MB)" % (key, len(raw) / 1048576.0))
    except Exception as e:
        failed.append(key)
        print("  %s: FAILED (%s)" % (key, e))

if failed:
    print("Some titles failed: %s. The page will say so per title;" % ", ".join(failed))
    print("re-run install.sh to retry just the missing ones.")
