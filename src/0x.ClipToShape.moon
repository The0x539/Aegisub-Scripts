tr = aegisub.gettext

export script_name = tr'Simple Clip to Shape'
export script_description = tr'Convert a clip to a shape, without all the nonsense'
export script_author = 'The0x539'
export script_version = '0.1.0'
export script_namespace = '0x.ClipToShape'

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

processLine = (line) ->
	data = ASSFoundation\parse line

	data\removeSections 2, nil

	shape = (data\removeTags {'clip_vect', 'iclip_vect'})[1]
	if shape == nil
		rect = (data\removeTags {'clip_rect', 'iclip_rect'})[1]
		if rect == nil
			return
		shape = rect\getVect!

	data\insertSections ASSFoundation.Section.Drawing {shape}

	pos = data\getPosition!
	pos.x, pos.y = 0, 0
	data\insertTags pos

	align = data\insertDefaultTags 'align'
	align.value = 7

	data\cleanTags!
	data\commit!

processAll = (subs, sel, _i) ->
	lines = LineCollection subs, sel, () -> true
	lines\runCallback (_subs, line, _i) -> processLine line
	lines\replaceLines!
	aegisub.set_undo_point 'convert clip to shape'

canProcess = (subs, sel, _i) ->
	for i in *sel
		if subs[i].text\find '\\i?clip'
			return true
	return false

aegisub.register_macro 'Clip to shape', script_description, processAll, canProcess
