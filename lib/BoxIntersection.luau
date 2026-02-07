--!native
--!strict

--from AxisAngle
local function boxInBox(cframe0: CFrame, size0: Vector3, cframe1: CFrame, size1: Vector3): boolean
	local m00, m01, m02, m03, m04, m05, m06, m07, m08, m09, m10, m11 = cframe0:GetComponents()
	local m12, m13, m14, m15, m16, m17, m18, m19, m20, m21, m22, m23 = cframe1:GetComponents()
	local m24, m25, m26 = size0.X / 2, size0.Y / 2, size0.Z / 2
	local m27, m28, m29 = size1.X / 2, size1.Y / 2, size1.Z / 2
	local m30, m31, m32 = m12 - m00, m13 - m01, m14 - m02
	local m00 = m03 * m30 + m06 * m31 + m09 * m32
	local m01 = m04 * m30 + m07 * m31 + m10 * m32
	local m02 = m05 * m30 + m08 * m31 + m11 * m32
	local m12 = m15 * m30 + m18 * m31 + m21 * m32
	local m13 = m16 * m30 + m19 * m31 + m22 * m32
	local m14 = m17 * m30 + m20 * m31 + m23 * m32
	local m30 = m12 > m27 and m12 - m27 or m12 < -m27 and m12 + m27 or 0
	local m31 = m13 > m28 and m13 - m28 or m13 < -m28 and m13 + m28 or 0
	local m32 = m14 > m29 and m14 - m29 or m14 < -m29 and m14 + m29 or 0
	local m33 = m00 > m24 and m00 - m24 or m00 < -m24 and m00 + m24 or 0
	local m34 = m01 > m25 and m01 - m25 or m01 < -m25 and m01 + m25 or 0
	local m35 = m02 > m26 and m02 - m26 or m02 < -m26 and m02 + m26 or 0
	local m36 = m30 * m30 + m31 * m31 + m32 * m32
	local m30 = m33 * m33 + m34 * m34 + m35 * m35
	local m31 = m24 < m25 and (m24 < m26 and m24 or m26) or (m25 < m26 and m25 or m26) :: number
	local m32 = m27 < m28 and (m27 < m29 and m27 or m29) or (m28 < m29 and m28 or m29) :: number
	if m36 < m31 * m31 or m30 < m32 * m32 then
		return true
	elseif m36 > m24 * m24 + m25 * m25 + m26 * m26 or m30 > m27 * m27 + m28 * m28 + m29 * m29 then
		return false
	else
		local m30 = m03 * m15 + m06 * m18 + m09 * m21
		local m31 = m03 * m16 + m06 * m19 + m09 * m22
		local m32 = m03 * m17 + m06 * m20 + m09 * m23
		local m03 = m04 * m15 + m07 * m18 + m10 * m21
		local m06 = m04 * m16 + m07 * m19 + m10 * m22
		local m09 = m04 * m17 + m07 * m20 + m10 * m23
		local m04 = m05 * m15 + m08 * m18 + m11 * m21
		local m07 = m05 * m16 + m08 * m19 + m11 * m22
		local m10 = m05 * m17 + m08 * m20 + m11 * m23
		local m05 = m29 * m29
		local m08 = m27 * m27
		local m11 = m28 * m28
		local m15 = m24 * m30
		local m16 = m25 * m03
		local m17 = m26 * m04
		local m18 = m24 * m31
		local m19 = m25 * m06
		local m20 = m26 * m07
		local m21 = m24 * m32
		local m22 = m25 * m09
		local m23 = m26 * m10
		local m33 = m15 + m16 + m17 - m12
		if m33 * m33 < m08 then
			local m34 = m18 + m19 + m20 - m13
			if m34 * m34 < m11 then
				local m35 = m21 + m22 + m23 - m14
				if m35 * m35 < m05 then
					return true
				end
			end
		end
		local m33 = -m15 + m16 + m17 - m12
		if m33 * m33 < m08 then
			local m34 = -m18 + m19 + m20 - m13
			if m34 * m34 < m11 then
				local m35 = -m21 + m22 + m23 - m14
				if m35 * m35 < m05 then
					return true
				end
			end
		end
		local m33 = m15 - m16 + m17 - m12
		if m33 * m33 < m08 then
			local m34 = m18 - m19 + m20 - m13
			if m34 * m34 < m11 then
				local m35 = m21 - m22 + m23 - m14
				if m35 * m35 < m05 then
					return true
				end
			end
		end
		local m33 = -m15 - m16 + m17 - m12
		if m33 * m33 < m08 then
			local m34 = -m18 - m19 + m20 - m13
			if m34 * m34 < m11 then
				local m35 = -m21 - m22 + m23 - m14
				if m35 * m35 < m05 then
					return true
				end
			end
		end
		local m33 = m15 + m16 - m17 - m12
		if m33 * m33 < m08 then
			local m34 = m18 + m19 - m20 - m13
			if m34 * m34 < m11 then
				local m35 = m21 + m22 - m23 - m14
				if m35 * m35 < m05 then
					return true
				end
			end
		end
		local m33 = -m15 + m16 - m17 - m12
		if m33 * m33 < m08 then
			local m34 = -m18 + m19 - m20 - m13
			if m34 * m34 < m11 then
				local m35 = -m21 + m22 - m23 - m14
				if m35 * m35 < m05 then
					return true
				end
			end
		end
		local m33 = m15 - m16 - m17 - m12
		if m33 * m33 < m08 then
			local m34 = m18 - m19 - m20 - m13
			if m34 * m34 < m11 then
				local m35 = m21 - m22 - m23 - m14
				if m35 * m35 < m05 then
					return true
				end
			end
		end
		local m33 = -m15 - m16 - m17 - m12
		if m33 * m33 < m08 then
			local m34 = -m18 - m19 - m20 - m13
			if m34 * m34 < m11 then
				local m35 = -m21 - m22 - m23 - m14
				if m35 * m35 < m05 then
					return true
				end
			end
		end
		local m12 = m24 * m24
		local m13 = m25 * m25
		local m14 = m26 * m26
		local m15 = m27 * m04
		local m16 = m28 * m07
		local m17 = m27 * m30
		local m18 = m28 * m31
		local m19 = m27 * m03
		local m20 = m28 * m06
		local m21 = m29 * m10
		local m22 = m29 * m32
		local m23 = m29 * m09
		local m35 = (m02 - m26 + m15 + m16) / m10
		if m35 * m35 < m05 then
			local m33 = m00 + m17 + m18 - m35 * m32
			if m33 * m33 < m12 then
				local m34 = m01 + m19 + m20 - m35 * m09
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 + m26 + m15 + m16) / m10
		if m35 * m35 < m05 then
			local m33 = m00 + m17 + m18 - m35 * m32
			if m33 * m33 < m12 then
				local m34 = m01 + m19 + m20 - m35 * m09
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 - m26 - m15 + m16) / m10
		if m35 * m35 < m05 then
			local m33 = m00 - m17 + m18 - m35 * m32
			if m33 * m33 < m12 then
				local m34 = m01 - m19 + m20 - m35 * m09
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 + m26 - m15 + m16) / m10
		if m35 * m35 < m05 then
			local m33 = m00 - m17 + m18 - m35 * m32
			if m33 * m33 < m12 then
				local m34 = m01 - m19 + m20 - m35 * m09
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 - m26 + m15 - m16) / m10
		if m35 * m35 < m05 then
			local m33 = m00 + m17 - m18 - m35 * m32
			if m33 * m33 < m12 then
				local m34 = m01 + m19 - m20 - m35 * m09
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 + m26 + m15 - m16) / m10
		if m35 * m35 < m05 then
			local m33 = m00 + m17 - m18 - m35 * m32
			if m33 * m33 < m12 then
				local m34 = m01 + m19 - m20 - m35 * m09
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 - m26 - m15 - m16) / m10
		if m35 * m35 < m05 then
			local m33 = m00 - m17 - m18 - m35 * m32
			if m33 * m33 < m12 then
				local m34 = m01 - m19 - m20 - m35 * m09
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 + m26 - m15 - m16) / m10
		if m35 * m35 < m05 then
			local m33 = m00 - m17 - m18 - m35 * m32
			if m33 * m33 < m12 then
				local m34 = m01 - m19 - m20 - m35 * m09
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m00 - m24 + m17 + m18) / m32
		if m35 * m35 < m05 then
			local m33 = m01 + m19 + m20 - m35 * m09
			if m33 * m33 < m13 then
				local m34 = m02 + m15 + m16 - m35 * m10
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 + m24 + m17 + m18) / m32
		if m35 * m35 < m05 then
			local m33 = m01 + m19 + m20 - m35 * m09
			if m33 * m33 < m13 then
				local m34 = m02 + m15 + m16 - m35 * m10
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 - m24 - m17 + m18) / m32
		if m35 * m35 < m05 then
			local m33 = m01 - m19 + m20 - m35 * m09
			if m33 * m33 < m13 then
				local m34 = m02 - m15 + m16 - m35 * m10
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 + m24 - m17 + m18) / m32
		if m35 * m35 < m05 then
			local m33 = m01 - m19 + m20 - m35 * m09
			if m33 * m33 < m13 then
				local m34 = m02 - m15 + m16 - m35 * m10
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 - m24 + m17 - m18) / m32
		if m35 * m35 < m05 then
			local m33 = m01 + m19 - m20 - m35 * m09
			if m33 * m33 < m13 then
				local m34 = m02 + m15 - m16 - m35 * m10
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 + m24 + m17 - m18) / m32
		if m35 * m35 < m05 then
			local m33 = m01 + m19 - m20 - m35 * m09
			if m33 * m33 < m13 then
				local m34 = m02 + m15 - m16 - m35 * m10
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 - m24 - m17 - m18) / m32
		if m35 * m35 < m05 then
			local m33 = m01 - m19 - m20 - m35 * m09
			if m33 * m33 < m13 then
				local m34 = m02 - m15 - m16 - m35 * m10
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 + m24 - m17 - m18) / m32
		if m35 * m35 < m05 then
			local m33 = m01 - m19 - m20 - m35 * m09
			if m33 * m33 < m13 then
				local m34 = m02 - m15 - m16 - m35 * m10
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m01 - m25 + m19 + m20) / m09
		if m35 * m35 < m05 then
			local m33 = m02 + m15 + m16 - m35 * m10
			if m33 * m33 < m14 then
				local m34 = m00 + m17 + m18 - m35 * m32
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 + m25 + m19 + m20) / m09
		if m35 * m35 < m05 then
			local m33 = m02 + m15 + m16 - m35 * m10
			if m33 * m33 < m14 then
				local m34 = m00 + m17 + m18 - m35 * m32
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 - m25 - m19 + m20) / m09
		if m35 * m35 < m05 then
			local m33 = m02 - m15 + m16 - m35 * m10
			if m33 * m33 < m14 then
				local m34 = m00 - m17 + m18 - m35 * m32
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 + m25 - m19 + m20) / m09
		if m35 * m35 < m05 then
			local m33 = m02 - m15 + m16 - m35 * m10
			if m33 * m33 < m14 then
				local m34 = m00 - m17 + m18 - m35 * m32
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 - m25 + m19 - m20) / m09
		if m35 * m35 < m05 then
			local m33 = m02 + m15 - m16 - m35 * m10
			if m33 * m33 < m14 then
				local m34 = m00 + m17 - m18 - m35 * m32
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 + m25 + m19 - m20) / m09
		if m35 * m35 < m05 then
			local m33 = m02 + m15 - m16 - m35 * m10
			if m33 * m33 < m14 then
				local m34 = m00 + m17 - m18 - m35 * m32
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 - m25 - m19 - m20) / m09
		if m35 * m35 < m05 then
			local m33 = m02 - m15 - m16 - m35 * m10
			if m33 * m33 < m14 then
				local m34 = m00 - m17 - m18 - m35 * m32
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 + m25 - m19 - m20) / m09
		if m35 * m35 < m05 then
			local m33 = m02 - m15 - m16 - m35 * m10
			if m33 * m33 < m14 then
				local m34 = m00 - m17 - m18 - m35 * m32
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m02 - m26 + m16 + m21) / m04
		if m35 * m35 < m08 then
			local m33 = m00 + m18 + m22 - m35 * m30
			if m33 * m33 < m12 then
				local m34 = m01 + m20 + m23 - m35 * m03
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 + m26 + m16 + m21) / m04
		if m35 * m35 < m08 then
			local m33 = m00 + m18 + m22 - m35 * m30
			if m33 * m33 < m12 then
				local m34 = m01 + m20 + m23 - m35 * m03
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 - m26 - m16 + m21) / m04
		if m35 * m35 < m08 then
			local m33 = m00 - m18 + m22 - m35 * m30
			if m33 * m33 < m12 then
				local m34 = m01 - m20 + m23 - m35 * m03
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 + m26 - m16 + m21) / m04
		if m35 * m35 < m08 then
			local m33 = m00 - m18 + m22 - m35 * m30
			if m33 * m33 < m12 then
				local m34 = m01 - m20 + m23 - m35 * m03
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 - m26 + m16 - m21) / m04
		if m35 * m35 < m08 then
			local m33 = m00 + m18 - m22 - m35 * m30
			if m33 * m33 < m12 then
				local Axi = m01 + m20 - m23 - m35 * m03
				if Axi * Axi < m13 then
					return true
				end
			end
		end
		local m35 = (m02 + m26 + m16 - m21) / m04
		if m35 * m35 < m08 then
			local m33 = m00 + m18 - m22 - m35 * m30
			if m33 * m33 < m12 then
				local sAn = m01 + m20 - m23 - m35 * m03
				if sAn * sAn < m13 then
					return true
				end
			end
		end
		local m35 = (m02 - m26 - m16 - m21) / m04
		if m35 * m35 < m08 then
			local m33 = m00 - m18 - m22 - m35 * m30
			if m33 * m33 < m12 then
				local gle = m01 - m20 - m23 - m35 * m03
				if gle * gle < m13 then
					return true
				end
			end
		end
		local m35 = (m02 + m26 - m16 - m21) / m04
		if m35 * m35 < m08 then
			local m33 = m00 - m18 - m22 - m35 * m30
			if m33 * m33 < m12 then
				local m34 = m01 - m20 - m23 - m35 * m03
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m00 - m24 + m18 + m22) / m30
		if m35 * m35 < m08 then
			local m33 = m01 + m20 + m23 - m35 * m03
			if m33 * m33 < m13 then
				local m34 = m02 + m16 + m21 - m35 * m04
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 + m24 + m18 + m22) / m30
		if m35 * m35 < m08 then
			local m33 = m01 + m20 + m23 - m35 * m03
			if m33 * m33 < m13 then
				local m34 = m02 + m16 + m21 - m35 * m04
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 - m24 - m18 + m22) / m30
		if m35 * m35 < m08 then
			local m33 = m01 - m20 + m23 - m35 * m03
			if m33 * m33 < m13 then
				local m34 = m02 - m16 + m21 - m35 * m04
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 + m24 - m18 + m22) / m30
		if m35 * m35 < m08 then
			local m33 = m01 - m20 + m23 - m35 * m03
			if m33 * m33 < m13 then
				local m34 = m02 - m16 + m21 - m35 * m04
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 - m24 + m18 - m22) / m30
		if m35 * m35 < m08 then
			local m33 = m01 + m20 - m23 - m35 * m03
			if m33 * m33 < m13 then
				local m34 = m02 + m16 - m21 - m35 * m04
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 + m24 + m18 - m22) / m30
		if m35 * m35 < m08 then
			local m33 = m01 + m20 - m23 - m35 * m03
			if m33 * m33 < m13 then
				local m34 = m02 + m16 - m21 - m35 * m04
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 - m24 - m18 - m22) / m30
		if m35 * m35 < m08 then
			local m33 = m01 - m20 - m23 - m35 * m03
			if m33 * m33 < m13 then
				local m34 = m02 - m16 - m21 - m35 * m04
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 + m24 - m18 - m22) / m30
		if m35 * m35 < m08 then
			local m33 = m01 - m20 - m23 - m35 * m03
			if m33 * m33 < m13 then
				local m34 = m02 - m16 - m21 - m35 * m04
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m01 - m25 + m20 + m23) / m03
		if m35 * m35 < m08 then
			local m33 = m02 + m16 + m21 - m35 * m04
			if m33 * m33 < m14 then
				local m34 = m00 + m18 + m22 - m35 * m30
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 + m25 + m20 + m23) / m03
		if m35 * m35 < m08 then
			local m33 = m02 + m16 + m21 - m35 * m04
			if m33 * m33 < m14 then
				local m34 = m00 + m18 + m22 - m35 * m30
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 - m25 - m20 + m23) / m03
		if m35 * m35 < m08 then
			local m33 = m02 - m16 + m21 - m35 * m04
			if m33 * m33 < m14 then
				local m34 = m00 - m18 + m22 - m35 * m30
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 + m25 - m20 + m23) / m03
		if m35 * m35 < m08 then
			local m33 = m02 - m16 + m21 - m35 * m04
			if m33 * m33 < m14 then
				local m34 = m00 - m18 + m22 - m35 * m30
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 - m25 + m20 - m23) / m03
		if m35 * m35 < m08 then
			local m33 = m02 + m16 - m21 - m35 * m04
			if m33 * m33 < m14 then
				local m34 = m00 + m18 - m22 - m35 * m30
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 + m25 + m20 - m23) / m03
		if m35 * m35 < m08 then
			local m33 = m02 + m16 - m21 - m35 * m04
			if m33 * m33 < m14 then
				local m34 = m00 + m18 - m22 - m35 * m30
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 - m25 - m20 - m23) / m03
		if m35 * m35 < m08 then
			local m33 = m02 - m16 - m21 - m35 * m04
			if m33 * m33 < m14 then
				local m34 = m00 - m18 - m22 - m35 * m30
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 + m25 - m20 - m23) / m03
		if m35 * m35 < m08 then
			local m33 = m02 - m16 - m21 - m35 * m04
			if m33 * m33 < m14 then
				local m34 = m00 - m18 - m22 - m35 * m30
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m02 - m26 + m21 + m15) / m07
		if m35 * m35 < m11 then
			local m33 = m00 + m22 + m17 - m35 * m31
			if m33 * m33 < m12 then
				local m34 = m01 + m23 + m19 - m35 * m06
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 + m26 + m21 + m15) / m07
		if m35 * m35 < m11 then
			local m33 = m00 + m22 + m17 - m35 * m31
			if m33 * m33 < m12 then
				local m34 = m01 + m23 + m19 - m35 * m06
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 - m26 - m21 + m15) / m07
		if m35 * m35 < m11 then
			local m33 = m00 - m22 + m17 - m35 * m31
			if m33 * m33 < m12 then
				local m34 = m01 - m23 + m19 - m35 * m06
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 + m26 - m21 + m15) / m07
		if m35 * m35 < m11 then
			local m33 = m00 - m22 + m17 - m35 * m31
			if m33 * m33 < m12 then
				local m34 = m01 - m23 + m19 - m35 * m06
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 - m26 + m21 - m15) / m07
		if m35 * m35 < m11 then
			local m33 = m00 + m22 - m17 - m35 * m31
			if m33 * m33 < m12 then
				local m34 = m01 + m23 - m19 - m35 * m06
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 + m26 + m21 - m15) / m07
		if m35 * m35 < m11 then
			local m33 = m00 + m22 - m17 - m35 * m31
			if m33 * m33 < m12 then
				local m34 = m01 + m23 - m19 - m35 * m06
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 - m26 - m21 - m15) / m07
		if m35 * m35 < m11 then
			local m33 = m00 - m22 - m17 - m35 * m31
			if m33 * m33 < m12 then
				local m34 = m01 - m23 - m19 - m35 * m06
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m02 + m26 - m21 - m15) / m07
		if m35 * m35 < m11 then
			local m33 = m00 - m22 - m17 - m35 * m31
			if m33 * m33 < m12 then
				local m34 = m01 - m23 - m19 - m35 * m06
				if m34 * m34 < m13 then
					return true
				end
			end
		end
		local m35 = (m00 - m24 + m22 + m17) / m31
		if m35 * m35 < m11 then
			local m33 = m01 + m23 + m19 - m35 * m06
			if m33 * m33 < m13 then
				local m34 = m02 + m21 + m15 - m35 * m07
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 + m24 + m22 + m17) / m31
		if m35 * m35 < m11 then
			local m33 = m01 + m23 + m19 - m35 * m06
			if m33 * m33 < m13 then
				local m34 = m02 + m21 + m15 - m35 * m07
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 - m24 - m22 + m17) / m31
		if m35 * m35 < m11 then
			local m33 = m01 - m23 + m19 - m35 * m06
			if m33 * m33 < m13 then
				local m34 = m02 - m21 + m15 - m35 * m07
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 + m24 - m22 + m17) / m31
		if m35 * m35 < m11 then
			local m33 = m01 - m23 + m19 - m35 * m06
			if m33 * m33 < m13 then
				local m34 = m02 - m21 + m15 - m35 * m07
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 - m24 + m22 - m17) / m31
		if m35 * m35 < m11 then
			local m33 = m01 + m23 - m19 - m35 * m06
			if m33 * m33 < m13 then
				local m34 = m02 + m21 - m15 - m35 * m07
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 + m24 + m22 - m17) / m31
		if m35 * m35 < m11 then
			local m33 = m01 + m23 - m19 - m35 * m06
			if m33 * m33 < m13 then
				local m34 = m02 + m21 - m15 - m35 * m07
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 - m24 - m22 - m17) / m31
		if m35 * m35 < m11 then
			local m33 = m01 - m23 - m19 - m35 * m06
			if m33 * m33 < m13 then
				local m34 = m02 - m21 - m15 - m35 * m07
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m00 + m24 - m22 - m17) / m31
		if m35 * m35 < m11 then
			local m33 = m01 - m23 - m19 - m35 * m06
			if m33 * m33 < m13 then
				local m34 = m02 - m21 - m15 - m35 * m07
				if m34 * m34 < m14 then
					return true
				end
			end
		end
		local m35 = (m01 - m25 + m23 + m19) / m06
		if m35 * m35 < m11 then
			local m33 = m02 + m21 + m15 - m35 * m07
			if m33 * m33 < m14 then
				local m34 = m00 + m22 + m17 - m35 * m31
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 + m25 + m23 + m19) / m06
		if m35 * m35 < m11 then
			local m33 = m02 + m21 + m15 - m35 * m07
			if m33 * m33 < m14 then
				local m34 = m00 + m22 + m17 - m35 * m31
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 - m25 - m23 + m19) / m06
		if m35 * m35 < m11 then
			local m33 = m02 - m21 + m15 - m35 * m07
			if m33 * m33 < m14 then
				local m34 = m00 - m22 + m17 - m35 * m31
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 + m25 - m23 + m19) / m06
		if m35 * m35 < m11 then
			local m33 = m02 - m21 + m15 - m35 * m07
			if m33 * m33 < m14 then
				local m34 = m00 - m22 + m17 - m35 * m31
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 - m25 + m23 - m19) / m06
		if m35 * m35 < m11 then
			local m33 = m02 + m21 - m15 - m35 * m07
			if m33 * m33 < m14 then
				local m34 = m00 + m22 - m17 - m35 * m31
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 + m25 + m23 - m19) / m06
		if m35 * m35 < m11 then
			local m33 = m02 + m21 - m15 - m35 * m07
			if m33 * m33 < m14 then
				local m34 = m00 + m22 - m17 - m35 * m31
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 - m25 - m23 - m19) / m06
		if m35 * m35 < m11 then
			local m33 = m02 - m21 - m15 - m35 * m07
			if m33 * m33 < m14 then
				local m34 = m00 - m22 - m17 - m35 * m31
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		local m35 = (m01 + m25 - m23 - m19) / m06
		if m35 * m35 < m11 then
			local m33 = m02 - m21 - m15 - m35 * m07
			if m33 * m33 < m14 then
				local m34 = m00 - m22 - m17 - m35 * m31
				if m34 * m34 < m12 then
					return true
				end
			end
		end
		return false
	end
