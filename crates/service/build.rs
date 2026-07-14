use std::time::{SystemTime, UNIX_EPOCH};

// Stamp the binary with its build time so `[build]` in the logs
// unambiguously identifies which deploy is running.
fn main() {
    let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
    println!("cargo:rustc-env=BUILD_TS={}", ts);
    println!("cargo:rerun-if-changed=src");
}
