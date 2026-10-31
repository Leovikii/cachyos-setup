#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Read Fontconfig values and compare XML without formatting or comments."""
import sys
import xml.etree.ElementTree as ET


def content(node):
    return (node.tag, tuple(sorted(node.attrib.items())), (node.text or "").strip(),
            tuple(content(child) for child in node))


try:
    root = ET.parse(sys.argv[2]).getroot()
    if sys.argv[1] == "rgba":
        values = root.findall("./match[@target='font']/edit[@name='rgba']/const")
        if len(values) != 1:
            sys.exit(1)
        print((values[0].text or "").strip())
    else:
        expected = ET.parse(sys.argv[3]).getroot()
        rendering = {content(edit) for match in expected.findall("./match[@target='font']")
                     if all(child.tag == "edit" for child in match) for edit in match}
        # 接受旧配置追加的同值渲染规则，保留条件规则及不同值以便检出冲突。
        for rule in list(root):
            if (rule.tag == "match" and rule.attrib == {"target": "pattern"} and len(rule)
                    and all(content(edit) in rendering for edit in rule)):
                root.remove(rule)
        sys.exit(content(root) != content(expected))
except (OSError, ET.ParseError):
    sys.exit(1)
