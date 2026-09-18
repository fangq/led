#!/usr/bin/env python3
"""Stress fixtures for LED, at the scale a working day actually reaches.

Run:  python3 tools/mkstress.py /somewhere/with/room
Then: ./bin/led --bench-open /somewhere/with/room/*

Sizes are chosen to be uncomfortable rather than absurd: a 5 MB log, a
2 MB C file (Linux has several), a 200-cell notebook with output, a 2 MB
Markdown lecture.  Written to $SCRATCH/stress and left there, so a
measurement can be repeated against the same bytes.
"""

import base64
import io
import json
import os
import struct
import sys

# Written wherever the first argument says, or beside this script.  Not into
# the repository: these are megabytes of generated noise, useful for an
# afternoon and not worth keeping.
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), 'stress')
os.makedirs(OUT, exist_ok=True)


def write(name, text):
    p = os.path.join(OUT, name)
    with io.open(p, 'w', encoding='utf8', newline='\n') as f:
        f.write(text)
    print('%-22s %8.1f MB' % (name, os.path.getsize(p) / 1e6))
    return p


def write_bytes(name, data):
    p = os.path.join(OUT, name)
    with open(p, 'wb') as f:
        f.write(data)
    print('%-22s %8.1f MB' % (name, os.path.getsize(p) / 1e6))
    return p


# ---- plain text: a log, which is what a multi-megabyte text file usually is
def plain(mb):
    out = []
    i = 0
    while sum(len(s) for s in out) < mb * 1000000:
        i += 1
        out.append('2026-09-17 11:%02d:%02d.%03d  worker[%d]  '
                   'request %d finished in %d ms, %d rows, status ok\n'
                   % (i % 60, (i * 7) % 60, i % 1000, i % 8, i,
                      (i * 13) % 900, (i * 29) % 5000))
    return ''.join(out)


# ---- C: many small functions, the shape of a generated parser or a driver
def c_source(mb):
    out = ['/* Generated stress fixture: %d MB of C. */\n'
           '#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n\n' % mb]
    i = 0
    while sum(len(s) for s in out) < mb * 1000000:
        i += 1
        out.append('''
/* Handler %(i)d: keeps a running total and complains about odd input. */
static int handle_%(i)d(const char *name, int value, double weight)
{
    static int calls = 0;
    int total = 0;
    char buffer[64];

    calls++;
    if (value < 0) {
        fprintf(stderr, "handle_%(i)d: negative value %%d\\n", value);
        return -1;
    }
    for (int k = 0; k < value %% 32; k++) {
        total += (k * %(i)d) %% 97;
        if (total > 100000) total /= 2;
    }
    snprintf(buffer, sizeof(buffer), "%%s=%%d", name ? name : "(none)", total);
    return (int)(total * weight) + calls;
}
''' % {'i': i})
    out.append('\nint main(void)\n{\n    int t = 0;\n')
    for k in range(1, min(i, 400)):
        out.append('    t += handle_%d("x", %d, 1.5);\n' % (k, k))
    out.append('    printf("%d\\n", t);\n    return 0;\n}\n')
    return ''.join(out)


def cpp_source(mb):
    out = ['// Generated stress fixture: %d MB of C++.\n'
           '#include <string>\n#include <vector>\n#include <map>\n\n'
           'namespace stress {\n\n' % mb]
    i = 0
    while sum(len(s) for s in out) < mb * 1000000:
        i += 1
        out.append('''
template <typename T>
class Holder%(i)d {
public:
    explicit Holder%(i)d(const std::string &name) : name_(name), count_(0) {}

    /* Adds one, and remembers how many times it has been asked. */
    void add(const T &value) {
        values_.push_back(value);
        ++count_;
        index_[name_ + std::to_string(count_)] = value;
    }

    std::size_t size() const { return values_.size(); }

private:
    std::string name_;
    int count_;
    std::vector<T> values_;
    std::map<std::string, T> index_;
};
''' % {'i': i})
    out.append('\n}  // namespace stress\n')
    return ''.join(out)


