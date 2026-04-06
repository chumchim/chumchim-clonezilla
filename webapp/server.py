#!/usr/bin/env python3
"""ChumChim-Clonezilla Web Server"""

import json
import os
import subprocess
import threading
import time
from http.server import HTTPServer, SimpleHTTPRequestHandler

PORT = 8080
PROGRESS = {"percent": 0, "message": "", "done": False, "success": False, "result_message": ""}

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=os.path.join(os.path.dirname(__file__), "static"), **kwargs)

    def do_GET(self):
        if self.path == "/api/disks":
            self.send_json(get_disks())
        elif self.path == "/api/images":
            self.send_json(get_images())
        elif self.path == "/api/progress":
            self.send_json(PROGRESS)
        elif self.path == "/api/shutdown":
            self.send_json({"ok": True})
            threading.Thread(target=lambda: os.system("poweroff")).start()
        else:
            super().do_GET()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length)) if length > 0 else {}

        if self.path == "/api/clone":
            threading.Thread(target=do_clone, args=(body,)).start()
            self.send_json({"started": True})
        elif self.path == "/api/install":
            threading.Thread(target=do_install, args=(body,)).start()
            self.send_json({"started": True})
        else:
            self.send_json({"error": "not found"}, 404)

    def send_json(self, data, code=200):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, format, *args):
        pass  # Suppress logs


