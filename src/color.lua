local function XYZfromRGB(r, g, b)
	r, g, b = r/0xFF, g/0xFF, b/0xFF

	local function f(n)
		if n > 0.04045 then
			return math.pow(((n + 0.055) / 1.055), 2.4)
		else
			return n / 12.92
		end
	end
	r, g, b = f(r), f(g), f(b)

	local x = r*0.4124564 + g*0.3575761 + b*0.1804375
	local y = r*0.2126729 + g*0.7151522 + b*0.0721750
	local z = r*0.0193339 + g*0.1191920 + b*0.9503041

	return x, y, z
end

local function RGBfromXYZ(x, y, z)
	local r = x*3.2404542 + y*-1.5371385 + z*-0.4985314
	local g = x*-0.9692660 + y*1.8760108 + z*0.0415560
	local b = x*0.0556434 + y*-0.2040259 + z*1.0572252

	local function f(n)
		if n > 0.0031308 then
			return 1.055 * math.pow(n, 1/2.4) - 0.055
		else
			return 12.92*n
		end
	end
	r, g, b = f(r), f(g), f(b)
	
	local function clamp(n)
		return math.min(math.max(n*255, 0), 255)
	end
	return clamp(r), clamp(g), clamp(b)
end

local function LABfromXYZ(x, y, z)
	local Xn, Yn, Zn = 0.95047, 1.0, 1.08883

	x, y, z = x/Xn, y/Yn, z/Zn

	local function f(n)
		if n > 0.008856 then
			return math.pow(n, 1/3)
		else
			return (903.3 * n + 16) / 116
		end
	end
	x, y, z = f(x), f(y), f(z)

	local l = (116 * y) - 16
	local a = 500 * (x - y)
	local b = 200 * (y - z)

	return l, a, b
end

local function XYZfromLAB(l, a, b)
	local ref_X, ref_Y, ref_Z = 0.95047, 1.0, 1.08883

	local y = (l + 16) / 116
	local x = a/500 + y
	local z = y - b/200

	local function fxz(n)
		if n^3 > 0.008856 then
			return n^3
		else
			return (116 * n - 16) / 903.3
		end
	end

	x, z = fxz(x), fxz(z)
	if l > (903.3 * 0.008856) then
		y = y^3
	else
		y = l / 903.3
	end

	return x*ref_X, y*ref_Y, z*ref_Z
end

local function LCHfromLAB(l, a, b)
	-- l is unchanged
	local c = math.sqrt(a*a + b*b)
	local h = math.atan2(b, a) * 180/math.pi
	h = h % 360
	
	return l, c, h
end

local function LABfromLCH(l, c, h)
	-- l is unchanged
	local hr = h * math.pi/180
	local a = math.cos(hr) * c
	local b = math.sin(hr) * c

	return l, a, b
end

local function interpolateLCh(t, l1, c1, h1, l2, c2, h2)
	local l = (1-t)*l1 + t*l2
	local c = (1-t)*c1 + t*c2

	if h2 - h1 >= 180 then
		h2 = h2 - 360
	elseif h1 - h2 >= 180 then
		h1 = h1 - 360
	end
	local h = (1-t)*h1 + t*h2
	h = h % 360
	return l, c, h
end

local function interpolate(t, a1, b1, c1, a2, b2, c2)
	local a = (1-t)*a1 + t*a2
	local b = (1-t)*b1 + t*b2
	local c = (1-t)*c1 + t*c2
	return a, b, c
end

local function lighten(x, y, z, amount, space)
	-- amount: value between -1 and 1
	-- 		   (though *technically* absolutely larger values) work too
	space = space or "lab"
	local l,a,b
	if space == "lch" or space == "lab" then
		l = x
	elseif space == "rgb" then
		l,a,b = LABfromXYZ(XYZfromRGB(x,y,z))
	elseif space == "xyz" then
		l,a,b = LABfromXYZ(x,y,z)
	else
		-- invalid colorspace requested, give up gracefully
		return x, y, z
	end

	if amount > 0 then
		local diff = 100 - l
		l = l + diff * amount
	else
		local diff = l
		l = l + diff * amount
	end

	if space == "lch" or space == "lab" then
		return l,y,z
	elseif space == "rgb" then
		return RGBfromXYZ(XYZfromLAB(l,a,b))
	elseif space == "xyz" then
		return XYZfromLAB(l,a,b)
	end
end

local function round(n)
	return math.floor(n + 0.5)
end

-- parse_ass_color helper function
-- sometimes you really wonder why someone used a signed integer
local function u32_from_f64(n)
	n = math.max(n, 0)
	n = math.min(n, 0xFFFFFFFF)
	n = round(n)
	return n
end

local function u8_from_f64(n)
	n = math.max(n, 0)
	n = math.min(n, 0xFF)
	n = round(n)
	return n