def python_source(mb):
    out = ['"""Generated stress fixture: %d MB of Python."""\n\n'
           'import math\nimport os\nimport sys\n\n' % mb]
    i = 0
    while sum(len(s) for s in out) < mb * 1000000:
        i += 1
        out.append('''
class Step%(i)d:
    """One step of the pipeline, with the usual bookkeeping."""

    def __init__(self, name, weight=1.0):
        self.name = name
        self.weight = weight
        self.seen = 0

    def run(self, rows):
        total = 0.0
        for k, row in enumerate(rows):
            if row is None:
                continue
            total += math.sqrt(abs(row) + %(i)d) * self.weight
            if k %% 97 == 0:
                total *= 0.999
        self.seen += len(rows)
        return total

    def __repr__(self):
        return "<Step%(i)d %%s seen=%%d>" %% (self.name, self.seen)
''' % {'i': i})
    return ''.join(out)


def markdown(mb):
    out = ['# A long lecture\n\n']
    i = 0
    while sum(len(s) for s in out) < mb * 1000000:
        i += 1
        out.append('''
## Section %(i)d

Some prose about section %(i)d, long enough to wrap in a preview pane and
to give the layout something to do.  It mentions `inline code`, a
[link](https://example.com/%(i)d) and *emphasis*.

### Under section %(i)d

| command | meaning |
| ------- | ------- |
| `step %(i)d` | does the %(i)dth thing |
| `undo %(i)d` | undoes it |

```c
/* Sample %(i)d */
int sample_%(i)d(int x)
{
    return x * %(i)d;
}
```
''' % {'i': i})
    return ''.join(out)


# ---- BJData: a records-and-arrays file, the shape MCX writes
def bjdata(mb):
    def s(text):
        b = text.encode('utf8')
        return b'U' + bytes([len(b)]) + b

    out = [b'{']
    out.append(s('formatVersion') + b'S' + s('1.0'))
    out.append(s('records') + b'[')
    i = 0
    size = 0
    while size < mb * 1000000:
        i += 1
        rec = [b'{']
        rec.append(s('id') + b'l' + struct.pack('<i', i))
        rec.append(s('name') + b'S' + s('record %d' % i))
        rec.append(s('weight') + b'D' + struct.pack('<d', i * 1.5))
        rec.append(s('flags') + b'T')
        rec.append(s('samples') + b'[' + b'$' + b'l' + b'#' + b'U' + bytes([16]))
        rec.append(struct.pack('<16i', *[(i + k) % 1000 for k in range(16)]))
        rec.append(b'}')
        blob = b''.join(rec)
        out.append(blob)
        size += len(blob)
    out.append(b']')
    out.append(b'}')
    data = b''.join(out)
    print('  (%d records)' % i)
    return data


# ---- a notebook with output, the shape a taught course has
def notebook(cells):
    png = base64.b64encode(open(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), 'meme.png'),
        'rb').read()).decode('ascii') if os.path.exists(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), 'meme.png')
    ) else None

    out = []
    for i in range(cells):
        if i % 3 == 0:
            out.append({
                "cell_type": "markdown", "metadata": {},
                "source": ["## Step %d\n" % i, "\n",
                           "Prose about step %d with `code` in it.\n" % i]})
        else:
            outputs = [{
                "output_type": "stream", "name": "stdout",
                "text": ["line %d of output from step %d\n" % (k, i)
                         for k in range(30)]}]
            if png and i % 25 == 0:
                outputs.append({
                    "output_type": "display_data", "metadata": {},
                    "data": {"image/png": png, "text/plain": ["<Figure>"]}})
            out.append({
                "cell_type": "code", "execution_count": i, "metadata": {},
                "outputs": outputs,
                "source": ["import numpy as np\n",
                           "x = np.arange(%d)\n" % i,
                           "print(x.sum())\n",
                           "for k in range(10):\n",
                           "    print('line', k, 'of step %d')\n" % i]})
    nb = {"cells": out,
          "metadata": {"kernelspec": {"display_name": "Python 3",
                                      "language": "python", "name": "python3"},
                       "language_info": {"name": "python"}},
          "nbformat": 4, "nbformat_minor": 5}
    return json.dumps(nb, indent=1, sort_keys=True, ensure_ascii=False) + '\n'


if __name__ == '__main__':
    write('plain-5mb.log', plain(5))
    write('plain-20mb.log', plain(20))
    write('big.c', c_source(2))
    write('big.cpp', cpp_source(2))
    write('big.py', python_source(2))
    write('big.md', markdown(2))
    write_bytes('big.bjd', bjdata(4))
    write('big.ipynb', notebook(200))
    write('huge.ipynb', notebook(800))
    print('in', OUT)
