"""Check that uninstall removes only owned files, preserving unrelated install-folder files."""
import importlib.util
from pathlib import Path
import tempfile

spec = importlib.util.spec_from_file_location('installer_build', Path(__file__).with_name('build.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert module.quote_nsis('cash$".txt') == 'cash$$$\\".txt'
with tempfile.TemporaryDirectory() as tmp:
    directory = Path(tmp)
    payload = directory / 'payload'
    (payload / 'zh-Hans').mkdir(parents=True)
    (payload / 'CampusConnect.exe').write_bytes(b'MZapp')
    (payload / 'zh-Hans' / 'resources.dll').write_bytes(b'MZresource')
    (payload / 'cash$.txt').write_text('escaping', encoding='utf-8')
    manifest = directory / 'delete.nsh'
    size, count = module.write_delete_manifest(payload, manifest)
    text = manifest.read_text(encoding='utf-8')
    assert count == 3 and size > 0
    assert 'Delete "$INSTDIR\\CampusConnect.exe"' in text
    assert 'Delete "$INSTDIR\\zh-Hans\\resources.dll"' in text
    assert 'RMDir "$INSTDIR\\zh-Hans"' in text
    assert 'RMDir /r' not in text and '*.*' not in text
    assert 'cash$$.txt' in text
    install = directory / 'install.nsh'
    module.write_install_manifest(payload, install)
    install_text = install.read_text(encoding='utf-8')
    assert 'CampusConnect.exe · 5 字节' in install_text
    assert 'SetOutPath "$INSTDIR\\zh-Hans"' in install_text
    assert 'File "/oname=resources.dll"' in install_text
    assert 'cash$$.txt' in install_text
    (payload / 'configuration.json').write_text('{}')
    try:
        module.write_delete_manifest(payload, manifest)
    except ValueError:
        pass
    else:
        raise AssertionError('Personal configuration accepted as installer payload')
print('PASS: detailed extraction manifest, exact-file uninstall manifest, path escaping, personal-data exclusion.')
