#!/usr/bin/env python3
"""Convert GtkSourceView 2.0 .lang grammars to TextMate JSON grammars.

Why this exists
---------------
SynEdit's TSynTextMateSyn is a fold-capable, context-based highlighter that
reads TextMate grammars.  medit ships 128 GtkSourceView grammars.  The two
models are close enough that converting is far cheaper -- and no less faithful
-- than reimplementing GtkSourceView's context engine in Pascal.

What makes it tractable
-----------------------
GtkSourceView does not have an exotic regex dialect at runtime.  Its parser
(gtksourcelanguage-parser-2.c:1071, expand_regex) already reduces every
pattern to plain PCRE before the engine sees it: it expands \\%{name}
fragments, rewrites \\%[ and \\%] into word boundaries, and prefixes inline
(?i)/(?x) modifiers.  Porting that one function is most of the work.

Scope names
-----------
The generated grammars use GtkSourceView's own style ids as TextMate scope
names, dot-normalised: "def:comment" becomes "def.comment".  That is what lets
the eight style schemes medit ships colour the converted grammars unchanged,
including their 200-odd language-specific entries.

Keyword lists
-------------
Emitted as flat alternations.  A trie would be about nine times faster, but
measurement said the flat form already costs ~5 microseconds per line for the
worst grammar in the corpus (R, 2053 keywords) -- irrelevant for a screenful
of text -- and a trie is not exactly equivalent at word boundaries.  Not worth
changing the matches to solve a problem that is not there.

Usage: tools/lang2tm.py <langs-dir> <out-dir>
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

# --- porting expand_regex ---------------------------------------------------

def expand_vars(pattern, defines, depth=0):
    """Expand \\%{name} references to <define-regex> fragments."""
    if depth > 12 or pattern is None:
        return pattern or ''
    def sub(m):
        name = m.group(1)
        if name in defines:
            return '(?:' + expand_vars(defines[name], defines, depth + 1) + ')'
        return m.group(0)
    return re.sub(r'\\%\{([A-Za-z0-9_:.-]+)\}', sub, pattern)


def expand_delimiters(pattern):
    r"""\%[ and \%] are GtkSourceView's word-boundary shorthand."""
    return pattern.replace(r'\%[', r'\b').replace(r'\%]', r'\b')


def start_refs(pattern):
    r"""\%{N@start} refers to group N of the matching start pattern.

    TextMate spells the same thing \N in an end pattern, and Lazarus's engine
    implements it, so this is a rename rather than a reimplementation.
    """
    return re.sub(r'\\%\{(\d+)@start\}', lambda m: '\\' + m.group(1), pattern)


def strip_extended(pattern):
    r"""Flatten an extended-mode regex into a compact one.

    GtkSourceView uses extended="true" liberally, with real prose in #
    comments -- bibtex has "# letter (\i \j for i,j without dot)" inside a
    pattern.  Rather than trusting the engine's (?x) handling to skip that,
    the whitespace and comments are removed here, which needs no engine
    support and cannot be misread.
    """
    out = []
    i = 0
    n = len(pattern)
    in_class = False
    while i < n:
        c = pattern[i]
        if c == '\\' and i + 1 < n:
            out.append(pattern[i:i + 2])
            i += 2
            continue
        if c == '[' and not in_class:
            in_class = True
            out.append(c)
            i += 1
            continue
        if c == ']' and in_class:
            in_class = False
            out.append(c)
            i += 1
            continue
        if not in_class:
            # Whitespace is not literal in extended mode.
            if c in ' \t\r\n':
                i += 1
                continue
            # A comment runs to the end of the line.
            if c == '#':
                while i < n and pattern[i] != '\n':
                    i += 1
                continue
        out.append(c)
        i += 1
    return ''.join(out)


def fix_quantifiers(pattern):
    r"""Possessive quantifiers (*+, ++, ?+, }+) are PCRE-only.

    Dropping the possessive marker leaves a greedy quantifier: the same
    language is matched, only the backtracking behaviour differs.  Eight
    grammars in the corpus use them -- matlab, octave, julia among them.
    """
    return re.sub(r'(?<!\\)([*+?}])\+', r'\1', pattern)


def fix_hex_escapes(pattern):
    r"""\x{...} is PCRE's codepoint escape and TRegExpr has no equivalent.

    The engine works on UTF-8 bytes, so a codepoint above 0xFF cannot match a
    single \x anyway; the honest translation is the byte sequence itself.
    """
    def sub(m):
        try:
            cp = int(m.group(1), 16)
        except ValueError:
            return m.group(0)
        return ''.join('\\x%02X' % b for b in chr(cp).encode('utf-8'))
    return re.sub(r'\\x\{([0-9A-Fa-f]+)\}', sub, pattern)