end

-- behavior is reasonably close to that of libass
-- quite possibly overengineered
local function parse_ass_color(c)
	-- skip *specific* leading garbage
	c = c:gsub('^[&H]*', '')

	-- this part specifically does not match the libass implementation.
	-- tonumber rejects (some) trailing garbage, but ass_strtod ignores it
	c = c:match('^[0-9A-Fa-f]*')

	local rgb = u32_from_f64(tonumber(c, 16) or 0)

	local bit = require('bit')
	local r = bit.rshift(bit.band(rgb, 0x000000FF), 0)
	local g = bit.rshift(bit.band(rgb, 0x0000FF00), 8)
	local b = bit.rshift(bit.band(rgb, 0x00FF0000), 16)
	return r, g, b
end

local function parse_ass_alpha(a)
	if type(a) == 'number' then
		return a
	end

	a = a:gsub('^[&H]*', '')
	a = a:match('^[0-9A-Fa-f]*')

	return u8_from_f64(tonumber(a, 16) or 0)
end

local function fmt_ass_color(r, g, b)
	r, g, b = round(r), round(g), round(b)
	return ("&H%02X%02X%02X&"):format(b, g, r)
end

local function fmt_ass_alpha(a)
	a = round(a)
	return ("&H%02X&"):format(a)
end

local function interp_lch(t, color_1, color_2)
	local l1, c1, h1 = LCHfromLAB(LABfromXYZ(XYZfromRGB(parse_ass_color(color_1))))
	local l2, c2, h2 = LCHfromLAB(LABfromXYZ(XYZfromRGB(parse_ass_color(color_2))))
	local l, c, h = interpolateLCh(t, l1, c1, h1, l2, c2, h2)
	local r, g, b = RGBfromXYZ(XYZfromLAB(LABfromLCH(l, c, h)))
	return fmt_ass_color(r, g, b)
end

local function interp_lab(t, color_1, color_2)
	local l1, a1, b1 = LABfromXYZ(XYZfromRGB(parse_ass_color(color_1)))
	local l2, a2, b2 = LABfromXYZ(XYZfromRGB(parse_ass_color(color_2)))
	local l, a, b = interpolate(t, l1, a1, b1, l2, a2, b2)
	local r, g, b = RGBfromXYZ(XYZfromLAB(l, a, b))
	return fmt_ass_color(r, g, b)
end

local function interp_xyz(t, color_1, color_2)
	local x1, y1, z1 = XYZfromRGB(parse_ass_color(color_1))
	local x2, y2, z2 = XYZfromRGB(parse_ass_color(color_2))
	local x, y, z = interpolate(t, x1, y1, z1, x2, y2, z2)
	local r, g, b = RGBfromXYZ(x, y, z)
	return fmt_ass_color(r, g, b)
end

local function interp_rgb(t, color_1, color_2)
	local r1, g1, b1 = parse_ass_color(color_1)
	local r2, g2, b2 = parse_ass_color(color_2)
	local r, g, b = interpolate(t, r1, g1, b1, r2, g2, b2)
	return fmt_ass_color(r, g, b)
end

local function interp_alpha(t, alpha_1, alpha_2)
	local a1 = parse_ass_alpha(alpha_1)
	local a2 = parse_ass_alpha(alpha_2)

	local a = (1-t)*a1 + t*a2
	return fmt_ass_alpha(a)
end

local fmt_rgb = fmt_ass_color

local function fmt_xyz(x, y, z)
	local r, g, b = RGBfromXYZ(x, y, z)
	return fmt_ass_color(r, g, b)
end

local function fmt_lab(l, a, b)
	local r, g, b = RGBfromXYZ(XYZfromLAB(l, a, b))
	return fmt_ass_color(r, g, b)
end

local function fmt_lch(l, c, h)
	local r, g, b = RGBfromXYZ(XYZfromLAB(LABfromLCH(l, c, h)))
	return fmt_ass_color(r, g, b)
end

local function lighten_ass(c, amount)
	local r, g, b = parse_ass_color(c)
	r, g, b = lighten(r, g, b, amount, "rgb")
	return fmt_ass_color(r, g, b)
end

local function darken_ass(c, amount)
	return lighten_ass(c, amount)
end

return {
	interp_lch = interp_lch,
	interp_lab = interp_lab,
	interp_xyz = interp_xyz,
	interp_rgb = interp_rgb,
	fmt_rgb = fmt_rgb,
	fmt_xyz = fmt_xyz,
	fmt_lab = fmt_lab,
	fmt_lch = fmt_lch,
	interp_alpha = interp_alpha,
	fmt_alpha = fmt_ass_alpha,
	lighten = lighten_ass,
	darken = darken_ass,
	lighten_complex = lighten,
}
