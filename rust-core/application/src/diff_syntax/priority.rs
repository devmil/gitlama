//! Lowers the calling thread to the platform's background CPU priority.
//!
//! Syntax colours are optional enrichment: their worker must never compete with foreground Git
//! work or the user interface. A platform without a reviewed call reports failure, and the
//! caller then leaves diffs plain instead of parsing at normal priority.

/// Lowers the current thread's priority. Returns whether it succeeded.
pub(super) fn lower_current_thread() -> bool {
    imp::lower()
}

#[cfg(target_os = "macos")]
mod imp {
    pub(super) fn lower() -> bool {
        // SAFETY: the call takes plain integers and changes only the calling thread's QoS class.
        #[allow(unsafe_code)]
        let result =
            unsafe { libc::pthread_set_qos_class_self_np(libc::qos_class_t::QOS_CLASS_UTILITY, 0) };
        result == 0
    }
}

#[cfg(target_os = "linux")]
mod imp {
    /// Niceness 10: below every interactive thread, above idle-only work.
    const NICENESS: i32 = 10;

    pub(super) fn lower() -> bool {
        // On Linux a thread ID names only that thread.
        rustix::process::setpriority_process(Some(rustix::thread::gettid()), NICENESS).is_ok()
    }
}

#[cfg(windows)]
mod imp {
    use windows::Win32::System::Threading::{
        GetCurrentThread, SetThreadPriority, THREAD_MODE_BACKGROUND_BEGIN,
    };

    pub(super) fn lower() -> bool {
        // SAFETY: the pseudo handle names the calling thread; background mode lowers its CPU,
        // I/O and memory priority.
        #[allow(unsafe_code)]
        unsafe {
            SetThreadPriority(GetCurrentThread(), THREAD_MODE_BACKGROUND_BEGIN).is_ok()
        }
    }
}

#[cfg(not(any(target_os = "macos", target_os = "linux", windows)))]
mod imp {
    pub(super) fn lower() -> bool {
        false
    }
}