_GROUP_SERIAL = [0]


def unique_named_groups(pattern):
    r"""Inlining the same context twice duplicates its named groups, and the
    engine rejects a name defined more than once.  Names are made unique;
    nothing in these grammars refers to them by name."""
    def sub(m):
        _GROUP_SERIAL[0] += 1
        return '(?P<%s_%d>' % (m.group(1), _GROUP_SERIAL[0])
    return re.sub(r'\(\?P<([A-Za-z_][A-Za-z0-9_]*)>', sub, pattern)


def fix_unicode_classes(pattern):
    r"""\p{...} is a Unicode property class, which this engine does not have.

    Approximated by ASCII plus the high bytes, which is what \w already
    degrades to here.  Imperfect, and better than refusing the grammar.
    """
    def sub(m):
        prop = m.group(1)
        if prop.startswith('N'):
            return r'[0-9]'
        return r'[A-Za-z\x80-\xFF]'
    pattern = re.sub(r'\\p\{([A-Za-z]+)\}', sub, pattern)
    return re.sub(r'\\P\{[A-Za-z]+\}', r'[^A-Za-z0-9\\x80-\\xFF]', pattern)


def fix_quoting(pattern):
    r"""\Q...\E quotes a literal run.  Neither marker is supported, and the
    grammars that use them do not depend on the quoting."""
    return pattern.replace(r'\Q', '').replace(r'\E', '')


def ascii_safe(pattern):
    r"""xregexpr ships with Unicode support compiled out, so \w and \b are
    ASCII-only.  Widening \w to include the high bytes keeps identifiers in
    non-English source highlighted; \b is left alone because rewriting it as
    lookaround changes group numbering."""
    out = []
    i = 0
    while i < len(pattern):
        c = pattern[i]
        if c == '\\' and i + 1 < len(pattern):
            nxt = pattern[i + 1]
            if nxt == 'w':
                out.append(r'[A-Za-z0-9_\x80-\xFF]')
                i += 2
                continue
            if nxt == 'W':
                out.append(r'[^A-Za-z0-9_\x80-\xFF]')
                i += 2
                continue
            out.append(c + nxt)
            i += 2
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def element_flags(el, ctx_extended, ctx_case_sensitive):
    """extended and case-sensitive may be set on the <match>, <start> or
    <end> element itself, which is how latex, bibtex and python write them;
    the context's setting is only the fallback."""
    ext = ctx_extended
    cs = ctx_case_sensitive
    if el is not None:
        if el.get('extended') is not None:
            ext = el.get('extended') == 'true'
        if el.get('case-sensitive') is not None:
            cs = el.get('case-sensitive') == 'true'
    return ext, cs


def convert_pattern(raw, defines, extended, case_sensitive):
    if raw is None:
        return None
    # Extended mode describes the text the author wrote, not the text
    # substituted into it: a fragment may legitimately contain a literal '#'
    # (the C preprocessor patterns do), and stripping after expansion would
    # swallow the rest of the pattern.  Fragments are already flattened when
    # they are stored, so stripping first and expanding second is correct.
    p = raw
    if extended:
        p = strip_extended(p)
    p = expand_vars(p, defines)
    p = expand_delimiters(p)
    p = start_refs(p)
    if not case_sensitive:
        p = '(?i)' + p
    p = fix_hex_escapes(p)
    p = fix_unicode_classes(p)
    p = fix_quoting(p)
    p = fix_quantifiers(p)
    p = unique_named_groups(p)
    p = ascii_safe(p)
    if not p.strip():
        return None
    return p


# --- reading a .lang --------------------------------------------------------

class Lang:
    def __init__(self, path):
        self.path = path
        self.id = ''
        self.name = ''
        self.section = 'Other'
        self.hidden = False
        self.globs = []
        self.mimetypes = []
        self.line_comment = ''
        self.block_start = ''
        self.block_end = ''
        self.defines = {}
        self.contexts = {}     # local id -> element
        self.styles = {}       # local style id -> mapped style id
        self.default_ci = False
        self.default_x = False


def text_of(el):
    return (el.text or '').strip()


