use std::ffi::{c_char, c_void, CStr};

#[no_mangle]
pub unsafe extern "C" fn try_lock_shared(key: *const c_char) -> *mut c_void {
    let key = CStr::from_ptr(key);
    match imp::try_lock_shared(key) {
        Some(guard) => Box::into_raw(Box::new(guard)).cast(),
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn try_lock_exclusive(key: *const c_char) -> *mut c_void {
    let key = CStr::from_ptr(key);
    match imp::try_lock_exclusive(key) {
        Some(guard) => Box::into_raw(Box::new(guard)).cast(),
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn lock_shared(key: *const c_char) -> *mut c_void {
    let key = CStr::from_ptr(key);
    let guard = imp::lock_shared(key);
    Box::into_raw(Box::new(guard)).cast()
}

#[no_mangle]
pub unsafe extern "C" fn lock_exclusive(key: *const c_char) -> *mut c_void {
    let key = CStr::from_ptr(key);
    let guard = imp::lock_exclusive(key);
    Box::into_raw(Box::new(guard)).cast()
}

#[no_mangle]
pub unsafe extern "C" fn unlock_shared(guard: *mut c_void) {
    if guard.is_null() {
        return;
    }
    let _ = Box::from_raw(guard as *mut imp::SharedGuard);
}

#[no_mangle]
pub unsafe extern "C" fn unlock_exclusive(guard: *mut c_void) {
    if guard.is_null() {
        return;
    }
    let _ = Box::from_raw(guard as *mut imp::ExclusiveGuard);
}

mod imp {
    use dashmap::mapref::one::{Ref, RefMut};
    use dashmap::try_result::TryResult;
    use dashmap::DashMap;
    use once_cell::sync::Lazy;

    type Key = std::ffi::CStr;
    type OwnedKey = std::ffi::CString;
    pub type SharedGuard = Ref<'static, OwnedKey, ()>;
    pub type ExclusiveGuard = RefMut<'static, OwnedKey, ()>;

    static LOCKS: Lazy<DashMap<OwnedKey, ()>> = Lazy::new(|| DashMap::with_shard_amount(256));

    pub fn try_lock_shared(key: &Key) -> Option<SharedGuard> {
        if let TryResult::Present(x) = LOCKS.try_get(key) {
            return Some(x);
        }

        let entry = LOCKS.try_entry(key.to_owned())?;
        Some(entry.or_default().downgrade())
    }

    pub fn try_lock_exclusive(key: &Key) -> Option<ExclusiveGuard> {
        let entry = LOCKS.try_entry(key.to_owned())?;
        Some(entry.or_default())
    }

    pub fn lock_shared(key: &Key) -> SharedGuard {
        if let Some(x) = LOCKS.get(key) {
            return x;
        }

        LOCKS.entry(key.to_owned()).or_default().downgrade()
    }

    pub fn lock_exclusive(key: &Key) -> ExclusiveGuard {
        LOCKS.entry(key.to_owned()).or_default()
    }
}
