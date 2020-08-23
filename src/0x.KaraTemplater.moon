require 'karaskel'

USE_KARAOK = true
local karaOK
if USE_KARAOK
	karaOK = require 'ln.kara'

-- A magic table that is interested in every style.
all_styles = {} 
setmetatable all_styles,
	__index: -> true
	__newindex: ->

-- The shared global scope for all template code.
class template_env
	:_G, :math, :table, :string, :unicode, :tostring, :tonumber, :aegisub, :error, :karaskel, :require

	printf: aegisub.log

	print: (...) ->
		args = {...}
		aegisub.log table.concat(args, '\t')
		aegisub.log '\n'

	-- Given a self object, returns an actual retime function, which cannot require a self parameter
	_retime = => (mode, start_offset, end_offset) ->
		return if @line == nil
		start_offset or= 0
		end_offset or= 0
		syl = @syl
		if syl == nil and @char != nil
			syl = @char.syl
		start_base, end_base = switch mode
			when 'syl'       then syl.start_time, syl.end_time
			when 'presyl'    then syl.start_time, syl.start_time
			when 'postsyl'   then syl.end_time, syl.end_time
			when 'line'      then 0, @orgline.duration
			when 'preline'   then 0, 0
			when 'postline'  then @orgline.duration, @orgline.duration
			when 'start2syl' then 0, syl.start_time
			when 'syl2end'   then syl.end_time, @orgline.duration
			when 'presyl2postline' then syl.start_time, @orgline.duration
			when 'preline2postsyl' then 0, syl.end_time
			when 'set', 'abs'
				@line.start_time = start_offset
				@line.end_time = end_offset
				@line.duration = end_offset - start_offset
				return
			else error "Unknown retime mode: #{mode}", 2

		orig_start = @line.start_time
		@line.start_time = orig_start + start_base + start_offset
		@line.end_time = orig_start + end_base + end_offset
		@line.duration = @line.end_time - @line.start_time

	_relayer = => (new_layer) -> @line.layer = new_layer

	_maxloop = => (var, val) ->
		with @loopctx
			if .max[var] == nil
				table.insert .vars, var
			.max[var] = val
			.state[var] or= 1
			-- BUG: there are unaccounted-for situations in which .done should be set to true
			unless .state[var] > .max[var]
				.done = false
		''

	_set = => (key, val) -> @[key] = val

	new: (@subs, @meta, @styles) =>
		@_ENV = @
		@tenv = @
		@subtitles = @subs

		if USE_KARAOK
			@ln = karaOK
			@ln.init @
			-- some monkey-patching to address some execution environment differences from karaOK
			monkey_patch = (f) -> (...) ->
				patched_syl, patched_line = false, false
				if @syl == nil and @char != nil
					@syl = @char
					patched_syl = true
				if @line == nil and @orgline != nil
					@line = @orgline
					patched_line = true
				retvals = {f ...}
				@syl = nil if patched_syl
				@line = nil if patched_line
				table.unpack retvals

			@ln.tag.pos = monkey_patch @ln.tag.pos
			@ln.tag.move = monkey_patch @ln.tag.move

		@retime = _retime @
		@relayer = _relayer @
		@maxloop = _maxloop @
		@set = _set @

