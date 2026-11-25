"""NetBox Custom Script „cfm-Abgleich“ (TODO 55 Baustein 3, DT2.3; Anleitung: tools/netbox/README.md).

Vergleicht die Planung einer Site in NetBox mit cfm (Soll) und den Geräten (Ist), auf Knopfdruck aus NetBox. Den Plan
liest es über das ORM (kein API-Token), Soll und Ist holt tools/netbox-abgleich.py als User cfm-netbox vom Manager
(SSH, nur Lesen: global.rsc netbox). Es ändert nichts, weder in NetBox noch in cfm. Läuft unter NetBox 3.7 bis 4.6.

Einstellungen in /etc/cfm-netbox.json (anderer Ort: Umgebungsvariable CFM_NETBOX_CONFIG):
  {"tool": "/opt/cfm/netbox-abgleich.py", "key": "/opt/cfm/cfm-netbox.key", "known_hosts": "/opt/cfm/known_hosts",
   "sites": {"<slug>": {"manager": "cfm-netbox@192.168.10.2", "port": 22, "vlan_group": null}}}
"""
import importlib.util
import json
import os
import shutil
import tempfile

try:  # nur in NetBox vorhanden; die Tests (tools/netbox/cfm_abgleich-test.py) laden die Datei ohne
    from extras.scripts import BooleanVar, ObjectVar, Script
    from dcim.models import Site
except ImportError:  # pragma: no cover
    Script = object
    Site = None

    def ObjectVar(**kw):
        return None

    def BooleanVar(**kw):
        return None

CONFIG = os.environ.get("CFM_NETBOX_CONFIG", "/etc/cfm-netbox.json")


