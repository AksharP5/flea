.import "../../ui/js/Devices.js" as Devices
.import "../../ui/js/Mounts.js" as Mounts
.import "../../ui/js/Eject.js" as Eject
.import "../../ui/js/Cloud.js" as Cloud

// RailAdditions rules 1 and 2: the volumes nothing has mounted, behind their own switch, and the
// menu those rows carry. Split out of tests/js/devices.js, which keeps the 0.2.1 rail's own parse.

// One internal disk carrying /, a second drive with five volumes, one of each exception the rule
// names. fstype and parttypename are what it reads, and tests/js/devices.js's live listing predates
// both columns, which is the other half of why this fixture is its own.
var unmountedBox = '{"blockdevices":['
                 + '{"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"size":256060514304,"type":"disk","model":"KBG40ZNS256G","fstype":null,"parttypename":null,'
                 + '"children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"size":256060514304,"type":"part","model":null,"fstype":"btrfs","parttypename":"Linux filesystem"}]},'
                 + '{"name":"sdb","path":"/dev/sdb","label":null,"mountpoints":[null],"rm":false,"size":2000398934016,"type":"disk","model":"Samsung SSD 870","fstype":null,"parttypename":null,'
                 + '"children":[{"name":"sdb1","path":"/dev/sdb1","label":"Archive","mountpoints":[null],"rm":false,"size":1000398934016,"type":"part","model":null,"fstype":"ext4","parttypename":"Linux filesystem"},'
                 + '{"name":"sdb2","path":"/dev/sdb2","label":null,"mountpoints":[null],"rm":false,"size":536870912,"type":"part","model":null,"fstype":"vfat","parttypename":"EFI System"},'
                 + '{"name":"sdb3","path":"/dev/sdb3","label":null,"mountpoints":["[SWAP]"],"rm":false,"size":8589934592,"type":"part","model":null,"fstype":"swap","parttypename":"Linux swap"},'
                 + '{"name":"sdb4","path":"/dev/sdb4","label":null,"mountpoints":[null],"rm":false,"size":268435456,"type":"part","model":null,"fstype":null,"parttypename":"Linux filesystem"},'
                 + '{"name":"sdb5","path":"/dev/sdb5","label":null,"mountpoints":[null],"rm":false,"size":268435456,"type":"part","model":null,"fstype":"crypto_LUKS","parttypename":"Linux filesystem"}]}'
                 + ']}'

function labels(rows) {
    return rows.map(function (e) { return e.label }).join(",")
}