-- Iterate over all sub lines, collecting those that are code chunks, templates, or mixins.
parse_templates = (subs, tenv) ->
	components =
		code: {once: {}, line: {}, word: {}, syl: {}, char: {}}
		template: {line: {}, word: {}, syl: {}, char: {}}
		mixin: {line: {}, word: {}, syl: {}, char: {}}

	interested_styles = {}

	aegisub.progress.set 0

	for i, line in ipairs subs
		error = error -- TODO: define local wrapper function that gives context

		continue unless line.class == 'dialogue' and line.comment

		effect = line.effect\gsub('^ *', '')\gsub(' *$', '')
		first_word = effect\gsub(' .*', '')
		continue unless components[first_word] != nil

		modifiers = [word for word in effect\gmatch '[^ ]+']
		line_type, classifier = modifiers[1], modifiers[2]

		if classifier == 'once' and line_type != 'code'
			error 'The `once` classifier is only valid on `code` lines.'

		interested_styles[line.style] = true unless classifier == 'once'

		component =
			interested_styles: {[line.style]: true}
			interested_layers: nil
			interested_actors: nil
			interested_template_actors: nil
			repetitions: {}
			repetition_order: {}
			condition: nil
			cond_is_negated: false
			keep_tags: false
			multi: false
			noblank: false
			notext: false
			merge_tags: true
			strip_trailing_space: true
			layer: line.layer
			template_actor: line.actor

			func: nil -- present on `code` lines
			text: nil -- present on `template` and `mixin` lines

		if line_type == 'code'
			func, err = load line.text, 'code line', 't', tenv
			error err if err != nil

			component.func = func
		else
			component.text = line.text

		j = 3
		while j <= #modifiers
			modifier = modifiers[j]
			j += 1
			switch modifier
				when 'cond', 'if', 'unless'
					if component.condition != nil
						error 'Encountered multiple `cond` modifiers on a single component.'
					path = modifiers[j]
					j += 1
					for pattern in *{'[^A-Za-z0-9_.]', '%.%.', '^[0-9.]', '%.$'}
						if path\match pattern
							error "Invalid condition path: #{path}"
					component.condition = path
					if modifier == 'unless'
						component.cond_is_negated = true

				when 'loop', 'repeat'
					loop_var, loop_count = modifiers[j], tonumber modifiers[j + 1]
					j += 2
					if component.repetitions[loop_var] != nil
						error "Encountered multiple `#{loop_var}` repetitions on a single component."
					component.repetitions[loop_var] = loop_count
					table.insert component.repetition_order, loop_var

				when 'style'
					style_name = modifiers[j]
					j += 1
					interested_styles[style_name] = true
					component.interested_styles[style_name] = true

				when 'anystyle'
					interested_styles = all_styles
					component.interested_styles = all_styles

				when 'noblank'
					if classifier == 'once'
						error 'The `noblank` modifier is invalid for `once` components.'
					component.noblank = true

				when 'keeptags', 'multi'
					unless classifier == 'syl'
						error "The `#{modifier}` modifier is only valid for `syl` components."
					error "The `#{modifier}` modifier is not yet implemented."

				when 'notext'
					unless line_type == 'template'
						error 'The `notext` modifier is only valid for templates.'
					component.notext = true

				when 'layer'
					unless line_type == 'mixin'
						error 'The `layer` modifier is only valid for mixins.'
					layer = tonumber modifiers[j]
					if layer == nil
						error "Invalid layer number: `#{modifiers[j]}`"
					j += 1
					component.interested_layers or= {}
					component.interested_layers[layer] = true

				when 'actor'
					if classifier == 'once'
						error 'The `actor` modifier is invalid for `once` components.'
					actor = modifiers[j]
					j += 1
					component.interested_actors or= {}
					component.interested_actors[actor] = true

				when 't_actor'
					unless line_type == 'mixin'
						error 'The `t_actor` modifier is only valid for mixins.'
					actor = modifiers[j]
					j += 1
					component.interested_template_actors or= {}
					component.interested_template_actors[actor] = true

				when 'nomerge'
					unless line_type == 'template'
						error 'The `nomerge` modifier is only valid for templates.'
					component.merge_tags = false

				when 'keepspace'
					unless line_type == 'template'
						error 'The `keepspace` modifier is only valid for templates.'
					component.strip_trailing_space = false

				else
					error "Unhandled modifier: `#{modifier}`"


		category = components[line_type]
		if category == nil
			error "Unhandled line type: `#{line_type}`"

		group = category[classifier]
		if group == nil
			error "Unhandled classifier: `#{line_type} #{classifier}`"

		table.insert group, component

		aegisub.progress.set 100 * i / #subs

	components, interested_styles

-- Delete subtitle lines generated by previous templater invocations.
remove_old_output = (subs) ->
	is_fx = (line) ->
		return false unless line.class == 'dialogue'
		return false unless line.effect == 'fx'
		return false if line.comment
		true

	subs.delete [i for i, line in ipairs subs when is_fx line]

-- Collect all lyrics that are fed into templates.
collect_template_input = (subs, interested_styles) ->
	is_kara = (line) ->
		return false unless line.class == 'dialogue'
		return false unless line.effect == 'karaoke' or line.effect == 'kara'
		return false unless interested_styles[line.style]
		true

	[line for line in *subs when is_kara line]

