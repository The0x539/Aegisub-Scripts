use parking_lot::lock_api::RawRwLock as _;
use parking_lot::RawRwLock;

static LOCK: RawRwLock = RawRwLock::INIT;

#[no_mangle]
pub extern "C" fn lock_shared() {
    LOCK.lock_shared()
}

#[no_mangle]
pub extern "C" fn lock_exclusive() {
    LOCK.lock_exclusive()
}

#[no_mangle]
pub extern "C" fn try_lock_shared() -> bool {
    LOCK.try_lock_shared()
}

#[no_mangle]
pub extern "C" fn try_lock_exclusive() -> bool {
    LOCK.try_lock_exclusive()
}

#[no_mangle]
pub unsafe extern "C" fn unlock_shared() {
    LOCK.unlock_shared()
}

#[no_mangle]
pub unsafe extern "C" fn unlock_exclusive() {
    LOCK.unlock_exclusive()
}
