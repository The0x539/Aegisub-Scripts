export script_name = 'Join pairs'
export script_description = 'Join pairs of lines with "Join (keep first)" behavior'
export script_author = 'The0x539'
export script_version = '1'

-- For the sake of this validation function's performance, this script assumes sel is a sorted list.
can_join_pairs = (subs, sel, _) -> (sel % 2 == 0) and (sel[#sel] - sel[1] == #sel - 1)

join_pairs = (subs, sel, _) ->
	to_del = {}
	for i = 1, #sel - 1, 2
		si, sj = sel[i], sel[i + 1]

		line = subs[si]
		line.end_time = subs[sj].end_time
		subs[si] = line

		table.insert to_del, sj
	
	subs.delete to_del
	aegisub.set_undo_point 'join pairs'
	return [i for i in *sel[1, #sel / 2]]

aegisub.register_macro script_name, script_description, join_pairs
