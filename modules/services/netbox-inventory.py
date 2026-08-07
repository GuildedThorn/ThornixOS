"""Seed Atlas with the verified ThornCloud inventory.

Run through Django, not with the system Python:

    thornix-netbox-seed

The seed is deliberately conservative. It creates missing records and fills
empty fields, but it never deletes records or overwrites a populated field.
That makes it safe to rerun after adding richer data in the NetBox UI.
"""

from django.contrib.contenttypes.models import ContentType
from django.db import transaction

from dcim.models import (
    Device,
    DeviceRole,
    DeviceType,
    Interface,
    MACAddress,
    Manufacturer,
    Platform,
    Site,
)
from ipam.models import IPAddress, Prefix, Service
from virtualization.models import Cluster, ClusterType, VirtualMachine, VMInterface


STATS = {"created": 0, "existing": 0, "filled": 0}


def ensure(model, lookup, defaults=None):
    """Get or create an object, filling only fields that are still empty."""
    defaults = defaults or {}
    obj, created = model.objects.get_or_create(**lookup, defaults=defaults)
    STATS["created" if created else "existing"] += 1

    changed = False
    if not created:
        for field, value in defaults.items():
            if getattr(obj, field, None) in (None, "") and value not in (None, ""):
                setattr(obj, field, value)
                changed = True

    # get_or_create() saves before model validation. Validate every object so
    # any bad fact rolls the enclosing transaction back instead of leaving a
    # partially seeded inventory.
    obj.full_clean()
    if changed:
        obj.save()
        STATS["filled"] += 1
    return obj


def ensure_interface(device, name, interface_type, **defaults):
    return ensure(
        Interface,
        {"device": device, "name": name},
        {"type": interface_type, **defaults},
    )


def ensure_vm_interface(vm, name="eth0", **defaults):
    return ensure(
        VMInterface,
        {"virtual_machine": vm, "name": name},
        defaults,
    )


def ensure_mac(interface, address):
    mac = MACAddress.objects.filter(mac_address=address).first()
    if mac is None:
        mac = MACAddress(mac_address=address, assigned_object=interface)
        mac.full_clean()
        mac.save()
        STATS["created"] += 1
    else:
        STATS["existing"] += 1
        if mac.assigned_object is None:
            mac.assigned_object = interface
            mac.full_clean()
            mac.save()
            STATS["filled"] += 1
        elif mac.assigned_object != interface:
            raise RuntimeError(
                f"MAC {address} is already assigned to {mac.assigned_object}, "
                f"not {interface}"
            )

    if interface.primary_mac_address is None:
        interface.primary_mac_address = mac
        interface.full_clean()
        interface.save()
        STATS["filled"] += 1
    elif interface.primary_mac_address != mac:
        raise RuntimeError(
            f"{interface} already has primary MAC {interface.primary_mac_address}, "
            f"not {address}"
        )
    return mac


def ensure_ip(interface, address, dns_name="", description=""):
    host = address.split("/", 1)[0]
    ip = IPAddress.objects.filter(vrf=None, address__net_host=host).first()
    if ip is None:
        ip = IPAddress(
            address=address,
            status="active",
            dns_name=dns_name,
            description=description,
            assigned_object=interface,
        )
        ip.full_clean()
        ip.save()
        STATS["created"] += 1
    else:
        STATS["existing"] += 1
        changed = False
        if ip.assigned_object is None:
            ip.assigned_object = interface
            changed = True
        elif ip.assigned_object != interface:
            raise RuntimeError(
                f"IP {host} is already assigned to {ip.assigned_object}, not {interface}"
            )
        if not ip.dns_name and dns_name:
            ip.dns_name = dns_name
            changed = True
        if not ip.description and description:
            ip.description = description
            changed = True
        if changed:
            ip.full_clean()
            ip.save()
            STATS["filled"] += 1
    return ip


def set_primary_ip(parent, ip):
    if parent.primary_ip4 is None:
        parent.primary_ip4 = ip
        parent.full_clean()
        parent.save()
        STATS["filled"] += 1
    elif parent.primary_ip4 != ip:
        raise RuntimeError(
            f"{parent} already has primary IP {parent.primary_ip4}, not {ip}"
        )


