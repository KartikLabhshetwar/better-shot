// Package videokit provides FFmpeg-based video processing for BetterShot.
// It runs as a standalone CLI tool that the Swift app calls via Process().
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
)

// CompressConfig holds video compression settings.
type CompressConfig struct {
	InputPath  string `json:"input_path"`
	OutputPath string `json:"output_path"`
	Quality    string `json:"quality"`    // "high", "medium", "low"
	Speed      string `json:"speed"`      // "ultrafast", "fast", "medium", "slow"
	Codec      string `json:"codec"`      // "h264", "hevc"
	Resolution string `json:"resolution"` // "original", "1080p", "720p", "480p"
	RemoveAudio bool  `json:"remove_audio"`
}

// TrimConfig holds video trim settings.
type TrimConfig struct {
	InputPath  string  `json:"input_path"`
	OutputPath string  `json:"output_path"`
	StartTime  float64 `json:"start_time"`
	EndTime    float64 `json:"end_time"`
}

// Result is returned as JSON to the Swift caller.
type Result struct {
	Success    bool   `json:"success"`
	OutputPath string `json:"output_path,omitempty"`
	InputSize  int64  `json:"input_size,omitempty"`
	OutputSize int64  `json:"output_size,omitempty"`
	Error      string `json:"error,omitempty"`
}

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	cmd := os.Args[1]

	switch cmd {
	case "compress":
		handleCompress()
	case "trim":
		handleTrim()
	case "probe":
		handleProbe()
	case "check":
		handleCheck()
	default:
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Fprintf(os.Stderr, `videokit — FFmpeg video processor for BetterShot

Usage:
  videokit check                          Check if FFmpeg is installed
  videokit probe <file>                   Get video metadata as JSON
  videokit compress '{"input_path":...}'  Compress a video
  videokit trim '{"input_path":...}'      Trim a video
`)
}

// handleCheck verifies FFmpeg is available.
func handleCheck() {
	path, err := findFFmpeg()
	if err != nil {
		outputJSON(Result{Success: false, Error: "FFmpeg not found. Install with: brew install ffmpeg"})
		return
	}
	outputJSON(Result{Success: true, OutputPath: path})
}

// handleProbe returns video metadata.
func handleProbe() {
	if len(os.Args) < 3 {
		outputJSON(Result{Success: false, Error: "probe requires a file path"})
		return
	}

	ffprobe, err := findTool("ffprobe")
	if err != nil {
		outputJSON(Result{Success: false, Error: "ffprobe not found"})
		return
	}

	filePath := os.Args[2]
	out, err := exec.Command(ffprobe,
		"-v", "quiet",
		"-print_format", "json",
		"-show_format",
		"-show_streams",
		filePath,
	).Output()

	if err != nil {
		outputJSON(Result{Success: false, Error: fmt.Sprintf("ffprobe failed: %v", err)})
		return
	}

	// Pass through ffprobe's JSON directly
	fmt.Print(string(out))
}

