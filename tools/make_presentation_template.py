#!/usr/bin/env python3
"""Write data/templates/presentation.potx: the deck File > New Presentation starts from.

A 16:9 PowerPoint template made from scratch (no Office file copied): one slide master, an Office-style
theme, four layouts -- Title Slide, Title and Content, Title Only, Blank -- and one slide, a Title Slide.
The zip is written with fixed timestamps, so running this again gives the same bytes.

    python3 tools/make_presentation_template.py [out.potx]
"""
import sys
import zipfile

P = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" ' \
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" ' \
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'
REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
PKG = 'http://schemas.openxmlformats.org/package/2006/relationships'
CT = 'application/vnd.openxmlformats-officedocument.presentationml.'
HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'

W, H = 12192000, 6858000      # 13.333 x 7.5 in: 16:9


def rels(items):
    return HEAD + '<Relationships xmlns="%s">' % PKG + ''.join(
        '<Relationship Id="%s" Type="%s%s" Target="%s"/>' % (i, REL, t, tg) for i, t, tg in items) + '</Relationships>'


def xfrm(x, y, w, h):
    return '<a:xfrm><a:off x="%d" y="%d"/><a:ext cx="%d" cy="%d"/></a:xfrm>' % (x, y, w, h)


def ph(sid, name, kind, idx=None, box=None, body='<a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang="en-US"/></a:p>'):
    at = (' type="%s"' % kind if kind else '') + (' idx="%d"' % idx if idx is not None else '')
    sp = '<p:spPr>%s</p:spPr>' % (xfrm(*box) if box else '')
    return ('<p:sp><p:nvSpPr><p:cNvPr id="%d" name="%s"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
            '<p:nvPr><p:ph%s/></p:nvPr></p:nvSpPr>%s<p:txBody>%s</p:txBody></p:sp>' % (sid, name, at, sp, body))


def tree(shapes):
    return ('<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
            '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/>'
            '<a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>%s</p:spTree></p:cSld>' % ''.join(shapes))


def cslds(name, shapes):
    return tree(shapes).replace('<p:cSld>', '<p:cSld name="%s">' % name, 1)


MAP = ('<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" '
       'accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>')

# where the master's placeholders are: the title across the top, the body under it
TITLE = (838200, 365125, 10515600, 1325563)
BODY = (838200, 1825625, 10515600, 4351338)


def lvl(n, size, bullet=True):
    mar = 228600 + 457200 * (n - 1)
    b = ('<a:buFont typeface="Arial"/><a:buChar char="&#8226;"/>' if bullet else '<a:buNone/>')
    return ('<a:lvl%dpPr marL="%d" indent="-228600" algn="l"><a:lnSpc><a:spcPct val="90000"/></a:lnSpc>'
            '<a:spcBef><a:spcPts val="1000"/></a:spcBef>%s<a:defRPr sz="%d" kern="1200"><a:solidFill>'
            '<a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mn-lt"/><a:ea typeface="+mn-ea"/>'
            '<a:cs typeface="+mn-cs"/></a:defRPr></a:lvl%dpPr>' % (n, mar, b, size, n))


MASTER = HEAD + ('<p:sldMaster %s>' % P) + tree([
    ph(2, 'Title Placeholder 1', 'title', box=TITLE,
       body='<a:bodyPr vert="horz" lIns="91440" tIns="45720" rIns="91440" bIns="45720" rtlCol="0" anchor="ctr">'
            '<a:normAutofit/></a:bodyPr><a:lstStyle/><a:p><a:r><a:rPr lang="en-US"/>'
            '<a:t>Click to edit Master title style</a:t></a:r></a:p>'),
    ph(3, 'Text Placeholder 2', 'body', idx=1, box=BODY,
       body='<a:bodyPr vert="horz" lIns="91440" tIns="45720" rIns="91440" bIns="45720" rtlCol="0">'
            '<a:normAutofit/></a:bodyPr><a:lstStyle/><a:p><a:pPr lvl="0"/><a:r><a:rPr lang="en-US"/>'
            '<a:t>Click to edit Master text styles</a:t></a:r></a:p><a:p><a:pPr lvl="1"/><a:r>'
            '<a:rPr lang="en-US"/><a:t>Second level</a:t></a:r></a:p><a:p><a:pPr lvl="2"/><a:r>'
            '<a:rPr lang="en-US"/><a:t>Third level</a:t></a:r></a:p>'),
]).replace('<p:cSld>', '<p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>', 1) + MAP + \
    '<p:sldLayoutIdLst>' + ''.join('<p:sldLayoutId id="%d" r:id="rId%d"/>' % (2147483649 + i, i + 1)
                                   for i in range(4)) + '</p:sldLayoutIdLst>' + \
    ('<p:txStyles><p:titleStyle><a:lvl1pPr algn="l" defTabSz="914400" rtl="0" eaLnBrk="1" latinLnBrk="0" '
     'hangingPunct="1"><a:lnSpc><a:spcPct val="90000"/></a:lnSpc><a:spcBef><a:spcPct val="0"/></a:spcBef>'
     '<a:buNone/><a:defRPr sz="4400" kern="1200"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill>'
     '<a:latin typeface="+mj-lt"/><a:ea typeface="+mj-ea"/><a:cs typeface="+mj-cs"/></a:defRPr></a:lvl1pPr>'
     '</p:titleStyle><p:bodyStyle>' + lvl(1, 2800) + lvl(2, 2400) + lvl(3, 2000) + lvl(4, 1800) + lvl(5, 1800) +
     '</p:bodyStyle><p:otherStyle><a:defPPr><a:defRPr lang="en-US"/></a:defPPr>' +
     lvl(1, 1800, False).replace('marL="228600" indent="-228600"', 'marL="0"') +
     '</p:otherStyle></p:txStyles></p:sldMaster>')