def ensure_service(parent, name, protocol, ports, description=""):
    content_type = ContentType.objects.get_for_model(parent)
    ports = sorted(set(ports))
    return ensure(
        Service,
        {
            "parent_object_type": content_type,
            "parent_object_id": parent.pk,
            "name": name,
            "protocol": protocol,
        },
        {"ports": ports, "description": description},
    )


@transaction.atomic
def seed():
    site = ensure(
        Site,
        {"name": "ThornCloud"},
        {
            "slug": "thorncloud",
            "status": "active",
            "time_zone": "America/Chicago",
            "description": "GuildedThorn home infrastructure",
        },
    )

    manufacturers = {
        name: ensure(Manufacturer, {"name": name}, {"slug": slug})
        for name, slug in (
            ("Apple", "apple"),
            ("Cisco", "cisco"),
            ("Netgear", "netgear"),
            ("Netgate", "netgate"),
            ("Unspecified", "unspecified"),
        )
    }

    platforms = {
        name: ensure(Platform, {"name": name}, {"slug": slug})
        for name, slug in (
            ("NixOS", "nixos"),
            ("pfSense Plus", "pfsense-plus"),
            ("TrueNAS SCALE", "truenas-scale"),
        )
    }

    role_specs = {
        "firewall": ("Firewall", "f44336", False),
        "hypervisor": ("Hypervisor", "9c27b0", False),
        "switch": ("Network Switch", "3f51b5", False),
        "storage": ("Storage Server", "00bcd4", False),
        "workstation": ("Workstation", "607d8b", False),
        "lab": ("Lab Host", "9e9e9e", False),
        "web": ("Web Application", "2196f3", True),
        "soc": ("Security Operations", "e91e63", True),
        "identity": ("Identity Provider", "673ab7", True),
        "provisioning": ("Network Boot", "ff9800", True),
        "inventory": ("Infrastructure Inventory", "4caf50", True),
        "pki": ("Certificate Authority", "795548", True),
        "vulnerability": ("Vulnerability Management", "c62828", True),
    }
    roles = {
        key: ensure(
            DeviceRole,
            {"name": name},
            {
                "slug": key,
                "color": color,
                "vm_role": vm_role,
            },
        )
        for key, (name, color, vm_role) in role_specs.items()
    }

    device_types = {
        "pfsense": ensure(
            DeviceType,
            {"manufacturer": manufacturers["Netgate"], "model": "XG-2758"},
            {"slug": "xg-2758", "u_height": 1, "description": "Netgate security appliance"},
        ),
        "mac": ensure(
            DeviceType,
            {"manufacturer": manufacturers["Apple"], "model": "Mac Pro 5,1"},
            {
                "slug": "mac-pro-5-1",
                "u_height": 0,
                "is_full_depth": False,
                "description": "Tower workstation used as the Proxmox hypervisor",
            },
        ),
        "lan-switch": ensure(
            DeviceType,
            {"manufacturer": manufacturers["Netgear"], "model": "GS308E"},
            {
                "slug": "gs308e",
                "u_height": 0,
                "is_full_depth": False,
                "description": "Eight-port gigabit smart switch",
            },
        ),
        "opt1-switch": ensure(
            DeviceType,
            {"manufacturer": manufacturers["Cisco"], "model": "Catalyst 3560G"},
            {
                "slug": "catalyst-3560g",
                "u_height": 1,
                "description": "OPT1 services-network switch; exact port count is undocumented",
            },
        ),
        "generic": ensure(
            DeviceType,
            {
                "manufacturer": manufacturers["Unspecified"],
                "model": "Physical host (model unknown)",
            },
            {
                "slug": "physical-host-model-unknown",
                "u_height": 0,
                "is_full_depth": False,
                "description": "Placeholder type until the physical model is inventoried",
            },
        ),
    }

    pfsense = ensure(
        Device,
        {"site": site, "name": "pfsense"},
        {
            "device_type": device_types["pfsense"],
            "role": roles["firewall"],
            "platform": platforms["pfSense Plus"],
            "status": "active",
            "serial": "0908161085",
            "description": "ThornCloud edge router, firewall, and VPN concentrator",
            "comments": "Netgate Device ID: ea008528ef5a76897829. No VLANs are configured.",
        },
    )
    pfsense_wan = ensure_interface(
        pfsense,
        "WAN",
        "10gbase-sr",
        description="Known address 64.53.182.82; prefix length is not documented",
    )
    pfsense_lan = ensure_interface(
        pfsense,
        "igb0 / LAN",
        "1000base-t",
        description="192.168.1.0/24 via the Netgear GS308E",
    )
    pfsense_opt1 = ensure_interface(
        pfsense,
        "igb1 / OPT1",
        "1000base-t",
        description="172.16.25.0/24 via the Cisco Catalyst 3560G",
    )
    pfsense_openvpn = ensure_interface(
        pfsense,
        "OPT3 / ThornVPN",
        "virtual",
        description="OpenVPN road-warrior network",
    )
    pfsense_wireguard = ensure_interface(
        pfsense,
        "WireGuard",
        "virtual",
        description="WireGuard road-warrior network",
    )
    ensure_mac(pfsense_opt1, "00:08:a2:0b:12:76")
    set_primary_ip(
        pfsense,
        ensure_ip(
            pfsense_lan,
            "192.168.1.1/24",
            "pfsense.guildedthorn.arpa",
            "LAN gateway",
        ),
    )
    ensure_ip(
        pfsense_lan,
        "192.168.1.74/24",
        description="Documented pfSense web UI and SSH management address",
    )
    ensure_ip(pfsense_opt1, "172.16.25.1/24", description="OPT1 gateway")
    ensure_ip(pfsense_openvpn, "10.0.8.1/24", description="OpenVPN gateway")
    ensure_ip(pfsense_wireguard, "10.10.10.1/24", description="WireGuard gateway")

    lan_switch = ensure(
        Device,
        {"site": site, "name": "lan-switch"},
        {
            "device_type": device_types["lan-switch"],
            "role": roles["switch"],
            "status": "active",
            "description": "Flat LAN distribution switch on pfSense igb0",
            "comments": "Physical switch port assignments and management address are not yet documented.",
        },
    )
    opt1_switch = ensure(
        Device,
        {"site": site, "name": "opt1-switch"},
        {
            "device_type": device_types["opt1-switch"],
            "role": roles["switch"],
            "status": "active",
            "description": "Flat OPT1 services-network switch on pfSense igb1",
            "comments": "Physical switch port assignments and management address are not yet documented.",
        },
    )

    mac = ensure(
        Device,
        {"site": site, "name": "mac"},
        {
            "device_type": device_types["mac"],
            "role": roles["hypervisor"],
            "platform": platforms["NixOS"],
            "status": "active",
            "description": "NixOS Proxmox VE hypervisor",
            "comments": "2x Intel Xeon X5690; 128 GiB ECC RAM; 1 TB Samsung 870 Evo.",
        },
    )
    mac_uplink = ensure_interface(
        mac,
        "enp9s0",
        "1000base-t",
        description="OPT1 uplink and vmbr0 bridge member",
    )
    ensure_mac(mac_uplink, "00:25:00:f4:7e:8c")
    ensure_interface(
        mac,
        "enp10s0",
        "1000base-t",
        enabled=False,
        description="Currently unused physical interface",
    )
    mac_bridge = ensure_interface(
        mac,
        "vmbr0",
        "bridge",
        description="Proxmox management and production-VM bridge",
    )
    set_primary_ip(
        mac,
        ensure_ip(
            mac_bridge,
            "172.16.25.3/24",
            "proxmox.guildedthorn.arpa",
            "Proxmox management",
        ),
    )
    ensure_interface(mac, "vmbr1", "bridge", enabled=False, description="Empty bridge")
    ensure_interface(mac, "vmbr2", "bridge", enabled=False, description="Empty bridge")

    truenas = ensure(
        Device,
        {"site": site, "name": "truenas"},
        {
            "device_type": device_types["generic"],
            "role": roles["storage"],
            "platform": platforms["TrueNAS SCALE"],
            "status": "active",
            "description": "TrueNAS SCALE storage and application host",
            "comments": "Hardware model is not yet documented. Data pool: platter (7.25 TiB).",
        },
    )
    truenas_if = ensure_interface(
        truenas,
        "management",
        "other",
        description="OPT1 interface; physical NIC model and switch port are undocumented",
    )
    ensure_mac(truenas_if, "70:85:c2:55:65:23")
    set_primary_ip(
        truenas,
        ensure_ip(
            truenas_if,
            "172.16.25.4/24",
            "truenas.guildedthorn.arpa",
            "TrueNAS management",
        ),
    )

    nixos = ensure(
        Device,
        {"site": site, "name": "nixos"},
        {
            "device_type": device_types["generic"],
            "role": roles["workstation"],
            "platform": platforms["NixOS"],
            "status": "active",
            "description": "Primary NixOS workstation on LAN",
            "comments": "Physical hardware model and interface identity are not yet inventoried.",
        },
    )
    nixos_if = ensure_interface(nixos, "primary", "other", description="LAN interface")
    set_primary_ip(
        nixos,
        ensure_ip(nixos_if, "192.168.1.6/24", description="Primary workstation address"),
    )

    scout = ensure(
        Device,
        {"site": site, "name": "scout"},
        {
            "device_type": device_types["generic"],
            "role": roles["workstation"],
            "platform": platforms["NixOS"],
            "status": "active",
            "description": "Roaming NixOS laptop",
            "comments": "Physical hardware model is not yet inventoried; home telemetry uses WireGuard.",
        },
    )
    scout_wg = ensure_interface(
        scout,
        "WireGuard",
        "virtual",
        description="ThornCloud road-warrior tunnel",
    )
    set_primary_ip(
        scout,
        ensure_ip(scout_wg, "10.10.10.3/32", description="Scout WireGuard address"),
    )

    mitm = ensure(
        Device,
        {"site": site, "name": "mitm"},
        {
            "device_type": device_types["generic"],
            "role": roles["lab"],
            "platform": platforms["NixOS"],
            "status": "offline",
            "description": "Former inline-proxy / lab host",
            "comments": "No ICMP or ARP response observed from OPT1 on 2026-08-06; current role remains to be confirmed.",
        },
    )
    mitm_if = ensure_interface(mitm, "primary", "other", description="Former OPT1 address")
    set_primary_ip(
        mitm,
        ensure_ip(
            mitm_if,
            "172.16.25.2/24",
            "mitm.guildedthorn.arpa",
            "Offline/reserved; current role to be confirmed",
        ),
    )

    for prefix, description in (
        ("192.168.1.0/24", "Main LAN on pfSense igb0; flat and untagged"),
        ("172.16.25.0/24", "OPT1 services network on pfSense igb1; flat and untagged"),
        ("10.0.8.0/24", "ThornVPN OpenVPN road-warrior network"),
        ("10.10.10.0/24", "WireGuard road-warrior network"),
    ):
        ensure(
            Prefix,
            {"prefix": prefix, "vrf": None},
            {"scope": site, "status": "active", "description": description},
        )

    cluster_type = ensure(
        ClusterType,
        {"name": "Proxmox VE"},
        {"slug": "proxmox-ve", "description": "Proxmox Virtual Environment"},
    )
    cluster = ensure(
        Cluster,
        {"name": "mac-proxmox"},
        {
            "type": cluster_type,
            "scope": site,
            "status": "active",
            "description": "Single-node Proxmox cluster on mac",
        },
    )
    if mac.cluster is None:
        mac.cluster = cluster
        mac.full_clean()
        mac.save()
        STATS["filled"] += 1
    elif mac.cluster != cluster:
        raise RuntimeError(f"mac is already assigned to cluster {mac.cluster}, not {cluster}")

    vm_specs = {
        "websites": {
            "role": roles["web"],
            "vcpus": 12,
            "memory": 8192,
            "disk": 102400,
            "start_on_boot": "on",
            "ip": "172.16.25.50/24",
            "mac": "bc:24:11:85:b7:09",
            "vmid": 102,
            "description": "GuildedThorn public web application and network sensor",
        },
        "soc": {
            "role": roles["soc"],
            "vcpus": 4,
            "memory": 8096,
            "disk": 61440,
            "start_on_boot": "off",
            "ip": "172.16.25.51/24",
            "mac": "bc:24:11:1f:9e:c2",
            "vmid": 103,
            "description": "SIEM, telemetry, and security operations",
        },
        "identity": {
            "role": roles["identity"],
            "vcpus": 2,
            "memory": 4096,
            "disk": 40960,
            "start_on_boot": "on",
            "ip": "172.16.25.52/24",
            "mac": "bc:24:11:82:96:d7",
            "vmid": 104,
            "description": "Authentik identity provider",
        },
        "pixie": {
            "role": roles["provisioning"],
            "vcpus": 2,
            "memory": 2048,
            "disk": 29696,
            "start_on_boot": "on",
            "ip": "172.16.25.53/24",
            "mac": "bc:24:11:1b:88:ea",
            "vmid": 105,
            "description": "iPXE and rescue-boot infrastructure",
        },
        "atlas": {
            "role": roles["inventory"],
            "vcpus": 2,
            "memory": 4096,
            "disk": 40960,
            "start_on_boot": "on",
            "ip": "172.16.25.54/24",
            "mac": "bc:24:11:4d:eb:e6",
            "vmid": 106,
            "description": "NetBox infrastructure source of truth",
        },
        "anvil": {
            "role": roles["pki"],
            "vcpus": 2,
            "memory": 2048,
            "disk": 20480,
            "start_on_boot": "on",
            "ip": "172.16.25.55/24",
            "vmid": 107,
            "description": "ThornCloud online issuing CA and internal ACME service",
            "comments": (
                "Proxmox VMID 107; declared by ThornixOS on 2026-08-06. "
                "The VM MAC must be inventoried after guarded provisioning."
            ),
        },
        "sieve": {
            "role": roles["vulnerability"],
            "vcpus": 4,
            "memory": 8192,
            "disk": 61440,
            "start_on_boot": "on",
            "ip": "172.16.25.56/24",
            "vmid": 108,
            "description": "Greenbone vulnerability management and active assessment",
            "comments": (
                "Proxmox VMID 108; declared by ThornixOS on 2026-08-06. "
                "The VM MAC must be inventoried after guarded provisioning."
            ),
        },
    }

    vms = {}
    vm_ips = {}
    for name, spec in vm_specs.items():
        vm = ensure(
            VirtualMachine,
            {"cluster": cluster, "name": name},
            {
                "site": site,
                "device": mac,
                "role": spec["role"],
                "platform": platforms["NixOS"],
                "status": "active",
                "start_on_boot": spec["start_on_boot"],
                "vcpus": spec["vcpus"],
                "memory": spec["memory"],
                "disk": spec["disk"],
                "description": spec["description"],
                "comments": spec.get(
                    "comments",
                    f"Proxmox VMID {spec['vmid']}; resources verified live on 2026-08-06.",
                ),
            },
        )
        interface = ensure_vm_interface(
            vm,
            description="VirtIO NIC on Proxmox vmbr0 / OPT1",
        )
        if spec.get("mac"):
            ensure_mac(interface, spec["mac"])
        ip = ensure_ip(
            interface,
            spec["ip"],
            f"{name}.guildedthorn.arpa",
            f"{name} primary address",
        )
        set_primary_ip(vm, ip)
        vms[name] = vm
        vm_ips[name] = ip

    services = (
        (pfsense, "pfSense HTTPS", "tcp", [443], "Web administration"),
        (pfsense, "SSH", "tcp", [22], "Key-only administration"),
        (pfsense, "Node exporter", "tcp", [9100], "SOC metrics scrape"),
        (pfsense, "OpenVPN", "udp", [1194], "ThornVPN"),
        (pfsense, "WireGuard", "udp", [4501], "Road-warrior endpoint"),
        (mac, "Proxmox HTTPS", "tcp", [8006], "Proxmox VE web administration"),
        (mac, "SSH", "tcp", [22], "Key-only administration"),
        (mac, "Node exporter", "tcp", [9100], "SOC metrics scrape"),
        (mac, "Comin exporter", "tcp", [4243], "Deployment metrics"),
        (truenas, "TrueNAS HTTPS", "tcp", [443], "Storage administration"),
        (truenas, "SeaweedFS S3", "tcp", [30304], "S3-compatible object storage"),
        (truenas, "Jellyfin HTTPS", "tcp", [8920], "Media streaming"),
        (vms["websites"], "SSH", "tcp", [22], "Key-only administration"),
        (vms["websites"], "GuildedThorn app", "tcp", [8080], "Loopback application backend"),
        (vms["websites"], "Owncast HTTP", "tcp", [8090], "Loopback Owncast UI"),
        (vms["websites"], "Owncast RTMP", "tcp", [1935], "Internal RTMP ingest"),
        (vms["soc"], "SSH", "tcp", [22], "Key-only administration"),
        (vms["soc"], "Grafana HTTPS", "tcp", [3000], "SOC dashboards"),
        (vms["soc"], "Loki mTLS", "tcp", [3100], "Fleet log ingestion and queries"),
        (vms["soc"], "Prometheus mTLS", "tcp", [9090], "Metrics queries and remote write"),
        (vms["soc"], "pfSense syslog", "udp", [5514], "pfSense remote syslog ingest"),
        (vms["identity"], "SSH", "tcp", [22], "Key-only administration"),
        (vms["identity"], "Authentik HTTPS", "tcp", [443], "Identity provider"),
        (vms["identity"], "Authentik metrics", "tcp", [9300], "SOC-only metrics scrape"),
        (vms["pixie"], "SSH", "tcp", [22], "Key-only administration"),
        (vms["pixie"], "iPXE HTTP", "tcp", [80], "Network-boot assets and menu"),
        (vms["pixie"], "TFTP", "udp", [69], "iPXE bootstrap"),
        (vms["atlas"], "SSH", "tcp", [22], "Key-only administration"),
        (vms["atlas"], "NetBox HTTPS", "tcp", [443], "Infrastructure source of truth"),
        (vms["atlas"], "Node exporter", "tcp", [9100], "SOC metrics scrape"),
        (vms["atlas"], "Comin exporter", "tcp", [4243], "Deployment metrics"),
        (vms["anvil"], "SSH", "tcp", [22], "Key-only administration"),
        (vms["anvil"], "step-ca HTTPS", "tcp", [443], "Internal ACME and CA API"),
        (vms["anvil"], "Node exporter", "tcp", [9100], "SOC metrics scrape"),
        (vms["anvil"], "Comin exporter", "tcp", [4243], "Deployment metrics"),
        (vms["sieve"], "SSH", "tcp", [22], "Key-only administration"),
        (vms["sieve"], "Greenbone HTTPS", "tcp", [443], "Vulnerability-management web UI"),
        (vms["sieve"], "Node exporter", "tcp", [9100], "SOC metrics scrape"),
        (vms["sieve"], "Comin exporter", "tcp", [4243], "Deployment metrics"),
    )
    for parent, name, protocol, ports, description in services:
        service = ensure_service(parent, name, protocol, ports, description)
        # Bind network-facing services to the parent's primary address. The
        # two loopback-only web backends stay unbound; their descriptions are
        # explicit so NetBox does not claim they listen on OPT1.
        primary_ip = getattr(parent, "primary_ip4", None)
        loopback_only = parent == vms["websites"] and name in {
            "GuildedThorn app",
            "Owncast HTTP",
        }
        if (
            primary_ip is not None
            and not loopback_only
            and not service.ipaddresses.filter(pk=primary_ip.pk).exists()
        ):
            service.ipaddresses.add(primary_ip)
            STATS["filled"] += 1

    print(
        "ThornCloud inventory seed complete: "
        f"{STATS['created']} created, {STATS['existing']} already present, "
        f"{STATS['filled']} empty fields/relations filled."
    )
    print(
        "No records were deleted. Unknown switch ports and the undocumented "
        "WAN prefix were intentionally left unset."
    )


# Django's `manage.py shell` executes stdin in its own module namespace, so
# __name__ is not guaranteed to be "__main__". This file is installed only as
# input to thornix-netbox-seed; execute explicitly when it is read.
seed()