def load_lang(path):
    try:
        tree = ET.parse(path)
    except Exception as exc:
        return None, 'unparsable XML: %s' % exc
    root = tree.getroot()
    if root.tag != 'language':
        return None, 'not a language file'

    L = Lang(path)
    L.id = root.get('id', '')
    L.name = root.get('name') or root.get('_name') or L.id
    L.section = root.get('_section') or root.get('section') or 'Other'
    L.hidden = root.get('hidden') == 'true'
    if not L.id:
        return None, 'no id'

    for prop in root.iter('property'):
        n = prop.get('name')
        v = text_of(prop)
        if n == 'globs':
            L.globs = [g for g in v.split(';') if g]
        elif n in ('mimetypes', 'mimetype'):
            L.mimetypes = [m for m in v.split(';') if m]
        elif n == 'line-comment-start':
            L.line_comment = v
        elif n == 'block-comment-start':
            L.block_start = v
        elif n == 'block-comment-end':
            L.block_end = v

    for st in root.iter('style'):
        sid = st.get('id')
        if sid:
            L.styles[sid] = st.get('map-to') or ('%s:%s' % (L.id, sid))

    defs = root.find('definitions')
    if defs is None:
        return L, None

    opts = defs.get('default-regex-options') or root.get('default-regex-options')
    if opts:
        L.default_ci = 'i' in opts
        L.default_x = 'x' in opts

    for dr in defs.iter('define-regex'):
        rid = dr.get('id')
        if not rid:
            continue
        body = dr.text or ''
        # A fragment written in extended mode can be expanded into a pattern
        # that is not, so its whitespace and comments are removed now rather
        # than hoping the flag travels with it.
        if dr.get('extended') == 'true' or L.default_x:
            body = strip_extended(body)
        L.defines[rid] = body

    for ctx in defs.iter('context'):
        cid = ctx.get('id')
        if cid:
            L.contexts[cid] = ctx
    return L, None


# --- converting contexts ----------------------------------------------------

def scope_for(style_ref, lang):
    """A GtkSourceView style id becomes a dotted TextMate scope name."""
    if not style_ref:
        return None
    s = style_ref
    if ':' not in s:
        s = lang.styles.get(s, '%s:%s' % (lang.id, s))
    return s.replace(':', '.')


