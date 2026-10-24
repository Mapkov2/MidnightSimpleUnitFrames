# Menu skin bridge ownership

The optional core bridge owns menu and Edit Mode chrome. It leaves unit frames
and profile color values to their existing owners. Motion settings are read
from the active skin appearance snapshot after login; profile binding refreshes
the snapshot. Menu animation and smooth-scrolling preferences remain separate,
and a reduced-motion request settles active menu animations.

The original source explanations below are retained verbatim. They are kept
here so startup does not load lengthy documentation on every supported client.
Executable and blank source bytes are unchanged by this documentation move.

```lua
    -- Search adds its rounded layers after the first skin pass. Include their
    -- identity in the cache so newly created, untinted artwork is hidden too.
```

```lua
    -- Native painters cache previous writes; restoring a provider is a paint boundary.
```

```lua
        -- Menu2 T.Button (the only setter of _msuf2RawSetScript) builds plain
        -- Buttons: no template, native state textures, Icon/Checked fields,
        -- dropdown mixin or Blizzard-gold text, and its pages never add them.
```

```lua
    -- Release before native repaint, including a modern -> native glyph switch.
```

```lua
--- Refresh reads the profile opt-out: connect at login at the earliest;
--- profile binds refresh again (MSUF_InitProfiles, ProfileRuntime.Apply).
```
