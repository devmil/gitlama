//! The configured diff renderer: a program
//! that turns the inspected diff into plain text. Each run previews its
//! exact commands and asks first, then polls until the text is ready; a
//! failure keeps the built-in diff. The settings card validates a program
//! with the core before it is stored.

use crate::backend::SessionCalls;
use crate::inspector::InspectorService;
use crate::notify::{Notifier, Topics};
use crate::prompts::Prompts;
use crate::rt;
use crate::settings::SettingsService;
use crate::workspace::WorkspaceService;
use gitlama_contract::diff_renderer::{
    NativeDiffRendererDefinition, NativeDiffRendererFailureKind, NativeDiffRendererPreview,
    NativeDiffRendererResult, NativeDiffRendererSettings, NativeDiffRendererState,
};
use gitlama_contract::dto::{NativePathIdentity, NativePathPlatform};
use serde_json::{Value, json};
use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::Duration;

const POLL: Duration = Duration::from_millis(40);

/// What a failed renderer says.
pub fn failure_key(kind: Option<NativeDiffRendererFailureKind>) -> &'static str {
    use NativeDiffRendererFailureKind::*;
    match kind {
        Some(InvalidDefinition) => "diffRendererInvalidDefinition",
        Some(Unavailable) => "diffRendererUnavailable",
        Some(InvalidCapability) => "diffRendererInvalidCapability",
        Some(InputTooLarge) => "diffRendererInputTooLarge",
        Some(OutputTooLarge) => "diffRendererOutputTooLarge",
        Some(LaunchFailed) => "diffRendererLaunchFailed",
        Some(ProcessFailed) => "diffRendererProcessFailed",
        Some(TimedOut) => "diffRendererTimedOut",
        Some(Canceled) => "diffRendererCanceled",
        Some(Stale) | None => "diffRendererStale",
    }
}

/// The preview a confirmation shows; `run` adds the diff's size and limits,
/// saving shows the output format instead.
pub fn preview_value(preview: &NativeDiffRendererPreview, run: bool) -> Value {
    json!({
        "run": run,
        "title": preview.title,
        "executable": preview.executable,
        "capabilityCommand": std::iter::once(preview.executable.clone()).chain(preview.capability_arguments.iter().cloned()).collect::<Vec<_>>().join("\n"),
        "renderCommand": std::iter::once(preview.executable.clone()).chain(preview.arguments.iter().cloned()).collect::<Vec<_>>().join("\n"),
        "protocol": preview.protocol,
        "mediaType": preview.media_type,
        "inputBytes": preview.input_bytes,
        "outputLimitBytes": preview.output_limit_bytes,
        "timeoutSeconds": preview.timeout_seconds,
    })
}

/// A renderer the settings card describes.
#[derive(Clone, Debug, Default)]
pub struct Form {
    pub id: String,
    pub title: String,
    pub executable: String,
    /// One argument per line.
    pub arguments: String,
}

pub fn form_definition(
    form: &Form,
    platform: NativePathPlatform,
) -> Option<NativeDiffRendererDefinition> {
    let (id, title, executable) = (form.id.trim(), form.title.trim(), form.executable.trim());
    if id.is_empty() || title.is_empty() || executable.is_empty() {
        return None;
    }
    let units = match platform {
        NativePathPlatform::Windows => executable.encode_utf16().collect(),
        NativePathPlatform::Unix => executable.bytes().map(u16::from).collect(),
    };
    Some(NativeDiffRendererDefinition {
        id: id.to_owned(),
        title: title.to_owned(),
        executable: NativePathIdentity {
            platform,
            units,
            remote: None,
        },
        arguments: form
            .arguments
            .split('\n')
            .filter(|line| !line.is_empty())
            .map(str::to_owned)
            .collect(),
    })
}

fn path_text(path: &NativePathIdentity) -> String {
    crate::session::display_path(path)
}

/// One run's outcome for the diff it rendered.
#[derive(Clone, Debug)]
struct Run {
    request_id: u64,
    result: NativeDiffRendererResult,
}

#[derive(Clone, Debug, Default)]
struct Card {
    busy: bool,
    failure: Option<&'static str>,
}

pub struct DiffRenderers {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    inspector: Rc<InspectorService>,
    settings: Rc<SettingsService>,
    prompts: Rc<Prompts>,
    notifier: Notifier,
    run: RefCell<Option<Run>>,
    /// Bumps per run, so a superseded run stops polling.
    sequence: Cell<u64>,
    card: RefCell<Card>,
}

