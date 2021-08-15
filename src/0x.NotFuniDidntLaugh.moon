export script_name = 'Not funi, didn\'t laugh'
export script_description = 'Helper script for dealing with idiosyncratic prosub timing'
export script_author = 'The0x539'
export script_version = '1'

util = require 'aegisub.util'

validate = (subs, sel, _) ->
	for li in *sel
		unless subs[li].text\find '\\N'
			return false
	true

validate_single = (subs, sel, i) ->
	#sel == 1 and sel[1] == i and validate subs, sel, i

strip = (text) -> text\gsub('^%- ?', '')\gsub('^ +', '')\gsub(' +$', '')

split = (line_a) ->
	line_b = util.copy line_a

	text = line_a.text
	end_of_a, start_of_b = text\find '\\N'
	end_of_a -= 1
	start_of_b += 1
	text_a = text\sub 1, end_of_a
	text_b = text\sub start_of_b

	line_a.text = strip text_a
	line_b.text = strip text_b
	if line_a.effect == 'split'
		line_a.effect = ''
		line_b.effect = ''

	line_a, line_b

ms_from_frame = (frame) ->
	ms = aegisub.ms_from_frame frame
	cs = ms / 10
	cs = math.floor(cs + 0.5)
	cs * 10

split_single = (subs, sel, i) ->
	frame = aegisub.project_properties!.video_position
	time = ms_from_frame frame
	line_a, line_b = split subs[i]
	line_a.end_time = time
	line_b.start_time = time
	subs[i] = line_b
	subs.insert i, line_a
	aegisub.set_undo_point 'split combined line at video'
	{i, i + 1}, i + 1

split_multiple = (subs, sel, active) ->
	table.sort sel
	new_selection = {}
	new_active = active

	for i = #sel, 1, -1
		li = sel[i]
		line_a, line_b = split subs[li]

		subs[li] = line_b
		subs.insert li, line_a

		--table.insert new_selection, li + i - 1
		table.insert new_selection, li + i
		if li <= active
			new_active += 1

	aegisub.set_undo_point 'split combined lines'
	new_selection, new_active

aegisub.register_macro "#{script_name}/Split line before current frame", script_description, split_single, validate_single
aegisub.register_macro "#{script_name}/Split selected lines", script_description, split_multiple, validate
