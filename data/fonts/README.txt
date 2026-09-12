Fira Code v6.2, from https://github.com/tonsky/FiraCode

Shipped byte for byte as upstream released it.  That is deliberate: the SIL
Open Font License reserves the name "Fira Code", so a modified file -- a
subset, a renamed family -- could not keep calling itself that.  Unmodified,
it can, and the licence asks only that OFL.txt travels with it.

Regular and Bold only.  The other four weights are not used: led asks for one
family and lets the toolkit pick the face, and the editor needs a real bold
rather than a synthesised one for highlighted text.
