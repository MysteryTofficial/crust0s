// Crust OS — Software Update panel for COSMIC Settings
//
// This panel is compiled during `build.sh` and installed to
// /usr/bin/cosmic-settings-update.  COSMIC Settings discovers it
// via the X-COSMIC-Settings-Panel key in the desktop file.
//
// The API below targets cosmic-epoch (cosmic-1.0). Adjust to the
// exact version available in your build environment.
//
// Build:  cargo build --release
// Test:   cargo run

use cosmic::app::{Command, Core, Settings};
use cosmic::widget::{self, button, column, container, row, text, toggler, progress_bar};
use cosmic::{Apply, Element};

#[derive(Debug, Clone)]
enum Message {
    CheckNow,
    InstallAll,
    ToggleAutoCheck(bool),
    FetchResult(Result<UpdateManifest, String>),
    InstallResult(Result<String, String>),
}

#[derive(Debug, Clone, Default, serde::Deserialize)]
struct UpdateManifest {
    packages: Vec<PackageEntry>,
}

#[derive(Debug, Clone, Default, serde::Deserialize)]
struct PackageEntry {
    name: String,
    version: String,
    #[serde(rename = "type")]
    pkg_type: String,
    severity: String,
    description: String,
}

#[derive(Debug, Clone)]
enum State {
    Idle,
    Checking,
    UpdatesAvailable(Vec<PackageEntry>),
    Installing,
    Done { success: bool, message: String },
    Error(String),
}

struct UpdatePanel {
    core: Core,
    state: State,
    auto_check: bool,
    manifest_url: String,
}

impl UpdatePanel {
    fn check_updates(&self) -> impl std::future::Future<Output = Result<UpdateManifest, String>> {
        let url = self.manifest_url.clone();
        async move {
            let resp = reqwest::get(&url)
                .await
                .map_err(|e| format!("Network error: {}", e))?;
            let manifest: UpdateManifest =
                resp.json().await.map_err(|e| format!("Parse error: {}", e))?;
            Ok(manifest)
        }
    }

    fn filter_available(&self, manifest: &UpdateManifest) -> Vec<PackageEntry> {
        manifest
            .packages
            .iter()
            .filter(|p| p.severity != "optional")
            .cloned()
            .collect()
    }
}

impl cosmic::Application for UpdatePanel {
    type Message = Message;
    type Executor = cosmic::executor::Default;
    type Flags = ();

    const APP_ID: &'static str = "org.crustos.SoftwareUpdate";

    fn core(&self) -> &Core {
        &self.core
    }

    fn core_mut(&mut self) -> &mut Core {
        &mut self.core
    }

    fn init(core: Core, _flags: ()) -> (Self, Command<Message>) {
        let panel = UpdatePanel {
            core,
            state: State::Idle,
            auto_check: true,
            manifest_url: "https://raw.githubusercontent.com/crust-os/crust-os-repo/main/update.json"
                .into(),
        };
        (panel, Command::none())
    }

    fn update(&mut self, message: Message) -> Command<Message> {
        match message {
            Message::CheckNow => {
                self.state = State::Checking;
                Command::perform(self.check_updates(), Message::FetchResult)
            }
            Message::FetchResult(result) => {
                match result {
                    Ok(manifest) => {
                        let available = self.filter_available(&manifest);
                        if available.is_empty() {
                            self.state = State::Done {
                                success: true,
                                message: "Your system is up to date.".into(),
                            };
                        } else {
                            self.state = State::UpdatesAvailable(available);
                        }
                    }
                    Err(e) => self.state = State::Error(e),
                }
                Command::none()
            }
            Message::InstallAll => {
                self.state = State::Installing;
                let future = async {
                    let output = std::process::Command::new("pkexec")
                        .args([
                            "pacman", "-Syu", "--noconfirm", "--overwrite=*",
                        ])
                        .output();
                    match output {
                        Ok(out) if out.status.success() => {
                            Ok("Updates installed successfully.".into())
                        }
                        Ok(out) => Err(String::from_utf8_lossy(&out.stderr).to_string()),
                        Err(e) => Err(format!("Failed to run update: {}", e)),
                    }
                };
                Command::perform(future, Message::InstallResult)
            }
            Message::InstallResult(result) => {
                match result {
                    Ok(msg) => self.state = State::Done { success: true, message: msg },
                    Err(e) => self.state = State::Done { success: false, message: e },
                }
                Command::none()
            }
            Message::ToggleAutoCheck(val) => {
                self.auto_check = val;
                Command::none()
            }
        }
    }

    fn view(&self) -> Element<Message> {
        let header = text("Software Update").size(24);

        let content: Element<_> = match &self.state {
            State::Idle => column()
                .push(text("No update check has been run yet."))
                .push(button(text("Check for Updates")).on_press(Message::CheckNow).padding(8))
                .spacing(12)
                .into(),
            State::Checking => column()
                .push(text("Checking for updates…"))
                .push(progress_bar::ProgressBar::new(0.0..=1.0, 0.5))
                .spacing(12)
                .into(),
            State::UpdatesAvailable(pkgs) => {
                let mut list = column().spacing(8);
                for pkg in pkgs {
                    let entry = row()
                        .push(text(&pkg.name).width(200))
                        .push(text(&pkg.version).width(100))
                        .push(text(&pkg.severity).width(80))
                        .push(text(&pkg.description))
                        .spacing(12);
                    list = list.push(entry);
                }
                column()
                    .push(text("Available Updates").size(18))
                    .push(list)
                    .push(button(text("Install All Updates")).on_press(Message::InstallAll).padding(12))
                    .spacing(16)
                    .into()
            }
            State::Installing => column()
                .push(text("Installing updates…"))
                .push(progress_bar::ProgressBar::new(0.0..=1.0, 0.5))
                .spacing(12)
                .into(),
            State::Done { success, message } => {
                let msg = format!("[{}] {}", if *success { "OK" } else { "FAIL" }, message);
                column()
                    .push(text(msg))
                    .push(button(text("Check Again")).on_press(Message::CheckNow).padding(8))
                    .spacing(12)
                    .into()
            }
            State::Error(e) => column()
                .push(text(format!("Error: {}", e)))
                .push(button(text("Retry")).on_press(Message::CheckNow).padding(8))
                .spacing(12)
                .into(),
        };

        let toggle = toggler("Automatic update checks")
            .on_toggle(Message::ToggleAutoCheck);

        container(
            column()
                .push(header)
                .push(widget::divider::horizontal::default())
                .push(content)
                .push(widget::divider::horizontal::default())
                .push(toggle)
                .spacing(16)
                .padding(24),
        )
        .into()
    }
}

fn main() -> cosmic::iced::Result {
    cosmic::app::run::<UpdatePanel>(Settings::default(), ())
}
