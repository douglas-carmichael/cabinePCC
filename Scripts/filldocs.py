#!/usr/bin/env python3
"""Fills a page of the documentation from its template.

    filldocs.py <template> <samples folder> <page> <scenario script>

Scripts/makedocs.sh calls it: there is no need to run it by hand.

{{file|command}} in the template is replaced by what the headless tool printed for that command in
<samples folder>/<file>.txt, word for word, from the line of its prompt to the line before the next
command's. {{file|command|n}} is the command's n-th time in that file. {{file|command|n|h..t}} keeps
the first h lines of it and the last t, with a line of ellipsis between, for an output too long to
quote whole. A command that is not in the samples stops the build, so that the page cannot go on
quoting what the program no longer prints.

The commands are read from the scenario script, from its --dcl options. That is how the end of one
command's output is told from a line of output that happens to begin with a dollar sign.
"""
import io
import os
import re
import sys


def commands(script):
    """Every command the scenario script gives the tool, as the tool prints it after its prompt."""
    text = io.open(script, encoding="utf-8").read()
    found = set()
    for double, single in re.findall(r'--dcl (?:"((?:[^"\\]|\\.)*)"|\'([^\']*)\')', text):
        found.add(single if single else double.replace('\\"', '"').replace("\\$", "$"))
    return found


def block(samples, known, name, command, nth=1, cut=None):
    """What the tool printed for a command: the line of its prompt and what followed it."""
    path = os.path.join(samples, name + ".txt")
    if not os.path.exists(path):
        sys.exit("filldocs: no sample file %s" % path)
    lines = io.open(path, encoding="utf-8").read().split("\n")
    seen, start = 0, None
    for index, line in enumerate(lines):
        if line == "$ " + command:
            seen += 1
            if seen == nth:
                start = index
                break
    if start is None:
        sys.exit("filldocs: no sample of %r (time %d) in %s" % (command, nth, path))
    end = len(lines)
    for index in range(start + 1, len(lines)):
        if lines[index].startswith("$ ") and lines[index][2:] in known:
            end = index
            break
    out = [line.rstrip() for line in lines[start:end]]
    while out and out[-1] == "":
        out.pop()
    if cut:
        head, tail = (int(part) for part in cut.split(".."))
        if head + tail < len(out):
            out = out[:head] + ["  …"] + out[len(out) - tail:]
    return "\n".join(out)


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    template, samples, page, script = sys.argv[1:]
    known = commands(script)
    text = io.open(template, encoding="utf-8").read()
    filled = [0]

    def fill(match):
        parts = match.group(1).split("|")
        if len(parts) < 2:
            sys.exit("filldocs: {{%s}} names no command" % match.group(1))
        nth = int(parts[2]) if len(parts) > 2 and parts[2] else 1
        filled[0] += 1
        return block(samples, known, parts[0], parts[1], nth, parts[3] if len(parts) > 3 else None)

    text = re.sub(r"\{\{([^{}]+)\}\}", fill, text)
    note = "<!-- Made by Scripts/makedocs.sh from Scripts/%s: change the template, not this page. -->\n" \
        % os.path.basename(template)
    io.open(page, "w", encoding="utf-8").write(note + text)

    # Prose keeps to 108 columns; a sample is as wide as the program printed it, and a table row as
    # long as its cells.
    fenced, wide = False, []
    for number, line in enumerate(text.split("\n"), 2):
        if line.startswith("```"):
            fenced = not fenced
        elif not fenced and len(line) > 108 and not line.startswith("|"):
            wide.append(number)
    print("filldocs: %s, %d lines, %d samples" % (page, len(text.split("\n")) + 1, filled[0]))
    if wide:
        print("filldocs: prose over 108 columns at lines %s" % ", ".join(str(n) for n in wide))


if __name__ == "__main__":
    main()
