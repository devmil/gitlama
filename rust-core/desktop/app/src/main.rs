//! GitLama's composition root: the workbench services, the Qt objects and
//! the QML window, and every lifetime until exit.

mod hooks;

use hooks::PlatformHooks;
use gitlama_qt::{AppState, Commands, Driver, Pump, PumpWaker, WorkspaceState};
use gitlama_workbench::app::App;
use gitlama_workbench::notify::Notifier;
use gitlama_workbench::rt::Runtime;
use qtbridge::{QApp, QObjectHolder};
use serde_json::json;
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;

static RESOURCES: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/gitlama.rcc"));

const VERSION: &str = env!("GITLAMA_VERSION");
const BUILD: &str = env!("GITLAMA_BUILD");

/// The Qt application name: on Linux it is the Wayland app id and must match
/// the desktop entry.
const APPLICATION_NAME: &str = if cfg!(target_os = "linux") {
    "de.devmil.gitlama"
} else {
    "GitLama"
};

fn os_name() -> &'static str {
    if cfg!(target_os = "macos") {
        "macos"
    } else if cfg!(target_os = "windows") {
        "windows"
    } else {
        "linux"
    }
}

#[cfg(target_os = "linux")]
unsafe extern "C" {
    fn gitlama_set_desktop_file_name(name: *const std::ffi::c_char);
}

/// The Wayland app id and X11 class, matching the desktop entry.
fn set_desktop_file_name() {
    #[cfg(target_os = "linux")]
    {
        let name = c"de.devmil.gitlama";
        // SAFETY: a static NUL-terminated string; the setter copies it.
        unsafe { gitlama_set_desktop_file_name(name.as_ptr()) };
    }
}

unsafe extern "C" {
    /// Registers the natively painted Qt Quick items (src/native).
    fn gitlama_register_native_types();
}

fn main() {
    // macOS starts applications with launchd's PATH; restart with the login
    // shell's before any thread exists so Git finds its helpers.
    #[cfg(target_os = "macos")]
    gitlama_core::gitlama_prepare_desktop_environment();

    gitlama_workbench::diagnostics::info("Launcher", "process_start", &[]);
    set_desktop_file_name();
    let mut application = QApp::new();
    application.application_name(APPLICATION_NAME);
    assert!(
        qtbridge::qresource::register_bytes(RESOURCES),
        "failed to register the embedded QML resource"
    );

    let runtime = Runtime::install();
    let waker = PumpWaker::new();
    {
        let waker = Arc::clone(&waker);
        runtime.set_wake_hook(Arc::new(move || waker.notify()));
    }
    let commands = Commands::new(Arc::clone(&waker));
    let notifier = Notifier::new();
    let app = App::new(notifier);

    let state = Rc::new(RefCell::new(AppState::default()));
    AppState::attach_qobject(&state);
    state.borrow_mut().commands = Some(commands.clone());
    state.borrow_mut().command_registry = gitlama_qt::command_registry();
    state.borrow_mut().platform = json!({
        "os": os_name(),
        "version": VERSION,
        "build": BUILD,
        "hyprland": std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some(),
        "remoteEnabled": false,
    });

    let workspace = Rc::new(RefCell::new(WorkspaceState::default()));
    WorkspaceState::attach_qobject(&workspace);
    workspace.borrow_mut().commands = Some(commands.clone());

    let sidebar = Rc::new(RefCell::new(gitlama_qt::SidebarState::default()));
    gitlama_qt::SidebarState::attach_qobject(&sidebar);
    sidebar.borrow_mut().commands = Some(commands.clone());
    let sidebar_rows = Rc::new(RefCell::new(gitlama_qt::RowModel::with_roles("key", gitlama_qt::SIDEBAR_ROLES)));
    gitlama_qt::RowModel::attach_qobject(&sidebar_rows);

    let history = Rc::new(RefCell::new(gitlama_qt::HistoryState::default()));
    gitlama_qt::HistoryState::attach_qobject(&history);
    history.borrow_mut().commands = Some(commands.clone());
    let history_rows = Rc::new(RefCell::new(gitlama_qt::HistoryModel::default()));
    gitlama_qt::HistoryModel::attach_qobject(&history_rows);

    let driver = Rc::new(Driver {
        history: Rc::clone(&history),
        history_rows: Rc::clone(&history_rows),
        history_context: RefCell::new(None),
        history_published: RefCell::new(None),
        sidebar: Rc::clone(&sidebar),
        sidebar_rows: Rc::clone(&sidebar_rows),
        app: Rc::clone(&app),
        runtime,
        commands,
        waker: Arc::clone(&waker),
        state: Rc::clone(&state),
        workspace: Rc::clone(&workspace),
    });
    let pump = Rc::new(RefCell::new(Pump::default()));
    Pump::attach_qobject(&pump);
    pump.borrow_mut().driver = Some(Rc::clone(&driver));
    waker.bind(pump.borrow().get_qml_method_invoker());
    app.start();
    driver.pump();

    // GITLAMA_QML_DIR loads the QML from a checkout instead of the embedded
    // resource, for iterating on the UI without rebuilding.
    let (import_path, main_qml) = match std::env::var("GITLAMA_QML_DIR") {
        Ok(dir) if !dir.is_empty() => {
            let dir = std::path::Path::new(&dir)
                .canonicalize()
                .unwrap_or_else(|_| dir.clone().into());
            (
                dir.display().to_string(),
                format!("file://{}/GitLama/Boot.qml", dir.display()),
            )
        }
        _ => ("qrc:/".to_owned(), "qrc:/GitLama/Boot.qml".to_owned()),
    };
    // SAFETY: registers QML types; called once on the GUI thread before
    // any QML loads.
    unsafe { gitlama_register_native_types() };
    let hooks = Rc::new(RefCell::new(PlatformHooks::default()));
    PlatformHooks::attach_qobject(&hooks);
    let properties = vec![
        ("app", state.borrow().as_qvariant()),
        ("hooks", hooks.borrow().as_qvariant()),
        ("workspace", workspace.borrow().as_qvariant()),
        ("sidebar", sidebar.borrow().as_qvariant()),
        ("sidebarRows", sidebar_rows.borrow().as_qvariant()),
        ("history", history.borrow().as_qvariant()),
        ("historyRows", history_rows.borrow().as_qvariant()),
    ];
    let exit_code = application
        .add_import_path(&import_path)
        .with_initial_properties(&properties)
        .load_qml_from_file(&main_qml)
        .run();

    // Flush settings and dispose the services before the engine goes.
    {
        let done = Rc::new(std::cell::Cell::new(false));
        let finished = Rc::clone(&done);
        let shutting_down = Rc::clone(&app);
        gitlama_workbench::rt::spawn_detached(async move {
            shutting_down.shutdown().await;
            finished.set(true);
        });
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        while !done.get() && std::time::Instant::now() < deadline {
            driver.runtime.run_until_stalled();
            std::thread::sleep(std::time::Duration::from_millis(2));
        }
    }
    waker.unbind();
    drop(application);
    drop(pump);
    drop(hooks);
    if exit_code != 0 {
        std::process::exit(exit_code);
    }
}
