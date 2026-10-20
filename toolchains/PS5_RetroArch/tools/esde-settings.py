#!/usr/bin/env python3
"""Read or change EmulationStation's settings on the console (frontends/es-de).

    tools/esde-settings.py                          print the settings that are set
    tools/esde-settings.py Theme=alekfull-nx-es-de StartupSystem=snes

ES-DE keeps its settings in /app0/es-de/ES-DE/settings/es_settings.xml, one element
per setting (<bool>, <int>, <float> or <string>, each with name and value) and no
root. A setting is changed in place, keeping its type; a new one is added as a
string. ES-DE writes the file itself when it quits or its menu changes a setting,
so change it while ES-DE is not running. The console's address and FTP account
are the ones tools/deploy-title.py reads from .env.
"""
from pathlib import Path
import importlib.util
import io
import json
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ps5_ftp import connect  # noqa: E402

ELEMENT = re.compile(r'<(bool|int|float|string) name="([^"]+)" value="([^"]*)" />')


def load_deploy():
    spec = importlib.util.spec_from_file_location('dt', Path(__file__).resolve().parent / 'deploy-title.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def escape(value):
    return value.replace('&', '&amp;').replace('"', '&quot;').replace('<', '&lt;').replace('>', '&gt;')


def apply(text, changes):
    """The settings file with each name=value of changes set, in place or added."""
    lines = text.splitlines() if text.strip() else ['<?xml version="1.0"?>']
    for name, value in changes:
        for index, line in enumerate(lines):
            match = ELEMENT.fullmatch(line.strip())
            if match and match.group(2) == name:
                lines[index] = f'<{match.group(1)} name="{name}" value="{escape(value)}" />'
                break
        else:
            lines.append(f'<string name="{name}" value="{escape(value)}" />')
    return '\n'.join(lines) + '\n'


def main(argv):
    changes = []
    for argument in argv[1:]:
        name, separator, value = argument.partition('=')
        if not separator or not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', name):
            raise SystemExit(f'expected Name=value, not {argument!r}')
        changes.append((name, value))
    deploy = load_deploy()
    param = Path(__file__).resolve().parent.parent / 'sce_sys' / 'param.json'
    title = json.loads(param.read_text())['titleId']
    remote = f'/data/homebrew/{title}/es-de/ES-DE/settings/es_settings.xml'
    with connect(**deploy.load_settings()) as ftp:
        current = io.BytesIO()
        try:
            ftp.retrbinary(f'RETR {remote}', current.write)
        except Exception:
            pass
        text = current.getvalue().decode('utf-8')
        if not changes:
            sys.stdout.write(text)
            return 0
        updated = apply(text, changes)
        ftp.storbinary(f'STOR {remote}', io.BytesIO(updated.encode('utf-8')))
        check = io.BytesIO()
        ftp.retrbinary(f'RETR {remote}', check.write)
        if check.getvalue() != updated.encode('utf-8'):
            raise SystemExit('the console did not keep the settings file as written')
    for name, value in changes:
        print(f'    {name} = {value}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
