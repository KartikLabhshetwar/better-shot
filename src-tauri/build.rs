fn main() {
    #[cfg(target_os = "macos")]
    {
        use std::process::Command;
        
        let output = Command::new("xcode-select")
            .arg("-p")
            .output();
        
        if let Ok(output) = output {
            let path = String::from_utf8_lossy(&output.stdout);
            if path.contains("CommandLineTools") {
                eprintln!("\n⚠️  WARNING: Xcode Command Line Tools detected, but full Xcode is required!");
                eprintln!("   The 'scap' crate requires full Xcode (not just Command Line Tools).");
                eprintln!("   Please install Xcode from the App Store and run:");
                eprintln!("   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer");
                eprintln!("   sudo xcodebuild -license accept\n");
            }
        }
    }
    
    tauri_build::build()
}
