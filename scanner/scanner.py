# scanner/scanner.py
"""
safepath scanner: ejecuta un escaneo nmap (XML), parsea puertos abiertos y POSTea
cada hallazgo al backend en /api/findings.

Este script realiza **una sola pasada** (ideal para usar con systemd timer).
"""
import os
import subprocess
import requests
import sys
import time
import xml.etree.ElementTree as ET

BACKEND_URL = os.getenv("BACKEND_URL", "http://127.0.0.1:8000")
TARGETS = os.getenv("TARGETS", "127.0.0.1").split(",")
NMAP_TIMEOUT = int(os.getenv("NMAP_TIMEOUT", "120"))
RETRY_POST = int(os.getenv("RETRY_POST", "3"))
RETRY_DELAY = float(os.getenv("RETRY_DELAY", "2"))

def run_nmap_xml(target: str) -> str:
    cmd = ["nmap", "-sV", "-oX", "-", target]
    print(f"[safepath-scanner] running: {' '.join(cmd)}")
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=NMAP_TIMEOUT)
        if r.returncode != 0:
            print(f"[safepath-scanner] nmap returned {r.returncode}, stderr:\n{r.stderr}")
        return r.stdout
    except Exception as e:
        print("[safepath-scanner] nmap error:", e)
        return ""

def parse_nmap_xml(xml_text: str, target: str) -> list:
    findings = []
    if not xml_text:
        return findings
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError as e:
        print("[safepath-scanner] XML parse error:", e)
        return findings

    for host in root.findall("host"):
        addrs = host.findall("address")
        ip = None
        if addrs:
            ip = addrs[0].get("addr")
        hostnames = host.find("hostnames")
        hostname = None
        if hostnames is not None:
            hn = hostnames.find("hostname")
            if hn is not None:
                hostname = hn.get("name")
        # ports
        ports = host.find("ports")
        if ports is None:
            continue
        for port in ports.findall("port"):
            state_el = port.find("state")
            if state_el is None or state_el.get("state") != "open":
                continue
            portid = port.get("portid")
            protocol = port.get("protocol")
            service_el = port.find("service")
            service_name = service_el.get("name") if service_el is not None else None
            service_product = service_el.get("product") if service_el is not None else None
            service_version = service_el.get("version") if service_el is not None else None
            evidence = []
            if service_product:
                evidence.append(service_product)
            if service_version:
                evidence.append(service_version)
            evidence_text = " ".join(evidence) if evidence else ""
            description = f"Puerto abierto {portid}/{protocol} - servicio: {service_name or 'unknown'}"
            if evidence_text:
                description += f" ({evidence_text})"
            findings.append({
                "host": hostname or target,
                "ip": ip or target,
                "port": str(portid),
                "protocol": protocol,
                "service": service_name,
                "severity": "medium",
                "description": description,
                "evidence": evidence_text
            })
    return findings

def post_finding(finding: dict) -> bool:
    url = BACKEND_URL.rstrip("/") + "/api/findings"
    for attempt in range(1, RETRY_POST+1):
        try:
            r = requests.post(url, json=finding, timeout=10)
            if r.status_code in (200, 201):
                print("[safepath-scanner] posted:", finding.get("host"), finding.get("port"))
                return True
            else:
                print(f"[safepath-scanner] post failed {r.status_code}: {r.text}")
        except Exception as e:
            print("[safepath-scanner] post exception:", e)
        time.sleep(RETRY_DELAY * attempt)
    return False

def main():
    total = 0
    for t in TARGETS:
        t = t.strip()
        if not t:
            continue
        xml = run_nmap_xml(t)
        findings = parse_nmap_xml(xml, t)
        for f in findings:
            posted = post_finding(f)
            total += 1
    print(f"[safepath-scanner] finished - total reported candidates: {total}")

if __name__ == "__main__":
    main()