end

--from AxisAngle
local function boxInSphere(cframe0: CFrame, size0: Vector3, position1: Vector3, radius1: number): boolean
	local relative = cframe0:PointToObjectSpace(position1)
	local sx, sy, sz = size0.X / 2, size0.Y / 2, size0.Z / 2
	local rx, ry, rz = relative.X, relative.Y, relative.Z

	local dx = rx > sx and rx - sx or rx < -sx and rx + sx or 0
	local dy = ry > sy and ry - sy or ry < -sy and ry + sy or 0
	local dz = rz > sz and rz - sz or rz < -sz and rz + sz or 0

	return dx * dx + dy * dy + dz * dz < radius1 * radius1
end

local function boxInCylinder(
	cframe0: CFrame,
	size0: Vector3,
	position1: Vector3,
	axis1: Vector3,
	height1: number,
	radius1: number
): boolean
	local half_extents = size0 / 2
	local half_height = height1 / 2
	local obb_pos = cframe0.Position

	local box_x = cframe0.RightVector
	local box_y = cframe0.UpVector
	local box_z = cframe0.LookVector

	local hx = box_x * half_extents.X
	local hy = box_y * half_extents.Y
	local hz = box_z * half_extents.Z

	local d = position1 - obb_pos

	local axes = {
		axis1,
		box_x,
		box_y,
		box_z,
		vector.cross(axis1, box_x),
		vector.cross(axis1, box_y),
		vector.cross(axis1, box_z),
	}

	for _, axis in axes do
		if vector.dot(axis, axis) < 1e-6 then
			continue
		end

		local box_extent = math.abs(vector.dot(axis, hx))
			+ math.abs(vector.dot(axis, hy))
			+ math.abs(vector.dot(axis, hz))
		local cross_term = vector.cross(axis, axis1)
		local radial = vector.magnitude(cross_term)
		local axial = math.abs(vector.dot(axis, axis1))
		local cyl_extent = radius1 * radial + half_height * axial

		local dist = math.abs(vector.dot(axis, d))
		if dist > box_extent + cyl_extent then
			return false
		end
	end

	local axis_dot_x = vector.dot(axis1, box_x)
	local axis_dot_y = vector.dot(axis1, box_y)
	local axis_dot_z = vector.dot(axis1, box_z)

	local sign_x = if axis_dot_x >= 0 then 1 else 0
	local sign_y = if axis_dot_y >= 0 then 1 else 0
	local sign_z = if axis_dot_z >= 0 then 1 else 0

	local critical_verteces = {
		obb_pos + sign_x * hx + sign_y * hy + sign_z * hz,
		obb_pos + sign_x * hx + sign_y * hy - sign_z * hz,
		obb_pos + sign_x * hx - sign_y * hy + sign_z * hz,
		obb_pos - sign_x * hx + sign_y * hy + sign_z * hz,
	}

	for _, vertex in critical_verteces do
		local to_vertex = vertex - position1
		local t = math.clamp(vector.dot(to_vertex, axis1), -half_height, half_height)
		local closest_on_axis = position1 + axis1 * t
		local axis = vertex - closest_on_axis
		local axis_sq = vector.dot(axis, axis)
		if axis_sq < 1e-6 then
			continue
		end

		local n = vector.normalize(axis)
		local box_extent = math.abs(vector.dot(n, hx)) + math.abs(vector.dot(n, hy)) + math.abs(vector.dot(n, hz))
		local cross_term = vector.cross(n, axis1)
		local radial = vector.magnitude(cross_term)
		local axial = math.abs(vector.dot(n, axis1))
		local cyl_extent = radius1 * radial + half_height * axial

		local dist = math.abs(vector.dot(n, d))
		if dist > box_extent + cyl_extent then
			return false
		end
	end

	return true
end

return {
	BoxInCylinder = boxInCylinder,
	BoxInBox = boxInBox,
	BoxInSphere = boxInSphere,
}
