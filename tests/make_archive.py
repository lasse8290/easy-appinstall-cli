#!/usr/bin/env python3
# Build test archives with a program and a data file.

import io
import stat
import sys
import tarfile
import zipfile

path, suffix, variant = sys.argv[1:]
entries = [("bundle/bin/tool", b"#!/bin/sh\necho archive-ok\n", 0o755, ""),
           ("bundle/data.txt", b"application data\n", 0o644, "")]
if variant == "ambiguous":
    entries.append(("bundle/bin/helper", b"#!/bin/sh\n", 0o755, ""))
elif variant == "noexec":
    entries[0] = (entries[0][0], entries[0][1], 0o644, "")
elif variant == "traversal":
    entries.append(("../../../escaped", b"bad", 0o644, ""))
elif variant == "absolute":
    entries.append((path.rsplit("/", 1)[0] + "/escaped", b"bad", 0o644, ""))
elif variant == "symlink_escape":
    entries.append(("bundle/link", b"", 0o777, "../../../escaped"))
elif variant == "symlink_inside":
    entries.append(("bundle/run", b"", 0o777, "bin/tool"))
elif variant == "ambiguous_link":
    entries.append(("bundle/run -> extra", b"", 0o777, path.rsplit("/", 1)[0] + "/escaped"))
elif variant == "parent_link":
    entries.append(("bundle/bin/run", b"", 0o777, "../bin/tool"))
elif variant == "fifo":
    entries.append(("bundle/pipe", b"", 0o644, "FIFO"))

if suffix == "zip":
    with zipfile.ZipFile(path, "w") as output:
        for name, data, mode, link in entries:
            member = zipfile.ZipInfo(name)
            member.create_system = 3
            member.external_attr = (mode | (stat.S_IFLNK if link else stat.S_IFREG)) << 16
            output.writestr(member, link.encode() if link else data)
else:
    compression = {"tar": "", "tar.gz": "gz", "tgz": "gz", "tar.bz2": "bz2",
                   "tbz2": "bz2", "tar.xz": "xz", "txz": "xz"}[suffix]
    with tarfile.open(path, "w:" + compression) as output:
        for name, data, mode, link in entries:
            member = tarfile.TarInfo(name)
            member.mode = mode
            if link:
                member.type = tarfile.FIFOTYPE if link == "FIFO" else tarfile.SYMTYPE
                member.linkname = link
                output.addfile(member)
            else:
                member.size = len(data)
                output.addfile(member, io.BytesIO(data))
