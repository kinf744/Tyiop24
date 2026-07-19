#!/usr/bin/env python3
"""
Free Basics Checker — Teste si un domaine est encore zero-rated sur Free Basics.
À executer depuis un téléphone sur le réseau MTN (ou autre opérateur partenaire).
"""

import urllib.request
import urllib.error
import ssl
import sys
import time
import json
import socket

VERSION = "1.0"

# Domaines de référence
DOMAINES_REFERENCE = {
    "facebook.com": {"attendu": True, "note": "Toujours sur Free Basics"},
    "learnbasicmath.github.io": {"attendu": True, "note": "Confirmé FB (GitHub Pages éducatif)"},
    "google.com": {"attendu": False, "note": "N'est PAS sur Free Basics"},
}

# Plateformes gratuites à tester (pour trouver un gap fonctionnel)
PLATEFORMES_GRATUITES = [
    # Sous-domaines Blogger/Blogspot (gratuits, reporter247 était Blogger)
    "testfbcheck.blogspot.com",
    "testfbcheck.blogspot.co.uk",
    "testfbcheck.blogspot.fr",
    "testfbcheck.blogspot.de",
    # Blogspot.com (version brève)
    "testfbcheck.blogspot.com",
    # wordpress.com gratuit
    "testfbcheck.wordpress.com",
    # GitHub Pages (déjà confirmé pour certains)
    "testfbcheck.github.io",
    # weebly
    "testfbcheck.weebly.com",
    # wix (sous-domaine)
    "testfbcheck.wixsite.com",
    # Site123
    "testfbcheck.site123.me",
    # Strikingly
    "testfbcheck.strikingly.com",
    # Jimdo
    "testfbcheck.jimdofree.com",
    # Yola
    "testfbcheck.yolasite.com",
    # Tumblr
    "testfbcheck.tumblr.com",
    # Medium
    "testfbcheck.medium.com",
]

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.5",
}

PROXY_CHECK_URLS = [
    "https://0.freebasics.com/",
    "https://freebasics.com/",
    "https://0.facebook.com/",
]


def color(status, text):
    if status == "OK":
        return f"\033[92m{text}\033[0m"
    elif status == "FAIL":
        return f"\033[91m{text}\033[0m"
    elif status == "WARN":
        return f"\033[93m{text}\033[0m"
    return text


def check_http(domain, path="/", timeout=10):
    """Teste si un domaine répond en HTTP/HTTPS"""
    results = {}
    for proto in ["https", "http"]:
        url = f"{proto}://{domain}{path}"
        try:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE

            req = urllib.request.Request(url, headers=HEADERS, method="GET")
            start = time.time()
            resp = urllib.request.urlopen(req, timeout=timeout, context=ctx)
            elapsed = time.time() - start
            body = resp.read()
            results[proto] = {
                "status": resp.status,
                "time": round(elapsed, 2),
                "size": len(body),
                "ok": True,
            }
        except urllib.error.HTTPError as e:
            results[proto] = {"status": e.code, "ok": False, "error": str(e)}
        except urllib.error.URLError as e:
            results[proto] = {"ok": False, "error": str(e.reason)}
        except Exception as e:
            results[proto] = {"ok": False, "error": str(e)}
    return results


def check_via_proxy(domain, timeout=10):
    """Tente d'accéder via le proxy Free Basics"""
    results = {}
    for proxy_url in PROXY_CHECK_URLS:
        try:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE

            # Méthode 1: Host header
            req = urllib.request.Request(proxy_url, headers={**HEADERS, "Host": domain}, method="GET")
            resp = urllib.request.urlopen(req, timeout=timeout, context=ctx)
            results["proxy_host"] = {"status": resp.status, "ok": True}
        except urllib.error.HTTPError as e:
            # 400/302 de FB = le proxy a traité la requête
            if e.code in (302, 400, 301):
                results["proxy_host"] = {"status": e.code, "ok": True, "note": "Proxy a répondu (good sign)"}
            else:
                results["proxy_host"] = {"status": e.code, "ok": False}
        except Exception as e:
            results["proxy_host"] = {"ok": False, "error": str(e)}

        # Méthode 2: URL directe
        try:
            req = urllib.request.Request(f"{proxy_url.rstrip('/')}/proxy/{domain}", headers=HEADERS, method="GET")
            resp = urllib.request.urlopen(req, timeout=timeout, context=ctx)
            results["proxy_url"] = {"status": resp.status, "ok": True}
        except urllib.error.HTTPError as e:
            results["proxy_url"] = {"status": e.code, "ok": e.code in (302,)}
        except Exception as e:
            results["proxy_url"] = {"ok": False, "error": str(e)}

        break  # Un seul proxy suffit

    return results


