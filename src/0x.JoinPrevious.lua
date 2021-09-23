local tr = aegisub.gettext

script_name = tr"Join previous"
script_description = tr"Set previous line's end to selected line's start"
script_author = "The0x539"
script_version = "1"

local function join_previous(subs, sel, i)
    local line = subs[i - 1]
    line.end_time = subs[i].start_time
    subs[i - 1] = line
    aegisub.set_undo_point(tr"join previous")
end

aegisub.register_macro(script_name, script_description, join_previous)