PROMPT = '<a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US"/><a:t>%s</a:t></a:r></a:p>'


def layout(kind, name, shapes):
    return HEAD + ('<p:sldLayout %s type="%s" preserve="1">' % (P, kind)) + cslds(name, shapes) + \
        '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>'


LAYOUTS = [
    layout('title', 'Title Slide', [
        ph(2, 'Title 1', 'ctrTitle', box=(1524000, 1122363, 9144000, 2387600),
           body='<a:bodyPr anchor="b"><a:normAutofit/></a:bodyPr><a:lstStyle><a:lvl1pPr algn="ctr">'
                '<a:defRPr sz="6000"/></a:lvl1pPr></a:lstStyle><a:p><a:r><a:rPr lang="en-US"/>'
                '<a:t>Click to add title</a:t></a:r></a:p>'),
        ph(3, 'Subtitle 2', 'subTitle', idx=1, box=(1524000, 3602038, 9144000, 1655762),
           body='<a:bodyPr><a:normAutofit/></a:bodyPr><a:lstStyle><a:lvl1pPr marL="0" indent="0" algn="ctr">'
                '<a:buNone/><a:defRPr sz="2400"/></a:lvl1pPr></a:lstStyle><a:p><a:r><a:rPr lang="en-US"/>'
                '<a:t>Click to add subtitle</a:t></a:r></a:p>'),
    ]),
    layout('obj', 'Title and Content', [
        ph(2, 'Title 1', 'title', body=PROMPT % 'Click to add title'),
        ph(3, 'Content Placeholder 2', None, idx=1, body=PROMPT % 'Click to add text'),
    ]),
    layout('titleOnly', 'Title Only', [ph(2, 'Title 1', 'title', body=PROMPT % 'Click to add title')]),
    layout('blank', 'Blank', []),
]

# the first slide: a Title Slide, its placeholders empty (the layout's prompts show through)
SLIDE = HEAD + ('<p:sld %s>' % P) + tree([
    ph(2, 'Title 1', 'ctrTitle'),
    ph(3, 'Subtitle 2', 'subTitle', idx=1),
]) + '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>'


def font(script_major):
    return '<a:latin typeface="%s" panose=""/><a:ea typeface=""/><a:cs typeface=""/>' % script_major