def check_dns(domain):
    """Vérifie la résolution DNS"""
    try:
        ips = socket.getaddrinfo(domain, 80)
        ip_list = list(set(addr[4][0] for addr in ips))
        return {"ok": True, "ips": ip_list[:5]}
    except socket.gaierror:
        return {"ok": False, "error": "NXDOMAIN (ne résout pas)"}


def test_domain(domain, timeout=10):
    """Test complet d'un domaine"""
    print(f"\n{'='*50}")
    print(f"  Domaine: {domain}")
    print(f"{'='*50}")

    # DNS
    print(f"\n  [DNS] ", end="")
    dns = check_dns(domain)
    if dns["ok"]:
        print(color("OK", f"Résolu → {', '.join(dns['ips'])}"))
    else:
        print(color("FAIL", f"Échec — {dns['error']}"))

    # HTTP
    print(f"  [HTTP]")
    http = check_http(domain, timeout=timeout)
    for proto, r in http.items():
        if r.get("ok"):
            sc = r["status"]
            sz = r["size"]
            et = r["time"]
            print(f"    {proto}: {color('OK', 'HTTP ' + str(sc))} | {sz} bytes | {et}s")
        else:
            err = r.get("error", "")
            print(f"    {proto}: {color('FAIL', err)}")

    # Proxy test (seulement si MTN)
    print(f"  [Proxy Free Basics] ", end="")
    proxy = check_via_proxy(domain, timeout=timeout)
    proxy_ok = any(v.get("ok") for v in proxy.values())
    if proxy_ok:
        print(color("OK", "Proxy a répondu"))
        for k, v in proxy.items():
            if v.get("ok"):
                print(f"    {k}: HTTP {v['status']} {v.get('note', '')}")
    else:
        print(color("WARN", "Pas de réponse proxy (hors réseau MTN ?)"))

    return {
        "domain": domain,
        "dns": dns,
        "http": http,
        "proxy": proxy,
    }


def main():
    print(f"\n  Free Basics Checker v{VERSION}")
    print(f"  {'='*30}")
    print(f"  Teste si un domaine est accessible via Free Basics")
    print(f"  À executer depuis un téléphone sur le réseau MTN")
    print()

    if len(sys.argv) < 2:
        print("Usage: python3 freebasics_checker.py <domaine> [domaine2 ...]")
        print()
        print("  Exemples:")
        print("    python3 freebasics_checker.py reporter247.org")
        print("    python3 freebasics_checker.py --all")
        print("    python3 freebasics_checker.py reporter247.org learnbasicmath.github.io")
        print("    python3 freebasics_checker.py --free      # Test plateformes gratuites")
        print()
        sys.exit(1)

    domains = sys.argv[1:]

    if "--all" in domains or "-a" in domains:
        domains = list(DOMAINES_REFERENCE.keys()) + ["reporter247.org"]
    if "--free" in domains or "-f" in domains:
        domains = PLATEFORMES_GRATUITES + ["facebook.com", "google.com"]

    # Test chaque domaine
    results = []
    for domain in domains:
        r = test_domain(domain)
        results.append(r)
        time.sleep(1)

    # Résumé
    print(f"\n\n{'='*50}")
    print(f"  RÉSUMÉ")
    print(f"{'='*50}")
    print(f"\n  {'Domaine':<35} {'DNS':<8} {'HTTP':<8} {'Proxy':<8} {'Verdict'}")
    print(f"  {'-'*35} {'-'*8} {'-'*8} {'-'*8} {'-'*15}")

    for r in results:
        d = r["domain"]
        dns = "OK" if r["dns"].get("ok") else "FAIL"
        http_ok = any(v.get("ok") and v.get("status") == 200 for v in r["http"].values())
        http = "OK" if http_ok else "NOK"
        proxy = "OK" if any(v.get("ok") for v in r["proxy"].values()) else "N/A"

        # Verdict Free Basics
        ref = DOMAINES_REFERENCE.get(d)
        if ref:
            if http_ok == ref["attendu"]:
                verdict = f"✅ {ref['note']}"
            else:
                verdict = f"⚠️ Inattendu"
        else:
            if http_ok:
                verdict = "✅ ACCESSIBLE (probablement FB)"
            else:
                verdict = "❌ PAS accessible (probablement pas FB)"

        print(f"  {d:<35} {dns:<8} {http:<8} {proxy:<8} {verdict}")

    print()
    print(f"  Si reporter247.org est 'ACCESSIBLE' → le cache FB est encore actif !")
    print(f"  Si 'PAS accessible' → whitelist purgée, soumission 8-10 semaines nécessaire.")
    print()


if __name__ == "__main__":
    main()
