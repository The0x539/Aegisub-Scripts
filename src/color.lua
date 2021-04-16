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

	r, g, b = r*100, g*100, b*100

	local x = r*0.4124 + g*0.3576 + b*0.1805
	local y = r*0.2126 + g*0.7152 + b*0.0722
	local z = r*0.0193 + g*0.1192 + b*0.9505

	return x, y, z
end

local function RGBfromXYZ(x, y, z)
	x, y, z = x/100, y/100, z/100

	local r = x*3.2406 + y*-1.5372 + z*-0.4986
	local g = x*-0.9689 + y*1.8758 + z*0.0415
	local b = x*0.0557 + y*-0.2040 + z*1.0570

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
	local Xn, Yn, Zn = 95.047, 100.000, 108.883

	x, y, z = x/Xn, y/Yn, z/Zn

	local function f(n)
		if n > 0.008856 then
			return math.pow(n, 1/3)
		else
			return (7.787 * n) + (16/116)
		end
	end
	x, y, z = f(x), f(y), f(z)

	local l
	if y > 0.008856 then
		l = (116 * y) - 16
	else
		l = 903.3 * y
	end
	local a = 500 * (x - y)
	local b = 200 * (y - z)

	return l, a, b
end

local function XYZfromLAB(l, a, b)
	local ref_X, ref_Y, ref_Z = 95.047, 100.000, 108.883

	local y = (l + 16) / 116
	local x = a/500 + y
	local z = y - b/200

	local function f(n)
		if n^3 > 0.008856 then
			return n^3
		else
			return (n - 16/116) / 7.787
		end
	end
	x, y, z = f(x), f(y), f(z)

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

local function parse_ass(c) -- "&H3F7F9F&"
	local b = c:sub(3,4)
	local g = c:sub(5,6)
	local r = c:sub(7,8)
	
	return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

local function fmt_ass(r, g, b)
	r, g, b = math.floor(r+0.5), math.floor(g+0.5), math.floor(b+0.5)
	return ("&H%02X%02X%02X&"):format(b, g, r)
end

local function interp_lch(t, color_1, color_2)
	local l1, c1, h1 = LCHfromLAB(LABfromXYZ(XYZfromRGB(parse_ass(color_1))))
	local l2, c2, h2 = LCHfromLAB(LABfromXYZ(XYZfromRGB(parse_ass(color_2))))
	local l, c, h = interpolateLCh(t, l1, c1, h1, l2, c2, h2)
	local r, g, b = RGBfromXYZ(XYZfromLAB(LABfromLCH(l, c, h)))
	return fmt_ass(r, g, b)
end

local function interp_lab(t, color_1, color_2)
	local l1, a1, b1 = LABfromXYZ(XYZfromRGB(parse_ass(color_1)))
	local l2, a2, b2 = LABfromXYZ(XYZfromRGB(parse_ass(color_2)))
	local l, a, b = interpolate(t, l1, a1, b1, l2, a2, b2)
	local r, g, b = RGBfromXYZ(XYZfromLAB(l, a, b))
	return fmt_ass(r, g, b)
end

local function interp_xyz(t, color_1, color_2)
	local x1, y1, z1 = XYZfromRGB(parse_ass(color_1))
	local x2, y2, z2 = XYZfromRGB(parse_ass(color_2))
	local x, y, z = interpolate(t, x1, y1, z1, x2, y2, z2)
	local r, g, b = RGBfromXYZ(x, y, z)
	return fmt_ass(r, g, b)
end

local function interp_rgb(t, color_1, color_2)
	local r1, g1, b1 = parse_ass(color_1)
	local r2, g2, b2 = parse_ass(color_2)
	local r, g, b = interpolate(t, r1, g1, b1, r2, g2, b2)
	return fmt_ass(r, g, b)
end

return {
	interp_lch = interp_lch,
	interp_lab = interp_lab,
	interp_xyz = interp_xyz,
	interp_rgb = interp_rgb
}
