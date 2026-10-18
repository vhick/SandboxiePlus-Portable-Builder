"""Offline safety/structural tests. These do NOT validate actual kernel/driver behavior."""
import tempfile
import unittest
import zipfile
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('verify_zip', ROOT / 'builder' / 'verify_zip.py')
verify_zip = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify_zip)

class BuilderTests(unittest.TestCase):
    def test_expected_workflow_only_manual(self):
        source = (ROOT/'.github/workflows/build-sandboxieplus-portable.yml').read_text()
        self.assertIn('workflow_dispatch:', source)
        self.assertNotIn('schedule:', source)
        self.assertNotIn('pull_request:', source)
        self.assertIn('upload-artifact@v4', source)
    def test_release_checksum_enforced(self):
        source = (ROOT/'builder/build_windows.ps1').read_text()
        self.assertIn('Get-FileHash', source)
        self.assertIn('SHA256', source)
        self.assertIn('throw \'No verifiable official SHA-256', source)
        self.assertIn('$release.prerelease', source)
    def test_official_portable_extraction(self):
        source = (ROOT/'builder/build_windows.ps1').read_text()
        self.assertIn('/PORTABLE=1',source)
        self.assertIn('/OPEN_AGENT=0',source)
        self.assertIn('/CURRENTUSER',source)
        self.assertNotIn('install SbieDrv',source)
        self.assertNotIn('install SbieSvc',source)
    def test_launcher_services_safety(self):
        source = (ROOT/'builder/SandboxiePlusPortable.cs').read_text()
        self.assertIn('IsServiceRegistered("SbieDrv")',source)
        self.assertIn('IsServiceRegistered("SbieSvc")',source)
        self.assertNotIn('KmdUtil.exe",',source)
        self.assertIn('return 3;',source)
    def test_ui_original_icon_from_tag(self):
        source = (ROOT/'builder/build_windows.ps1').read_text()
        self.assertIn('Installer/SandManInstall.ico',source)
        self.assertIn('$ReleaseTag',source)
        self.assertNotIn('ExtractAssociatedIcon', source)
    def test_config_preserved_in_data(self):
        source = (ROOT/'builder/SandboxiePlusPortable.cs').read_text()
        self.assertIn('Data',source)
        self.assertIn('SaveCopy(working, saved)',source)
        self.assertIn('FileRootPath=', source)
        self.assertIn('String.IsNullOrWhiteSpace(content)', source)  # upstream empties both INIs
    def test_driver_state_must_be_absent_after_exit(self):
        source = (ROOT/'builder/SandboxiePlusPortable.cs').read_text()
        self.assertIn('return 4;',source)
        self.assertIn('Do NOT update or move App.',source)
    def test_archive_structure(self):
        required = ['SandboxiePlusPortable/SandboxiePlusPortable.exe',
                    'SandboxiePlusPortable/App/SandboxiePlus/SandMan.exe',
                    'SandboxiePlusPortable/App/SandboxiePlus/SbieSvc.exe',
                    'SandboxiePlusPortable/App/SandboxiePlus/SbieDrv.sys',
                    'SandboxiePlusPortable/Data/Settings/Sandboxie.ini',
                    'SandboxiePlusPortable/Data/Settings/Sandboxie-Plus.ini',
                    'SandboxiePlusPortable/App/AppInfo/appicon.ico',
                    'SandboxiePlusPortable/Other/PACKAGE-INFO.txt']
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'test.zip'
            with zipfile.ZipFile(p,'w') as z:
                for name in required: z.writestr(name,'test')
            self.assertEqual(verify_zip.verify(str(p)),len(required))
    def test_archive_rejects_ini_in_app(self):
        req = ['SandboxiePlusPortable/SandboxiePlusPortable.exe',
                    'SandboxiePlusPortable/App/SandboxiePlus/SandMan.exe',
                    'SandboxiePlusPortable/App/SandboxiePlus/SbieSvc.exe',
                    'SandboxiePlusPortable/App/SandboxiePlus/SbieDrv.sys',
                    'SandboxiePlusPortable/Data/Settings/Sandboxie.ini',
                    'SandboxiePlusPortable/Data/Settings/Sandboxie-Plus.ini',
                    'SandboxiePlusPortable/App/AppInfo/appicon.ico',
                    'SandboxiePlusPortable/Other/PACKAGE-INFO.txt',
                    'SandboxiePlusPortable/App/SandboxiePlus/Sandboxie.ini']
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'test.zip'
            with zipfile.ZipFile(p,'w') as z:
                for name in req: z.writestr(name,'test')
            with self.assertRaisesRegex(RuntimeError,'under Data'):
                verify_zip.verify(str(p))

if __name__ == '__main__': unittest.main()