// handleCompress compresses a video using FFmpeg.
func handleCompress() {
	if len(os.Args) < 3 {
		outputJSON(Result{Success: false, Error: "compress requires a JSON config"})
		return
	}

	var cfg CompressConfig
	if err := json.Unmarshal([]byte(os.Args[2]), &cfg); err != nil {
		outputJSON(Result{Success: false, Error: fmt.Sprintf("invalid config: %v", err)})
		return
	}

	ffmpeg, err := findFFmpeg()
	if err != nil {
		outputJSON(Result{Success: false, Error: "FFmpeg not found"})
		return
	}

	if cfg.OutputPath == "" {
		ext := filepath.Ext(cfg.InputPath)
		base := strings.TrimSuffix(cfg.InputPath, ext)
		cfg.OutputPath = base + "_compressed" + ext
	}

	args := []string{"-i", cfg.InputPath, "-y"}

	// Codec
	switch cfg.Codec {
	case "hevc":
		args = append(args, "-c:v", "libx265")
	default:
		args = append(args, "-c:v", "libx264")
	}

	// Quality (CRF)
	crf := "26"
	switch cfg.Quality {
	case "high":
		crf = "20"
	case "low":
		crf = "32"
	}
	args = append(args, "-crf", crf)

	// Speed preset
	speed := "medium"
	if cfg.Speed != "" {
		speed = cfg.Speed
	}
	args = append(args, "-preset", speed)

	// Resolution
	switch cfg.Resolution {
	case "1080p":
		args = append(args, "-vf", "scale=-2:1080")
	case "720p":
		args = append(args, "-vf", "scale=-2:720")
	case "480p":
		args = append(args, "-vf", "scale=-2:480")
	}

	// Audio
	if cfg.RemoveAudio {
		args = append(args, "-an")
	} else {
		args = append(args, "-c:a", "copy")
	}

	args = append(args, cfg.OutputPath)

	cmd := exec.Command(ffmpeg, args...)
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		outputJSON(Result{Success: false, Error: fmt.Sprintf("ffmpeg failed: %v", err)})
		return
	}

	inputSize := fileSize(cfg.InputPath)
	outputSize := fileSize(cfg.OutputPath)

	outputJSON(Result{
		Success:    true,
		OutputPath: cfg.OutputPath,
		InputSize:  inputSize,
		OutputSize: outputSize,
	})
}

// handleTrim trims a video without re-encoding.
func handleTrim() {
	if len(os.Args) < 3 {
		outputJSON(Result{Success: false, Error: "trim requires a JSON config"})
		return
	}

	var cfg TrimConfig
	if err := json.Unmarshal([]byte(os.Args[2]), &cfg); err != nil {
		outputJSON(Result{Success: false, Error: fmt.Sprintf("invalid config: %v", err)})
		return
	}

	ffmpeg, err := findFFmpeg()
	if err != nil {
		outputJSON(Result{Success: false, Error: "FFmpeg not found"})
		return
	}

	if cfg.OutputPath == "" {
		ext := filepath.Ext(cfg.InputPath)
		base := strings.TrimSuffix(cfg.InputPath, ext)
		cfg.OutputPath = base + "_trimmed" + ext
	}

	duration := cfg.EndTime - cfg.StartTime
	args := []string{
		"-i", cfg.InputPath,
		"-ss", formatTime(cfg.StartTime),
		"-t", formatTime(duration),
		"-c", "copy",
		"-y",
		cfg.OutputPath,
	}

	cmd := exec.Command(ffmpeg, args...)
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		outputJSON(Result{Success: false, Error: fmt.Sprintf("ffmpeg trim failed: %v", err)})
		return
	}

	outputJSON(Result{
		Success:    true,
		OutputPath: cfg.OutputPath,
		InputSize:  fileSize(cfg.InputPath),
		OutputSize: fileSize(cfg.OutputPath),
	})
}

// findFFmpeg locates the FFmpeg binary.
func findFFmpeg() (string, error) {
	return findTool("ffmpeg")
}

func findTool(name string) (string, error) {
	// Check common Homebrew paths first
	paths := []string{
		"/opt/homebrew/bin/" + name,
		"/usr/local/bin/" + name,
	}
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p, nil
		}
	}
	// Fall back to PATH
	return exec.LookPath(name)
}

func formatTime(seconds float64) string {
	h := int(seconds) / 3600
	m := (int(seconds) % 3600) / 60
	s := seconds - float64(h*3600+m*60)
	return fmt.Sprintf("%02d:%02d:%s", h, m, strconv.FormatFloat(s, 'f', 3, 64))
}

func fileSize(path string) int64 {
	info, err := os.Stat(path)
	if err != nil {
		return 0
	}
	return info.Size()
}

func outputJSON(v interface{}) {
	data, _ := json.Marshal(v)
	fmt.Println(string(data))
}
