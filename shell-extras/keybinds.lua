-- A left click ends type-search's keyboard capture (non-consuming: the click still reaches the target).
hl.bind("mouse:272", hl.dsp.global("typesearch:click"), { non_consuming = true, description = "type-search: release keyboard on click" })
