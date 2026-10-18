"""Validate portable ZIP, including PortableApps.com menu metadata and icon PNG dimensions."""
from __future__ import annotations
import configparser
import io
import struct
import sys
import zipfile
from pathlib import PurePosixPath

BASE = 'SandboxiePlusPortable/'
ICONS = (16, 32, 75, 128, 256)


def verify(path):
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        required = {
            BASE + 'SandboxiePlusPortable.exe',
            BASE + 'App/SandboxiePlus/SandMan.exe',
            BASE + 'App/SandboxiePlus/SbieDrv.sys',
            BASE + 'App/SandboxiePlus/SbieSvc.exe',
            BASE + 'App/AppInfo/appicon.ico',
            BASE + 'App/AppInfo/appinfo.ini',
            BASE + 'Data/Settings/Sandboxie.ini',
            BASE + 'Data/Settings/Sandboxie-Plus.ini',
            BASE + 'Other/PACKAGE-INFO.txt',
        } | {BASE + f'App/AppInfo/appicon_{size}.png' for size in ICONS}
        missing = required - names
        if missing:
            raise RuntimeError('Missing package members: ' + ', '.join(sorted(missing)))
        if BASE + 'App/SandboxiePlus/Sandboxie.ini' in names:
            raise RuntimeError('Configuration INI must be stored under Data, not App')
        if BASE + 'App/SandboxiePlus/Sandboxie-Plus.ini' in names:
            raise RuntimeError('UI configuration INI must be stored under Data, not App')
        if not all(not name.startswith('/') and '..' not in PurePosixPath(name).parts for name in names):
            raise RuntimeError('ZIP contains unsafe paths')
        cfg = configparser.ConfigParser(interpolation=None)
        cfg.read_file(io.StringIO(archive.read(BASE + 'App/AppInfo/appinfo.ini').decode('utf-8-sig')))
        details = cfg['Details']
        control = cfg['Control']
        if (details.get('Name') != 'Sandboxie Plus Portable'
                or details.get('Category') != 'Security'
                or control.get('Start') != 'SandboxiePlusPortable.exe'
                or control.get('Icons') != '1'
                or cfg['Format'].get('Type') != 'PortableApps.comFormat'):
            raise RuntimeError('PortableApps Menu metadata is incorrect')
        for size in ICONS:
            data = archive.read(BASE + f'App/AppInfo/appicon_{size}.png')
            if len(data) < 24 or data[:8] != b'\x89PNG\r\n\x1a\n':
                raise RuntimeError(f'appicon_{size}.png is not PNG')
            width, height = struct.unpack('>II', data[16:24])
            if (width, height) != (size, size):
                raise RuntimeError(f'appicon_{size}.png has wrong dimensions: {width}x{height}')
        return len(names)

if __name__ == '__main__':
    num = verify(sys.argv[1])
    print('Verified PortableApps Menu metadata and icon files:', num, 'archive entries')