impl DiffRenderers {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        inspector: Rc<InspectorService>,
        settings: Rc<SettingsService>,
        prompts: Rc<Prompts>,
        notifier: Notifier,
    ) -> Rc<Self> {
        Rc::new(Self {
            calls,
            workspace,
            inspector,
            settings,
            prompts,
            notifier,
            run: RefCell::new(None),
            sequence: Cell::new(0),
            card: RefCell::new(Card::default()),
        })
    }

    fn changed(&self) {
        self.notifier.notify(Topics::OPERATIONS);
    }

    pub fn configured(&self) -> Option<NativeDiffRendererSettings> {
        self.settings
            .with(|document| document.diff_renderer.clone())
    }

    fn set_result(&self, sequence: u64, request_id: u64, result: NativeDiffRendererResult) {
        if self.sequence.get() == sequence {
            *self.run.borrow_mut() = Some(Run { request_id, result });
            self.changed();
        }
    }

    fn fallback(failure: NativeDiffRendererFailureKind) -> NativeDiffRendererResult {
        NativeDiffRendererResult {
            state: NativeDiffRendererState::Fallback,
            title: None,
            text: None,
            accessibility_text: None,
            activity_ids: Vec::new(),
            failure: Some(gitlama_contract::diff_renderer::NativeDiffRendererFailure {
                kind: failure,
            }),
        }
    }

    /// Renders the inspected diff with the configured renderer.
    pub async fn render(&self) {
        let Some(settings) = self.configured() else {
            return;
        };
        let Some(identity) = self.workspace.current().map(|session| session.identity) else {
            return;
        };
        let Some(request_id) = self.inspector.current().diff.map(|diff| diff.request_id()) else {
            return;
        };
        let sequence = self.sequence.get() + 1;
        self.sequence.set(sequence);
        let (session, generation) = (identity.native_id, identity.generation);
        let definition = NativeDiffRendererDefinition {
            id: settings.id,
            title: settings.title,
            executable: settings.executable,
            arguments: settings.arguments,
        };
        let preview = match self
            .calls
            .repository_session_diff_renderer_preview(session, generation, request_id, definition)
            .await
        {
            Ok(result) => match (result.preview, result.failure) {
                (Some(preview), None) => preview,
                (_, failure) => {
                    let kind = failure
                        .map_or(NativeDiffRendererFailureKind::Stale, |failure| failure.kind);
                    return self.set_result(sequence, request_id, Self::fallback(kind));
                }
            },
            Err(_) => {
                return self.set_result(
                    sequence,
                    request_id,
                    Self::fallback(NativeDiffRendererFailureKind::Stale),
                );
            }
        };
        let answer = self
            .prompts
            .ask("confirmRenderer", preview_value(&preview, true))
            .await;
        if answer != Some(Value::Bool(true)) || self.sequence.get() != sequence {
            let _ = self
                .calls
                .repository_session_diff_renderer_cancel(session, generation, preview.token)
                .await;
            return;
        }
        let mut result = match self
            .calls
            .repository_session_diff_renderer_execute(session, generation, preview.token)
            .await
        {
            Ok(result) => result,
            Err(_) => {
                return self.set_result(
                    sequence,
                    request_id,
                    Self::fallback(NativeDiffRendererFailureKind::Stale),
                );
            }
        };
        self.set_result(sequence, request_id, result.clone());
        while result.state == NativeDiffRendererState::Pending {
            rt::sleep(POLL).await;
            if self.sequence.get() != sequence {
                let _ = self
                    .calls
                    .repository_session_diff_renderer_cancel(session, generation, preview.token)
                    .await;
                return;
            }
            result = match self
                .calls
                .repository_session_diff_renderer_poll(session, generation, preview.token)
                .await
            {
                Ok(result) => result,
                Err(_) => Self::fallback(NativeDiffRendererFailureKind::Stale),
            };
            self.set_result(sequence, request_id, result.clone());
        }
    }

    /// Shows the built-in diff again; a running renderer stops.
    pub fn use_built_in(&self) {
        self.sequence.set(self.sequence.get() + 1);
        *self.run.borrow_mut() = None;
        self.changed();
    }

    /// Checks the renderer `form` describes, asks to store it, and stores it.
    pub async fn save(&self, form: Form) {
        if self.card.borrow().busy {
            return;
        }
        let Some(root) = self.workspace.active_canonical() else {
            return;
        };
        let Some(definition) = form_definition(&form, root.platform) else {
            self.card.borrow_mut().failure = Some(failure_key(Some(
                NativeDiffRendererFailureKind::InvalidDefinition,
            )));
            return self.changed();
        };
        let Some(identity) = self.workspace.current().map(|session| session.identity) else {
            return;
        };
        *self.card.borrow_mut() = Card {
            busy: true,
            failure: None,
        };
        self.changed();
        let validated = self
            .calls
            .repository_session_diff_renderer_validate(
                identity.native_id,
                identity.generation,
                definition.clone(),
            )
            .await;
        let preview = match validated {
            Ok(result) => match (result.preview, result.failure) {
                (Some(preview), None) => Ok(preview),
                (_, failure) => Err(failure_key(failure.map(|failure| failure.kind))),
            },
            Err(_) => Err(failure_key(None)),
        };
        let failure = match preview {
            Err(key) => Some(key),
            Ok(preview) => {
                if self
                    .prompts
                    .ask("confirmRendererSave", preview_value(&preview, false))
                    .await
                    == Some(Value::Bool(true))
                {
                    let stored = NativeDiffRendererSettings {
                        id: definition.id,
                        title: definition.title,
                        executable: definition.executable,
                        arguments: definition.arguments,
                    };
                    self.settings
                        .update_durable(
                            |document| document.diff_renderer = Some(stored.clone()),
                            |current, previous| {
                                current.diff_renderer = previous.diff_renderer.clone()
                            },
                        )
                        .await
                        .err()
                        .map(|_| "settingsSaveFailed")
                } else {
                    None
                }
            }
        };
        *self.card.borrow_mut() = Card {
            busy: false,
            failure,
        };
        self.changed();
    }

    pub async fn remove(&self) {
        let _ = self
            .settings
            .update_durable(
                |document| document.diff_renderer = None,
                |current, previous| current.diff_renderer = previous.diff_renderer.clone(),
            )
            .await;
        *self.card.borrow_mut() = Card::default();
        self.changed();
    }

    /// The renderer's run for the inspected diff and the settings card.
    pub fn value(&self) -> Value {
        let request_id = self.inspector.current().diff.map(|diff| diff.request_id());
        let run = self.run.borrow();
        let result = run
            .as_ref()
            .filter(|run| Some(run.request_id) == request_id)
            .map(|run| {
                let result = &run.result;
                json!({
                    "state": match result.state {
                        NativeDiffRendererState::Pending => "pending",
                        NativeDiffRendererState::Ready => "ready",
                        NativeDiffRendererState::Fallback => "fallback",
                        NativeDiffRendererState::Canceled => "canceled",
                    },
                    "title": result.title,
                    "text": result.text,
                    "accessibilityText": result.accessibility_text,
                    "failure": failure_key(result.failure.as_ref().map(|failure| failure.kind)),
                })
            });
        let configured = self.configured();
        let card = self.card.borrow();
        json!({
            "configured": configured.is_some(),
            "result": result,
            "card": {
                "busy": card.busy,
                "failure": card.failure,
                "id": configured.as_ref().map_or_else(|| "plain-text".to_owned(), |renderer| renderer.id.clone()),
                "title": configured.as_ref().map(|renderer| renderer.title.clone()).unwrap_or_default(),
                "executable": configured.as_ref().map(|renderer| path_text(&renderer.executable)).unwrap_or_default(),
                "arguments": configured.as_ref().map(|renderer| renderer.arguments.join("\n")).unwrap_or_default(),
            },
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_complete_form_describes_a_renderer() {
        let form = Form {
            id: " plain ".into(),
            title: "Plain".into(),
            executable: "/usr/bin/cat".into(),
            arguments: "-\n\n".into(),
        };
        let definition = form_definition(&form, NativePathPlatform::Unix).unwrap();
        assert_eq!(definition.id, "plain");
        assert_eq!(definition.arguments, ["-"]);
        assert!(
            form_definition(
                &Form {
                    title: " ".into(),
                    ..form
                },
                NativePathPlatform::Unix
            )
            .is_none()
        );
    }

    #[test]
    fn failures_name_their_messages() {
        assert_eq!(failure_key(None), "diffRendererStale");
        assert_eq!(
            failure_key(Some(NativeDiffRendererFailureKind::TimedOut)),
            "diffRendererTimedOut"
        );
    }
}