def lade_tool(path):
    spec = importlib.util.spec_from_file_location("cfm_netbox_abgleich", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def _cf(o, k):
    v = (getattr(o, "custom_field_data", None) or {}).get(k)
    return v.strip() if isinstance(v, str) and v.strip() else None


def _ip(a):
    return str(a.address) if a is not None else None


def plan_aus_objekten(site_slug, devices, interfaces, vlans, prefixes, ips, terms):
    """NetBox-Objekte (Modelle oder Attrappen mit denselben Attributen) -> Plan wie netbox-abgleich.plan_from_netbox.
    terms = Tunnel-Terminations oder None (NetBox ohne VPN-Modul)."""
    plan = {"site": site_slug, "devices": {}, "interfaces": {}, "cables": [], "vlans": {}, "prefixes": {}, "ips": [],
            "tunnels": {}}
    for d in devices:
        if not d.name:
            continue
        role = getattr(d, "role", None) or getattr(d, "device_role", None)
        dt = d.device_type
        pip = _ip(d.primary_ip4)
        plan["devices"][d.name] = {
            "serial": d.serial or "", "model": dt.model or "", "part": dt.part_number or "",
            "nbrole": role.name if role else "", "role": _cf(d, "cfm_role"), "port_default": _cf(d, "cfm_port_default"),
            "ip": pip.split("/")[0] if pip else None, "status": d.status}
        plan["interfaces"][d.name] = {}
    seen = set()
    for i in interfaces:
        dn = i.device.name
        if dn not in plan["interfaces"]:
            continue
        plan["interfaces"][dn][i.name] = {
            "type": i.type or "", "enabled": i.enabled, "mode": i.mode or None,
            "untag": i.untagged_vlan.vid if i.untagged_vlan else None,
            "tag": sorted(v.vid for v in i.tagged_vlans.all()),
            "lag": i.lag.name if i.lag else None, "spec": _cf(i, "cfm_port")}
        if getattr(i, "cable", None):
            peers = [p for p in (i.link_peers or []) if hasattr(p, "device") and hasattr(p, "name")]
            if len(peers) == 1:
                a, b = (dn, i.name), (peers[0].device.name, peers[0].name)
                key = tuple(sorted([a, b]))
                if key not in seen:
                    seen.add(key)
                    plan["cables"].append([a[0], a[1], b[0], b[1]])
    for v in vlans:
        plan["vlans"][str(v.vid)] = v.name or ""
    for p in prefixes:
        plan["prefixes"][str(p.prefix)] = p.vlan.vid if p.vlan else None
    got = set()
    for a in ips:
        if a.pk in got:
            continue
        got.add(a.pk)
        ao = a.assigned_object
        dev = ao.device.name if ao is not None and hasattr(ao, "device") and getattr(ao, "device", None) else None
        plan["ips"].append({"addr": str(a.address), "dns": a.dns_name or "", "dev": dev,
                            "if": ao.name if dev else None, "role": a.role or None})
    if terms is None:
        plan["tunnels"] = None
    else:
        for t in terms:
            tn = t.tunnel.name
            term = t.termination
            dev = term.device.name if term is not None and getattr(term, "device", None) else None
            plan["tunnels"].setdefault(tn, [])
            if dev and dev not in plan["tunnels"][tn]:
                plan["tunnels"][tn].append(dev)
    return plan


def plan_from_orm(site, vlan_group=None):  # pragma: no cover - braucht NetBox
    from django.contrib.contenttypes.models import ContentType
    from django.core.exceptions import FieldError
    from dcim.models import Device, Interface
    from ipam.models import VLAN, IPAddress, Prefix
    devices = list(Device.objects.filter(site=site).select_related("device_type", "primary_ip4"))
    interfaces = list(Interface.objects.filter(device__site=site).select_related("device", "untagged_vlan", "lag")
                      .prefetch_related("tagged_vlans"))
    vlans = VLAN.objects.filter(group__slug=vlan_group) if vlan_group else VLAN.objects.filter(site=site)
    try:
        prefixes = list(Prefix.objects.filter(_site=site))   # ab 4.2 (scope), _site ist der Cache
    except FieldError:
        prefixes = list(Prefix.objects.filter(site=site))
    ips = []
    for p in prefixes:
        ips.extend(IPAddress.objects.filter(address__net_host_contained=str(p.prefix)))
    ct = ContentType.objects.get_for_model(Interface)
    ids = [i.pk for i in interfaces]
    ips.extend(IPAddress.objects.filter(assigned_object_type=ct, assigned_object_id__in=ids))
    try:
        from vpn.models import TunnelTermination
        terms = list(TunnelTermination.objects.filter(termination_type=ct, termination_id__in=ids).select_related("tunnel"))
    except ImportError:
        terms = None
    return plan_aus_objekten(site.slug, devices, interfaces, vlans, prefixes, ips, terms)


class CfmAbgleich(Script):
    class Meta:
        name = "cfm-Abgleich"
        description = "Planung der Site mit cfm (Soll) und den Geräten (Ist) vergleichen – ändert nichts"
        commit_default = False

    site = ObjectVar(model=Site, description="Site = cfm-Standort (Eintrag in /etc/cfm-netbox.json)")
    alle = BooleanVar(default=False, description="auch Infos zeigen (z.B. Adressen, die nur in NetBox stehen)")

    def run(self, data, commit):
        with open(CONFIG, encoding="utf-8") as f:
            cfg = json.load(f)
        site = data["site"]
        sc = (cfg.get("sites") or {}).get(site.slug)
        if not sc:
            self.log_failure("Site %s fehlt in %s (sites)" % (site.slug, CONFIG))
            return
        ab = lade_tool(cfg.get("tool", "/opt/cfm/netbox-abgleich.py"))
        plan = plan_from_orm(site, sc.get("vlan_group"))
        tmp = tempfile.mkdtemp(prefix="cfm-nb-")
        try:
            n = ab.fetch_state_lesend(sc["manager"], int(sc.get("port", 22)), tmp, cfg.get("key"), cfg.get("known_hosts"))
            soll, ist = ab.load_state(tmp)
        except Exception as e:
            self.log_failure("Soll/Ist vom Manager %s: %s" % (sc["manager"], e))
            return
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        items = ab.abgleich(plan, soll, ist, data.get("alle", False))
        for x in items:
            msg = "%s – %s: %s" % (x["bereich"], x["objekt"], x["text"])
            {"abweichung": self.log_failure, "hinweis": self.log_warning}.get(x["art"], self.log_info)(msg)
        na = sum(1 for x in items if x["art"] == "abweichung")
        if not na:
            self.log_success("Keine Abweichung (%d Geräte, cfm v%s)" % (n, ab._s(soll.get("v"))))
        return ab.bericht(items, "NetBox-Abgleich: Site %s <-> cfm v%s" % (site.slug, ab._s(soll.get("v"))))
