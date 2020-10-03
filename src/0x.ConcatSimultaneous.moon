export script_name = 'ConcatSimultaneous'
export script_description = 'Perform "Join (concatenate)" on any adjacent lines with matching start/end timestamps'
export script_author = 'The0x539'
export script_version = '0.1.0'

main = (subs, sel, _) ->
	for i = #sel, 2, -1
		idx1, idx2 = sel[i-1], sel[i]
		line1, line2 = subs[idx1], subs[idx2]
		if line1.start_time == line2.start_time and line1.end_time == line2.end_time
			line1.text = line1.text\gsub(' +$', '') .. ' ' .. line2.text\gsub('^ +', '')
			subs[idx1] = line1
			subs.delete idx2

aegisub.register_macro 'Concat simultaneous lines', script_description, main
