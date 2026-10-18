"""Ensure the ready-to-use output ZIP contains a safe, portable hierarchy."""
from __future__ import annotations
import sys
import zipfile
from pathlib import Path

def verify(path):
    with zipfile.ZipFile(path) as z:
        names = set(z.namelist())
        base = 'SandboxiePlusPortable/'
        required = {
            base + 'SandboxiePlusPortable.exe',
            base + 'App/SandboxiePlus/SandMan.exe',
            base + 'App/SandboxiePlus/SbieDrv.sys',
            base + 'App/SandboxiePlus/SbieSvc.exe',
            base + 'App/AppInfo/appicon.ico',
            base + 'Data/Settings/Sandboxie.ini',
            base + 'Data/Settings/Sandboxie-Plus.ini',
            base + 'Other/PACKAGE-INFO.txt',
        }
        missing = required - names
        if missing:
            raise RuntimeError('Missing package members: '+', '.join(sorted(missing)))
        if base + 'App/SandboxiePlus/Sandboxie.ini' in names:
            raise RuntimeError('Configuration INI must be stored under Data, not App')
        if base + 'App/SandboxiePlus/Sandboxie-Plus.ini' in names:
            raise RuntimeError('UI configuration INI must be stored under Data, not App')
        assert all(not n.startswith('/') and '..' not in Path(n).parts for n in names)
        return len(names)

if __name__ == '__main__':
    num = verify(sys.argv[1]); print('Validated portable ZIP with', num, 'entries')
