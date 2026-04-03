# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['server_main.py'],
    pathex=[],
    binaries=[],
    datas=[('runtime', 'runtime'), ('memory', 'memory'), ('apps', 'apps'), ('core', 'core'), ('dictionaries', 'dictionaries'), ('terms.json', '.')],
    hiddenimports=['uvicorn.logging', 'uvicorn.protocols.http', 'uvicorn.protocols.http.auto', 'uvicorn.protocols.http.h11_impl', 'uvicorn.protocols.websockets', 'uvicorn.protocols.websockets.auto', 'uvicorn.lifespan', 'uvicorn.lifespan.on', 'uvicorn.lifespan.off', 'runtime', 'runtime.models', 'runtime.models.events', 'runtime.models.config', 'runtime.fastpath', 'runtime.fastpath.stt', 'runtime.fastpath.corrector', 'runtime.fastpath.pipeline', 'runtime.slowpath', 'runtime.slowpath.worker', 'runtime.slowpath.polisher', 'runtime.routing', 'runtime.routing.profiles', 'memory', 'memory.sqlite_store', 'apps.desktop', 'apps.desktop.server', 'core', 'core.audio'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='voxlog-server',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
