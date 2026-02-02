from __future__ import annotations

import os
from flask import Flask, request, jsonify
from vm_manager import VmManager, VmConfig

app = Flask(__name__)

WORK_DIR = os.environ.get("VMS_WORK_DIR", "/srv/vms")
CONN_URI = os.environ.get("LIBVIRT_URI", "qemu:///system")
DEFAULT_NET = os.environ.get("VMS_NETWORK", "default")
DEFAULT_ARCH = os.environ.get("VMS_ARCH", "x86_64")

def get_mgr() -> VmManager:
    mgr = VmManager(conn_uri=CONN_URI, work_dir=WORK_DIR)
    mgr.connect()
    return mgr

def err(msg: str, code: int = 400):
    return jsonify({"ok": False, "error": msg}), code

@app.get("/health")
def health():
    return jsonify({"ok": True})

@app.post("/vms")
def create_vm():
    data = request.get_json(force=True, silent=True) or {}
    name = data.get("name")
    if not name:
        return err("Missing field: name", 400)

    cfg = VmConfig(
        name=name,
        memory_mib=int(data.get("memory_mib", 1024)),
        vcpus=int(data.get("vcpus", 1)),
        disk_size_gb=int(data.get("disk_size_gb", 10)),
        network_name=str(data.get("network_name", DEFAULT_NET)),
        os_arch=str(data.get("os_arch", DEFAULT_ARCH)),
    )
    recreate = bool(data.get("recreate", False))

    try:
        mgr = get_mgr()
        dom = mgr.create_and_start(cfg, recreate=recreate)
        return jsonify({"ok": True, "name": dom.name()})
    except Exception as e:
        return err(str(e), 500)

@app.delete("/vms/<name>")
def delete_vm(name: str):
    delete_files = request.args.get("delete_files", "true").lower() in ("1", "true", "yes")
    try:
        mgr = get_mgr()
        cfg = VmConfig(name=name, network_name=DEFAULT_NET, os_arch=DEFAULT_ARCH)
        mgr.delete_vm(cfg, delete_files=delete_files)
        return jsonify({"ok": True, "name": name, "deleted_files": delete_files})
    except Exception as e:
        return err(str(e), 500)

@app.post("/vms/<name>/start")
def start_vm(name: str):
    try:
        mgr = get_mgr()
        mgr.start_vm(name)
        return jsonify({"ok": True, "name": name})
    except KeyError:
        return err("VM not found", 404)
    except Exception as e:
        return err(str(e), 500)

@app.post("/vms/<name>/stop")
def stop_vm(name: str):
    try:
        mgr = get_mgr()
        mgr.stop_vm(name)
        return jsonify({"ok": True, "name": name})
    except KeyError:
        return err("VM not found", 404)
    except Exception as e:
        return err(str(e), 500)

@app.get("/vms/<name>/status")
def status_vm(name: str):
    try:
        mgr = get_mgr()
        st = mgr.status_vm(name)
        return jsonify({"ok": True, "status": st})
    except KeyError:
        return err("VM not found", 404)
    except Exception as e:
        return err(str(e), 500)

@app.get("/vms/<name>/ip")
def get_ip(name: str):
    timeout = int(request.args.get("timeout", "120"))
    network_name = request.args.get("network", DEFAULT_NET)

    try:
        mgr = get_mgr()
        cfg = VmConfig(name=name, network_name=network_name, os_arch=DEFAULT_ARCH)
        ip = mgr.wait_for_ip(cfg, timeout_s=timeout)
        return jsonify({"ok": True, "name": name, "ip": ip})
    except TimeoutError as e:
        return err(str(e), 504)
    except Exception as e:
        return err(str(e), 500)
