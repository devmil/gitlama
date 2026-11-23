//! Returns freed heap memory to the operating system. Startup and loading a repository
//! allocate and free a great deal (the QML engine compiles every component, a history page
//! is decoded once); glibc keeps freed pages in the process until it is asked to release
//! them, so the resident size stays at its peak. One trim after the work settles brings it
//! back to what is live.

/// Releases free heap pages (glibc only; elsewhere the allocator returns them itself).
pub fn release_free_pages() {
    #[cfg(all(target_os = "linux", target_env = "gnu"))]
    {
        unsafe extern "C" {
            fn malloc_trim(pad: usize) -> i32;
        }
        // SAFETY: malloc_trim only releases unused pages of the allocator's own arenas.
        unsafe {
            malloc_trim(0);
        }
    }
}

/// Releases free heap pages once `delay` after now, on the runtime.
pub fn release_free_pages_after(delay: std::time::Duration) {
    crate::rt::spawn_detached(async move {
        crate::rt::sleep(delay).await;
        crate::rt::blocking(release_free_pages).await;
    });
}
