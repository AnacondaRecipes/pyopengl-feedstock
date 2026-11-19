"""Windows-only post-install tests for PyOpenGL 3.1.10.

Verifies that the conda build contains the natively built GLE DLL
(gle64.vc14.dll on win-64, glearm64.vc14.dll on win-arm64) and that
no legacy VC9/VC10 prebuilts leaked in from the PyPI sdist (they
would fail conda-build's overlinking check with MSVCR90/100 errors).

Kept as a standalone script rather than an inline `python -c "..."`
because cmd.exe treats bare `%` as env-var delimiters even inside
double quotes, which truncated the original one-liner to `'gle_s`.
"""

import os
import sysconfig


def test_win_dlls():
    plat = sysconfig.get_platform()
    suffix = {"win-amd64": "64", "win-arm64": "arm64"}[plat]
    import OpenGL

    dlls_dir = os.path.join(os.path.dirname(OpenGL.__file__), "DLLS")
    dlls = os.listdir(dlls_dir)
    print(f"Platform: {plat}, suffix: {suffix}")
    print(f"DLLS dir: {dlls_dir}")
    for d in sorted(dlls):
        print(f"  {d}")

    expected = f"gle{suffix}.vc14.dll"
    assert expected in dlls, f"{expected} not in {dlls}"
    assert not any(x.endswith(".vc9.dll") for x in dlls), dlls
    assert not any(x.endswith(".vc10.dll") for x in dlls), dlls

    # Verify the loader can actually find the bundled DLL
    from OpenGL.platform import win32

    assert win32.size == suffix, (win32.size, suffix)
    print(f"GLE loader size suffix: {win32.size}")


if __name__ == "__main__":
    test_win_dlls()
    print("test_win: OK")
