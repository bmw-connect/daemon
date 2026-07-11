use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

use carplay_protocol::{DspState, EQ_BANDS, Source};

pub const DEFAULT_OUTPUT_DEVICE: &str = "plughw:sndrpihifiberry";

fn default_output_device() -> String {
    DEFAULT_OUTPUT_DEVICE.into()
}

#[derive(Serialize, Deserialize)]
pub struct Settings {
    pub volume: f32,
    pub eq_gains: Vec<f32>,
    pub loudness: bool,
    pub limiter: bool,
    pub muted: bool,
    pub source: Source,
    // Absent from files written before this field existed — falls back to the HifiBerry.
    #[serde(default = "default_output_device")]
    pub output_device: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            volume: 0.8,
            eq_gains: vec![0.0; EQ_BANDS],
            loudness: true,
            limiter: true,
            muted: false,
            source: Source::Airplay,
            output_device: default_output_device(),
        }
    }
}

impl From<&DspState> for Settings {
    fn from(s: &DspState) -> Self {
        Self {
            volume: s.volume,
            eq_gains: s.eq_gains.clone(),
            loudness: s.loudness,
            limiter: s.limiter,
            muted: s.muted,
            source: s.source,
            output_device: default_output_device(),
        }
    }
}

impl From<Settings> for DspState {
    fn from(s: Settings) -> Self {
        let mut eq_gains = vec![0.0f32; EQ_BANDS];
        let len = s.eq_gains.len().min(EQ_BANDS);
        eq_gains[..len].copy_from_slice(&s.eq_gains[..len]);
        DspState {
            volume: s.volume,
            eq_gains,
            loudness: s.loudness,
            limiter: s.limiter,
            muted: s.muted,
            source: s.source,
        }
    }
}

fn path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    PathBuf::from(home).join(".carplay-audio.json")
}

fn load_settings() -> Settings {
    std::fs::read_to_string(path())
        .ok()
        .and_then(|s| serde_json::from_str::<Settings>(&s).ok())
        .unwrap_or_default()
}

pub fn load() -> (DspState, String) {
    let file = path();
    let settings = load_settings();
    // Create the file on first run so it can be found and edited by hand.
    if !file.exists() {
        if let Ok(json) = serde_json::to_string_pretty(&settings) {
            let _ = std::fs::write(&file, json);
        }
    }
    println!("[settings] file: {}", file.display());
    let output_device = settings.output_device.clone();
    (DspState::from(settings), output_device)
}

pub fn save(state: &DspState) -> Result<()> {
    let mut settings = Settings::from(state);
    // The output device is only configurable by editing the file; keep whatever is there.
    settings.output_device = load_settings().output_device;
    let json = serde_json::to_string_pretty(&settings)?;
    std::fs::write(path(), json)?;
    Ok(())
}
