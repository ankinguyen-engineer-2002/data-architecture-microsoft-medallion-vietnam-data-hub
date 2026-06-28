from __future__ import annotations

import json
import subprocess
import urllib.parse
import urllib.request


def client_credentials_token(
    *,
    tenant_id: str,
    client_id: str,
    client_secret: str,
    scope: str,
) -> str:
    body = urllib.parse.urlencode(
        {
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
            "scope": scope,
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token",
        data=body,
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))["access_token"]


def az_cli_token(scope: str) -> str:
    result = subprocess.run(
        ["az", "account", "get-access-token", "--resource", scope, "--query", "accessToken", "-o", "tsv"],
        capture_output=True, text=True, timeout=60,
    )
    if result.returncode != 0:
        raise RuntimeError(f"az account get-access-token failed: {result.stderr.strip()}")
    token = result.stdout.strip()
    if not token:
        raise RuntimeError("az account get-access-token returned empty token")
    return token
