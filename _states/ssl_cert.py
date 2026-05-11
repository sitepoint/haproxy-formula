# -*-Python-*-
"""
Salt state module for deploying SSL certificate bundles with validity checking.

Provides the ``ssl_cert.deployed`` state, which behaves like ``file.managed``
but skips deployment if the entity certificate contained in the PEM bundle has
expired or cannot be parsed.
"""

import logging

log = logging.getLogger(__name__)

__virtualname__ = "ssl_cert"

try:
    from OpenSSL import crypto

    HAS_OPENSSL = True
except ImportError:
    HAS_OPENSSL = False


def __virtual__():
    if HAS_OPENSSL:
        return __virtualname__
    return False, "pyOpenSSL is required but not available"


def _extract_first_cert(pem_content):
    """Extract the first PEM certificate block from a bundle.

    Skips any preceding blocks (e.g. private key) and returns the first
    ``-----BEGIN CERTIFICATE-----`` ... ``-----END CERTIFICATE-----`` block,
    or None if no such block is found.
    """
    cert_lines = []
    in_cert = False
    for line in pem_content.splitlines():
        if line.strip() == "-----BEGIN CERTIFICATE-----":
            in_cert = True
            cert_lines = [line]
            continue
        if in_cert:
            cert_lines.append(line)
            if line.strip() == "-----END CERTIFICATE-----":
                return "\n".join(cert_lines) + "\n"
    return None


def _cert_is_valid(cert_pem):
    """Return True if the certificate has not expired."""
    try:
        cert = crypto.load_certificate(crypto.FILETYPE_PEM, cert_pem)
        return not cert.has_expired()
    except crypto.Error as exc:
        log.error("Failed to parse certificate: %s", exc)
        return False


def deployed(name, contents=None, **kwargs):
    """Deploy an SSL certificate bundle only if the entity certificate is valid.

    If the certificate is expired or cannot be parsed, the state succeeds with
    no changes and the file is not created or updated.

    ``show_changes`` is always ``False`` to prevent private key material from
    appearing in Salt output; the argument is silently ignored if passed.

    All other keyword arguments are passed through to ``file.managed``.

    name
        Path to the certificate bundle file to deploy.

    contents
        The PEM bundle to deploy. The first ``-----BEGIN CERTIFICATE-----``
        block is extracted and checked for expiry; any preceding blocks
        (e.g. a private key) are skipped.

    CLI Example:

    .. code-block:: bash

        salt '*' state.single ssl_cert.deployed name=/etc/haproxy/certs/example.pem
    """
    kwargs.pop("show_changes", None)

    cert_pem = _extract_first_cert(contents or "")

    if cert_pem is None:
        return {
            "name": name,
            "result": False,
            "comment": "No PEM certificate block found in contents",
            "changes": {},
        }

    if not _cert_is_valid(cert_pem):
        return {
            "name": name,
            "result": True,
            "comment": f"{name} not deployed: certificate is expired or invalid",
            "changes": {},
        }

    return __states__["file.managed"](
        name=name,
        contents=contents,
        show_changes=False,
        **kwargs,
    )
