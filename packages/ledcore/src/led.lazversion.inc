{ led - a light editor.  Which Lazarus are we compiling against?

  led is developed against Lazarus 4.2 and has to keep building on the 2.2
  that Debian and Ubuntu still ship.  SynEdit, AnchorDocking and a few LCL
  controls gained members between the two, so a handful of call sites need
  two shapes.  This include is the single place that decides which, so a
  guard reads as "the API is newer than 2.2" rather than repeating version
  arithmetic.

  Include it right after the interface's uses clause -- it needs LazVersion,
  a LazUtils unit that both versions ship -- and then guard on the symbol
  LED_LAZ3_UP with an IFDEF.  laz_fullversion is
  ((major*100 + minor)*100 + release)*100 + patch, so 2.2.0.4 is 2020004 and
  4.2.0 is 4020000.  Lazarus 1.x had no LazVersion at all, hence DECLARED. }

{$IF DECLARED(laz_fullversion)}
  {$IF laz_fullversion >= 3000000}
    {$DEFINE LED_LAZ3_UP}
  {$ENDIF}
{$ENDIF}
