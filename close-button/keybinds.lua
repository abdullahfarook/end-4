-- >>> close-button-drag >>>
-- Hand button: while hovered the shell enters this submap so a left-press starts a compositor drag (like SUPER + drag).
hl.define_submap("handdrag", function()
    hl.bind("mouse:272", hl.dsp.window.drag(), { mouse = true })
end)
-- <<< close-button-drag <<<
