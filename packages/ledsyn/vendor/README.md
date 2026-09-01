# Vendored TextMate grammar engine

These files are copied verbatim from Lazarus, tag `lazarus_4_2`, except for
two clearly marked local patches described below.

| File | Upstream path |
|---|---|
| `syntextmatesyn.pas` | `components/synedit/syntextmatesyn.pas` |
| `textmategrammar.pas` | `components/lazedit/textmategrammar.pas` |
| `xregexpr.pas` | `components/lazedit/xregexpr.pas` |
| `regexpr_compilers.inc` | `components/lazedit/regexpr_compilers.inc` |
| `plist2json.pas` | `components/lazutils/plist2json.pas` |

## Why they are here

`led` colours the 127 converted grammars with `TSynTextMateSyn`, which lives in
the `LazEdit` package.  That package — and the TextMate engine as a whole —
first ships with Lazarus 3.x; Lazarus 2.2 has no TextMate support at all.
Vendoring keeps one tree buildable on both, instead of pinning every developer
to a Lazarus new enough to supply the engine.

Nothing here is on the unit path of `ledcore`, so the `nogui` constraint that
keeps the core testable is unaffected.

## What was deliberately left out

`xregexpr_unicodedata.pas` (4 MB) is **not** vendored.  It is reached only from
`{$IFDEF FastUnicodeData}`, and `xregexpr.pas` does `{$UNDEF FastUnicodeData}`
whenever `UnicodeRE` is off — which it is, by default and in our build.  If you
ever define `UnicodeRE`, this file must be fetched as well; the compiler will
say so plainly.

That `UnicodeRE` is off is also *why* `tools/lang2tm.py` performs the
ASCII-safety rewrites: `\w`, `\b`, `.` and case folding are byte-oriented here.

## Local patches

Both are tagged `*** led local patch ***` in the source so a future re-sync can
find them with grep.

1. **`syntextmatesyn.pas` — the language-name hook.**  `TSynCustomHighlighter`
   gained a per-instance `GetInstanceLanguageName` after 2.2.  Before that,
   `LanguageName` read the *class* function `GetLanguageName`, whose base
   implementation raises for any class that does not override it.  The `override`
   is now conditional on `laz_fullversion >= 3000000` (from LazUtils'
   `LazVersion`); on older Lazarus the method is declared plain and
   `GetLanguageName` is overridden to return a stable `'TextMate'` rather than
   raise.

   Callers wanting the real per-grammar name must not go through the base
   property, because on 2.2 it cannot reach the instance.  `Led.Syn.Factory`'s
   `LedHighlighterLanguageName` asks the grammar directly, which returns the
   same string on every version.

2. Nothing else.  `textmategrammar.pas`, `xregexpr.pas`, `regexpr_compilers.inc`
   and `plist2json.pas` are byte-for-byte upstream and compile unmodified
   against FPC 3.2.2.

## Re-syncing

```sh
RAW=https://gitlab.com/freepascal.org/lazarus/lazarus/-/raw/lazarus_4_2
curl -sfLO $RAW/components/synedit/syntextmatesyn.pas       # then re-apply patch 1
curl -sfLO $RAW/components/lazedit/textmategrammar.pas
curl -sfLO $RAW/components/lazedit/xregexpr.pas
curl -sfLO $RAW/components/lazedit/regexpr_compilers.inc
curl -sfLO $RAW/components/lazutils/plist2json.pas
```

`bin/langcheck data/grammars` loading all 127 grammars is the gate that says the
re-sync worked.

## Licence

Lazarus components are LGPL-2.1-or-later with the linking exception, the same
licence `led` itself uses.