THEME = HEAD + ('<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Led">'
                '<a:themeElements><a:clrScheme name="Led">'
                '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
                '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
                '<a:dk2><a:srgbClr val="1F2A44"/></a:dk2><a:lt2><a:srgbClr val="E8EBF0"/></a:lt2>'
                '<a:accent1><a:srgbClr val="2F6FB5"/></a:accent1><a:accent2><a:srgbClr val="E07B39"/></a:accent2>'
                '<a:accent3><a:srgbClr val="8A9199"/></a:accent3><a:accent4><a:srgbClr val="E8B530"/></a:accent4>'
                '<a:accent5><a:srgbClr val="4FA3D1"/></a:accent5><a:accent6><a:srgbClr val="5C9E47"/></a:accent6>'
                '<a:hlink><a:srgbClr val="2F6FB5"/></a:hlink><a:folHlink><a:srgbClr val="7A4FA3"/></a:folHlink>'
                '</a:clrScheme><a:fontScheme name="Led"><a:majorFont>' + font('Calibri Light') +
                '</a:majorFont><a:minorFont>' + font('Calibri') + '</a:minorFont></a:fontScheme>'
                '<a:fmtScheme name="Led"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
                '<a:solidFill><a:schemeClr val="phClr"><a:tint val="60000"/></a:schemeClr></a:solidFill>'
                '<a:solidFill><a:schemeClr val="phClr"><a:shade val="80000"/></a:schemeClr></a:solidFill>'
                '</a:fillStyleLst><a:lnStyleLst>'
                '<a:ln w="6350" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/>'
                '</a:solidFill><a:prstDash val="solid"/><a:miter lim="800000"/></a:ln>'
                '<a:ln w="12700" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/>'
                '</a:solidFill><a:prstDash val="solid"/><a:miter lim="800000"/></a:ln>'
                '<a:ln w="19050" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/>'
                '</a:solidFill><a:prstDash val="solid"/><a:miter lim="800000"/></a:ln></a:lnStyleLst>'
                '<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/>'
                '</a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>'
                '<a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
                '<a:solidFill><a:schemeClr val="phClr"><a:tint val="95000"/></a:schemeClr></a:solidFill>'
                '<a:solidFill><a:schemeClr val="phClr"><a:shade val="90000"/></a:schemeClr></a:solidFill>'
                '</a:bgFillStyleLst></a:fmtScheme></a:themeElements><a:objectDefaults/>'
                '<a:extraClrSchemeLst/></a:theme>')

PRES = HEAD + ('<p:presentation %s saveSubsetFonts="1">' % P) + \
    '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>' \
    '<p:sldIdLst><p:sldId id="256" r:id="rId2"/></p:sldIdLst>' \
    '<p:sldSz cx="%d" cy="%d"/><p:notesSz cx="6858000" cy="9144000"/>' % (W, H) + \
    '<p:defaultTextStyle><a:defPPr><a:defRPr lang="en-US"/></a:defPPr>' + \
    lvl(1, 1800, False).replace('marL="228600" indent="-228600"', 'marL="0"') + \
    '</p:defaultTextStyle></p:presentation>'

TYPES = HEAD + ('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                '<Default Extension="xml" ContentType="application/xml"/>'
                '<Override PartName="/ppt/presentation.xml" ContentType="%stemplate.main+xml"/>'
                '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="%sslideMaster+xml"/>' % (CT, CT) +
                ''.join('<Override PartName="/ppt/slideLayouts/slideLayout%d.xml" ContentType="%sslideLayout+xml"/>'
                        % (i + 1, CT) for i in range(4)) +
                '<Override PartName="/ppt/slides/slide1.xml" ContentType="%sslide+xml"/>' % CT +
                '<Override PartName="/ppt/theme/theme1.xml" '
                'ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/></Types>')

PARTS = [
    ('[Content_Types].xml', TYPES),
    ('_rels/.rels', rels([('rId1', 'officeDocument', 'ppt/presentation.xml')])),
    ('ppt/presentation.xml', PRES),
    ('ppt/_rels/presentation.xml.rels', rels([('rId1', 'slideMaster', 'slideMasters/slideMaster1.xml'),
                                              ('rId2', 'slide', 'slides/slide1.xml'),
                                              ('rId3', 'theme', 'theme/theme1.xml')])),
    ('ppt/slideMasters/slideMaster1.xml', MASTER),
    ('ppt/slideMasters/_rels/slideMaster1.xml.rels',
     rels([('rId%d' % (i + 1), 'slideLayout', '../slideLayouts/slideLayout%d.xml' % (i + 1)) for i in range(4)] +
          [('rId5', 'theme', '../theme/theme1.xml')])),
] + [x for i, L in enumerate(LAYOUTS) for x in (
    ('ppt/slideLayouts/slideLayout%d.xml' % (i + 1), L),
    ('ppt/slideLayouts/_rels/slideLayout%d.xml.rels' % (i + 1),
     rels([('rId1', 'slideMaster', '../slideMasters/slideMaster1.xml')])))] + [
    ('ppt/slides/slide1.xml', SLIDE),
    ('ppt/slides/_rels/slide1.xml.rels', rels([('rId1', 'slideLayout', '../slideLayouts/slideLayout1.xml')])),
    ('ppt/theme/theme1.xml', THEME),
]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'data/templates/presentation.potx'
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, text in PARTS:
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, text.encode('utf-8'))


if __name__ == '__main__':
    main()
