"""Empaqueta el commit actual y los binarios verificados para las pruebas físicas."""
import argparse
import hashlib
import io
import os
from pathlib import Path
import stat
import subprocess
import tarfile
import tempfile
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


ROOT = Path(__file__).resolve().parent.parent
ARTIFACT_DIRS = (
    Path("mobile/artifacts"),
    Path("esp32/artifacts/uart-bridge"),
    Path("esp32/artifacts/ble-test"),
)
EXPECTED = {
    ARTIFACT_DIRS[0]: {"app-debug.apk", "app-release-unsigned.apk"},
    **{
        folder: {"healthband_bridge.bin", "bootloader/bootloader.bin",
                 "partition_table/partition-table.bin", "flash_args", "sdkconfig"}
        for folder in ARTIFACT_DIRS[1:]
    },
}
FORBIDDEN_PARTS = {
    ".git", ".gradle", ".idea", ".kotlin", ".DS_Store", "__MACOSX__",
    "__pycache__", ".venv", ".env", "local.properties", "build",
    "credentials.json", "secrets", "deliverables",
}
FORBIDDEN_SUFFIXES = {".zip", ".jks", ".pem", ".key", ".p12", ".db", ".sqlite", ".sqlite3"}


def add_entry(archive, name, content, mode=0o644):
    """Fija el orden, las fechas y los permisos para reconstruir el ZIP."""
    info = ZipInfo(name, (1980, 1, 1, 0, 0, 0))
    info.create_system = 3
    info.external_attr = (stat.S_IFREG | mode) << 16
    archive.writestr(info, content, compress_type=ZIP_DEFLATED, compresslevel=9)


def read_artifacts(entries, folder):
    """Verifica cada artefacto contra el manifiesto incluido en el commit."""
    manifest, _ = entries[(folder / "SHA256SUMS.txt").as_posix()]
    expected = {}
    for line in manifest.decode("ascii").splitlines():
        digest, name = line.split("  ", 1)
        if name in expected:
            raise ValueError(f"Nombre duplicado en manifiesto: {name}")
        expected[name] = digest
    if set(expected) != EXPECTED[folder]:
        raise ValueError(f"Manifiesto incompleto o inesperado: {folder}")
    if folder == ARTIFACT_DIRS[0]:
        for name in expected:
            with ZipFile(ROOT / folder / name) as apk:
                if "AndroidManifest.xml" not in apk.namelist():
                    raise ValueError(f"APK inválido: {name}")
    for name, digest in expected.items():
        path = folder / name
        content = (ROOT / path).read_bytes()
        if hashlib.sha256(content).hexdigest() != digest:
            raise ValueError(f"SHA-256 incorrecto: {path}")
        name_in_zip = path.as_posix()
        entry = entries.get(name_in_zip)
        if entry is not None and entry[0] != content:
            raise ValueError(f"El artefacto local difiere del commit: {path}")
        entries.setdefault(name_in_zip, (content, 0o644))


def make_package(output):
    """Añade archivos versionados y los únicos artefactos enumerados."""
    snapshot = subprocess.check_output(["git", "archive", "--format=tar", "HEAD"], cwd=ROOT)
    entries = {}
    with tarfile.open(fileobj=io.BytesIO(snapshot)) as source:
        for member in source:
            if member.isdir():
                continue
            path = Path(member.name)
            if not member.isfile() or FORBIDDEN_PARTS.intersection(path.parts) or path.suffix in FORBIDDEN_SUFFIXES:
                raise ValueError(f"Archivo incompatible con la entrega: {path}")
            with source.extractfile(member) as file:
                entries[path.as_posix()] = (file.read(), member.mode)
    for folder in ARTIFACT_DIRS:
        read_artifacts(entries, folder)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, prefix=".healthband-", suffix=".tmp") as temporary:
        with ZipFile(temporary, "w") as archive:
            for name, (data, mode) in sorted(entries.items()):
                add_entry(archive, name, data, mode)
        temporary.flush()
        with ZipFile(temporary.name) as archive:
            corrupt = archive.testzip()
            if corrupt:
                raise ValueError(f"Entrada corrupta: {corrupt}")
        # El temporal vive junto al destino y se publica solo después de la verificación.
        os.link(temporary.name, output)
    print(f"{output} {output.stat().st_size} bytes")
    print(f"SHA-256 {hashlib.sha256(output.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "deliverables/healthband-final-testing.zip")
    args = parser.parse_args()
    make_package(args.output.resolve())
