tr = aegisub.gettext

export script_name = tr'Stable Retime'
export script_description = tr'Set start/end timestamps while preserving kara/transform timing'
export script_author = 'The0x539'
export script_version = '0.1.0'
export script_namespace = '0x.StableRetime'

DependencyControl = require 'l0.DependencyControl'
rec = DependencyControl {
	feed: 'https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json'
	{
		{
			'a-mo.LineCollection'
			version: '1.0.1'
			url: 'https://github.com/TypesettingTools/Aegisub-Motion'
			feed: 'https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json'
		}
		{
			'l0.ASSFoundation'
			version: '0.2.2'
			url: 'https://github.com/TypesettingTools/ASSFoundation'
			feed: 'https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json'
		}
	}
}
LineCollection, ASSFoundation = rec\requireModules!

processLine = (line, start, videoPosition) ->
	startDelta = if start then videoPosition - line.start_time else 0
	endDelta = if start then 0 else videoPosition - line.end_time

	data = ASSFoundation\parse line

	ktags = data\getTags {'k_fill', 'k_sweep', 'k_bord'}
	unless #ktags == 0
		ktags[1].value -= startDelta
		if ktags[1].value < 0
			error 'Attempted to shift line start past end of first syl'

		ktags[#ktags].value += endDelta
		if ktags[#ktags].value < 0
			error 'Attempted to shift line end past start of last syl'

	for tag in *data\getTags {'transform', 'move'}
		if tag.startTime.value == 0 and tag.endTime.value == 0
			tag.endTime += line.duration

		tag.startTime -= startDelta
		tag.endTime += endDelta

	for tag in *data\getTags {'fade'}
		tag.inStartTime -= startDelta
		tag.outStartTime -= endDelta

	data\commit!
	line.start_time += startDelta
	line.end_time += endDelta

processAll = (subs, sel, start) ->
	videoFrame = aegisub.project_properties!.video_position
	if not start
		videoFrame += 1
	videoPosition = aegisub.ms_from_frame video_frame
	videoPosition -= videoPosition % 10

	lines = LineCollection subs, sel, () -> true
	lines\runCallback (_subs, line, _i) -> processLine line, start, videoPosition
	lines\replaceLines!

setStart = (subs, sel, _i) ->
	processAll subs, sel, true
	aegisub.set_undo_point 'Snap start to video, preserving tag timing'

setEnd = (subs, sel, _i) ->
	processAll subs, sel, false
	aegisub.set_undo_point 'Snap end to video, preserving tag timing'

aegisub.register_macro 'Stable Retime/Set Start', script_description, setStart
aegisub.register_macro 'Stable Retime/Set End', script_description, setEnd