function run(check) {
    var off = Devices.parseDevices(unmountedBox, false)
    check("with the switch off the rail is the one 0.2.1 drew", labels(off), "nvme0n1")
    var on = Devices.parseDevices(unmountedBox, true)
    check("the volume nothing mounted joins the rail, and only it", labels(on), "nvme0n1,Archive")
    check("the unmounted volume reads as unmounted", on[1].mounted, false)
    check("it has no mountpoint to open, so it has no path", on[1].path, "")
    check("it keeps the RailDetails column's own size", on[1].size, 1000398934016)
    check("it is not removable, so nothing offers to eject a fixed disk", on[1].removable, false)
    check("and it carries its device node, which is what gio mounts", on[1].device, "/dev/sdb1")
    check("only a row built under the switch carries the board's own menu", on[1].volumeMenu, true)
    // A stick is a row either way, so it is the one that says what the switch does to an existing row.
    var stickBox = '{"blockdevices":[{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":true,"size":124656812032,"type":"disk","model":"USB Flash Disk","fstype":null,"parttypename":null,'
              + '"children":[{"name":"sda1","path":"/dev/sda1","label":"128GB","mountpoints":["/run/media/gm/128GB"],"rm":true,"size":124656812032,"type":"part","model":null,"fstype":"vfat","parttypename":"W95 FAT32"}]}]}'
    check("and a row built without it carries the menu it carried in 0.2.1",
          Devices.parseDevices(stickBox, false)[0].volumeMenu, false)

    // Rule 1's three exceptions, each named by lsblk rather than guessed from a name.
    check("swap is not a place to browse", labels(on).indexOf("sdb3"), -1)
    check("the EFI system partition is the box's own plumbing", labels(on).indexOf("sdb2"), -1)
    check("a volume with no filesystem has nothing to mount", labels(on).indexOf("sdb4"), -1)
    check("a locked LUKS container mounts through its crypt child, never itself", labels(on).indexOf("sdb5"), -1)

    // Rule 2's rows, which only a row from rule 1 carries.
    function solid(rows) { return rows.filter(function (r) { return r.separator !== true }) }
    var unmounted = { group: "device", kind: "volume", mounted: false, removable: false, volumeMenu: true }
    check("an unmounted volume offers the mount its own activation does",
          solid(Mounts.railMenu(unmounted)).map(function (r) { return r.label + ":" + r.action }).join(","), "Mount:mountVolume")
    var mounted = { group: "device", kind: "volume", mounted: true, removable: false, volumeMenu: true }
    check("a mounted one offers the open beside the release",
          solid(Mounts.railMenu(mounted)).map(function (r) { return r.label + ":" + r.action }).join(","),
          "Open:open,Unmount:unmountVolume")
    var stick = { group: "device", kind: "volume", mounted: true, removable: true, volumeMenu: true }
    check("and Eject stays where it stands today, on a volume somebody can pull out",
          solid(Mounts.railMenu(stick)).map(function (r) { return r.label }).join(","), "Open,Unmount,Eject")
    check("with the switch off a mounted stick opens beside its eject",
          solid(Mounts.railMenu({ group: "device", kind: "volume", mounted: true, removable: true })).map(function (r) { return r.label }).join(","),
          "Open,Eject")
    check("and an unmounted one opens no menu at all",
          Mounts.railMenu({ group: "device", kind: "volume", mounted: false, removable: true }).length, 0)

    // CloudMounts: a FUSE mount inside the home folder shows in NETWORK under its
    // folder's name. Sample input, /proc/self/mountinfo lines (id parent maj:min root
    // mountpoint options, then fstype source superoptions):
    // 23 1 8:1 / /home/u/gdrive rw,nosuid,nodev - fuse.rclone remote: rw,user_id=1000,group_id=1000
    // 24 1 8:1 / /home/u/My\040Drive rw,nosuid,nodev - fuse.rclone remote: rw,user_id=1000,group_id=1000
    // 31 1 0:27 / /home/u/ProtonDrive rw,nosuid,nodev - fuse.protondrive proton: rw,user_id=1000
    // 18 1 8:1 / /home/u rw,nosuid,nodev - btrfs /dev/sda1 rw
    // 40 1 0:40 / /run/user/1000/gvfs rw,nosuid,nodev - fuse.gvfsd-fuse gvfsd-fuse rw,user_id=1000
    var mountsBody = "23 1 8:1 / /home/u/gdrive rw,nosuid,nodev - fuse.rclone remote: rw,user_id=1000,group_id=1000\n"
        + "24 1 8:1 / /home/u/My\\040Drive rw,nosuid,nodev - fuse.rclone remote: rw,user_id=1000,group_id=1000\n"
        + "31 1 0:27 / /home/u/ProtonDrive rw,nosuid,nodev - fuse.protondrive proton: rw,user_id=1000\n"
        + "18 1 8:1 / /home/u rw,nosuid,nodev - btrfs /dev/sda1 rw\n"
        + "40 1 0:40 / /run/user/1000/gvfs rw,nosuid,nodev - fuse.gvfsd-fuse gvfsd-fuse rw,user_id=1000\n"
    var clouds = Cloud.parseCloudMounts(mountsBody, "/home/u")
    check("three FUSE mounts inside home parse to three rows", clouds.length, 3)
    check("the first row names the folder's own path", clouds[0].path, "/home/u/gdrive")
    check("an octal escape decodes to the folder's real name", clouds[1].path, "/home/u/My Drive")
    check("the home directory itself is not a cloud mount",
          clouds.some(function (c) { return c.path === "/home/u" }), false)
    check("the gvfs FUSE mount is not inside home and stays out",
          clouds.some(function (c) { return c.path.indexOf("/run/") === 0 }), false)
    check("an empty body parses to nothing", Cloud.parseCloudMounts("", "/home/u").length, 0)
    check("garbage parses to nothing", Cloud.parseCloudMounts("not mountinfo at all\n", "/home/u").length, 0)
    check("no home means no rows", Cloud.parseCloudMounts(mountsBody, "").length, 0)
    check("a stacked mountpoint names one row, not two",
          Cloud.parseCloudMounts(mountsBody + "44 1 0:44 / /home/u/gdrive rw - fuse.rclone remote: rw\n", "/home/u").length, 3)

    // The row itself: a server mark and a green square, and no menu at defaults, like
    // Dropbox's row, because the tool that made the mount owns it.
    var grow = { label: "gdrive", group: "network", kind: "cloud", uri: "", path: "/home/u/gdrive", mounted: true, glyph: "server" }
    check("a cloud row draws the server mark", grow.glyph, "server")
    check("a cloud row offers no menu row", Mounts.railMenu(grow).length, 0)
    check("and no right-click row either", Mounts.rowMenu(grow).length, 0)
    check("and no eject mark either", Eject.releasable(grow), false)
}

