tr = aegisub.gettext

export script_name = tr'Stable Retime'
export script_description = tr'Set start/end timestamps while preserving kara/transform timing'
export script_author = 'The0x539'
export script_version = '0.2.0'
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
		-- if these are both zero, the original tag probably omitted timestamps
		-- this has the behavior of making the transform span the line's entire duration
		-- this script should ensure that it spans the *original* duration
		-- no matter which delta is nonzero, this will require making the tag's timestamps explicit
		if tag.startTime.value == 0 and tag.endTime.value == 0
			tag.endTime += line.duration

		-- "timestamp" values, as used in all the non-\k tags that this script modifies, are relative to a line's start time
		-- as such, to preserve tag timing, one must apply the negated start delta to all such tags
		-- setting explicit timestamps is important, as explained above, but beyond that, the end delta should be irrelevant
		tag.startTime -= startDelta
		tag.endTime -= startDelta

	-- this script can only meaningfully support 7-arg complex fade, not 2-arg simple fade
	-- these are documented as "\fade" and "\fad" respectively, but renderers decide using argument count
	-- assf calls them "fade" and "fade_simple", and expects \fade to be complex and \fad to be simple
	-- it may not be ideal, but unlike renderers, automation macros are allowed to fail in cases like this
	-- Go fix your tags before they break some other macro that's less aware of this situation.
	for tag in *data\getTags {'fade'}
		tag.inStartTime -= startDelta
		tag.outStartTime -= startDelta

	data\commit!
	line.start_time += startDelta
	line.end_time += endDelta

msFromFrame = (frame) ->
	ms = aegisub.ms_from_frame frame
	cs = ms / 10
	cs = math.floor(cs + 0.5)
	return cs * 10

processAll = (subs, sel, start) ->
	videoFrame = aegisub.project_properties!.video_position
	if not start
		videoFrame += 1
	videoPosition = msFromFrame videoFrame

	lines = LineCollection subs, sel, () -> true
	lines\runCallback (_subs, line, _i) -> processLine line, start, videoPosition
	lines\replaceLines!

splitAll = (subs, sel, before) ->
	-- "chunk": some contiguous selected lines. A selection consists of one or more chunks.

	sel_a = {}
	sel_b = {}

	-- this and similar variables are indices into `sel`
	chunkStart = 1
	-- how many lines we've inserted to the left of where we're currently working
	offset = 0
	while chunkStart <= #sel
		-- determine where this chunk ends
		chunkEnd = chunkStart
		while sel[chunkEnd + 1] == sel[chunkEnd] + 1
			chunkEnd += 1
		chunkLen = (chunkEnd - chunkStart) + 1

		insertionIdx = sel[chunkEnd] + 1 + offset
		-- duplicate the lines, iterating backwards to preserve order
		for i = chunkEnd, chunkStart, -1
			lineIdx = sel[i] + offset
			-- this insertion happens backwards for each chunk, but that shouldn't matter
			table.insert sel_a, lineIdx
			table.insert sel_b, lineIdx + chunkLen

			subs.insert insertionIdx, subs[lineIdx]

		-- update offset and move on to next chunk
		offset += chunkLen
		chunkStart += chunkLen

	videoFrame = aegisub.project_properties!.video_position
	if not before
		videoFrame += 1
	videoPosition = msFromFrame videoFrame

	leftLines = LineCollection subs, sel_a, () -> true
	leftLines\runCallback (_, line, _i) -> processLine line, false, videoPosition
	leftLines\replaceLines!

	rightLines = LineCollection subs, sel_b, () -> true
	rightLines\runCallback (_, line, _i) -> processLine line, true, videoPosition
	rightLines\replaceLines!

	return sel_b

setStart = (subs, sel, _i) ->
	processAll subs, sel, true
	aegisub.set_undo_point 'Snap start to video, preserving tag timing'

setEnd = (subs, sel, _i) ->
	processAll subs, sel, false
	aegisub.set_undo_point 'Snap end to video, preserving tag timing'

splitBefore = (subs, sel, _i) ->
	new_sel = splitAll subs, sel, true
	aegisub.set_undo_point 'Split lines before current frame, preserving tag timing'
	return new_sel

splitAfter = (subs, sel, _i) ->
	new_sel = splitAll subs, sel, false
	aegisub.set_undo_point 'Split lines after current frame, preserving tag timing'
	return new_sel

aegisub.register_macro 'Stable Retime/Set Start', script_description, setStart
aegisub.register_macro 'Stable Retime/Set End', script_description, setEnd
aegisub.register_macro 'Stable Retime/Split Before', script_description, splitBefore
aegisub.register_macro 'Stable Retime/Split After', script_description, splitAfter
