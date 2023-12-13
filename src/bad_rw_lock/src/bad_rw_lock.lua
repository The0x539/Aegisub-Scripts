local ffi = require 'ffi'
local requireffi = require 'requireffi.requireffi'

ffi.cdef [[
	void lock_shared(void);
	void lock_exclusive(void);
	bool try_lock_shared(void);
	bool try_lock_exclusive(void);
	void unlock_shared(void);
	void unlock_exclusive(void);
]]

local impl = requireffi 'bad_rw_lock.bad_rw_lock'

local lib = {}

function lib.lock_shared()
	impl.lock_shared()
end

function lib.lock_exclusive()
	impl.lock_exclusive()
end

function lib.try_lock_shared()
	return impl.try_lock_shared()
end

function lib.try_lock_exclusive()
	return impl.try_lock_exclusive()
end

function lib.unlock_shared()
	impl.unlock_shared()
end

function lib.unlock_exclusive()
	impl.unlock_exclusive()
end

return lib
