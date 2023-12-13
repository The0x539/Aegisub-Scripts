local ffi = require 'ffi'
local requireffi = require 'requireffi.requireffi'

ffi.cdef [[
	void *try_lock_shared(const char *key);
	void *try_lock_exclusive(const char *key);
	void *lock_shared(const char *key);
	void *lock_exclusive(const char *key);
	void unlock_shared(void *guard);
	void unlock_exclusive(void *guard);
]]

local impl = requireffi 'bad_rw_lock.bad_rw_lock'

local lib = {}

function lib.try_lock_shared(key)
	local guard = impl.try_lock_shared(key)
	if guard == nil then
		return nil
	end
	return guard
end

function lib.try_lock_exclusive(key)
	local guard = impl.try_lock_exclusive(key)
	if guard == nil then
		return nil
	end
	return guard
end

function lib.lock_shared(key)
	return impl.lock_shared(key)
end

function lib.lock_exclusive(key)
	return impl.lock_exclusive(key)
end

function lib.unlock_shared(guard)
	impl.unlock_shared(guard)
end

function lib.unlock_exclusive(guard)
	impl.unlock_exclusive(guard)
end

return lib
