local tr = aegisub.gettext

script_name = tr"Join previous"
script_description = tr"Set previous line's end to selected line's start"
script_author = "The0x539"
script_version = "2"

local function join_previous(subs, sel, i)
    local j = i - 1
    while subs[j].comment do
        j = j - 1
    end
    local previous = subs[j]
    previous.end_time = subs[i].start_time
    subs[j] = previous
    aegisub.set_undo_point(tr"join previous")
end

aegisub.register_macro(script_name, script_description, join_previous)

