# Menu skin bridge ownership

This is a historical note for the former core menu/Edit Mode skin bridge.
`MSUF_UIThemeBridge.lua` and `MSUF_Menu2_ThemeSkin.lua` were removed in
`161c4134b`; they no longer own or load any chrome. Current skin integration
belongs to MapkoSkin / the Suite skin bridge.

The source explanations below describe the removed implementation. They were
originally moved out of its startup source to reduce loaded documentation bytes;
they do not specify the current skin or motion contract.

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
