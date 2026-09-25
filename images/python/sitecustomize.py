# FIPS enforcement for hashlib, loaded by every interpreter through site.
#
# CPython probes each OpenSSL hash at import and, for any hash OpenSSL refuses
# (md5, blake2, ... under the FIPS provider), silently switches to its own
# built-in implementation, which is not FIPS validated. hmac, file_digest and
# hashlib.new follow the same fallback. Without this module, hashlib.md5()
# simply works.
#
# After this module runs:
#   - Security use (the default) goes through OpenSSL and its FIPS provider.
#     Non-approved algorithms (md5, blake2, ...) raise ValueError.
#   - usedforsecurity=False keeps the built-in implementations. FIPS permits
#     non-approved algorithms for non-security purposes such as checksums.
#
# `python -S` (no site) skips this module, and code that imports the built-in
# modules (_md5, _sha2, ...) directly bypasses it.

import hashlib as _hashlib_mod

try:
    import _hashlib
except ImportError:  # pragma: no cover - CPython without OpenSSL
    _hashlib = None

if _hashlib is not None:
    _builtin_constructor = _hashlib_mod.__dict__["__get_builtin_constructor"]

    def _builtin_new(name, data=b"", **kwargs):
        return _builtin_constructor(name)(data, **kwargs)

    def _not_available(name):
        return ValueError(
            f"{name} is not available for security use in FIPS mode; "
            "pass usedforsecurity=False for non-security uses"
        )

    def _fips_new(name, data=b"", **kwargs):
        if kwargs.get("usedforsecurity", True):
            try:
                return _hashlib.new(name, data, **kwargs)
            except ValueError as exc:
                raise _not_available(name) from exc
        return _builtin_new(name, data, **kwargs)

    def _fips_constructor(name, builtin):
        openssl = getattr(_hashlib, "openssl_" + name, None)

        def constructor(data=b"", *, usedforsecurity=True, **kwargs):
            if usedforsecurity:
                if openssl is None:
                    raise _not_available(name)
                try:
                    return openssl(data, usedforsecurity=True, **kwargs)
                except ValueError as exc:
                    raise _not_available(name) from exc
            return builtin(data, usedforsecurity=False, **kwargs)

        constructor.__name__ = name
        constructor.__qualname__ = name
        return constructor

    for _name in _hashlib_mod.algorithms_guaranteed:
        _builtin = getattr(_hashlib_mod, _name, None)
        if _builtin is not None:
            setattr(_hashlib_mod, _name, _fips_constructor(_name, _builtin))
    _hashlib_mod.new = _fips_new

    del _name, _builtin

# Debian's default sitecustomize: install the apport exception handler if
# available.
try:
    import apport_python_hook
except ImportError:
    pass
else:
    apport_python_hook.install()
