//! Utility functions for common operations

use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

/// Custom error type for better error handling
pub type AppResult<T> = Result<T, String>;

/// Get current timestamp in milliseconds
pub fn get_timestamp() -> AppResult<u64> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("Failed to get timestamp: {}", e))
        .map(|d| d.as_millis() as u64)
}

/// Ensure a directory exists, creating it if necessary
pub fn ensure_dir(path: &PathBuf) -> AppResult<()> {
    fs::create_dir_all(path).map_err(|e| format!("Failed to create directory: {}", e))
}

/// Generate a unique filename with a prefix and timestamp
pub fn generate_filename(prefix: &str, extension: &str) -> AppResult<String> {
    let timestamp = get_timestamp()?;
    Ok(format!("{}_{}.{}", prefix, timestamp, extension))
}

/// Generate a unique filename with prefix, id, and timestamp
pub fn generate_filename_with_id(prefix: &str, id: u32, extension: &str) -> AppResult<String> {
    let timestamp = get_timestamp()?;
    Ok(format!("{}_{}_{}.{}", prefix, id, timestamp, extension))
}
