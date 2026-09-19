.import "../../ui/js/Devices.js" as Devices
.import "../../ui/js/Mounts.js" as Mounts

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
    var unmounted = { group: "device", kind: "volume", mounted: false, removable: false, volumeMenu: true }
    check("an unmounted volume offers the mount its own activation does",
          Mounts.railMenu(unmounted).map(function (r) { return r.label + ":" + r.action }).join(","), "Mount:mountVolume")
    var mounted = { group: "device", kind: "volume", mounted: true, removable: false, volumeMenu: true }
    check("a mounted one offers the open beside the release",
          Mounts.railMenu(mounted).map(function (r) { return r.label + ":" + r.action }).join(","),
          "Open:openVolume,Unmount:unmountVolume")
    var stick = { group: "device", kind: "volume", mounted: true, removable: true, volumeMenu: true }
    check("and Eject stays where it stands today, on a volume somebody can pull out",
          Mounts.railMenu(stick).map(function (r) { return r.label }).join(","), "Open,Unmount,Eject")
    check("with the switch off a mounted stick offers exactly what it offered in 0.2.1",
          Mounts.railMenu({ group: "device", kind: "volume", mounted: true, removable: true }).map(function (r) { return r.label }).join(","),
          "Eject")
    check("and an unmounted one opens no menu at all",
          Mounts.railMenu({ group: "device", kind: "volume", mounted: false, removable: true }).length, 0)
}

