.import "../../ui/js/Phones.js" as Phones
.import "../../ui/js/Mounts.js" as Mounts

function run(check) {
    // Real gio mount -li output, captured on the box with a Samsung phone on USB (2026-09-11),
    // cut to the lines the parser reads plus the noise it must survive.
    var unplugged = 'Drive(0): CT2000T700SSD3\n'
                  + '  Type: GProxyDrive (GProxyVolumeMonitorUDisks2)\n'
    check("a box with no phone parses to nothing", Phones.parsePhones(unplugged).length, 0)
    check("empty gio output parses to nothing", Phones.parsePhones("").length, 0)
    check("garbage gio output parses to nothing", Phones.parsePhones("not gio output at all\n").length, 0)

    var idle = 'Volume(0): SAMSUNG Android\n'
             + '  Type: GProxyVolume (GProxyVolumeMonitorMTP)\n'
             + '  ids:\n'
             + "   unix-device: '/dev/bus/usb/001/013'\n"
             + '  activation_root=mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/\n'
             + '  themed icons:  [multimedia-player]\n'
             + '  can_mount=1\n'
             + '  can_eject=0\n'
             + '  should_automount=1\n'
    var rows = Phones.parsePhones(idle)
    check("a plugged phone is one row", rows.length, 1)
    check("the row keeps the volume's own label", rows[0].label, "SAMSUNG Android")
    check("the row's uri is the activation root", rows[0].uri, "mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/")
    check("an unmounted phone reads as unmounted", rows[0].mounted, false)
    check("a phone rides the DEVICES group", rows[0].group + "|" + rows[0].kind, "device|phone")
    check("the path stays empty until the open resolves it", rows[0].path, "")
    // ui/SidebarRow.qml draws a device row's detail when size !== null, and undefined passes that.
    check("the row carries a null size rather than none", rows[0].size, null)

    // Mounted: gio adds the volume's own indented Mount() inside the block, and a top-level
    // shadow Mount() after it, which is parseMounts's to skip and not a second phone.
    var live = idle
             + '  Mount(0): SAMSUNG Android -> mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/\n'
             + '    Type: GProxyShadowMount (GProxyVolumeMonitorMTP)\n'
             + '    can_unmount=1\n'
             + 'Mount(1): mtp -> mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/\n'
             + '  Type: GDaemonMount\n'
             + '  is_shadowed=1\n'
    var mounted = Phones.parsePhones(live)
    check("the mounted phone is still one row", mounted.length, 1)
    // Measured on this box: gvfs prints can_mount=0 for a volume it has already mounted, so a guard
    // reading can_mount alone loses the row at the moment the rail needs its Unmount.
    var mountedNoRemount = 'Volume(0): SAMSUNG Android\n'
                         + '  Type: GProxyVolume (GProxyVolumeMonitorMTP)\n'
                         + '  activation_root=mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/\n'
                         + '  can_mount=0\n'
                         + '  can_eject=0\n'
                         + '  Mount(0): SAMSUNG Android -> mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/\n'
    var live0 = Phones.parsePhones(mountedNoRemount)
    check("a mounted volume that can no longer be mounted is still a row", live0.length, 1)
    check("and it reads as mounted, so the rail offers its Unmount",
          live0.length === 1 ? live0[0].mounted + "|" + Mounts.railMenu(live0[0]).map(function (r) { return r.action }).join(",")
                             : "no row", "true|openPhone,unmountPhone")
    check("the indented Mount() flips it to mounted", mounted[0].mounted, true)
    check("the shadow mount is not a network row either", Mounts.parseMounts(live).length, 0)

    // A udisks volume prints indented under its Drive() block; even hoisted to column zero its
    // Type line is the wrong monitor, so both guards hold on their own.
    var stick = 'Drive(4): WD_BLACK SN850X 4000GB\n'
              + '  Type: GProxyDrive (GProxyVolumeMonitorUDisks2)\n'
              + '  Volume(0): STEAM\n'
              + '    Type: GProxyVolume (GProxyVolumeMonitorUDisks2)\n'
              + '    can_mount=0\n'
              + '    Mount(0): STEAM -> file:///run/media/gm/STEAM\n'
    check("a udisks volume under its drive is not a phone", Phones.parsePhones(stick).length, 0)
    var hoisted = 'Volume(0): STEAM\n'
                + '  Type: GProxyVolume (GProxyVolumeMonitorUDisks2)\n'
                + '  activation_root=file:///run/media/gm/STEAM\n'
                + '  can_mount=1\n'
    check("a top-level udisks volume is still the wrong monitor", Phones.parsePhones(hoisted).length, 0)

    // A camera speaks PTP through the GPhoto2 monitor, the other volume kind with no block device.
    var camera = 'Volume(0): Canon Digital Camera\n'
               + '  Type: GProxyVolume (GProxyVolumeMonitorGPhoto2)\n'
               + '  activation_root=gphoto2://%5Busb%3A001%2C010%5D/\n'
               + '  can_mount=1\n'
    var cam = Phones.parsePhones(camera)
    check("a gphoto2 camera is a row too", cam.length, 1)
    check("its uri is the gphoto2 activation root", cam[0].uri, "gphoto2://%5Busb%3A001%2C010%5D/")
    check("a gphoto2 mount is not a network row", Mounts.parseMounts('Mount(0): camera -> gphoto2://%5Busb%3A001%2C010%5D/\n').length, 0)

    // A volume that refuses mounting, or names no root to mount, is not a row anyone can act on.
    var refusing = 'Volume(0): SAMSUNG Android\n'
                 + '  Type: GProxyVolume (GProxyVolumeMonitorMTP)\n'
                 + '  activation_root=mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/\n'
                 + '  can_mount=0\n'
    check("can_mount=0 is not a row", Phones.parsePhones(refusing).length, 0)
    var rootless = 'Volume(0): SAMSUNG Android\n'
                 + '  Type: GProxyVolume (GProxyVolumeMonitorMTP)\n'
                 + '  can_mount=1\n'
    check("no activation root is not a row", Phones.parsePhones(rootless).length, 0)

    // Two phones are two rows, and the block walk does not bleed one's fields into the other.
    var two = idle
            + 'Volume(1): Pixel 7\n'
            + '  Type: GProxyVolume (GProxyVolumeMonitorMTP)\n'
            + '  activation_root=mtp://Google_Pixel_7_1A2B/\n'
            + '  can_mount=1\n'
            + '  Mount(0): Pixel 7 -> mtp://Google_Pixel_7_1A2B/\n'
    var pair = Phones.parsePhones(two)
    check("two phones are two rows", pair.length, 2)
    check("the first stays unmounted", pair[0].mounted, false)
    check("the second's mount is its own", pair[1].mounted + "|" + pair[1].uri, "true|mtp://Google_Pixel_7_1A2B/")

    // The rail's shared plumbing: menu, key and release, the same contract volumes and shares hold.
    check("a mounted phone offers its open and its release, never an eject",
          Mounts.railMenu(mounted[0]).map(function (r) { return r.action }).join(","), "openPhone,unmountPhone")
    check("an unmounted phone offers the mount its own row does",
          Mounts.railMenu(rows[0]).map(function (r) { return r.action }).join(","), "mountPhone")
    check("a phone's key is its uri", Mounts.railKey(mounted[0]), "mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/")
    check("rowMenu adds no share rows to a phone",
          Mounts.rowMenu(mounted[0]).map(function (r) { return r.action }).join(","), "openPhone,unmountPhone")

    // Release resolves through the sidebar, which owns the phone Service; a stale key does nothing.
    var releasedKey = ""
    var openedKey = ""
    var sidebar = { deviceEntries: [mounted[0]], releasePhone: function (key) { releasedKey = key },
                    openPhone: function (key) { openedKey = key } }
    Mounts.release("unmountPhone", "mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/", null, null, sidebar)
    check("unmountPhone hands the key to the sidebar", releasedKey, "mtp://SAMSUNG_SAMSUNG_Android_RQGL705T0NR/")
    Mounts.release("mountPhone", "mtp://Google_Pixel_7_1A2B/", null, null, sidebar)
    check("mountPhone hands its own key to the same row's activation", openedKey, "mtp://Google_Pixel_7_1A2B/")

    // An unchanged poll must not assign, and a mount-state flip must: the two sides of sameEntries.
    check("an unchanged poll compares equal", Mounts.sameEntries(rows, Phones.parsePhones(idle)), true)
    check("a mount-state flip does not", Mounts.sameEntries(rows, mounted), false)

    // PhoneMark rule 1: the monitor picks the mark, because it is the transport the device answers
    // on and not the brand on the case. An iPhone comes through GPhoto2 and takes the camera.
    check("an MTP volume draws the phone", rows[0].glyph, "smartphone")
    var lens = 'Volume(0): Canon EOS R6\n'
             + '  Type: GProxyVolume (GProxyVolumeMonitorGPhoto2)\n'
             + '  activation_root=gphoto2://usb%3A001%2C014/\n'
             + '  can_mount=1\n'
    var lensRows = Phones.parsePhones(lens)
    check("a GPhoto2 volume draws the camera", lensRows.length + "|" + lensRows[0].glyph, "1|camera")
    check("and it is a phone row in every other respect",
          lensRows[0].group + "|" + lensRows[0].kind + "|" + lensRows[0].uri, "device|phone|gphoto2://usb%3A001%2C014/")

    // Issue 133 (mfilm77): gio trash has nowhere to put a file on either mount, so neither the menu
    // row nor the key is offered there. The FUSE folder is what names the scheme that reached it.
    check("an MTP folder cannot trash", Mounts.trashable("/run/user/1000/gvfs/mtp:host=SAMSUNG_RQGL705T0NR/DCIM"), false)
    check("a PTP folder cannot trash", Mounts.trashable("/run/user/1000/gvfs/gphoto2:host=usb%3A001%2C014/store"), false)
    check("a share folder still can", Mounts.trashable("/run/user/1000/gvfs/smb-share:server=nas,share=media"), true)
    check("and so does every ordinary path", Mounts.trashable("/home/gm/Downloads"), true)

    // Directive 44, captured on the box with GM's iPhone on USB (iOS 26.6.2, 2026-09-14). It answers
    // on two monitors at once: GPhoto2 for the camera store, which lists zero folders on this iOS
    // even unlocked and trusted, and AFC for the files, which lists DCIM.
    var phone = 'Volume(0): iPhone\n'
              + '  Type: GProxyVolume (GProxyVolumeMonitorGPhoto2)\n'
              + '  ids:\n'
              + "   unix-device: '/dev/bus/usb/001/005'\n"
              + '  activation_root=gphoto2://Apple_Inc._iPhone_00008130001641411883401C/\n'
              + '  can_mount=1\n'
              + '  can_eject=0\n'
              + '  should_automount=1\n'
              + "Volume(1): Documents on GM\u2019s iPhone\n"
              + '  Type: GProxyVolume (GProxyVolumeMonitorAfc)\n'
              + '  ids:\n'
              + "   uuid: '00008130-001641411883401C'\n"
              + '  uuid=00008130-001641411883401C\n'
              + '  activation_root=afc://00008130-001641411883401C:3/\n'
              + '  can_mount=1\n'
              + '  can_eject=0\n'
              + '  should_automount=1\n'
    var iphone = Phones.parsePhones(phone)
    check("an iPhone on two monitors is one row", iphone.length, 1)
    check("and it is the phone, not the camera store", iphone[0].glyph, "smartphone")
    check("the row's uri is the AFC root, never the documents volume gvfs advertises",
          iphone[0].uri, "afc://00008130-001641411883401C/")
    check("the label is the phone's own, with the documents share taken off the front",
          iphone[0].label, "GM\u2019s iPhone")
    check("an unmounted iPhone reads as unmounted", iphone[0].mounted, false)
    check("and it rides DEVICES like any other phone",
          iphone[0].group + "|" + iphone[0].kind, "device|phone")

    // The root mount prints at column zero rather than inside the volume block, which is the whole
    // reason the parser collects those lines: reading only the indented Mount() misses it.
    var live = phone + "Mount(2): GM\u2019s iPhone -> afc://00008130-001641411883401C/\n"
                     + '  Type: GDaemonMount\n'
    var liveRows = Phones.parsePhones(live)
    check("a mounted iPhone is still one row", liveRows.length, 1)
    check("and the root mount is what says it is mounted", liveRows[0].mounted, true)

    // And gvfs answers can_mount=0 for the volume once its root is mounted, the same way it does for
    // MTP, so the row has to be kept by the mount rather than dropped before the mount is looked at.
    var liveNoRemount = phone.replace("  activation_root=afc://00008130-001641411883401C:3/\n  can_mount=1\n",
                                      "  activation_root=afc://00008130-001641411883401C:3/\n  can_mount=0\n")
                      + "Mount(2): GM\u2019s iPhone -> afc://00008130-001641411883401C/\n"
    var keptRows = Phones.parsePhones(liveNoRemount)
    check("a mounted iPhone gvfs will not remount is still a row", keptRows.length, 1)
    check("and it reads as mounted", keptRows[0].mounted, true)

    // gvfs may automount the documents volume on its own, and its Mount() prints inside the block the
    // way an MTP one does, but it is afc://<uuid>:3/ and not the root this row offers to mount.
    var docsOnly = phone + ''
    docsOnly = docsOnly.replace("  activation_root=afc://00008130-001641411883401C:3/\n",
                                "  activation_root=afc://00008130-001641411883401C:3/\n"
                              + "  Mount(1): Documents on GM\u2019s iPhone -> afc://00008130-001641411883401C:3/\n")
    var docsRows = Phones.parsePhones(docsOnly)
    check("the documents volume's own mount is not the phone's", docsRows.length, 1)
    check("so the row still offers its mount rather than an unmount", docsRows[0].mounted, false)

    // An AFC volume with no uuid cannot name the root, and the row must not fall back to the share.
    var noUuid = phone.replace("  uuid=00008130-001641411883401C\n", "")
    var noUuidRows = Phones.parsePhones(noUuid)
    check("an AFC volume with no uuid is not a row", noUuidRows.length, 1)
    check("and what is left is the camera leg, not the documents share",
          noUuidRows[0].glyph + "|" + noUuidRows[0].uri,
          "camera|gphoto2://Apple_Inc._iPhone_00008130001641411883401C/")

    // Neither the share's can_mount nor its mount is about the root the row names.
    var automounted = phone.replace("  activation_root=afc://00008130-001641411883401C:3/\n  can_mount=1\n",
                                    "  activation_root=afc://00008130-001641411883401C:3/\n  can_mount=0\n"
                                  + "  Mount(1): Documents on GM\u2019s iPhone -> afc://00008130-001641411883401C:3/\n")
    var autoRows = Phones.parsePhones(automounted)
    // Not the row count: a dropped AFC row leaves its camera twin standing and the count still reads one.
    check("an automounted documents share does not decide the phone's row",
          autoRows[0].uri, "afc://00008130-001641411883401C/")
    check("the row is still the phone", autoRows[0].glyph, "smartphone")
    check("and it still offers its mount rather than an unmount", autoRows[0].mounted, false)

    // gvfs can publish more than one AFC volume for one phone, and they rebuild to the same root.
    var twice = phone + 'Volume(2): Documents on GM\u2019s iPhone\n'
                      + '  Type: GProxyVolume (GProxyVolumeMonitorAfc)\n'
                      + '  uuid=00008130-001641411883401C\n'
                      + '  activation_root=afc://00008130-001641411883401C:4/\n'
                      + '  can_mount=1\n'
    check("two AFC volumes on one uuid are one row", Phones.parsePhones(twice).length, 1)

    // The fold is on the serial the two monitors share, so a real camera beside a phone keeps its row.
    var both = phone + 'Volume(2): Canon EOS R6\n'
                     + '  Type: GProxyVolume (GProxyVolumeMonitorGPhoto2)\n'
                     + '  activation_root=gphoto2://usb%3A001%2C014/\n'
                     + '  can_mount=1\n'
    var bothRows = Phones.parsePhones(both)
    check("a camera plugged in beside the iPhone is its own row", bothRows.length, 2)
    check("and it is still the camera", bothRows[1].glyph + "|" + bothRows[1].label, "camera|Canon EOS R6")

    // With no AFC volume to fold into, an iPhone's GPhoto2 leg is the only row there is, and it draws
    // the camera: the mark names the transport, which is what rule 1 says.
    var ptpOnly = 'Volume(0): iPhone\n'
                + '  Type: GProxyVolume (GProxyVolumeMonitorGPhoto2)\n'
                + '  activation_root=gphoto2://Apple_Inc._iPhone_00008130001641411883401C/\n'
                + '  can_mount=1\n'
    var ptpRows = Phones.parsePhones(ptpOnly)
    check("without gvfs-afc the iPhone is one camera row", ptpRows.length + "|" + ptpRows[0].glyph, "1|camera")

    // The iPhone's root mount must not become a Network row as well, the same rule mtp and gphoto2
    // already have: its row is the rail's, built from the volume block.
    var shadow = "Mount(2): GM\u2019s iPhone -> afc://00008130-001641411883401C/\n"
               + 'Mount(3): isos on nas -> smb://nas/isos/\n'
    var shares = Mounts.parseMounts(shadow)
    check("the iPhone's mount is not a network share", shares.length, 1)
    check("and the real share beside it still is", shares[0].uri, "smb://nas/isos/")
}