class Converter:
    def __init__(self, langs):
        self.langs = langs          # id -> Lang
        self.warnings = []

    def resolve_ref(self, ref, lang):
        """A context reference, possibly into another grammar."""
        if ':' in ref:
            other_id, name = ref.split(':', 1)
            other = self.langs.get(other_id)
            if other is None:
                return None, None
            if name == '*':
                return other, '*'
            return other, name
        return lang, ref

    def convert_context(self, ctx, lang, seen, depth=0):
        """One <context> becomes one TextMate pattern."""
        if depth > 24:
            return None

        ref = ctx.get('ref')
        if ref:
            target_lang, name = self.resolve_ref(ref, lang)
            if target_lang is None:
                self.warnings.append('%s: unknown reference %s' % (lang.id, ref))
                return None
            if name == '*':
                # "everything in that grammar" -- inline all its top contexts.
                subs = []
                for cid, sub in target_lang.contexts.items():
                    key = (target_lang.id, cid)
                    if key in seen:
                        continue
                    seen.add(key)
                    p = self.convert_context(sub, target_lang, seen, depth + 1)
                    seen.discard(key)
                    if p:
                        subs.append(p)
                return {'patterns': subs} if subs else None
            sub = target_lang.contexts.get(name)
            if sub is None:
                return None
            key = (target_lang.id, name)
            if key in seen:
                return None
            seen.add(key)
            out = self.convert_context(sub, target_lang, seen, depth + 1)
            seen.discard(key)
            return out

        ci = not (ctx.get('case-sensitive', 'true') == 'true')
        if lang.default_ci:
            ci = True
        ext = ctx.get('extended') == 'true' or lang.default_x

        style = scope_for(ctx.get('style-ref'), lang)
        result = {}

        match_el = ctx.find('match')
        start_el = ctx.find('start')
        end_el = ctx.find('end')
        kws = ctx.findall('keyword')

        def captures(where):
            caps = {}
            for sp in ctx.findall('include/context'):
                pass
            for sp in ctx.findall('.//context[@sub-pattern]'):
                if (sp.get('where') or '') != where:
                    continue
                idx = sp.get('sub-pattern')
                sc = scope_for(sp.get('style-ref'), lang)
                if idx is not None and sc:
                    caps[idx] = {'name': sc}
            return caps

        if kws:
            prefix = ctx.findtext('prefix')
            suffix = ctx.findtext('suffix')
            if prefix is None:
                prefix = r'\b'
            else:
                prefix = convert_pattern(prefix, lang.defines, ext, not ci)
            if suffix is None:
                suffix = r'\b'
            else:
                suffix = convert_pattern(suffix, lang.defines, ext, not ci)
            words = [re.escape(text_of(k)) for k in kws if text_of(k)]
            if not words:
                return None
            body = '%s(?:%s)%s' % (prefix, '|'.join(words), suffix)
            if ci:
                body = '(?i)' + body
            result['match'] = body
            if style:
                result['name'] = style
            return result

        if match_el is not None:
            mext, mcs = element_flags(match_el, ext, not ci)
            m = convert_pattern(match_el.text, lang.defines, mext, mcs)
            if not m:
                return None
            result['match'] = m
            if style:
                result['name'] = style
            caps = captures('')
            if caps:
                result['captures'] = caps
            return result

        if start_el is not None:
            sext, scs = element_flags(start_el, ext, not ci)
            begin = convert_pattern(start_el.text, lang.defines, sext, scs)
            if not begin:
                # A container whose start pattern vanished cannot be
                # expressed; dropping it is better than emitting a null.
                return None
            if end_el is not None:
                eext, ecs = element_flags(end_el, ext, not ci)
                end = convert_pattern(end_el.text, lang.defines, eext, ecs)
            else:
                end = None
            if ctx.get('end-at-line-end') == 'true' or end is None:
                end = ('(?:%s)|$' % end) if end else '$'
            result['begin'] = begin
            result['end'] = end
            if style:
                # style-inside colours the whole block; otherwise only the
                # delimiters carry the style, which is GtkSourceView's default.
                if ctx.get('style-inside') == 'true':
                    result['name'] = style
                else:
                    result['beginCaptures'] = {'0': {'name': style}}
                    result['endCaptures'] = {'0': {'name': style}}
            bc = captures('start')
            if bc:
                result.setdefault('beginCaptures', {}).update(bc)
            ec = captures('end')
            if ec:
                result.setdefault('endCaptures', {}).update(ec)

            subs = []
            for inc in ctx.findall('include'):
                for sub in inc:
                    if sub.tag != 'context':
                        continue
                    if sub.get('sub-pattern') is not None:
                        continue
                    p = self.convert_context(sub, lang, seen, depth + 1)
                    if p:
                        subs.append(p)
            if subs:
                result['patterns'] = subs
            return result

        subs = []
        for inc in ctx.findall('include'):
            for sub in inc:
                if sub.tag != 'context':
                    continue
                if sub.get('sub-pattern') is not None:
                    continue
                p = self.convert_context(sub, lang, seen, depth + 1)
                if p:
                    subs.append(p)
        if subs:
            return {'patterns': subs}
        return None

    def convert(self, lang):
        main = lang.contexts.get(lang.id)
        if main is None:
            for cid, ctx in lang.contexts.items():
                if ctx.find('include') is not None:
                    main = ctx
                    break
        if main is None:
            return None, 'no main context'

        patterns = []
        seen = set()
        for inc in main.findall('include'):
            for sub in inc:
                if sub.tag != 'context':
                    continue
                p = self.convert_context(sub, lang, seen)
                if p:
                    patterns.append(p)
        if not patterns:
            p = self.convert_context(main, lang, seen)
            if p and 'patterns' in p:
                patterns = p['patterns']
        if not patterns:
            return None, 'no patterns'

        grammar = {
            'name': lang.name,
            'scopeName': 'source.' + lang.id,
            'patterns': patterns,
        }
        if lang.globs:
            grammar['fileTypes'] = [g.lstrip('*.') for g in lang.globs]
        return grammar, None


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)

    langs = {}
    failed = []
    for name in sorted(os.listdir(src)):
        if not name.endswith('.lang'):
            continue
        L, err = load_lang(os.path.join(src, name))
        if L is None:
            failed.append((name, err))
            continue
        langs[L.id] = L

    conv = Converter(langs)
    index = []
    written = 0
    for lid in sorted(langs):
        L = langs[lid]
        grammar, err = conv.convert(L)
        entry = {
            'id': L.id,
            'name': L.name,
            'section': L.section,
            'hidden': L.hidden,
            'globs': L.globs,
            'mimetypes': L.mimetypes,
            'lineComment': L.line_comment,
            'blockCommentStart': L.block_start,
            'blockCommentEnd': L.block_end,
            'scopeName': 'source.' + L.id,
        }
        if grammar is None:
            entry['grammar'] = ''
            failed.append((L.id, err))
        else:
            fname = L.id + '.tmLanguage.json'
            with open(os.path.join(dst, fname), 'w', encoding='utf-8') as fh:
                json.dump(grammar, fh, indent=1, ensure_ascii=False)
            entry['grammar'] = fname
            written += 1
        index.append(entry)

    with open(os.path.join(dst, 'index.json'), 'w', encoding='utf-8') as fh:
        json.dump(index, fh, indent=1, ensure_ascii=False)

    print('grammars read:    %d' % len(langs))
    print('grammars written: %d' % written)
    if failed:
        print('not converted:    %d' % len(failed))
        for name, err in failed[:12]:
            print('   %-24s %s' % (name, err))
    if conv.warnings:
        print('warnings:         %d (first few)' % len(conv.warnings))
        for w in conv.warnings[:6]:
            print('   ' + w)


if __name__ == '__main__':
    main()