-- Add additional data to the syls generated by karaskel.
preproc_syls = (line) ->
	assert line.syls == nil, 'karaskel populated line.syls (this is unexpected)'
	line.syls = line.kara
	for syl in *line.syls
		with syl
			.is_blank = (#.text_stripped == 0)
			.is_space = (#.text_spacestripped == 0 and not .is_blank)

-- Generate word objects resembling the syl objects karaskel makes.
preproc_words = (line) ->
	line.words = {}
	current_word = {syls: {}}

	local seen_space
	seen_space = false

	for syl in *line.syls
		if #syl.prespace > 0 and #line.words > 0
			seen_space = true

		if seen_space and not syl.is_space
			table.insert line.words, current_word
			current_word = {syls: {}}
			seen_space = false

		syl.word = current_word
		table.insert current_word.syls, syl

		if syl.is_space or #syl.postspace > 0
			seen_space = true

	if #line.syls > 0
		assert #current_word.syls > 0, 'there should always be a word left over when the loop ends'
		table.insert line.words, current_word

	for i, word in ipairs line.words
		with word
			first_syl = .syls[1]
			last_syl = .syls[#.syls]

			.text = table.concat [syl.text for syl in *.syls]
			.text_stripped = table.concat [syl.text_stripped for syl in *.syls]
			.kdur = 0
			.line = line
			.i = i
			.prespace = first_syl.prespace
			.postspace = last_syl.postspace
			.text_spacestripped = .text_stripped\gsub('^[ \t]*', '')\gsub('[ \t]*$', '')
			.width = 0
			.height = 0
			.prespacewidth = first_syl.prespacewidth
			.postspacewidth = last_syl.postspacewidth
			.left = first_syl.left
			.right = last_syl.right
			.center = (.left + .right) / 2

			for syl in *.syls
				.kdur += syl.kdur
				.width += syl.width
				.height = math.max .height, syl.height

			.is_blank = (#.text_stripped == 0)
			.is_space = (#.text_spacestripped == 0 and not .is_blank)

-- Generate char objects resembling the syl objects karaskel creates.
preproc_chars = (line) ->
	line.chars = {}
	i = 1
	left = 0
	for word in *line.words
		word.chars = {}
		for syl in *word.syls
			syl.chars = {}
			for ch in unicode.chars syl.text_stripped
				char = {:syl, :word, :line, :i}
				char.text = ch
				char.is_space = (ch == ' ' or ch == '\t') -- matches karaskel behavior
				char.chars = {char}

				char.width, char.height, char.descent, _ = aegisub.text_extents line.styleref, ch
				char.left = left
				char.center = left + char.width/2
				char.right = left + char.width

				left += char.width

				table.insert syl.chars, char
				table.insert word.chars, char
				table.insert line.chars, char

				i += 1

	-- TODO: more karaskel-esque info for char objects

-- Give all objects within a line information about their position in terms of words, syls, and chars.
populate_indices = (line) ->
	wi, si, ci = 1, 1, 1
	line.wi, line.si, line.ci = wi, si, ci
	for word in *line.words
		word.wi, word.si, word.ci = wi, si, ci
		for syl in *word.syls
			syl.wi, syl.si, syl.ci = wi, si, ci
			for char in *syl.chars
				char.wi, char.si, char.ci = wi, si, ci
				ci += 1
			si += 1
		wi += 1

-- Populate lines with extra information necessary for template evaluation.
-- Includes both karaskel preprocessing and some additional custom data.
preproc_lines = (subs, meta, styles, lines) ->
	aegisub.progress.set 0
	for i, line in ipairs lines
		karaskel.preproc_line subs, meta, styles, line

		line.is_blank = (#line.text_stripped == 0)
		line.is_space = (line.text_stripped\find('[^ \t]') == nil)

		preproc_syls line
		preproc_words line
		preproc_chars line
		populate_indices line

		aegisub.progress.set 100 * i / #lines

-- Traverse a path such as foo.bar.baz within a table.
traverse_path = (path, root) ->
	node = root
	for segment in path\gmatch '[^.]+'
		node = node[segment]
		break if node == nil
	node

-- If a component has a `cond` predicate, determine whether that predicate is satisfied.
eval_cond = (path, tenv) ->
	return true if path == nil
	cond = traverse_path(path, tenv)
	switch cond
		when nil then error "Condition not found: #{path}", 2
		when true, false then cond
		else not (not cond!)

-- Determine whether a component should be executed at all.
-- If using `loop`, runs on every iteration.
should_eval = (component, tenv, obj, base_component) ->
	if tenv.orgline != nil
		-- `orgline` is nil iff the component is a `once` component.
		-- Style filtering is irrelevant for `once` components.
		return false unless component.interested_styles[tenv.orgline.style]

	-- man this syntax looks like a mistake compared to rust's `if let Some(...) = ... {`
	if layers = component.interested_layers
		-- Only mixins can have a `layer` modifier.
		return false unless layers[tenv.line.layer]
	
	if actors = component.interested_actors
		-- Actor filtering is irrelevant for `once` components.
		return false unless actors[tenv.orgline.actor]

	if actors = component.interested_template_actors
		-- Only mixins can have a `t_actor` modifier.
		return false unless actors[base_component.template_actor]

	if component.noblank
		-- `obj` is nil iff the component is a `once` component.
		-- No-blank filtering is irrelevant for `once` components.
		return false if obj.is_blank or obj.is_space

	cond_val = eval_cond component.condition, tenv
	if component.cond_is_negated
		return false if cond_val
	else
		return false unless cond_val

	true

-- Evaluate a dollar-variable.
eval_inline_var = (tenv) -> (var) ->
	syl = tenv.syl or tenv.char.syl
	val = switch var
		when '$sylstart' then syl.start_time
		when '$sylend' then syl.end_time
		when '$syldur' then syl.duration
		else
			if var\sub(1, 6) == '$loop_'
				loop_var = var\sub 7
				tenv.loopctx.state[loop_var]
			elseif var\sub(1, 9) == '$maxloop_'
				loop_var = var\sub 10
				tenv.loopctx.max[loop_var]
			else
				error "Unrecognized inline variable: #{var}"

	tostring val

-- Evaluate an inline Lua expression.
eval_inline_expr = (tenv) -> (expr) ->
	expr = expr\sub 2, -2 -- remove the `!`s
	func_body = "return (#{expr});"
	func, err = load func_body, "inline expression `#{func_body}`", t, tenv
	error err if err != nil
	val = func!
	if val == nil then '' else tostring(val)

-- Expand dollar-variables and inline Lua expressions within a template or mixin.
eval_body = (text, tenv) ->
	text\gsub('%$[a-z_]+', eval_inline_var tenv)\gsub('!.-!', eval_inline_expr tenv)

-- A collection of variables to iterate over in a particular order.
class loopctx
	new: (component) =>
		@vars = component.repetition_order
		@state = {var, 1 for var in *@vars}
		@max = component.repetitions
		@done = false

	incr: =>
		if #@vars == 0
			@done = true
			return

		@state[@vars[1]] += 1
		for i, var in ipairs @vars
			next_var = @vars[i + 1]
			if @state[var] > @max[var]
				if next_var != nil
					@state[var] = 1
					@state[next_var] += 1
				else
					@done = true
					return

-- Given a map of char indices to prepended text, evaluate the each mixin's body and insert its text at the appropriate index.
apply_mixins = (template, mixins, objs, tenv, tags, cls) ->
	for obj in *objs
		did_insert = false
		if tenv[cls] == nil
			tenv[cls] = obj
			did_insert = true

		for mixin in *mixins
			if should_eval mixin, tenv, obj, template
				ci = if cls == 'line' then 0 else obj.ci
				tags[ci] or= {}
				tag = eval_body mixin.text, tenv
				table.insert tags[ci], tag

		if did_insert
			tenv[cls] = nil

-- Combine the prefix generated from the `template` with the results of `apply_mixins` and the line's text itself.
build_text = (prefix, chars, tags, template) ->
	segments = {prefix}
	if tags[0]
		table.insert segments, tag for tag in *tags[0]
	for char in *chars
		if tags[char.ci] != nil
			table.insert segments, tag for tag in *tags[char.ci]
		unless template.notext
			table.insert segments, char.text

	table.concat segments

-- Where the magic happens. Run code, run templates, run components.
apply_templates = (subs, lines, components, tenv) ->
	run_code = (cls, orgobj) ->
		for code in *components.code[cls]
			tenv.loopctx = loopctx code
			while not tenv.loopctx.done
				if should_eval code, tenv, orgobj
					code.func!
				tenv.loopctx\incr!
			tenv.loopctx = nil
	
	run_mixins = (classes, template) ->
		tags = {}
		for cls in *classes
			mixins = components.mixin[cls]
			objs = if cls == 'line' then {tenv.line} else tenv.line[cls .. 's']
			apply_mixins template, mixins, objs, tenv, tags, cls
		tags

	run_templates = (cls, orgobj) ->
		for template in *components.template[cls]
			tenv.template_actor = template.template_actor
			tenv.loopctx = loopctx template
			while not tenv.loopctx.done
				if should_eval template, tenv, orgobj
					with tenv.line = table.copy tenv.orgline
						.comment = false
						.effect = 'fx'
						.layer = template.layer
						-- TODO: all this mutable access to the original is super sketchy. do something about it?
						.chars = orgobj.chars
						.words, .syls = switch cls
							when 'line' then .words, .syls
							when 'word' then {orgobj}, orgobj.syls
							when 'syl' then nil, {orgobj}
							when 'char' then nil, nil

						-- I have no idea what I'm doing.
						--ci_offset = orgobj.chars[1].ci - 1
						--char.i -= ci_offset for char in *.chars

						--if .syls
						--	si_offset = .syls[1].si - 1
						--	syl.i -= si_offset for syl in *.syls

						--if .words
						--	wi_offset = .words[1].wi - 1
						--	word.i -= wi_offset for word in *.words

					prefix = eval_body template.text, tenv
					mixin_classes = switch cls
						when 'line', 'word' then {'line', 'word', 'syl', 'char'}
						when 'syl' then {'line', 'syl', 'char'}
						when 'char' then {'line', 'char'}

					tags = run_mixins mixin_classes, template
					tenv.line.text = build_text prefix, tenv.line.chars, tags, template

					if template.merge_tags
						-- A primitive way of doing this. Patches welcome.
						-- Otherwise, if you're doing something fancy enough that this breaks it and `nomerge` isn't acceptable, you're on your own.
						tenv.line.text = tenv.line.text\gsub '}{', ''

					if template.strip_trailing_space
						-- Less primitive than the above thing, but still primitive. Might have worst-case quadratic performance.
						tenv.line.text = tenv.line.text\gsub ' *$', ''

					subs.append tenv.line

					tenv.line = nil
				tenv.loopctx\incr!
			tenv.loopctx = nil

	run_code 'once'

	for orgline in *lines
		tenv.orgline = orgline
		run_code 'line'
		run_templates 'line', orgline

		for orgword in *orgline.words
			tenv.word = orgword
			run_code 'word', orgword
			run_templates 'word', orgword
			tenv.word = nil

		for orgsyl in *orgline.syls
			tenv.syl = orgsyl
			-- TODO: `multi` support
			run_code 'syl', orgsyl
			run_templates 'syl', orgsyl
			tenv.syl = nil

		for orgchar in *orgline.chars
			tenv.char = orgchar
			run_code 'char', orgchar
			run_templates 'char', orgchar
			tenv.char = nil

		tenv.orgline = nil

-- Entry point
main = (subs, sel, active) ->
	math.randomseed os.time!

	task = aegisub.progress.task

	task 'Collecting header data...'
	meta, styles = karaskel.collect_head subs, false

	tenv = template_env subs, meta, styles

	task 'Parsing templates...'
	components, interested_styles = parse_templates subs, tenv

	task 'Removing old template output...'
	remove_old_output subs

	task 'Collecting template input...'
	lines = collect_template_input subs, interested_styles

	task 'Preprocessing template input...'
	preproc_lines subs, meta, styles, lines

	task 'Applying templates...'
	apply_templates subs, lines, components, tenv

	aegisub.set_undo_point 'apply karaoke template'

aegisub.register_macro '0x539\'s Templater', 'no description', main