def run_cmd(cmd):
    """Run command and return output"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        return result.stdout.strip()
    except:
        return ""


def get_disks():
    """Get list of disks"""
    boot_usb = find_boot_usb()
    win_disk = find_windows_disk()

    disks = []
    output = run_cmd("lsblk -d -o NAME,SIZE,MODEL,TYPE -n")
    for line in output.split("\n"):
        parts = line.split()
        if len(parts) >= 4 and parts[-1] == "disk":
            name = parts[0]
            size = parts[1]
            model = " ".join(parts[2:-1]) if len(parts) > 3 else ""
            is_boot = f"/dev/{name}" == boot_usb
            disks.append({
                "name": name,
                "size": size,
                "model": model,
                "is_boot_usb": is_boot
            })

    return {"disks": disks, "windows_disk": win_disk, "boot_usb": boot_usb}


def get_images():
    """Scan all drives for Clonezilla images"""
    images = []
    output = run_cmd("lsblk -l -o NAME,FSTYPE -n | grep -v '^$'")
    for line in output.split("\n"):
        parts = line.split()
        if len(parts) < 1:
            continue
        dev = f"/dev/{parts[0]}"
        mount_point = f"/tmp/_scan_{parts[0]}"
        os.makedirs(mount_point, exist_ok=True)
        os.system(f"mount {dev} {mount_point} 2>/dev/null")

        if os.path.isdir(mount_point):
            for entry in os.listdir(mount_point):
                full = os.path.join(mount_point, entry)
                if os.path.isdir(full) and (
                    os.path.isfile(os.path.join(full, "disk")) or
                    os.path.isfile(os.path.join(full, "parts"))
                ):
                    size = run_cmd(f"du -sh '{full}' | cut -f1")
                    date = run_cmd(f"stat -c %y '{full}' | cut -d' ' -f1")
                    note = ""
                    note_file = os.path.join(mount_point, f".note_{entry}")
                    if os.path.isfile(note_file):
                        with open(note_file) as f:
                            note = f.read().strip()
                    images.append({
                        "name": entry,
                        "size": size,
                        "date": date,
                        "note": note,
                        "dev": dev
                    })
        os.system(f"umount {mount_point} 2>/dev/null")

    return {"images": images}


def find_boot_usb():
    """Find the USB we booted from"""
    output = run_cmd("lsblk -l -o NAME -n")
    for name in output.split("\n"):
        name = name.strip()
        if not name:
            continue
        mp = f"/tmp/_boot_{name}"
        os.makedirs(mp, exist_ok=True)
        os.system(f"mount /dev/{name} {mp} 2>/dev/null")
        if os.path.isdir(os.path.join(mp, "live")):
            os.system(f"umount {mp} 2>/dev/null")
            import re
            return "/dev/" + re.sub(r'[0-9]+$', '', re.sub(r'p[0-9]+$', '', name))
        os.system(f"umount {mp} 2>/dev/null")
    return ""


def find_windows_disk():
    """Find disk with Windows installed"""
    output = run_cmd("lsblk -l -o NAME -n")
    for name in output.split("\n"):
        name = name.strip()
        if not name:
            continue
        mp = f"/tmp/_win_{name}"
        os.makedirs(mp, exist_ok=True)
        os.system(f"mount -o ro /dev/{name} {mp} 2>/dev/null")
        if os.path.isdir(os.path.join(mp, "Windows", "System32")):
            os.system(f"umount {mp} 2>/dev/null")
            import re
            return re.sub(r'[0-9]+$', '', re.sub(r'p[0-9]+$', '', name))
        os.system(f"umount {mp} 2>/dev/null")
    return ""


def do_clone(params):
    """Run clone in background"""
    global PROGRESS
    PROGRESS = {"percent": 0, "message": "Starting clone...", "done": False, "success": False, "result_message": ""}

    src = params.get("source", "")
    save_disk = params.get("save_disk", "")
    name = params.get("name", "Image")
    note = params.get("note", "")
    speed = params.get("speed", "normal")

    compress = {
        "fast": "-z0",
        "normal": "-z1p",
        "small": "-z5p"
    }.get(speed, "-z1p")

    # Mount save disk
    save_part = run_cmd(f"lsblk -l -o NAME /dev/{save_disk} | tail -1").strip()
    os.system(f"mkdir -p /home/partimag && mount /dev/{save_part} /home/partimag 2>/dev/null")

    # Save note
    if note:
        with open(f"/home/partimag/.note_{name}", "w") as f:
            f.write(note)

    PROGRESS["message"] = f"Cloning /dev/{src}..."
    PROGRESS["percent"] = 5

    # Run ocs-sr
    cmd = f"/usr/sbin/ocs-sr -q2 -c -j2 {compress} -i 16777216 -sfsck -senc -p true savedisk \"{name}\" \"{src}\""
    process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    # Monitor progress
    while process.poll() is None:
        line = process.stdout.readline().decode(errors="ignore")
        if "%" in line:
            try:
                pct = int(line.strip().split("%")[0].split()[-1])
                PROGRESS["percent"] = min(pct, 99)
            except:
                pass
        PROGRESS["message"] = f"Cloning /dev/{src} → {name}"
        time.sleep(1)

    success = process.returncode == 0
    size = run_cmd(f"du -sh /home/partimag/{name} | cut -f1") if success else ""

    os.system("umount /home/partimag 2>/dev/null")

    PROGRESS["percent"] = 100
    PROGRESS["done"] = True
    PROGRESS["success"] = success
    PROGRESS["result_message"] = f"Image: {name} ({size})" if success else "Clone failed!"


def do_install(params):
    """Run install in background"""
    global PROGRESS
    PROGRESS = {"percent": 0, "message": "Starting install...", "done": False, "success": False, "result_message": ""}

    image_name = params.get("image", "")
    image_dev = params.get("image_dev", "")
    target = params.get("target", "")

    os.system(f"mkdir -p /home/partimag && mount {image_dev} /home/partimag 2>/dev/null")

    PROGRESS["message"] = f"Installing {image_name}..."
    PROGRESS["percent"] = 5

    cmd = f'/usr/sbin/ocs-sr -g auto -e1 auto -e2 -r -j2 -c -p true restoredisk "{image_name}" "{target}"'
    process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    while process.poll() is None:
        line = process.stdout.readline().decode(errors="ignore")
        if "%" in line:
            try:
                pct = int(line.strip().split("%")[0].split()[-1])
                PROGRESS["percent"] = min(pct, 99)
            except:
                pass
        PROGRESS["message"] = f"Installing {image_name} → /dev/{target}"
        time.sleep(1)

    success = process.returncode == 0
    os.system("umount /home/partimag 2>/dev/null")

    PROGRESS["percent"] = 100
    PROGRESS["done"] = True
    PROGRESS["success"] = success
    PROGRESS["result_message"] = "Remove USB and restart." if success else "Install failed!"


if __name__ == "__main__":
    print(f"ChumChim-Clonezilla Web UI: http://localhost:{PORT}")
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
