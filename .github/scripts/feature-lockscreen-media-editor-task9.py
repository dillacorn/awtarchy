from pathlib import Path

path = Path("tests/test-quickshell-lockscreen-selector-flyout.sh")
text = path.read_text(encoding="utf-8")
old = '''contains "$EDITOR" 'if (additive) root.selectElement(parent.elementName, true);' \\
    'additive preview selection does not use the shared element selection path'\ncontains "$EDITOR" 'else if (!root.selectedContains(parent.elementName)) root.selectElement(parent.elementName, false);' \\
    'new single-element preview selection does not use the shared element selection path'\ncontains "$EDITOR" 'else root.activeDrawer = "element";' \\
    'pressing an already-selected group member does not expose Element settings while preserving the group'\n'''
new = '''python3 - "$EDITOR" <<'PY_SELECTION'\nfrom pathlib import Path\nimport re\nimport sys\n\ntext = Path(sys.argv[1]).read_text(encoding="utf-8")\npattern = re.compile(\n    r'if\\s*\\(additive\\)\\s*'\n    r'root\\.selectElement\\(parent\\.elementName,\\s*true\\);\\s*'\n    r'else\\s+if\\s*\\(!root\\.selectedContains\\(parent\\.elementName\\)\\)\\s*'\n    r'root\\.selectElement\\(parent\\.elementName,\\s*false\\);\\s*'\n    r'else\\s*root\\.activeDrawer\\s*=\\s*"element";',\n    re.S,\n)\nif not pattern.search(text):\n    raise SystemExit(\n        'FAIL: preview press selection no longer routes additive, new-single, and existing-group cases through the shared selection path'\n    )\nPY_SELECTION\n'''
if new not in text:
    if text.count(old) != 1:
        raise SystemExit("selector selection-contract anchor changed")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
